import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../supabase_client.dart';

/// Wraps Supabase Auth. The `profiles` and `streaks` rows are created
/// server-side by the `handle_new_user` trigger, so signup needs no follow-up
/// insert here.
class AuthRepository {
  const AuthRepository();

  /// Emits on sign-in, sign-out, and token refresh. Drives the auth gate.
  Stream<AuthState> get authStateChanges => db.auth.onAuthStateChange;

  Session? get session => db.auth.currentSession;

  User? get user => db.auth.currentUser;

  bool get isSignedIn => session != null;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) {
    return db.auth.signUp(
      email: email.trim(),
      password: password,
      // Read by handle_new_user() to seed profiles.full_name.
      data: {'full_name': fullName.trim()},
      emailRedirectTo: SupabaseConfig.oauthRedirect,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return db.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Opens the system browser; completion arrives via the deep link and shows
  /// up on [authStateChanges], not as a return value.
  Future<bool> signInWithGoogle() {
    return db.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseConfig.oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> sendPasswordReset(String email) {
    return db.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: SupabaseConfig.oauthRedirect,
    );
  }

  Future<void> signOut() => db.auth.signOut();
}
