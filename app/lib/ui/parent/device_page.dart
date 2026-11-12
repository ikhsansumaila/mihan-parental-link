import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/schedule.dart';
import '../../data/repo.dart';
import '../format.dart';
import '../widgets/day_timeline.dart';
import 'schedule_editor.dart';

class DevicePage extends StatefulWidget {
  final String deviceId;

  /// true = ditampilkan di panel kanan (tanpa tombol back).
  final bool embedded;
  const DevicePage({super.key, required this.deviceId, this.embedded = false});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final Stream<DeviceInfo?> _stream = Repo.instance.device(widget.deviceId);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Re-render tiap 30 detik supaya status "sekarang" ikut bergerak.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Repo get _repo => Repo.instance;

  Future<void> _run(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (ok != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  void _override(String mode, Duration? d) {
    final until = d == null ? null : DateTime.now().add(d).millisecondsSinceEpoch;
    _run(
      () => _repo.setOverride(widget.deviceId, Override(mode, until)),
      mode == 'lock' ? 'HP dikunci' : 'HP dibuka',
    );
  }

  Future<void> _editSchedule(DeviceInfo dev, [Schedule? s]) async {
    final result = await ScheduleEditor.open(context, initial: s);
    if (result == null) return;
    final list = List.of(dev.policy.schedules);
    final i = list.indexWhere((x) => x.id == result.id);
    if (i >= 0) {
      list[i] = result;
    } else {
      list.add(result);
    }
    await _run(() => _repo.savePolicy(dev.id, dev.policy.copyWith(schedules: list)), 'Jadwal disimpan');
  }

  Future<void> _deleteSchedule(DeviceInfo dev, Schedule s) async {
    final ok = await _confirm('Hapus jadwal "${s.name}"?');
    if (!ok) return;
    final list = dev.policy.schedules.where((x) => x.id != s.id).toList();
    await _run(() => _repo.savePolicy(dev.id, dev.policy.copyWith(schedules: list)), 'Jadwal dihapus');
  }

  Future<void> _toggle(DeviceInfo dev, Schedule s, bool v) => _run(() => _repo.savePolicy(
        dev.id,
        dev.policy.copyWith(schedules: [for (final x in dev.policy.schedules) x.id == s.id ? x.copyWith(enabled: v) : x]),
      ));

  Future<bool> _confirm(String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ya')),
          ],
        ),
      ) ??
      false;

