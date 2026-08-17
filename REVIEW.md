# StudyTrail review — 15 August 2026

This review is read-only: no production code was changed. Items are ordered by
impact and should be resolved before adding new user-facing features.

**Status lines added 17 August 2026** record what has since been fixed. Two
findings remain open: the chat tab still promises answers no Edge Function
generates (P1), and there are still no meaningful tests (P2).

## P0 — Prevent direct reward and badge manipulation

`award_xp(amount)`, `log_activity(minutes, tasks, xp)`, and
`unlock_badge(badge_key)` are callable RPCs with values supplied by the
authenticated client. Row Level Security ensures students can only change
their own data, but it does not stop a modified client from calling:

```text
award_xp(999999)
log_activity(999999, 999999, 999999)
unlock_badge('goal_crusher')
```

**Required change:** move privileged reward helpers behind a server-controlled
workflow. Revoke direct client execution where possible; calculate XP and
badges inside security-definer RPCs or Edge Functions that validate the action
and derive all rewards server-side. Do not accept raw XP or badge keys from a
client as proof of achievement.

**Relevant files:** `supabase/migrations/0007_activity.sql` lines 14, 63, 161.

**Status — fixed, `supabase/migrations/0008_rewards.sql`.** All three functions
are dropped from `public` and re-created in `app_private`, a schema PostgREST
does not expose and `anon`/`authenticated` have no `USAGE` on. XP is now derived
from rows the server can verify, and the finding turned out to be wider than
described: the same forgery was reachable straight through PostgREST
(`PATCH /profiles {xp:999999}`, `POST /activity_log`, `POST /user_badges`)
because no migration granted or revoked anything. Table and column privileges
are now narrowed — checked *before* RLS, so they can do what a policy cannot.
`ProfileRepository.addXp` and the old `unlockBadge` were deleted with them.

## P1 — Make multi-step writes atomic or recoverable

Several user actions span independent calls:

- Creating a goal first deactivates the old goal, then inserts the new goal,
  then inserts subjects.
- Completing a daily task updates the task, optionally updates a milestone,
  then logs activity.
- Uploading material writes Storage first, then the `materials` row.

A failure midway can leave a student with no active goal, a task completed in
the database but visually reverted, mismatched roadmap state, or an orphaned
Storage object.

**Required change:** use purpose-built RPCs/Edge Functions for transactional
database workflows. For Storage, implement compensating cleanup when the
database insert fails and retain a retryable `failed` status for ingestion.

**Relevant files:**

- `studytrail_flutter/lib/data/repositories/goal_repository.dart` line 35
- `studytrail_flutter/lib/state/home_store.dart` line 69
- `studytrail_flutter/lib/data/repositories/material_repository.dart`

**Status — fixed.** Goal creation is one `create_goal` RPC
(`0009_atomicity.sql`); task completion plus its milestone mirror and reward is
one `complete_task` RPC (`0008_rewards.sql`). Storage can't join a Postgres
transaction, so `uploadFile` now removes the object it just wrote if the
`materials` insert fails, and `deleteMaterial` drops the row *before* the object
— an orphaned object costs storage, an orphaned row breaks the screen.
`materials.status` is client-settable except for `embedded`, which a trigger
rejects unless embedded chunks exist, so a failed ingest is retryable.

## P1 — Do not promise AI answers before the AI service exists

The chat UI says Trail AI “Knows your syllabus” and claims it answers from
uploaded material. The current store persists only the student message; no
answer is generated until the Phase C Edge Function exists.

**Required change:** either finish the authenticated `chat` Edge Function
before exposing this tab, or label it “AI study assistant — coming soon” and
disable sending. When implemented, return an answer with citations and show a
clear retry state.

**Relevant files:** `studytrail_flutter/lib/screens/chat_screen.dart`,
`studytrail_flutter/lib/state/chat_store.dart`.

## P1 — Preserve failed flashcard reviews

