import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/enforcer.dart';
import '../format.dart';

/// Layar di HP anak: status + checklist izin yang wajib diberikan.
/// Tidak ada tombol "keluar" — pelepasan hanya bisa dari akun orang tua.
class ChildHome extends StatefulWidget {
  final String deviceId;
  final VoidCallback onUnpaired;
  const ChildHome({super.key, required this.deviceId, required this.onUnpaired});

  @override
  State<ChildHome> createState() => _ChildHomeState();
}

class _ChildHomeState extends State<ChildHome> with WidgetsBindingObserver {
  Map<String, dynamic> _s = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _poll();
  }

  Future<void> _poll() async {
    final s = await Enforcer.status();
    if (!mounted) return;
    if (s['deviceId'] == null) {
      widget.onUnpaired();
      return;
    }
    setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final locked = _s['locked'] == true;
    final next = _s['nextChange'] is int ? DateTime.fromMillisecondsSinceEpoch(_s['nextChange'] as int) : null;

    Widget perm(String key, String title, String desc, VoidCallback onFix, {bool required = false}) {
      final ok = _s[key] == true;
      return ListTile(
        leading: Icon(ok ? Icons.check_circle : (required ? Icons.error : Icons.radio_button_unchecked),
            color: ok ? Colors.green : (required ? t.colorScheme.error : t.colorScheme.outline)),
        title: Text(title),
        subtitle: Text(desc),
        trailing: ok ? null : FilledButton.tonal(onPressed: onFix, child: const Text('Aktifkan')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('OctaLink')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: locked ? t.colorScheme.errorContainer : const Color(0xFFD7F2DE),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(locked ? Icons.lock : Icons.lock_open, size: 56),
              const SizedBox(height: 8),
              Text(locked ? 'Waktu pakai habis' : 'Boleh dipakai', style: t.textTheme.headlineSmall),
              if (_s['reason'] != null) Text('${_s['reason']}', textAlign: TextAlign.center),
              if (next != null)
                Text('${locked ? 'Terbuka' : 'Terkunci'} ${fmtWhen(next)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('Pengaturan HP (dilakukan orang tua)', style: t.textTheme.titleMedium),
        const SizedBox(height: 4),
        perm('accessibility', 'Layanan aksesibilitas', 'Wajib. Dipakai untuk menampilkan layar kunci.',
            Enforcer.openAccessibility,
            required: true),
        perm('admin', 'Admin perangkat', 'Mencegah aplikasi di-uninstall tanpa izin.', Enforcer.requestAdmin,
            required: true),
        perm('battery', 'Abaikan optimasi baterai', 'Supaya OctaLink tidak dimatikan sistem.',
            Enforcer.requestBattery),
        perm('notifications', 'Notifikasi', 'Menampilkan status OctaLink di bilah notifikasi.',
            Enforcer.requestNotifications),
        const SizedBox(height: 16),
        Text(
          'Untuk melepas HP ini, orang tua memilih "Lepaskan perangkat" dari aplikasi/web OctaLink.\n'
          'ID: ${widget.deviceId}',
          style: t.textTheme.bodySmall,
        ),
      ]),
    );
  }
}
