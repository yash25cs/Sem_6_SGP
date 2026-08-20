import { HttpError } from './supa.ts';

/// Thin client for the two Gemini surfaces these functions need.
///
/// Verified against the live docs on 2026-08-20, and it is worth writing down
/// because older samples look nothing like this:
///
///   * Generation is `POST /v1beta/interactions` with the model **in the body**.
///     `models/{model}:generateContent` is no longer documented at all. The
///     answer is not at `candidates[0]...` — the response is
///     `{id, status, steps[]}` and the text lives on the last step whose `type`
///     is `model_output`, at `content[0].text`.
///   * Embeddings are unchanged: `POST /v1beta/models/{model}:embedContent`
///     (and `:batchEmbedContents`), vector at `embeddings[n].values`.
///   * `gemini-embedding-2` rejects `task_type` and expects task *templates* in
///     the text instead — see [documentText] / [queryText].
///
/// The docs also contradict themselves in two places: the migration guide says
/// `/v1beta2/interactions` and a `response_format` **array**, while the
/// text-generation, structured-output and document-processing pages all say
/// `/v1beta/interactions` and a `response_format` **object**. So the base URL is
/// an env var, and [interact] degrades through the other shapes on a 400 that
/// names the field rather than failing the whole ingest over a doc discrepancy.

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
  return env('GEMINI_TEXT_MODEL', 'gemini-3.7-flash');
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

