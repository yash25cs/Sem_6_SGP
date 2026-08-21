import { HttpError } from './supa.ts';

/// Thin client for the two Gemini surfaces these functions need.
///
/// Every shape below was **measured against this project's own key** on
/// 2026-08-22, not read off a docs page, because the docs sent an earlier
/// version of this file down a path that does not work:
///
///   * Generation is `POST /v1beta/models/{model}:generateContent`, answer at
///     `candidates[0].content.parts[].text`. `/v1beta/interactions` does exist
///     and does answer, but it is not in any model's
///     `supportedGenerationMethods`, and it turns thinking back on for models
///     that otherwise skip it — so it buys nothing and costs latency.
///     `/v1beta2/interactions`, which the migration guide recommends, is a 404.
///   * `systemInstruction`, `generationConfig.responseMimeType` +
///     `responseSchema`, and an inline PDF part all work in that one shape. The
///     degradation ladder this file used to carry was guarding against
///     doc contradictions that measurement resolved; it is gone.
///   * Embeddings: `POST /v1beta/models/{model}:batchEmbedContents`, vector at
///     `embeddings[n].values`. `gemini-embedding-2` answers in ~0.4 s and was
///     never the slow part. It rejects `task_type` and expects task *templates*
///     in the text instead — see [documentText] / [queryText].
///
/// **Model choice is load-bearing.** Measured, same three-word prompt:
/// `gemini-3.7-flash` never answered inside 22 s on either endpoint, with
/// thinking off or on; `gemini-3.6-flash` took 12.5 s and returned an *empty*
/// answer with `finishReason: MAX_TOKENS`, having spent the entire output budget
/// thinking; `gemini-3.5-flash-lite` answered in 0.77 s and does not think.
/// Anything set in `GEMINI_TEXT_MODEL` needs the same check — a thinking model
/// here reads as "the chatbot hangs, then says try again".

const DEFAULT_BASE = 'https://generativelanguage.googleapis.com/v1beta';

/// How many texts go in one `:batchEmbedContents` call.
const EMBED_BATCH = 100;

/// Must match `material_chunks.embedding vector(768)` and its HNSW index.
/// Changing it means re-embedding everything, so it's read from the env only so
/// that a mismatch can be diagnosed without a redeploy — not as a knob to turn.
export const EMBED_DIM = Number(Deno.env.get('GEMINI_EMBED_DIM') ?? '768');

function env(name: string, fallback: string): string {
  const value = Deno.env.get(name)?.trim();
  return value && value.length > 0 ? value : fallback;
}

function base(): string {
  return env('GEMINI_API_BASE', DEFAULT_BASE).replace(/\/+$/, '');
}

export function textModel(): string {
  return env('GEMINI_TEXT_MODEL', 'gemini-3.5-flash-lite');
}

export function embedModel(): string {
  return env('GEMINI_EMBED_MODEL', 'gemini-embedding-2');
}

function apiKey(): string {
  const key = Deno.env.get('GEMINI_API_KEY')?.trim();
  if (!key) {
    throw new HttpError(
      503,
      'The AI features are not set up for this project yet.',
    );
  }
  return key;
}

/// A rejection from Gemini, carrying both the student-facing message and the
/// raw upstream detail so [interact] can decide whether a retry in a different
/// shape is worth attempting.
class GeminiError extends HttpError {
  constructor(
    status: number,
    message: string,
    readonly upstreamStatus: number,
    readonly detail: string,
  ) {
    super(status, message);
    this.name = 'GeminiError';
  }
}

const RETRYABLE = new Set([429, 500, 502, 503, 504]);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/// Ceiling for one call including its retries, when the caller names none.
const DEFAULT_BUDGET_MS = 45_000;

interface PostOptions {
  /// Hard ceiling for the whole call, retries and backoff included.
  budgetMs?: number;
  /// Ceiling for a single attempt. Capped by whatever budget is left.
  attemptMs?: number;
}

/// POSTs to Gemini with retries on the transient statuses, inside a deadline.
///
/// The deadline is not politeness. A Gemini call with no `AbortSignal` hung long
/// enough to take the whole Edge Function worker down with
/// `546 WORKER_RESOURCE_LIMIT` — which reaches the student as a blank failure
/// with no message, because the worker died before it could write one. Bounding
/// every attempt turns that into a real error the caller can report.
///
/// Three attempts at most: a free-tier 429 is common enough that giving up on
/// the first would make ingestion feel broken.
/// Whatever Gemini sent back. The shape is theirs, not ours, so it stays loose
/// and every read of it is defensive.
// deno-lint-ignore no-explicit-any
type GeminiJson = any;

