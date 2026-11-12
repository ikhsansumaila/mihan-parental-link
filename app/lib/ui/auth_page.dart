import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthPage extends StatefulWidget {
  final VoidCallback? onBack;
  const AuthPage({super.key, this.onBack});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = FirebaseAuth.instance;
    try {
      // Kalau sebelumnya login anonim (mis. sempat pilih mode anak), keluar dulu.
      if (auth.currentUser?.isAnonymous == true) await auth.signOut();
      if (_register) {
        await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Isi email dulu.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link reset password sudah dikirim ke email.')));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _msg(e));
    }
  }

  String _msg(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'Format email tidak valid.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email atau password salah.',
        'email-already-in-use' => 'Email sudah terdaftar. Silakan masuk.',
        'weak-password' => 'Password minimal 6 karakter.',
        _ => e.message ?? e.code,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: widget.onBack == null
          ? null
          : AppBar(leading: BackButton(onPressed: widget.onBack), title: const Text('Orang tua')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              Icon(Icons.shield_moon_outlined, size: 56, color: t.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Mihan Parental Link', style: t.textTheme.headlineMedium, textAlign: TextAlign.center),
              Text(_register ? 'Buat akun orang tua' : 'Masuk sebagai orang tua',
                  textAlign: TextAlign.center, style: t.textTheme.bodyLarge),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_register ? 'Daftar' : 'Masuk'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _register = !_register),
                child: Text(_register ? 'Sudah punya akun? Masuk' : 'Belum punya akun? Daftar'),
              ),
              if (!_register) TextButton(onPressed: _reset, child: const Text('Lupa password')),
            ]),
          ),
        ),
      ),
    );
  }
}
