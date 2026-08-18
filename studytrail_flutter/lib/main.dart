import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/local_prefs.dart';
import 'data/repositories/goal_repository.dart';
import 'state/stores.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/timer_banner.dart';
import 'shell.dart';
import 'screens/welcome_screen.dart';
import 'screens/upload_material_screen.dart';
import 'screens/set_target_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.apiKey,
    );
  }

  runApp(const StudyTrailApp());
}

class StudyTrailApp extends StatelessWidget {
  const StudyTrailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        if (SupabaseConfig.isConfigured)
          ChangeNotifierProvider(create: (_) => AuthStore()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'StudyTrail',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          // `builder` wraps the Navigator, so the data stores end up *above*
          // every route — including the ones pushed on top of the shell
          // (Pomodoro, Quiz, Achievements, Analytics). A scope placed inside
          // `home:` would only cover the shell's own subtree, and those pushed
          // screens would fail to find their store.
          //
          // [PomodoroOverlay] sits inside the scope (it reads `PomodoroStore`)
          // and outside the navigator, which is what lets a running focus timer
          // stay on screen across every route.
          builder: (context, navigator) => SupabaseConfig.isConfigured
              ? _SignedInScope(
                  userId: context.select<AuthStore, String?>((a) => a.user?.id),
                  child: PomodoroOverlay(
                    child: navigator ?? const SizedBox.shrink(),
                  ),
                )
              : (navigator ?? const SizedBox.shrink()),
          home: SupabaseConfig.isConfigured
              ? const RootFlow()
              : const _ConfigErrorScreen(),
        ),
      ),
    );
  }
}

/// Top-level flow. Auth comes first because uploads and goals both need a
/// `user_id`: welcome → signup/login → upload → set target → app.
/// The welcome tour is first-install only; after that a signed-out launch opens
/// straight on sign-in. A returning user with a goal already saved lands in the
/// shell.
enum _Stage { welcome, login, signup, upload, target, app }

class RootFlow extends StatefulWidget {
  const RootFlow({super.key});

  @override
  State<RootFlow> createState() => _RootFlowState();
}

class _RootFlowState extends State<RootFlow> {
  _Stage _stage = _Stage.welcome;

