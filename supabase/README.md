# StudyTrail — Supabase backend

Postgres schema, RLS, RPCs, Storage, and (later) Edge Functions for the
StudyTrail Flutter app. Nothing here touches `studytrail_ui.html` or the
existing Flutter UI.

```
supabase/
  config.toml          # local/dev project config
  migrations/          # ordered SQL — apply 0001 → 0009
  all_migrations.sql   # GENERATED: all nine concatenated, for the SQL editor
  functions/           # Edge Functions (Phase C)
```

## What's in the migrations

| File | Contents |
|---|---|
| `0001_init_schema.sql` | `vector` + `pgcrypto` extensions, 7 enums, `classes`, `profiles`, `goals`, `subjects`, `milestones`, `milestone_tasks`, `daily_tasks` |
| `0002_features.sql` | `materials` + `material_chunks` (pgvector 768, HNSW cosine), flashcards w/ SM-2, `deck_stats` view, quizzes, streaks/activity/badges/sessions, chat tables |
| `0003_rls.sql` | Owner-only RLS (`auth.uid() = user_id`) on all 20 user tables; owner-scoped `profiles`; read-all `badges`/`classes` |
| `0004_functions.sql` | `handle_new_user()` trigger, `match_material_chunks()` (RAG), `get_class_leaderboard()`, `apply_sr_grade()` (SM-2) |
| `0005_storage.sql` | Private `materials` bucket + `/{uid}/…` prefix policies |
| `0006_seed.sql` | 10 badges + one default class (`CE-A 2025`) |
| `0007_activity.sql` | `activity_log` roll-up, streak advance, `finish_quiz_attempt()` |
| `0008_rewards.sql` | **Security.** `app_private` schema, `xp_rules`, server-derived XP + badge evaluation, column-level privileges. Closes REVIEW.md P0 |
| `0009_atomicity.sql` | `create_goal()` (three writes → one transaction), retryable material ingest. Closes REVIEW.md P1 |

All files are idempotent — safe to re-run.

> **0008 is not optional.** It *drops* `award_xp`, `log_activity`, and
> `unlock_badge`, and the app no longer calls them. A project still on 0007 will
> 404 on `complete_task` / `record_focus_session` / `evaluate_badges`; a project
> on 0008 running an older build of the app will fail on the dropped RPCs. Apply
> it and ship the matching build together.


## Setup

### 1. Create the hosted project

Sign in at [supabase.com](https://supabase.com) → **New project** (free tier).
Pick a region close to you (e.g. `ap-south-1` Mumbai) for lowest mobile latency.
Save the database password.

### 2. Apply the schema

**Option A — Dashboard (no CLI needed, fastest):**
Open **SQL Editor** → paste the contents of `all_migrations.sql` → **Run**.

**Option B — CLI:**

```bash
npx --yes supabase@latest login
```

```bash
npx --yes supabase@latest link --project-ref YOUR_PROJECT_REF
```

```bash
npx --yes supabase@latest db push
```

### 3. Enable pgvector

`0001` runs `create extension if not exists vector`. If it errors on the free
tier, enable **vector** under **Database → Extensions** first, then re-run.

### 4. Auth settings

**Authentication → Providers → Email**: enabled. For development turn
**Confirm email** OFF so signups can log in immediately.

**Authentication → URL Configuration**: add redirect URL
`in.charusat.studytrail://login-callback` (needed for Google OAuth later).

### 5. Grab the keys

**Project Settings → API** → copy the **Project URL** and **anon public** key.
These go into the Flutter app via `--dart-define` (never committed):

```bash
flutter run -d 3C15A60003Y00000 --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
```

The `anon` key is safe to ship — RLS is what protects the data. The
**service_role** key must never appear in the app.

## Verifying RLS

After signing up on the device, in the SQL editor:

```sql
select id, email, full_name from profiles;
select * from streaks;
```

Both should show exactly one row, auto-created by the `handle_new_user`
trigger. Because the SQL editor runs as `postgres` it bypasses RLS; to verify
the policies themselves, query PostgREST with a real user JWT.

## Phase C — Edge Functions

Not yet written. When they land, the Gemini key is set as a function secret,
never in the app:

```bash
npx --yes supabase@latest secrets set GEMINI_API_KEY=your_key_here
```

## Regenerating `all_migrations.sql`

It is a plain concatenation of `migrations/*.sql` in filename order:

```bash
cat supabase/migrations/*.sql > supabase/all_migrations.sql
```

Verify it by byte count — the output must equal the sum of the parts, which is
what proves nothing was reordered or dropped:

```bash
python -c "import glob,os;p=sorted(glob.glob('supabase/migrations/0*.sql'));print(sum(os.path.getsize(f) for f in p), os.path.getsize('supabase/all_migrations.sql'))"
```
