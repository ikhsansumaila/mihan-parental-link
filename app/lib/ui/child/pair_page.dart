import 'package:flutter/material.dart';

import '../../data/google_auth.dart';
import '../../data/repo.dart';
import '../../platform/enforcer.dart';

/// HP anak: login dengan Gmail anak → konfirmasi akun orang tua → terhubung.
class PairPage extends StatefulWidget {
  final VoidCallback onPaired;
  final VoidCallback onBack;
  const PairPage({super.key, required this.onPaired, required this.onBack});

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Mulai bersih supaya pemilih akun Google selalu muncul.
      await GoogleAuth.signOut();
      final user = await GoogleAuth.signIn();
      if (user == null) return; // dibatalkan

      final reg = await Repo.instance.findMyRegistration();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Hubungkan HP ini?'),
          content: Text(
            'HP ini akan diawasi oleh akun orang tua:\n\n'
            '${reg.ownerEmail}\n\n'
            'Pastikan itu benar akun orang tua kamu.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bukan')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ya, hubungkan')),
          ],
        ),
      );
      if (ok != true) {
        await GoogleAuth.signOut();
        return;
      }

      final id = await Repo.instance.pairCurrentGoogleUser(model: await Enforcer.model());
      await Enforcer.activate(id);
      widget.onPaired();
    } catch (e) {
      await GoogleAuth.signOut();
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _back() async {
    await GoogleAuth.signOut();
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: const Text('Hubungkan HP anak'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.child_care, size: 64, color: t.colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              '1. Orang tua menekan "Tambah anak" di aplikasi atau web Mihan Parental Link, '
              'lalu memasukkan Gmail anak.\n\n'
              '2. Di HP ini, tekan tombol di bawah dan pilih Gmail anak.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: t.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Masuk dengan Google')),
            ),
          ],
        ),
      ),
    );
  }
}