  /// True while deciding where to land — reading the first-run flag when signed
  /// out, or checking for an existing goal when signed in. Starts true so the
  /// first frame is the splash instead of a flash of the welcome tour.
  bool _resolving = true;
  AuthStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    // The store scope is keyed on the user id, so signing in rebuilds this
    // widget from scratch.
    _lastStatus = context.read<AuthStore>().status;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// Picks the entry stage on cold start.
  Future<void> _bootstrap() async {
    if (context.read<AuthStore>().status == AuthStatus.signedIn) {
      await _resolveEntryStage();
      return;
    }
    final seenWelcome = await LocalPrefs.hasSeenWelcome();
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _stage = seenWelcome ? _Stage.login : _Stage.welcome;
    });
  }

  /// Leaving the tour, whether finished or skipped. The flag write isn't
  /// awaited: it's a local preference, and holding up navigation on disk I/O
  /// would be a worse trade than the tour reappearing if the write loses a race
  /// with the process dying.
  void _finishWelcome() {
    LocalPrefs.setSeenWelcome();
    _go(_Stage.signup);
  }

  void _go(_Stage s) {
    if (!mounted) return;
    setState(() => _stage = s);
  }

  /// After sign-in, skip onboarding when the account already has a goal.
  Future<void> _resolveEntryStage() async {
    setState(() => _resolving = true);
    var next = _Stage.upload;
    try {
      if (await const GoalRepository().hasAnyGoal()) next = _Stage.app;
    } catch (_) {
      // Offline or schema not applied yet — onboarding is the safe landing.
    }
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _stage = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();

    // React to session changes: sign-in decides where to land, sign-out
    // returns to sign-in rather than the tour, which is install-scoped.
    if (auth.status != _lastStatus) {
      final previous = _lastStatus;
      _lastStatus = auth.status;

      if (auth.status == AuthStatus.signedIn) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _resolveEntryStage());
      } else if (auth.status == AuthStatus.signedOut &&
          previous == AuthStatus.signedIn) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _go(_Stage.login));
      }
    }

    if (_resolving) return const _SplashScreen();

    // Guard: never show post-auth stages without a session. Sign-in, not the
    // tour, is the landing here — reaching these stages means the app has
    // already been used.
    if (!auth.isSignedIn &&
        (_stage == _Stage.upload ||
            _stage == _Stage.target ||
            _stage == _Stage.app)) {
      _stage = _Stage.login;
    }

    final child = switch (_stage) {
      _Stage.welcome => WelcomeScreen(onDone: _finishWelcome),
      _Stage.login => LoginScreen(
          onSignIn: () {},
          onSignUp: () => _go(_Stage.signup),
        ),
      _Stage.signup => SignupScreen(
          onCreate: () {},
          onSignIn: () => _go(_Stage.login),
        ),
      _Stage.upload => UploadMaterialScreen(
          onNext: () => _go(_Stage.target),
          // Upload is the first step *after* auth, so there is no earlier
          // onboarding stage to return to — the tour is install-scoped and
          // signup already happened. Back therefore means "leave this
          // account's onboarding", and the sign-out listener above lands on
          // the sign-in screen.
          onBack: () => auth.signOut(),
        ),
      _Stage.target => SetTargetScreen(
          onDone: () => _go(_Stage.app),
          onBack: () => _go(_Stage.upload),
        ),
      _Stage.app => const HomeShell(),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_stage), child: child),
    );
  }
}

/// Holds the data stores for the signed-in session.
///
/// Keyed on [userId] so signing out and back in as someone else rebuilds every
/// store from scratch — app-scoped stores would otherwise hand the next
/// student the previous one's cached rows. Null (signed out) is a distinct key,
/// so the stores are also dropped on sign-out rather than lingering.
class _SignedInScope extends StatelessWidget {
  const _SignedInScope({required this.userId, required this.child});

  final String? userId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      key: ValueKey(userId),
      // Lazy by default: each store is constructed the first time a screen
      // reads it, so opening Home doesn't fetch quizzes and flashcards too.
      providers: [
        ChangeNotifierProvider(create: (_) => HomeStore()),
        ChangeNotifierProvider(create: (_) => RoadmapStore()),
        ChangeNotifierProvider(create: (_) => FlashcardStore()),
        ChangeNotifierProvider(create: (_) => QuizStore()),
        ChangeNotifierProvider(create: (_) => ChatStore()),
        ChangeNotifierProvider(create: (_) => ProgressStore()),
        ChangeNotifierProvider(create: (_) => GamificationStore()),
        ChangeNotifierProvider(create: (_) => ProfileStore()),
        ChangeNotifierProvider(create: (_) => PomodoroStore()),
        ChangeNotifierProvider(create: (_) => OnboardingStore()),
      ],
      child: child,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(child: CircularProgressIndicator(color: p.primary)),
    );
  }
}

/// Shown when the app was built without Supabase credentials, so the failure
/// is legible instead of a crash on first query.
class _ConfigErrorScreen extends StatelessWidget {
  const _ConfigErrorScreen();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: p.error, size: 44),
            const SizedBox(height: 16),
            Text('Backend not configured',
                style: TextStyle(
                    color: p.ink, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(SupabaseConfig.missingMessage,
                style: TextStyle(color: p.ink2, fontSize: 14, height: 1.5)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.line, width: 1.2),
              ),
              child: SelectableText(
                'flutter run \\\n'
                '  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \\\n'
                '  --dart-define=SUPABASE_ANON_KEY=eyJ...',
                style: TextStyle(
                    color: p.ink2, fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