The flashcard store advances to the next card before the server-side grade is
saved. If the request fails, the card remains due in the database but disappears
from the current session.

**Required change:** keep a pending-review queue, restore the card on failure,
and offer retry. Alternatively wait for a successful grade before advancing.

**Relevant file:** `studytrail_flutter/lib/state/flashcard_store.dart` line 59.

**Status — fixed.** The advance stays optimistic, but a failed grade puts the
card back on the end of the queue and decrements the session counter, so it
comes round again instead of disappearing. Re-queued at the end rather than at
its old index: by the time the failure returns the student may have graded
further cards, and yanking the view backwards would be worse than the wait.

## P2 — Add parent-ownership integrity checks

Most policies validate only `auth.uid() = user_id`. A modified client can still
reference another user’s known parent UUID (for example a goal, deck, or quiz)
while supplying its own `user_id`. This does not normally expose rows, but it
allows invalid cross-user relationships and complicates future joins.

**Required change:** enforce matching ownership with insert/update policies or
prefer RPCs that derive parent ids from rows already owned by the caller.

**Relevant files:** `supabase/migrations/0001_init_schema.sql`,
`supabase/migrations/0002_features.sql`, `supabase/migrations/0003_rls.sql`.

**Status — largely fixed, by removing the write rather than policing it.** The
paths that cross a parent boundary now go through RPCs that check it:
`record_focus_session` rejects a subject that isn't the caller's,
`finish_quiz_attempt` matches every question to the caller, `complete_task`
derives the milestone task from the row it just read, `create_goal` derives
`goal_id` from the goal it just inserted. Everything else was narrowed instead:
roadmap, quiz, and quiz-question rows are no longer client-insertable at all
(they're generated artefacts), so there is nothing left to point at a stranger's
parent. Chat threads/messages are the remaining gap and close in Phase C, when
the `chat` function becomes the only writer.

## P2 — Make XP semantics consistent

Quiz completion invokes `award_xp`, but Pomodoro and flashcard actions only
write `activity_log.xp_earned`. The progress view can therefore show earned XP
that is absent from the student profile and leaderboard.

**Required change:** choose one server-side reward path for every activity and
define the XP rules in one documented location.

**Relevant files:** `supabase/migrations/0007_activity.sql`,
`studytrail_flutter/lib/state/pomodoro_store.dart`,
`studytrail_flutter/lib/state/flashcard_store.dart`.

**Status — fixed, `0008_rewards.sql`.** Every reward path now calls both
`log_activity` and `award_xp`, so `activity_log.xp_earned` and `profiles.xp` can
no longer disagree. The amounts live in one readable table, `xp_rules`, which is
also the ceiling applied to the client-writable `quiz_questions.xp_reward`. The
four `logActivity(xp: …)` calls the stores used to make are gone.

## P2 — Establish meaningful automated tests and source control

There is one smoke widget test. No repository, store, migration/RLS, or
critical-flow tests protect the project. The workspace also has no Git
repository, so changes cannot be reviewed, restored, or attributed safely.

**Required change:** initialise Git, add a remote, and introduce tests for
signup bootstrap, RLS isolation, XP restrictions, goal creation rollback,
flashcard grading failure, and the onboarding-to-home path.

**Relevant file:** `studytrail_flutter/test/widget_test.dart` line 8.

**Status — half done, and the open half.** Git is initialised with a GitHub
remote (three commits as of the baseline push). The tests are not written; the
smoke test is still the only one. This is the next piece of work, and the
reward RPCs added in 0008 are the first thing that needs covering — they are
the code most likely to be attacked and the code no test currently touches.

## Suggested delivery order

1. Fix P0 reward/badge RPC access and unify XP.
2. Add transactional workflows for goals and task completion.
3. Add tests plus Git before Phase C changes.
4. Implement Edge Functions for material ingestion and AI chat.
5. Build the real-time buddy room only after the core flows are stable.
