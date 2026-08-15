# StudyTrail

StudyTrail is a Flutter mobile exam-preparation planner for the SGP project.
It helps a student turn a syllabus into a roadmap, daily tasks, review cards,
quizzes, progress insights, and—once Phase C is deployed—cited AI help.

## Repository layout

```text
studytrail_flutter/  Flutter application
supabase/            PostgreSQL migrations, RLS, Storage policies, RPCs
SGP/                 Project proposal and academic context
studytrail_ui.html   Earlier browser UI prototype (kept unchanged)
FLOW.md              Runtime and data-flow documentation
DECISIONS.md         Architecture decisions and trade-offs
OWNERSHIP.md         Module ownership and security boundaries
REVIEW.md            Known review findings and recommended fixes
DAILY_PLAN.md        Small, pushable daily delivery plan
```

## Run the Flutter app

1. Create `studytrail_flutter/dart_define.json` locally. It is ignored by Git.

   ```json
   {
     "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
     "SUPABASE_ANON_KEY": "YOUR_PUBLISHABLE_KEY"
   }
   ```

2. Run on a connected Android device:

   ```powershell
   cd studytrail_flutter
   flutter pub get
   flutter run --dart-define-from-file=dart_define.json
   ```

For the complete Supabase setup, see [SETUP.md](SETUP.md) and
[supabase/README.md](supabase/README.md).

## Security rules

- Never commit `dart_define.json`, a Gemini key, or a Supabase `service_role`
  key.
- The Flutter app uses only the Supabase URL and anon/publishable key.
- All user data is protected with Supabase Row Level Security.
- Gemini calls belong only in authenticated Supabase Edge Functions.

## Development cadence

Follow [DAILY_PLAN.md](DAILY_PLAN.md): one focused change per day, one
descriptive commit, then update the flow and decision documentation when a
meaningful path or trade-off changes.
