import 'package:supabase_flutter/supabase_flutter.dart';

/// Shortcut to the initialised Supabase client.
///
/// Valid only after `Supabase.initialize` has completed in `main()`.
SupabaseClient get db => Supabase.instance.client;

/// The signed-in user's id, or null when signed out.
String? get currentUserId => db.auth.currentUser?.id;

/// Same, but throws instead of returning null — for repository writes that
/// have no meaning without a session.
String get requireUserId {
  final id = currentUserId;
  if (id == null) {
    throw StateError('No signed-in user. This call requires authentication.');
  }
  return id;
}

/// Turns Supabase/Postgres errors into something worth showing a student.
///
/// Postgres error codes we care about:
/// `23505` unique violation, `23503` FK violation, `42501` RLS denial.
String friendlyError(Object error) {
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login')) {
      return 'Wrong email or password.';
    }
    if (m.contains('already registered') || m.contains('already been')) {
      return 'That email already has an account. Try signing in.';
    }
    if (m.contains('email not confirmed')) {
      return 'Check your inbox and confirm your email first.';
    }
    if (m.contains('password')) return error.message;
    return error.message;
  }

  if (error is PostgrestException) {
    switch (error.code) {
      case '23505':
        return 'That already exists.';
      case '23503':
        return 'Something it depends on is missing. Try reloading.';
      case '42501':
        return 'You do not have access to that.';
      case 'PGRST116':
        return 'Not found.';
      // PostgREST could not find the function or table the app asked for. That
      // is never a data problem — it means the project is running an older set
      // of migrations than this build, so say the one thing that fixes it
      // instead of surfacing "in the schema cache" to a student.
      case 'PGRST202':
      case 'PGRST205':
        return 'This build needs a newer database. Apply '
            'supabase/all_migrations.sql in the Supabase SQL editor.';
    }
    return error.message;
  }

  if (error is StorageException) return error.message;

  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'The AI service is unavailable right now. Try again shortly.';
  }

  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return 'No internet connection.';
  }
  return 'Something went wrong. Please try again.';
}
