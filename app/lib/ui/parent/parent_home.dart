import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/google_auth.dart';
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
  late final _children = Repo.instance.childrenOf(widget.user.uid);
  late final _devices = Repo.instance.devicesOf(widget.user.uid);

  Future<void> _addDevice() async {
    final child = await showDialog<ChildInfo>(context: context, builder: (_) => const _AddChildDialog());
    if (child == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _WaitDialog(child: child),
    );
  }

  Future<void> _removePending(ChildInfo c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus ${c.name}?'),
        content: Text('${c.email} tidak akan bisa lagi menghubungkan HP ke akun ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) await Repo.instance.removeChild(c.email);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChildInfo>>(
      stream: _children,
      builder: (context, kidSnap) => StreamBuilder<List<DeviceInfo>>(
        stream: _devices,
        builder: (context, snap) {
          final devices = snap.data ?? const <DeviceInfo>[];
          final linked = devices.map((d) => d.childEmail).toSet();
          final pending = (kidSnap.data ?? const <ChildInfo>[]).where((c) => !linked.contains(c.email)).toList();
          return LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              if (wide && _selected == null && devices.isNotEmpty) _selected = devices.first.id;
              if (_selected != null && snap.hasData && !devices.any((d) => d.id == _selected)) _selected = null;

              final list = _DeviceList(
                devices: devices,
                pending: pending,
                onRemovePending: _removePending,
                loading: !snap.hasData && !snap.hasError,
                error: snap.error,
                selected: wide ? _selected : null,
                showAddButton: wide,
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
                title: const Text('Mihan Parental Link'),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.account_circle),
                    onSelected: (v) {
                      if (v == 'logout') GoogleAuth.signOut();
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
                    label: const Text('Tambah anak'),
                  ),
                );
              }
              return Scaffold(
                appBar: appBar,
                body: Row(
                  children: [
                    SizedBox(width: 340, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selected == null
                          ? const Center(child: Text('Pilih atau tambahkan perangkat'))
                          : DevicePage(key: ValueKey(_selected), deviceId: _selected!, embedded: true),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<DeviceInfo> devices;
  final List<ChildInfo> pending;
  final void Function(ChildInfo) onRemovePending;
  final bool loading;
  final Object? error;
  final String? selected;
  final bool showAddButton; // layar lebar tidak punya FAB
  final void Function(DeviceInfo) onTap;
  final VoidCallback onAdd;

  const _DeviceList({
    required this.devices,
    required this.pending,
    required this.onRemovePending,
    required this.loading,
    required this.error,
    required this.selected,
    required this.showAddButton,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $error')),
      );
    }
    if (devices.isEmpty && pending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_android, size: 64, color: t.colorScheme.outline),
              const SizedBox(height: 12),
              Text('Belum ada HP anak', style: t.textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'Daftarkan Gmail anak, lalu login dengan Gmail itu di aplikasi Mihan Parental Link '
                'di HP anak (pilih "Anak").',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Tambah anak')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final d in devices)
          ListTile(
            selected: d.id == selected,
            leading: CircleAvatar(
              backgroundColor: d.status['locked'] == true ? t.colorScheme.errorContainer : const Color(0xFFD7F2DE),
              child: Icon(
                d.status['locked'] == true ? Icons.lock : Icons.lock_open,
                color: d.status['locked'] == true ? t.colorScheme.onErrorContainer : const Color(0xFF1E7B3A),
              ),
            ),
            title: Text(d.name),
            subtitle: Text(
              [
                d.status['locked'] == true ? 'Terkunci' : 'Terbuka',
                d.online ? 'online' : (d.lastSeen != null ? 'terakhir ${fmtAgo(d.lastSeen!)}' : 'offline'),
                if (!d.protectionOk) '⚠ proteksi mati',
              ].join(' · '),
            ),
            trailing: _UnreadBadge(deviceId: d.id),
            onTap: () => onTap(d),
          ),
        for (final c in pending)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: t.colorScheme.surfaceContainerHighest,
              child: Icon(Icons.hourglass_empty, color: t.colorScheme.outline),
            ),
            title: Text(c.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                const Text('Menunggu login di HP anak'),
              ],
            ),
            isThreeLine: true,
            trailing: IconButton(tooltip: 'Hapus', icon: const Icon(Icons.close), onPressed: () => onRemovePending(c)),
          ),
        if (showAddButton)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Tambah anak')),
          ),
      ],
    );
  }
}

class _AddChildDialog extends StatefulWidget {
  const _AddChildDialog();
  @override
  State<_AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends State<_AddChildDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = Repo.normEmail(_email.text);
    if (name.isEmpty) return setState(() => _error = 'Isi nama anak.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return setState(() => _error = 'Format Gmail tidak valid.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Repo.instance.addChild(name: name, email: email);
      if (mounted) Navigator.pop(context, ChildInfo(email: email, name: name));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tambah anak'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama (mis. Budi)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Gmail anak', hintText: 'budi@gmail.com'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
    ],
  );
}

/// Instruksi + tunggu sampai HP anak login dengan Gmail-nya.
class _WaitDialog extends StatelessWidget {
  final ChildInfo child;
  const _WaitDialog({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return StreamBuilder<List<DeviceInfo>>(
      stream: Repo.instance.devicesOf(FirebaseAuth.instance.currentUser!.uid),
      builder: (context, snap) {
        final done = (snap.data ?? const <DeviceInfo>[]).any((d) => d.childEmail == child.email);
        final body = done
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 12),
                  Text('HP ${child.name} berhasil terhubung!', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('Selanjutnya buat jadwal untuk perangkat ini.', textAlign: TextAlign.center),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Di HP anak:'),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Pasang & buka Mihan Parental Link\n'
                    '2. Pilih "Anak"\n'
                    '3. Tekan "Masuk dengan Google" dan pilih:',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(child.email, style: t.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('Menunggu HP anak… (boleh ditutup, nanti tersambung sendiri)', style: t.textTheme.bodySmall),
                ],
              );
        return AlertDialog(
          title: Text('Hubungkan HP ${child.name}'),
          content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: body),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(done ? 'Selesai' : 'Tutup'))],
        );
      },
    );
  }
}

/// Jumlah pesan anak yang belum dibaca, di samping nama perangkat.
class _UnreadBadge extends StatefulWidget {
  final String deviceId;
  const _UnreadBadge({required this.deviceId});
  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge> {
  late final _count = Repo.instance.unreadCount(widget.deviceId);

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: _count,
        builder: (context, snap) {
          final n = snap.data ?? 0;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (n > 0)
              Badge(
                label: Text('$n'),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chat_bubble, size: 20)),
              ),
            const Icon(Icons.chevron_right),
          ]);
        },
      );
}
