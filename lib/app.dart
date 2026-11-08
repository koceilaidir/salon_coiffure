import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/models.dart';
import 'data/repo.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';
import 'widgets/common.dart';

class SalonApp extends StatelessWidget {
  const SalonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestion du salon',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// Affiche l'écran de connexion ou l'application selon la session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) return const LoginScreen();
        return ProfileGate(key: ValueKey(session.user.id));
      },
    );
  }
}

/// Vérifie que le compte connecté a bien un profil (gérante ou propriétaire).
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  Profile? _profile;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await repo.myProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _error != null) {
      return Scaffold(body: LoadState(error: _error, onRetry: _load));
    }
    final p = _profile;
    if (p == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text("Ce compte n'est pas autorisé sur ce salon.",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Demandez au propriétaire de vous créer un accès.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: repo.signOut, child: const Text('Se déconnecter')),
          ]),
        ),
      );
    }
    return Shell(profile: p);
  }
}

/// Affiché si l'application a été lancée sans les clés Supabase.
class ConfigMissingApp extends StatelessWidget {
  const ConfigMissingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Configuration manquante.\n\n'
              'Lancez l\'application avec :\n'
              'flutter run -d windows --dart-define-from-file=env.json\n\n'
              '(voir README.md)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
