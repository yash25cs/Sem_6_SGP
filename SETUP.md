# StudyTrail — setup

What you need to do once, to get the app talking to a real backend.

## 1. Create a Supabase project (free)

1. Sign in at [supabase.com](https://supabase.com) → **New project**.
2. Region: pick the closest one (e.g. **South Asia (Mumbai)**) — this is the
   single biggest factor in how snappy the app feels on your phone.
3. Set a database password and save it somewhere.

Wait ~2 minutes for provisioning.

## 2. Apply the database schema

Open **SQL Editor** → **New query** → paste the entire contents of
`supabase/all_migrations.sql` → **Run**.

You should see `Success. No rows returned`. Verify under **Table Editor**:
24 tables including `profiles`, `goals`, `material_chunks`, `flashcards`, and
`xp_rules` (the XP amounts — if that one is missing, the security migration
didn't run and the app's reward RPCs will 404).

If the `vector` extension errors, enable it first under
**Database → Extensions** (search "vector"), then re-run. The script is
idempotent, so re-running is safe.

If the storage section errors with *"must be owner of table objects"*, create
the bucket manually: **Storage → New bucket** → name `materials`, **not**
public → then add the four policies from `supabase/migrations/0005_storage.sql`
under **Storage → Policies**.

## 3. Turn off email confirmation (for development)

**Authentication → Sign In / Providers → Email** → turn **Confirm email**
OFF. Otherwise every test signup waits on an inbox round-trip.

## 4. Copy your keys

**Project Settings → API Keys**:

- **Project URL** — `https://xxxxxxxx.supabase.co`
- **anon / publishable key** — starts with `eyJ` or `sb_publishable_`

The anon key is safe to put in the app; RLS is what protects the data. The
**service_role** key must never go in the app.

## 5. Run the app

```bash
flutter run -d 3C15A60003Y00000 --dart-define=SUPABASE_URL=https://YOUR.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_KEY
```

Running without these shows a "Backend not configured" screen instead of
crashing.

To avoid retyping, put them in `studytrail_flutter/dart_define.json`:

```json
{
  "SUPABASE_URL": "https://YOUR.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_KEY"
}
```

```bash
flutter run -d 3C15A60003Y00000 --dart-define-from-file=dart_define.json
```

That file is gitignored — keep it off version control.

## 6. Verify it worked

1. Tap through Welcome → **Create account** with a real-looking email.
2. In the dashboard, **Authentication → Users** shows the new user.
3. **Table Editor → profiles** shows a matching row — created automatically by
   the `handle_new_user` trigger, along with a row in `streaks`.
4. Force-quit the app and reopen it: you should still be signed in.

## Notes

- **Onboarding order changed.** Auth now comes first (welcome → signup →
  upload → set target), because uploads and goals both need a `user_id`.
  A returning account that already has a goal skips straight to the home shell.
- **Google sign-in** additionally needs the provider enabled in the dashboard
  and `in.charusat.studytrail://login-callback` added under
  **Authentication → URL Configuration**. The Android intent-filter is already
  in place.
- **Gemini API key** is what turns on material ingestion and AI chat. Get one
  from [aistudio.google.com](https://aistudio.google.com) → **Get API key**, then
  set it as a Supabase *function* secret — never a `--dart-define`, so it can't
  ship in the APK:

  ```bash
  npx --yes supabase@latest secrets set GEMINI_API_KEY=your_key_here --project-ref tmakrbqggezkxtygythc
  ```

  Then deploy the two functions that read it (`--use-api` bundles server-side, so
  no Docker or Deno is needed locally):

  ```bash
  npx --yes supabase@latest functions deploy embed-material chat --use-api --project-ref tmakrbqggezkxtygythc
  ```

  Until both are done, uploads land on **Failed** with a readable reason and Chat
  keeps the question without answering. `supabase/README.md` lists the optional
  model/base-URL overrides.