async function post(
  path: string,
  body: unknown,
  opts: PostOptions = {},
): Promise<GeminiJson> {
  const deadline = Date.now() + (opts.budgetMs ?? DEFAULT_BUDGET_MS);
  let last: GeminiError | null = null;

  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await sleep(600 * attempt);

    // Under a second left is not enough for a round trip; stop rather than
    // spend the remainder proving it.
    const remaining = deadline - Date.now();
    if (remaining < 1_000) break;
    const attemptMs = Math.min(opts.attemptMs ?? remaining, remaining);

    let response: Response;
    try {
      response = await fetch(`${base()}${path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey(),
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(attemptMs),
      });
    } catch (error) {
      const timedOut = (error as Error)?.name === 'TimeoutError';
      if (timedOut) {
        console.warn(`Gemini ${path} did not answer within ${attemptMs}ms`);
      }
      // Transport failure or timeout: no response at all, so retry it like a
      // 503 for as long as the budget allows.
      last = new GeminiError(
        503,
        timedOut
          ? 'The AI took too long to answer. Try again.'
          : 'Could not reach the AI service. Try again shortly.',
        0,
        String(error),
      );
      continue;
    }

    if (response.ok) {
      try {
        return await response.json();
      } catch (error) {
        throw new GeminiError(
          502,
          'The AI sent back something unreadable. Try again.',
          response.status,
          String(error),
        );
      }
    }

    const detail = (await response.text().catch(() => '')).slice(0, 800);
    const failure = new GeminiError(
      statusFor(response.status),
      messageFor(response.status),
      response.status,
      detail,
    );

    if (!RETRYABLE.has(response.status)) throw failure;
    last = failure;
  }

  throw last ??
    new GeminiError(503, 'The AI service is unavailable right now.', 0, '');
}

function statusFor(upstream: number): number {
  if (upstream === 429) return 429;
  if (upstream >= 500) return 503;
  return 502;
}

function messageFor(upstream: number): string {
  switch (upstream) {
    case 400:
      return 'The AI could not process that request.';
    case 401:
    case 403:
      return "This project's AI key was rejected. Check GEMINI_API_KEY.";
    case 404:
      return 'The AI model set for this project is unavailable.';
    case 413:
      return 'That file is too large for the AI to read in one go.';
    case 429:
      return 'The AI is busy right now. Try again in a minute.';
    default:
      return upstream >= 500
        ? 'The AI service is having trouble. Try again shortly.'
        : 'The AI could not process that request.';
  }
}

export type InputItem =
  | { type: 'text'; text: string }
  | { type: 'document'; data: string; mime_type: string };

export interface InteractOptions {
  input: string | InputItem[];
  systemInstruction?: string;
  /// JSON Schema for structured output. Omit for prose.
  schema?: GeminiJson;
  temperature?: number;
  /// Room for the answer. The model's ceiling is 65536; asking for less than the
  /// answer needs comes back as [finishReason] `MAX_TOKENS` and a cut-off reply.
  maxOutputTokens?: number;
  /// Ceiling for the whole call. A PDF transcription earns more of the worker's
  /// wall clock than a chat reply does.
  budgetMs?: number;
}

/// One generation call, returning the model's text.
export async function interact(opts: InteractOptions): Promise<string> {
  const parts = typeof opts.input === 'string'
    ? [{ text: opts.input }]
    : opts.input.map((item) =>
      item.type === 'text'
        ? { text: item.text }
        : { inline_data: { mime_type: item.mime_type, data: item.data } }
    );

  const generationConfig: Record<string, GeminiJson> = {};
  if (opts.temperature !== undefined) {
    generationConfig.temperature = opts.temperature;
  }
  if (opts.maxOutputTokens !== undefined) {
    generationConfig.maxOutputTokens = opts.maxOutputTokens;
  }
  if (opts.schema) {
    generationConfig.responseMimeType = 'application/json';
    generationConfig.responseSchema = opts.schema;
  }

  const body: Record<string, GeminiJson> = {
    contents: [{ role: 'user', parts }],
    // Nothing a student says needs to live in Google's history for us to answer
    // the next question, and this app keeps its own transcript in
    // `chat_messages`.
    ...(opts.systemInstruction
      ? { systemInstruction: { parts: [{ text: opts.systemInstruction }] } }
      : {}),
    ...(Object.keys(generationConfig).length > 0 ? { generationConfig } : {}),
  };

  let response: GeminiJson;
  try {
    response = await post(
      `/models/${textModel()}:generateContent`,
      body,
      { budgetMs: opts.budgetMs, attemptMs: opts.budgetMs },
    );
  } catch (error) {
    if (error instanceof GeminiError && error.upstreamStatus === 400) {
      // A 400 here is our bug, not the student's. Log what upstream actually
      // objected to so the dashboard says it plainly.
      console.error('Gemini rejected the request:', error.detail);
    }
    throw error;
  }

  return outputText(response);
}

/// Text of the first candidate, with the two silent-failure modes named.
function outputText(response: GeminiJson): string {
  const candidate = response?.candidates?.[0];
  const text = (candidate?.content?.parts ?? [])
    .filter((p: GeminiJson) => typeof p?.text === 'string')
    .map((p: GeminiJson) => p.text as string)
    .join('')
    .trim();
  if (text.length > 0) return text;

  const finish = candidate?.finishReason ?? response?.promptFeedback?.blockReason;
  if (finish === 'MAX_TOKENS') {
    // Measured on `gemini-3.6-flash`: reasoning tokens are drawn from the same
    // budget as the answer, so a thinking model can spend all of it and emit
    // nothing at all. Says which knob to turn rather than "try again".
    console.error(
      `Model ${textModel()} returned no text and finished on MAX_TOKENS. ` +
        'Usage: ' + JSON.stringify(response?.usageMetadata ?? {}),
    );
    throw new HttpError(
      502,
      'The AI ran out of room before it answered. Try a shorter question.',
    );
  }
  console.error(`Empty Gemini answer, finishReason=${finish}`);
  throw new HttpError(502, 'The AI returned an empty answer. Try again.');
}

/// Embeds [texts] in order, in batches.
///
/// No normalisation step on purpose: `match_material_chunks` ranks with `<=>`,
/// pgvector's **cosine** distance, which divides by both magnitudes itself. So
/// the manual L2 division that `gemini-embedding-001` documents for non-3072
/// dimensions would change nothing here.
export async function embedTexts(texts: string[]): Promise<number[][]> {
  if (texts.length === 0) return [];

  const model = embedModel();
  // Only `gemini-embedding-001` accepts task_type; `gemini-embedding-2` rejects
  // it outright, which is why the default path sends none and uses templates.
  const taskType = Deno.env.get('GEMINI_EMBED_TASK_TYPE')?.trim();
  const vectors: number[][] = [];

  for (let i = 0; i < texts.length; i += EMBED_BATCH) {
    const slice = texts.slice(i, i + EMBED_BATCH);
    // A measured batch answers in well under a second, so one still running at
    // 20s is stuck rather than busy.
    const response = await post(`/models/${model}:batchEmbedContents`, {
      requests: slice.map((text) => ({
        model: `models/${model}`,
        content: { parts: [{ text }] },
        output_dimensionality: EMBED_DIM,
        ...(taskType ? { taskType } : {}),
      })),
    }, { budgetMs: 40_000, attemptMs: 20_000 });

    const list = response?.embeddings;
    if (!Array.isArray(list) || list.length !== slice.length) {
      throw new HttpError(
        502,
        'The AI returned the wrong number of embeddings. Try again.',
      );
    }
    for (const entry of list) {
      const values = entry?.values;
      if (!Array.isArray(values) || values.length !== EMBED_DIM) {
        // A dimension mismatch would be stored happily by PostgREST and then
        // fail at query time, so it stops here where the cause is obvious.
        throw new HttpError(
          500,
          `The embedding model returned ${
            Array.isArray(values) ? values.length : 0
          } dimensions, but this project stores ${EMBED_DIM}.`,
        );
      }
      vectors.push(values as number[]);
    }
  }

  return vectors;
}

/// Document-side template for `gemini-embedding-2`, which has no `task_type`.
export function documentText(
  unitLabel: string | null | undefined,
  content: string,
): string {
  const label = unitLabel?.trim();
  return `title: ${label && label.length > 0 ? label : 'none'} | text: ${content}`;
}

/// Query-side template. Must stay paired with [documentText] — mixing task
/// templates between the two sides is what makes retrieval quietly worse.
export function queryText(question: string): string {
  return `task: search result | query: ${question}`;
}

/// Parses JSON that a model produced, tolerating the wrappers they add.
///
/// Structured output makes this unnecessary in theory; in practice a fenced
/// ```json block or a leading "Here you go:" shows up often enough that failing
/// the whole ingest over it would be the wrong trade.
// deno-lint-ignore no-explicit-any
export function parseJsonObject(raw: string): any {
  const trimmed = raw.trim().replace(/^```(?:json)?/i, '').replace(/```$/, '');
  try {
    return JSON.parse(trimmed);
  } catch (_) {
    const start = trimmed.indexOf('{');
    const end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(trimmed.slice(start, end + 1));
      } catch (_) {
        // Fall through to the shared failure below.
      }
    }
  }
  throw new HttpError(
    502,
    'The AI returned an unreadable result. Try again.',
  );
}
