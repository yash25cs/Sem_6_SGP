# StudyTrail execution flow

This is the living trace of how the application runs. Update it whenever a
meaningful file, service boundary, or user flow changes.

## Runtime path

```text
Flutter app starts
  -> SupabaseConfig reads compile-time dart defines
  -> Supabase.initialize
  -> StudyTrailApp provides ThemeController and AuthStore
  -> RootFlow checks the current auth session
      -> signed out: Welcome -> Sign up / Log in
      -> signed in with no goal: Upload material -> Set target
      -> signed in with a goal: HomeShell
  -> HomeShell keeps five tabs alive with IndexedStack
      -> Home | Roadmap | Chat | Cards | Profile
```

## Data flow

```text
Screen widget
  -> Provider store (state/)
  -> Repository (data/repositories/)
  -> Supabase Flutter client
  -> Supabase Auth / PostgREST / Storage / RPC
  -> PostgreSQL with row-level security
```

Each signed-in user gets a fresh provider scope keyed by their user id. This
prevents cached study data from one account appearing for another account after
sign-out and sign-in.

## Important user journeys

### Account and onboarding

1. `WelcomeScreen` takes the student to `SignupScreen` or `LoginScreen`.
2. Supabase Auth creates/authenticates the user.
3. `handle_new_user()` creates matching `profiles` and `streaks` rows.
4. `UploadMaterialScreen` uploads a file to the private `materials` bucket or
   records a video link.
5. `SetTargetScreen` creates the active goal and its subjects.
6. `RootFlow` detects an existing goal on later launches and opens the app.

### Daily planning

1. Home loads profile, active goal, streak, today’s tasks, and subjects.
2. Completing a task writes `daily_tasks.done`.
3. The app logs activity and refreshes the streak.
4. Roadmap task changes recompute and persist the goal progress percentage.

### Learning tools

1. Flashcards read decks and cards from Supabase.
2. Grading a card calls the server-side `apply_sr_grade` RPC, which applies
   SM-2 scheduling.
3. Quiz choices are submitted to `finish_quiz_attempt`; correctness and XP are
   calculated on the server.
4. Chat sends the question to the `chat` Edge Function, which writes both the
   student's turn and the cited AI answer server-side; the app then reloads the
   thread.

### Material ingestion

1. The upload screen stores the file in the private `materials` bucket and
   inserts a `materials` row.
2. It then invokes `embed-material`, which downloads the file, splits it into
   sections, embeds each one, and writes `material_chunks`.
3. Chunks are inserted before `materials.status` becomes `embedded` — the
   `0009` status trigger rejects that status while a material has no chunks.
4. Video links are recorded but not read: `embed-material` refuses them and the
   screen says so.

## Backend boundaries

- Flutter may use only the Supabase URL and anon/publishable key.
- RLS limits every user-owned row to `auth.uid() = user_id`.
- The `materials` Storage bucket is private and scoped to `/{user-id}/...`.
- Gemini is called only from Supabase Edge Functions. Its API key is a function
  secret and never enters Flutter, requests, documentation, or version control.
- `embed-material` and `chat` act as the calling student: they forward the
  request's JWT to `supabase-js` and rely on RLS, so no service-role key exists
  in either function.

## Current implementation status — 21 August 2026

- Flutter UI and live-data wiring are implemented.
- Supabase schema, RLS, storage policies, seed data, and RPCs are applied,
  including `0008` and `0009` (verified on the hosted project: all seven reward
  RPCs resolve, and all 20 owner-scoped tables return nothing to an anon caller).
- The verified flashcard deck-count flow fetches the aggregated `deck_stats`
  view separately, then merges counts into deck rows in Flutter. PostgREST
  cannot embed an aggregated view because it has no foreign-key relationship.
- Material ingestion and cited AI chat are implemented as the `embed-material`
  and `chat` Edge Functions. Both are deployed and ACTIVE with `verify_jwt`,
  `GEMINI_API_KEY` is set, and both modules were confirmed to boot. The Gemini
  request path itself is still unexercised — it needs one signed-in upload.
- Flashcard, quiz, and roadmap generation and real-time study rooms are still
  pending Edge Functions (Phase C follow-up / Phase D).

## Update rule

After every meaningful change, append a dated entry to the **Change log** below
and update the affected path above. Also record any design or technical choice
in `DECISIONS.md`.

## Change log

| Date | Change | Files / area | Verification |
|---|---|---|---|
| 2026-08-13 | Created the living project-flow document. | Root documentation | Initial flow reconciled with Flutter and Supabase implementation. |
| 2026-08-13 | Fixed flashcard deck statistics query. | `studytrail_flutter/lib/data/repositories/flashcard_repository.dart` | `flutter analyze` and web build succeeded; live deck statistics query returned correct counts. |
| 2026-08-15 | Completed a read-only architecture and security review. | `REVIEW.md` | Confirmed reward-RPC, multi-step write, chat-delivery, and test-coverage risks from source inspection. |
| 2026-08-15 | Added a daily GitHub delivery plan and root repository ignore rules. | `DAILY_PLAN.md`, `.gitignore` | Ready for a clean source-control baseline; local credentials and generated files are excluded. |
| 2026-08-15 | Removed test-account defaults from the backend verification helper before source-control setup. | `supabase/verify_backend.py` | Script now requires supplied test credentials and reads local Supabase defines from an ignored file. |
| 2026-08-15 | Initialised Git and pushed the StudyTrail baseline to GitHub `main`. | Repository root | Commit `aaf625a` is now the shared baseline; future work follows `DAILY_PLAN.md`. |
| 2026-08-20 | Added the `embed-material` and `chat` Edge Functions and wired both client paths. | `supabase/functions/`, `supabase/config.toml`, `studytrail_flutter/lib/data/repositories/{material,chat}_repository.dart`, `lib/state/{onboarding,chat}_store.dart`, `lib/screens/upload_material_screen.dart`, `lib/models/study_material.dart` | `flutter analyze` clean and `flutter build apk --debug` succeeded. End-to-end ingestion and cited chat still need `GEMINI_API_KEY` and a `functions deploy`. |
| 2026-08-21 | Deployed both Edge Functions and applied migrations `0008`/`0009` on the hosted project. | Hosted Supabase project (no source change) | `functions list` shows both ACTIVE with `verify_jwt`; an anon-key POST to each returned the functions' own 401 JSON, proving the Deno modules load and `requireUser` runs. All seven reward RPCs plus `create_goal` resolve; 20/20 owner tables return no rows to an anon caller. The Gemini request path is still unexercised. |
