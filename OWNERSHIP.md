# Own the mental model — StudyTrail

Documentation supports understanding; it does not replace it. Before accepting
or changing any feature, be able to explain the path below in your own words.

## What each area owns

| Area | Owns | Must not own |
|---|---|---|
| `studytrail_flutter/lib/screens/` | Visual layout, local interaction, navigation | Raw database queries or secret handling |
| `studytrail_flutter/lib/state/` | Loading, mutation, error state for a feature | Widget styling or SQL |
| `studytrail_flutter/lib/data/repositories/` | Supabase reads, writes, RPC calls, data mapping | UI state or API secrets |
| `studytrail_flutter/lib/models/` | Typed app data and database mapping | Network calls |
| `studytrail_flutter/lib/theme/` and `lib/widgets/` | Shared visual language and reusable UI | Feature-specific persistence |
| `supabase/migrations/` | Database tables, RLS, RPCs, triggers, storage policy | Flutter UI behaviour |
| `supabase/functions/` | Server-side AI and privileged backend workflows | Client secrets or user-id values supplied by the request body |

## The questions to answer before a change

1. Which user action starts this flow?
2. Which screen calls which store method?
3. Which repository or Edge Function owns the server call?
4. Which table, Storage object, or RPC changes?
5. How does RLS ensure the caller can only touch their own data?
6. What loading, empty, and error state does the student see?
7. How will the change be verified?

## Non-negotiable security model

- The app can contain the Supabase URL and anon/publishable key only.
- Never place a Supabase `service_role` key in Flutter, a commit, or a client
  request.
- Never place `GEMINI_API_KEY` in Flutter. It belongs only in Supabase Edge
  Function secrets.
- Edge Functions identify the caller from their JWT, never from a `user_id`
  field received in JSON.
- RLS is the data boundary. Do not disable it just to make a query work.

## Current mental model to own

```text
Student taps a feature
  -> Screen presents the interaction
  -> Store tracks loading/error and calls a repository
  -> Repository uses authenticated Supabase client
  -> RLS validates the user and PostgreSQL updates data
  -> Store refreshes state
  -> Screen rebuilds with the result
```

For AI features, insert an Edge Function between the repository and the
database. That function validates the JWT, retrieves only the caller’s RAG
chunks, uses the server-side Gemini secret, and saves a traceable response.

## Update rule

When a new module is introduced, add it to the ownership table. When a flow is
changed, update the mental model and cross-check `FLOW.md` and `DECISIONS.md`.