  Future<void> _rename(DeviceInfo dev) async {
    final c = TextEditingController(text: dev.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti nama'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _run(() => _repo.renameDevice(dev.id, name));
  }

  Future<void> _remove(DeviceInfo dev) async {
    final ok = await _confirm('Lepaskan "${dev.name}"? Proteksi di HP anak akan berhenti dan aplikasi '
        'bisa di-uninstall.');
    if (!ok) return;
    await _run(() => _repo.deleteDevice(dev.id));
    if (mounted && !widget.embedded) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceInfo?>(
      stream: _stream,
      builder: (context, snap) {
        final dev = snap.data;
        final body = !snap.hasData
            ? (snap.connectionState == ConnectionState.active
                ? const Center(child: Text('Perangkat tidak ditemukan'))
                : const Center(child: CircularProgressIndicator()))
            : _content(dev!);
        if (widget.embedded) return body;
        return Scaffold(appBar: AppBar(title: Text(dev?.name ?? 'Perangkat')), body: body);
      },
    );
  }

  Widget _content(DeviceInfo dev) {
    final t = Theme.of(context);
    final now = DateTime.now();
    final decision = PolicyEngine.evaluate(dev.policy, now);
    final today = DateOnly.of(now);
    final o = dev.policy.override;
    final overrideActive = o != null && o.activeAt(now);
    final schedules = List.of(dev.policy.schedules)
      ..sort((a, b) => scheduleState(a, decision.schedule, today).index
          .compareTo(scheduleState(b, decision.schedule, today).index));

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.embedded) ...[
        Row(children: [
          Expanded(child: Text(dev.name, style: t.textTheme.headlineSmall)),
          _settingsMenu(dev),
        ]),
        const SizedBox(height: 12),
      ],

      // ---------------- status
      _StatusCard(dev: dev, decision: decision),
      const SizedBox(height: 12),

      // ---------------- aksi cepat
      Wrap(spacing: 8, runSpacing: 8, children: [
        MenuAnchor(
          builder: (c, ctrl, _) => FilledButton.tonalIcon(
            onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
            icon: const Icon(Icons.lock),
            label: const Text('Kunci sekarang'),
          ),
          menuChildren: [
            for (final e in _durations)
              MenuItemButton(onPressed: () => _override('lock', e.$2), child: Text(e.$1)),
          ],
        ),
        MenuAnchor(
          builder: (c, ctrl, _) => FilledButton.tonalIcon(
            onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
            icon: const Icon(Icons.more_time),
            label: const Text('Beri waktu tambahan'),
          ),
          menuChildren: [
            for (final e in _durations)
              MenuItemButton(onPressed: () => _override('unlock', e.$2), child: Text(e.$1)),
          ],
        ),
        if (overrideActive)
          OutlinedButton.icon(
            onPressed: () => _run(() => _repo.setOverride(dev.id, null), 'Kembali ke jadwal'),
            icon: const Icon(Icons.undo),
            label: const Text('Kembali ke jadwal'),
          ),
        if (!widget.embedded) _settingsMenu(dev),
      ]),
      const SizedBox(height: 20),

      // ---------------- hari ini
      Text('Hari ini (${dayNames[now.weekday - 1]})', style: t.textTheme.titleMedium),
      const SizedBox(height: 8),
      DayTimeline(
        windows: decision.schedule?.windowsFor(now.weekday) ??
            (dev.policy.noScheduleMode == 'locked' ? const [] : const [TimeWindow(0, 1440)]),
        height: 22,
        showLabels: true,
        nowMinute: now.hour * 60 + now.minute,
      ),
      const SizedBox(height: 4),
      Text(
        decision.schedule == null
            ? 'Tidak ada jadwal yang berlaku hari ini.'
            : 'Mengikuti "${decision.schedule!.name}": '
                '${decision.schedule!.windowsFor(now.weekday).isEmpty ? 'terkunci seharian' : decision.schedule!.windowsFor(now.weekday).join(', ')}',
        style: t.textTheme.bodySmall,
      ),
      const SizedBox(height: 24),

      // ---------------- daftar jadwal
      Row(children: [
        Expanded(child: Text('Jadwal', style: t.textTheme.titleMedium)),
        FilledButton.icon(
          onPressed: () => _editSchedule(dev),
          icon: const Icon(Icons.add),
          label: const Text('Jadwal baru'),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
        'Jadwal dengan masa aktif mengalahkan jadwal permanen. Jika ada beberapa, yang periodenya '
        'paling pendek menang.',
        style: t.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (schedules.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.event_note, size: 40),
              const SizedBox(height: 8),
              Text(
                dev.policy.noScheduleMode == 'locked'
                    ? 'Belum ada jadwal — HP terkunci terus.'
                    : 'Belum ada jadwal — HP bebas dipakai.',
              ),
            ]),
          ),
        ),
      for (final s in schedules) ...[
        _ScheduleCard(
          schedule: s,
          state: scheduleState(s, decision.schedule, today),
          onEdit: () => _editSchedule(dev, s),
          onDelete: () => _deleteSchedule(dev, s),
          onDuplicate: () => _duplicateSimple(dev, s),
          onToggle: (v) => _toggle(dev, s, v),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Future<void> _duplicateSimple(DeviceInfo dev, Schedule s) async {
    final copy = Schedule(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: '${s.name} (salinan)',
      enabled: s.enabled,
      startDate: s.startDate,
      endDate: s.endDate,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      days: s.days,
    );
    final edited = await ScheduleEditor.open(context, initial: copy);
    if (edited == null) return;
    await _run(
      () => _repo.savePolicy(dev.id, dev.policy.copyWith(schedules: [...dev.policy.schedules, edited])),
      'Jadwal disalin',
    );
  }

  Widget _settingsMenu(DeviceInfo dev) => PopupMenuButton<String>(
        tooltip: 'Pengaturan perangkat',
        icon: const Icon(Icons.settings),
        onSelected: (v) {
          switch (v) {
            case 'rename':
              _rename(dev);
            case 'nosched':
              _run(() => _repo.savePolicy(
                    dev.id,
                    dev.policy.copyWith(noScheduleMode: dev.policy.noScheduleMode == 'locked' ? 'unlocked' : 'locked'),
                  ));
            case 'tamper':
              _run(() => _repo.savePolicy(dev.id, dev.policy.copyWith(tamperGuard: !dev.policy.tamperGuard)));
            case 'remove':
              _remove(dev);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('Ganti nama')),
          CheckedPopupMenuItem(
            value: 'nosched',
            checked: dev.policy.noScheduleMode == 'locked',
            child: const Text('Kunci jika tidak ada jadwal'),
          ),
          CheckedPopupMenuItem(
            value: 'tamper',
            checked: dev.policy.tamperGuard,
            child: const Text('Cegah anak mematikan proteksi'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'remove', child: Text('Lepaskan perangkat')),
        ],
      );
}

const _durations = <(String, Duration?)>[
  ('15 menit', Duration(minutes: 15)),
  ('30 menit', Duration(minutes: 30)),
  ('1 jam', Duration(hours: 1)),
  ('2 jam', Duration(hours: 2)),
  ('Sampai saya batalkan', null),
];

class _StatusCard extends StatelessWidget {
  final DeviceInfo dev;
  final Decision decision;
  const _StatusCard({required this.dev, required this.decision});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final locked = decision.locked;
    final bg = locked ? t.colorScheme.errorContainer : const Color(0xFFD7F2DE);
    final fg = locked ? t.colorScheme.onErrorContainer : const Color(0xFF0F5223);
    final reported = dev.status['locked'];
    final mismatch = reported is bool && reported != locked && dev.online;

    final warnings = <String>[
      if (dev.status['accessibility'] != true) 'Layanan aksesibilitas Mihan Parental Link mati — HP tidak bisa dikunci.',
      if (dev.status['admin'] != true) 'Admin perangkat belum aktif — aplikasi mudah di-uninstall.',
      if (!dev.online) 'HP offline${dev.lastSeen != null ? ' (terakhir ${fmtAgo(dev.lastSeen!)})' : ''}. '
          'Jadwal tetap berjalan di HP, perubahan diterapkan saat online.',
      if (mismatch) 'HP belum menerima perubahan terbaru.',
    ];

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(locked ? Icons.lock : Icons.lock_open, color: fg, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(locked ? 'Terkunci' : 'Boleh dipakai',
                    style: t.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                Text(decision.reason, style: TextStyle(color: fg)),
                if (decision.nextChange != null)
                  Text(
                    '${locked ? 'Terbuka' : 'Terkunci'} ${fmtWhen(decision.nextChange!)}',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                  ),
              ]),
            ),
          ]),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber, size: 18, color: fg),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w, style: TextStyle(color: fg))),
                ]),
              ),
          ],
          if (dev.model != null) ...[
            const SizedBox(height: 8),
            Text('${dev.model}${dev.status['battery'] != null ? ' · baterai ${dev.status['battery']}%' : ''}',
                style: t.textTheme.bodySmall?.copyWith(color: fg)),
          ],
        ]),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final Schedule schedule;
  final ScheduleState state;
  final VoidCallback onEdit, onDelete, onDuplicate;
  final void Function(bool) onToggle;

  const _ScheduleCard({
    required this.schedule,
    required this.state,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (label, color) = switch (state) {
      ScheduleState.active => ('Sedang berlaku', const Color(0xFF1E7B3A)),
      ScheduleState.upcoming => ('Akan datang', t.colorScheme.primary),
      ScheduleState.standby => ('Cadangan', t.colorScheme.outline),
      ScheduleState.expired => ('Kedaluwarsa', t.colorScheme.outline),
      ScheduleState.disabled => ('Nonaktif', t.colorScheme.outline),
    };
    final s = schedule;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(s.name, style: t.textTheme.titleMedium),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(label, style: t.textTheme.labelSmall?.copyWith(color: color)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(fmtPeriod(s), style: t.textTheme.bodySmall),
                ]),
              ),
              Switch(value: s.enabled, onChanged: onToggle),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'edit' => onEdit(),
                  'dup' => onDuplicate(),
                  'del' => onDelete(),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Ubah')),
                  PopupMenuItem(value: 'dup', child: Text('Duplikat')),
                  PopupMenuItem(value: 'del', child: Text('Hapus')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            for (var d = 1; d <= 7; d++)
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 4),
                child: Row(children: [
                  SizedBox(width: 36, child: Text(dayShort[d - 1], style: t.textTheme.labelSmall)),
                  Expanded(child: DayTimeline(windows: s.windowsFor(d), height: 10)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
