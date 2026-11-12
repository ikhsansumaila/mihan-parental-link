import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/repo.dart';
import '../format.dart';
import 'device_page.dart';

/// Layar utama orang tua. Lebar ≥ 900px: daftar di kiri + detail di kanan.
/// Lebih sempit (HP / web mobile): daftar, tap untuk buka detail.
class ParentHome extends StatefulWidget {
  final User user;
  const ParentHome({super.key, required this.user});

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  String? _selected;

  Future<void> _addDevice() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || !mounted) return;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _PairDialog(childName: name));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeviceInfo>>(
      stream: Repo.instance.devicesOf(widget.user.uid),
      builder: (context, snap) {
        final devices = snap.data ?? const <DeviceInfo>[];
        return LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          if (wide && _selected == null && devices.isNotEmpty) _selected = devices.first.id;
          if (_selected != null && snap.hasData && !devices.any((d) => d.id == _selected)) _selected = null;

          final list = _DeviceList(
            devices: devices,
            loading: !snap.hasData && !snap.hasError,
            error: snap.error,
            selected: wide ? _selected : null,
            onTap: (d) {
              if (wide) {
                setState(() => _selected = d.id);
              } else {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => DevicePage(deviceId: d.id)));
              }
            },
            onAdd: _addDevice,
          );

          final appBar = AppBar(
            title: const Text('OctaLink'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle),
                onSelected: (v) {
                  if (v == 'logout') FirebaseAuth.instance.signOut();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text(widget.user.email ?? '')),
                  const PopupMenuItem(value: 'logout', child: Text('Keluar')),
                ],
              ),
            ],
          );

          if (!wide) {
            return Scaffold(
              appBar: appBar,
              body: list,
              floatingActionButton: FloatingActionButton.extended(
                onPressed: _addDevice,
                icon: const Icon(Icons.add),
                label: const Text('Tambah HP anak'),
              ),
            );
          }
          return Scaffold(
            appBar: appBar,
            body: Row(children: [
              SizedBox(width: 340, child: list),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selected == null
                    ? const Center(child: Text('Pilih atau tambahkan perangkat'))
                    : DevicePage(key: ValueKey(_selected), deviceId: _selected!, embedded: true),
              ),
            ]),
          );
        });
      },
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<DeviceInfo> devices;
  final bool loading;
  final Object? error;
  final String? selected;
  final void Function(DeviceInfo) onTap;
  final VoidCallback onAdd;

  const _DeviceList({
    required this.devices,
    required this.loading,
    required this.error,
    required this.selected,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $error')));
    if (devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phone_android, size: 64, color: t.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Belum ada HP anak', style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Pasang aplikasi OctaLink di HP anak, pilih "Anak", lalu masukkan kode pairing.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Tambah HP anak')),
          ]),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      for (final d in devices)
        ListTile(
          selected: d.id == selected,
          leading: CircleAvatar(
            backgroundColor: d.status['locked'] == true ? t.colorScheme.errorContainer : const Color(0xFFD7F2DE),
            child: Icon(d.status['locked'] == true ? Icons.lock : Icons.lock_open,
                color: d.status['locked'] == true ? t.colorScheme.onErrorContainer : const Color(0xFF1E7B3A)),
          ),
          title: Text(d.name),
          subtitle: Text([
            d.status['locked'] == true ? 'Terkunci' : 'Terbuka',
            d.online ? 'online' : (d.lastSeen != null ? 'terakhir ${fmtAgo(d.lastSeen!)}' : 'offline'),
            if (!d.protectionOk) '⚠ proteksi mati',
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(d),
        ),
      if (selected != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Tambah HP anak')),
        ),
    ]);
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tambah HP anak'),
        content: TextField(
          controller: _c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama (mis. HP Budi)'),
          onSubmitted: (v) => v.trim().isNotEmpty ? Navigator.pop(context, v.trim()) : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () => _c.text.trim().isNotEmpty ? Navigator.pop(context, _c.text.trim()) : null,
            child: const Text('Lanjut'),
          ),
        ],
      );
}

/// Tampilkan kode pairing & tunggu sampai HP anak memakainya.
class _PairDialog extends StatefulWidget {
  final String childName;
  const _PairDialog({required this.childName});
  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  String? _code;
  Object? _error;
  StreamSubscription<List<DeviceInfo>>? _sub;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    try {
      final code = await Repo.instance.createPairingCode(widget.childName);
      if (!mounted) return;
      setState(() => _code = code);
      _sub = Repo.instance.devicesOf(FirebaseAuth.instance.currentUser!.uid).listen((list) {
        if (list.any((d) => d.pairingCode == code) && mounted) {
          setState(() => _done = true);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_code != null && !_done) Repo.instance.deletePairingCode(_code!).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget body;
    if (_error != null) {
      body = Text('Gagal: $_error');
    } else if (_code == null) {
      body = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (_done) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 12),
        Text('${widget.childName} berhasil terhubung!', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Selanjutnya buat jadwal untuk perangkat ini.', textAlign: TextAlign.center),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Di HP anak: buka OctaLink → pilih "Anak" → masukkan kode:', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SelectableText(
          '${_code!.substring(0, 3)} ${_code!.substring(3)}',
          style: t.textTheme.displayMedium?.copyWith(letterSpacing: 6, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Berlaku 15 menit', style: t.textTheme.bodySmall),
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text('Menunggu HP anak…', style: t.textTheme.bodySmall),
      ]);
    }
    return AlertDialog(
      title: Text('Hubungkan ${widget.childName}'),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_done ? 'Selesai' : 'Batal')),
      ],
    );
  }
}
