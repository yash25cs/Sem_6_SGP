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

## Update rule

For each meaningful decision, add the next `D-###` item with the decision,
reason, and trade-off. If a decision is superseded, keep it and add a new entry
that links back to it.