/// POSTs to Gemini with retries on the transient statuses.
///
/// Three attempts total: a free-tier 429 is common enough that giving up on the
/// first one would make ingestion feel broken, and the whole ladder costs under
/// two seconds of the function's wall clock.
// deno-lint-ignore no-explicit-any
async function post(path: string, body: unknown): Promise<any> {
  let last: GeminiError | null = null;

  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await sleep(600 * attempt);

    let response: Response;
    try {
      response = await fetch(`${base()}${path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey(),
        },
        body: JSON.stringify(body),
      });
    } catch (error) {
      // Transport failure: no response at all, so retry it like a 503.
      last = new GeminiError(
        503,
        'Could not reach the AI service. Try again shortly.',
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
  // deno-lint-ignore no-explicit-any
  schema?: any;
  temperature?: number;
}

/// One generation call, returning the model's text.
///
/// `store: false` on every request: Interactions keep conversation state
/// server-side by default, and this app already keeps its own transcript in
/// `chat_messages`. Nothing a student says needs to live in Google's history
/// for us to answer the next question.
export async function interact(opts: InteractOptions): Promise<string> {
  // Degradations, each triggered only by a 400 that names the field it's about,
  // and each strictly less capable than the last. See the note at the top of
  // this file for why a documented request shape needs a ladder at all.
  let schemaAsArray = false;
  let schemaInPrompt = false;
  let foldSystemIntoInput = false;
  let dropGenerationConfig = false;

  for (let attempt = 0; attempt < 5; attempt++) {
    // With no `response_format`, the schema has to travel as instruction text —
    // `parseJsonObject` is what makes that survivable.
    const instruction = [
      opts.systemInstruction,
      schemaInPrompt && opts.schema
        ? `Reply with JSON matching this schema and nothing else — no prose, no code fences:\n${
          JSON.stringify(opts.schema)
        }`
        : null,
    ].filter(Boolean).join('\n\n');

    const input = foldSystemIntoInput && instruction
      ? prependText(opts.input, `${instruction}\n\n`)
      : opts.input;

    // deno-lint-ignore no-explicit-any
    const body: Record<string, any> = {
      model: textModel(),
      input,
      store: false,
    };
    if (instruction && !foldSystemIntoInput) {
      body.system_instruction = instruction;
    }
    if (opts.temperature !== undefined && !dropGenerationConfig) {
      body.generation_config = { temperature: opts.temperature };
    }
    if (opts.schema && !schemaInPrompt) {
      const format = {
        type: 'text',
        mime_type: 'application/json',
        schema: opts.schema,
      };
      body.response_format = schemaAsArray ? [format] : format;
    }

    try {
      return outputText(await post('/interactions', body));
    } catch (error) {
      if (!(error instanceof GeminiError)) throw error;

      if (error.upstreamStatus === 400) {
        if (opts.schema && !schemaInPrompt && /response_format/i.test(error.detail)) {
          // Object form rejected → array form → give up on the field entirely
          // and ask for JSON in words.
          if (schemaAsArray) {
            schemaInPrompt = true;
          } else {
            schemaAsArray = true;
          }
          continue;
        }
        if (
          instruction && !foldSystemIntoInput &&
          /system_instruction/i.test(error.detail)
        ) {
          foldSystemIntoInput = true;
          continue;
        }
        if (
          body.generation_config && !dropGenerationConfig &&
          /generation_config|temperature/i.test(error.detail)
        ) {
          dropGenerationConfig = true;
          continue;
        }
        // A 400 we don't recognise is our bug, not the student's. Log the
        // upstream detail so the dashboard says what was actually wrong.
        console.error('Gemini rejected the request:', error.detail);
        throw error;
      }

      if (error.upstreamStatus === 404) {
        // Either the endpoint or the model. Try the pre-Interactions surface
        // once before giving up — some keys and models are still served there.
        console.warn('Interactions 404; falling back to generateContent');
        return await generateContentFallback(opts);
      }

      throw error;
    }
  }

  throw new HttpError(502, 'The AI could not process that request.');
}

function prependText(
  input: string | InputItem[],
  prefix: string,
): string | InputItem[] {
  if (typeof input === 'string') return prefix + input;
  return [{ type: 'text', text: prefix }, ...input];
}

/// Text of the last `model_output` step.
// deno-lint-ignore no-explicit-any
function outputText(response: any): string {
  const steps = Array.isArray(response?.steps) ? response.steps : [];
  for (let i = steps.length - 1; i >= 0; i--) {
    if (steps[i]?.type !== 'model_output') continue;
    const content = Array.isArray(steps[i]?.content) ? steps[i].content : [];
    const text = content
      // deno-lint-ignore no-explicit-any
      .filter((c: any) => typeof c?.text === 'string')
      // deno-lint-ignore no-explicit-any
      .map((c: any) => c.text as string)
      .join('')
      .trim();
    if (text.length > 0) return text;
  }
  throw new HttpError(502, 'The AI returned an empty answer. Try again.');
}

/// The classic `:generateContent` shape, for keys or models still served there.
async function generateContentFallback(opts: InteractOptions): Promise<string> {
  const parts = typeof opts.input === 'string'
    ? [{ text: opts.input }]
    : opts.input.map((item) =>
      item.type === 'text'
        ? { text: item.text }
        : { inline_data: { mime_type: item.mime_type, data: item.data } }
    );

  // deno-lint-ignore no-explicit-any
  const body: Record<string, any> = {
    contents: [{ role: 'user', parts }],
  };
  if (opts.systemInstruction) {
    body.system_instruction = { parts: [{ text: opts.systemInstruction }] };
  }
  // deno-lint-ignore no-explicit-any
  const generationConfig: Record<string, any> = {};
  if (opts.temperature !== undefined) {
    generationConfig.temperature = opts.temperature;
  }
  if (opts.schema) {
    generationConfig.responseMimeType = 'application/json';
    generationConfig.responseSchema = opts.schema;
  }
  if (Object.keys(generationConfig).length > 0) {
    body.generationConfig = generationConfig;
  }

  const response = await post(
    `/models/${textModel()}:generateContent`,
    body,
  );
  const text = (response?.candidates?.[0]?.content?.parts ?? [])
    // deno-lint-ignore no-explicit-any
    .filter((p: any) => typeof p?.text === 'string')
    // deno-lint-ignore no-explicit-any
    .map((p: any) => p.text as string)
    .join('')
    .trim();
  if (!text) {
    throw new HttpError(502, 'The AI returned an empty answer. Try again.');
  }
  return text;
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
    const response = await post(`/models/${model}:batchEmbedContents`, {
      requests: slice.map((text) => ({
        model: `models/${model}`,
        content: { parts: [{ text }] },
        output_dimensionality: EMBED_DIM,
        ...(taskType ? { taskType } : {}),
      })),
    });

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
