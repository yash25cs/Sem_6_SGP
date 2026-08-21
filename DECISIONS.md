# StudyTrail decisions

This is the record of meaningful engineering decisions: what was chosen, why,
and the accepted trade-off. Update it whenever implementation changes involve a
non-trivial choice.

## Decision log

### D-001 — Keep the existing HTML prototype unchanged

- **Decision:** Preserve `studytrail_ui.html`; build the production frontend in
  `studytrail_flutter/` and backend assets in `supabase/`.
- **Why:** The HTML gallery is a useful visual reference and is a separate
  deliverable. Replacing it would risk losing approved UI work.
- **Trade-off:** Two UI representations must stay visually aligned.

### D-002 — Supabase for the mobile backend

- **Decision:** Use hosted Supabase for Auth, PostgreSQL, Storage, Realtime,
  Row Level Security, and Edge Functions.
- **Why:** It gives the Flutter app a direct, low-latency data layer without a
  separately hosted application server or mobile cold starts.
- **Trade-off:** Database schema and RLS policies must be designed carefully;
  PostgREST query limitations shape some repository queries.

### D-003 — Provider stores and repositories

- **Decision:** Screen widgets talk to `ChangeNotifier` stores; stores talk to
  repositories; repositories own Supabase calls.
- **Why:** It keeps rendering, async state, and persistence responsibilities
  separate and testable.
- **Trade-off:** More files than direct screen-to-database calls, but clearer
  error handling and less duplicated logic.

### D-004 — Scope data stores to the authenticated user

- **Decision:** Put the signed-in store scope above the Navigator and key it by
  user id.
- **Why:** Pushed pages need access to the same stores, while a user switch
  must discard the previous user’s cached data.
- **Trade-off:** Stores reload after sign-in/sign-out, intentionally favouring
  privacy and correctness over cache reuse.

### D-005 — Server-side scoring and spaced repetition

- **Decision:** Keep quiz scoring, XP awards, streak updates, and SM-2 card
  scheduling in Supabase RPCs.
- **Why:** A client can be altered; the backend is the authority for progress
  and rewards.
- **Trade-off:** The app needs network access to finalise those actions.

### D-006 — Gemini only in Edge Functions

- **Decision:** Use Gemini free-tier models from Supabase Edge Functions, not
  directly from Flutter.
- **Why:** The Gemini API key must remain secret and requests must derive the
  authenticated user from the Supabase JWT.
- **Trade-off:** AI features require Edge Function deployment and a Gemini key
  before they can be enabled.

### D-007 — Fetch flashcard statistics separately

- **Decision:** Query `flashcard_decks` and the aggregate `deck_stats` view
  separately, then merge the results in `FlashcardRepository`.
- **Why:** PostgREST cannot embed a `GROUP BY` view because it cannot infer a
  foreign-key relationship, producing `PGRST200`.
- **Trade-off:** One extra lightweight query avoids a schema workaround and
  keeps the statistics view secure with `security_invoker`.

### D-008 — Keep generated credentials out of source control

- **Decision:** Use gitignored `studytrail_flutter/dart_define.json` with
  `--dart-define-from-file` for the project URL and publishable key.
- **Why:** Developers can run the app without hardcoding environment-specific
  values in Dart files.
- **Trade-off:** Each development machine needs a local configuration file.

### D-009 — Use a clean baseline, then daily feature commits

- **Decision:** Create one honest baseline commit for the current working
  Flutter/Supabase implementation, then deliver one focused feature or fix per
  daily commit.
- **Why:** The workspace was developed before Git was initialised. Artificially
  splitting the existing snapshot into a fake history would make debugging and
  review less trustworthy.
- **Trade-off:** The first commit is larger, but every later change is small,
  reviewable, and traceable in `DAILY_PLAN.md`.

### D-010 — Do not publish test-account credentials

- **Decision:** The backend verification helper requires a test email and
  password at runtime instead of embedding a default test account.
- **Why:** Test credentials are still credentials; publishing them makes the
  live project unnecessarily vulnerable and creates cleanup work.
- **Trade-off:** Running the helper requires two explicit command arguments.

### D-011 — Ingestion and chat functions act as the caller, not as `service_role`

- **Decision:** `embed-material` and `chat` build their Supabase client from the
  request's own `Authorization` header, so RLS decides what they can read and
  write and `match_material_chunks` resolves `auth.uid()` to the real caller. No
  service-role key is used or stored for either function.
- **Why:** Every table they touch — `material_chunks`, `chat_messages`,
  `chat_citations` — is still owner-insertable, so the elevated key would buy
  nothing and would make a `user_id` in the request body meaningful, which is
  exactly what `OWNERSHIP.md` forbids.
- **Trade-off:** `generate-quiz` and `generate-roadmap` cannot follow this
  pattern: `0008_rewards.sql` revokes `insert` on their tables from
  `authenticated`, so they will need the service-role key and must verify the
  JWT themselves before writing.

### D-012 — Read PDFs with Gemini's document vision, not a Deno PDF parser

- **Decision:** `embed-material` sends the PDF to Gemini as a `document` input
  and asks for ordered, unit-labelled sections. `.txt` and `.md` are split
  locally with no model call.
