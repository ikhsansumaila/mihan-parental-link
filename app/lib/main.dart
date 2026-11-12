import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'platform/enforcer.dart';
import 'ui/auth_page.dart';
import 'ui/child/child_home.dart';
import 'ui/child/pair_page.dart';
import 'ui/parent/parent_home.dart';
import 'ui/role_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Object? initError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    initError = e;
  }
  runApp(MihanParentalLinkApp(initError: initError));
}

class MihanParentalLinkApp extends StatelessWidget {
  final Object? initError;
  const MihanParentalLinkApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D6B), brightness: b),
          useMaterial3: true,
          cardTheme: const CardThemeData(margin: EdgeInsets.zero),
        );
    return MaterialApp(
      title: 'Mihan Parental Link',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: initError != null ? _SetupMissing(error: initError!) : const RootGate(),
    );
  }
}

/// Menentukan layar awal:
/// - Android & sudah dipasangkan sebagai HP anak → ChildHome
/// - Login sebagai orang tua (bukan anonim) → ParentHome
/// - Web → login orang tua
/// - Selain itu → pilih peran
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late Future<String?> _deviceId = Enforcer.deviceId();
  String? _role; // dipilih di RolePage

  void _refresh() => setState(() => _deviceId = Enforcer.deviceId());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _deviceId,
      builder: (context, devSnap) {
        if (devSnap.connectionState != ConnectionState.done) return const _Splash();
        final deviceId = devSnap.data;
        if (deviceId != null) return ChildHome(deviceId: deviceId, onUnpaired: _refresh);

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const _Splash();
            final user = snap.data;
            if (user != null && !user.isAnonymous) return ParentHome(user: user);
            if (kIsWeb || _role == 'parent') {
              return AuthPage(onBack: kIsWeb ? null : () => setState(() => _role = null));
            }
            if (_role == 'child') {
              return PairPage(onPaired: _refresh, onBack: () => setState(() => _role = null));
            }
            return RolePage(onPick: (r) => setState(() => _role = r));
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _SetupMissing extends StatelessWidget {
  final Object error;
  const _SetupMissing({required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 56),
                const SizedBox(height: 16),
                Text('Firebase belum dikonfigurasi', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text('Jalankan `flutterfire configure --platforms=android,web` di folder app/, '
                    'lalu build ulang. Lihat README.md.'),
                const SizedBox(height: 12),
                Text('$error', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        ),
      );
}
