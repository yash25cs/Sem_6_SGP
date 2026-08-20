/// CORS for the Edge Functions.
///
/// The Android app doesn't need this — `functions.invoke` from Dart isn't a
/// browser request and never sends a preflight. It's here because the same two
/// functions serve Flutter web the moment the app is built for it, and a
/// missing preflight there fails in a way that looks like the function is down.
export const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

/// Answers a preflight, or returns null when this isn't one.
export function preflight(req: Request): Response | null {
  if (req.method !== 'OPTIONS') return null;
  return new Response('ok', { headers: corsHeaders });
}