- **Why:** Neither Deno nor Docker is installed on the development machine, so a
  bundled parser could not be run even once before deploying, and pdf.js under
  the Edge Runtime is a common source of crashes. Gemini also keeps headings and
  table text readable, which a raw text extractor usually loses.
- **Trade-off:** Ingestion costs one generation call per document and is capped
  at roughly 14 MB per PDF, since the file has to be inlined as base64. Large
  files will need the Gemini Files API later.

### D-013 — Request shape for Gemini's Interactions API degrades instead of failing

- **Decision:** `_shared/gemini.ts` reads the API base URL and model ids from
  function secrets, and on a `400` that names `response_format`,
  `system_instruction` or `generation_config` it retries with a simpler request
  — down to asking for JSON in words and parsing it defensively.
- **Why:** Google's own documentation disagrees with itself about the
  Interactions endpoint (`/v1beta` vs `/v1beta2`) and about whether
  `response_format` is an object or an array. None of it can be verified locally
  without Deno, so the first real test is a deploy against live infrastructure.
- **Trade-off:** More code than a single request shape, and a wrong guess costs
  an extra round trip before it corrects itself.
- **Superseded by D-014** on 2026-08-22, once the live deploy made guessing
  unnecessary.

### D-014 — One measured request shape, not a degradation ladder

- **Decision:** Supersedes D-013. `interact()` sends exactly one shape —
  `POST /v1beta/models/{model}:generateContent` with camelCase
  `systemInstruction` and `generationConfig` — and reads the answer from
  `candidates[0].content.parts[].text`. The retry ladder, the `prependText`
  fallback and the `generateContentFallback` path are deleted.
- **Why:** Deploying settled every question the docs left open. The shape above
  works with `systemInstruction`, with `responseMimeType` +`responseSchema`, and
  with an inlined PDF. `/v1beta/interactions` does answer, but it appears in no
  model's `supportedGenerationMethods` and it re-enables thinking;
  `/v1beta2/interactions` is a 404.
- **Trade-off:** A future API change now fails outright instead of limping. That
  is the better failure: the ladder turned a wrong guess into a slow, silent
  degradation, and a hard 400 with the response body logged is diagnosable in
  one deploy.

### D-015 — Every Gemini call runs under a deadline

- **Decision:** `post()` takes a `budgetMs` for the whole call and an
  `attemptMs` per try, and each `fetch` carries `AbortSignal.timeout`. Chat asks
  for 30 s, PDF sectioning 90 s, embeddings 40 s with 20 s attempts. A timeout
  surfaces as `503 "The AI took too long to answer. Try again."`.
- **Why:** An unbounded call hits the Edge Runtime's own ceiling instead —
  `HTTP 546 {"code":"WORKER_RESOURCE_LIMIT"}` — and the worker is killed before
  it can write an error, so the student sees a blank failure with nothing in the
  logs. This is the reported symptom "it takes so much time and tells me to try
  again."
- **Trade-off:** A genuinely slow-but-successful answer is now thrown away. With
  the model in D-016 answering in under a second, that trade is close to free.

### D-016 — `gemini-3.5-flash-lite` for text, because thinking models never answer

- **Decision:** `GEMINI_TEXT_MODEL` defaults to `gemini-3.5-flash-lite`.
- **Why:** Measured against this project's key on 2026-08-22, the previous
  default `gemini-3.7-flash` never answered inside 22 s — on
  `:generateContent` or `/v1beta/interactions`, thinking off or on. Worse,
  `gemini-3.6-flash` returned in 12.5 s with `finishReason: MAX_TOKENS` and
  **empty text**, because thinking spends the same token budget as the answer.
  `gemini-3.5-flash` answered in 923 ms but spent 39 of 40 tokens thinking.
  `-lite` does no thinking: 765 ms, and it still honours `systemInstruction`,
  JSON schemas, and inline PDFs. Ingesting a real PDF went from 124.7 s (which
  died on the worker limit) to 7.4 s; chat answers land in 5.4–7.5 s.
- **Trade-off:** A lite model reasons less well on a hard question. For a tutor
  quoting the student's own notes back at them the retrieved excerpts carry the
  reasoning, and an answer that arrives beats a better one that never does.
  Anything set in `GEMINI_TEXT_MODEL` needs re-timing before it is trusted —
  `outputText()` now names both silent failures (`MAX_TOKENS`, empty text) in
  the logs so a bad swap is obvious.

### D-017 — 20 materials per student, enforced in the store

- **Decision:** `OnboardingStore.maxMaterials = 20`, checked in
  `pickAndUpload` (an oversized multi-file pick is trimmed to the free slots
  rather than refused wholesale) and surfaced in both places a file can be
  added: the onboarding drop zone and the chat screen's materials sheet.
- **Why:** Cost and answer quality point the same way. Every file is read by
  Gemini once on upload and its chunks are searched on every question, and
  `match_material_chunks` returns the 6 best regardless of how many exist — so
  past a point more files stop improving answers and start diluting retrieval,
  with a stray page from a half-related PDF outranking the right unit.
- **Trade-off:** A student with more than a semester's material has to remove
  something. Enforced client-side, so it is a guardrail rather than a security
  boundary; the real limits are the bucket quota and RLS.

## Update rule

For each meaningful decision, add the next `D-###` item with the decision,
reason, and trade-off. If a decision is superseded, keep it and add a new entry
that links back to it.
