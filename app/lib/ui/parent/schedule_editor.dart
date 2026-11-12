import 'package:flutter/material.dart';

import '../../core/schedule.dart';
import '../format.dart';
import '../widgets/day_timeline.dart';

/// Halaman buat / ubah jadwal mingguan.
/// - Banyak slot per hari
/// - Masa aktif opsional (tanggal mulai–selesai)
class ScheduleEditor extends StatefulWidget {
  final Schedule? initial;
  const ScheduleEditor({super.key, this.initial});

  static Future<Schedule?> open(BuildContext context, {Schedule? initial}) =>
      Navigator.of(context).push<Schedule>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScheduleEditor(initial: initial)),
      );

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _Preset {
  final String label;
  final Map<int, List<TimeWindow>> days;
  const _Preset(this.label, this.days);
}

final _presets = [
  _Preset('Hari sekolah', {
    for (var d = 1; d <= 5; d++)
      d: const [TimeWindow(5 * 60 + 30, 6 * 60 + 30), TimeWindow(14 * 60, 17 * 60), TimeWindow(19 * 60 + 30, 21 * 60)],
    6: const [TimeWindow(8 * 60, 12 * 60), TimeWindow(15 * 60, 21 * 60)],
    7: const [TimeWindow(8 * 60, 12 * 60), TimeWindow(15 * 60, 21 * 60)],
  }),
  _Preset('Masa ujian', {
    for (var d = 1; d <= 7; d++) d: const [TimeWindow(18 * 60, 19 * 60)],
  }),
  _Preset('Liburan', {
    for (var d = 1; d <= 7; d++) d: const [TimeWindow(7 * 60, 12 * 60), TimeWindow(13 * 60, 21 * 60)],
  }),
];

class _ScheduleEditorState extends State<ScheduleEditor> {
  late final TextEditingController _name;
  late bool _enabled;
  DateOnly? _start;
  DateOnly? _end;
  late Map<int, List<TimeWindow>> _days;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _name = TextEditingController(text: s?.name ?? '');
    _enabled = s?.enabled ?? true;
    _start = s?.startDate;
    _end = s?.endDate;
    _days = {for (var d = 1; d <= 7; d++) d: List.of(s?.windowsFor(d) ?? const <TimeWindow>[])};
  }

  // ------------------------------------------------------------ period

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDateRange: (_start != null && _end != null)
          ? DateTimeRange(start: _start!.toDateTime(), end: _end!.toDateTime())
          : null,
      helpText: 'Pilih masa aktif jadwal',
    );
    if (r != null) {
      setState(() {
        _start = DateOnly.of(r.start);
        _end = DateOnly.of(r.end);
      });
    }
  }

  void _quickRange({int days = 0, int months = 0}) {
    final base = _start?.toDateTime() ?? DateTime.now();
    final s = DateTime(base.year, base.month, base.day);
    final e = DateTime(s.year, s.month + months, s.day + days - 1);
    setState(() {
      _start = DateOnly.of(s);
      _end = DateOnly.of(e);
    });
  }

  // ------------------------------------------------------------ windows

  Future<int?> _pickTime(String help, int initial) async {
    final t = await showTimePicker(
      context: context,
      helpText: help,
      initialTime: TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60),
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _editWindow(int day, [int? index]) async {
    final existing = index == null ? null : _days[day]![index];
    final defaultStart = existing?.start ?? (_days[day]!.isEmpty ? 16 * 60 : _days[day]!.last.end);
    final start = await _pickTime('Jam mulai boleh pakai', defaultStart.clamp(0, 1439));
    if (start == null || !mounted) return;
    var end = await _pickTime('Jam selesai (00:00 = tengah malam)', existing?.end ?? (start + 60).clamp(0, 1439));
    if (end == null) return;
    if (end == 0) end = 1440;
    if (end <= start) {
      _snack('Jam selesai harus setelah jam mulai. Untuk lewat tengah malam, buat 2 slot '
          '(mis. 22:00–00:00 dan 00:00–01:00 di hari berikutnya).');
      return;
    }
    final w = TimeWindow(start, end);
    final others = List.of(_days[day]!);
    if (index != null) others.removeAt(index);
    if (others.any((o) => w.start < o.end && o.start < w.end)) {
      _snack('Slot $w bertabrakan dengan slot lain di hari ${dayNames[day - 1]}.');
      return;
    }
    setState(() => _days[day] = [...others, w]..sort((a, b) => a.start.compareTo(b.start)));
  }

  void _copyDay(int from, List<int> to) {
    setState(() {
      for (final d in to) {
        if (d != from) _days[d] = List.of(_days[from]!);
      }
    });
    _snack('Jadwal ${dayNames[from - 1]} disalin.');
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ------------------------------------------------------------ save

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Beri nama jadwal dulu.');
      return;
    }
    if (_start != null && _end != null && _end!.compareTo(_start!) < 0) {
      _snack('Tanggal selesai harus setelah tanggal mulai.');
      return;
    }
    final base = widget.initial ??
        Schedule(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
          name: name,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          days: const {},
        );
    Navigator.of(context).pop(base.copyWith(
      name: name,
      enabled: _enabled,
      startDate: _start,
      endDate: _end,
      clearStart: _start == null,
      clearEnd: _end == null,
      days: {for (final e in _days.entries) if (e.value.isNotEmpty) e.key: e.value},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasPeriod = _start != null || _end != null;
    final totalMinutes = _days.values.expand((l) => l).fold<int>(0, (a, w) => a + w.end - w.start);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Jadwal baru' : 'Ubah jadwal'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _save, child: const Text('Simpan')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 48), children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nama jadwal',
                hintText: 'mis. Hari sekolah, Masa ujian, Liburan',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktif'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (_isNew) ...[
              Text('Mulai dari template', style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in _presets)
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(p.label),
                    onPressed: () => setState(() {
                      if (_name.text.trim().isEmpty) _name.text = p.label;
                      _days = {for (var d = 1; d <= 7; d++) d: List.of(p.days[d] ?? const <TimeWindow>[])};
                    }),
                  ),
              ]),
              const SizedBox(height: 20),
            ],

            // ---------------- masa aktif
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.date_range),
                    const SizedBox(width: 8),
                    Text('Masa aktif', style: t.textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Selamanya'), icon: Icon(Icons.all_inclusive)),
                      ButtonSegment(value: true, label: Text('Periode tertentu'), icon: Icon(Icons.event)),
                    ],
                    selected: {hasPeriod},
                    onSelectionChanged: (s) {
                      if (s.first) {
                        _quickRange(months: 1);
                      } else {
                        setState(() => _start = _end = null);
                      }
                    },
                  ),
                  if (hasPeriod) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.edit_calendar),
                      label: Text(
                        '${_start != null ? fmtDate(_start!) : '…'}  →  ${_end != null ? fmtDate(_end!) : '…'}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final q in [('1 minggu', 7, 0), ('2 minggu', 14, 0), ('1 bulan', 0, 1), ('3 bulan', 0, 3)])
                        ChoiceChip(
                          label: Text(q.$1),
                          selected: false,
                          onSelected: (_) => _quickRange(days: q.$2, months: q.$3),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'Selama periode ini, jadwal ini menggantikan jadwal permanen. '
                      'Setelah lewat, otomatis kembali ke jadwal permanen.',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // ---------------- mingguan
            Row(children: [
              Expanded(child: Text('Jam boleh pakai per hari', style: t.textTheme.titleMedium)),
              Text('Total ${(totalMinutes / 60).toStringAsFixed(1)} jam/minggu', style: t.textTheme.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text('Di luar slot hijau, HP anak terkunci. Hari tanpa slot = terkunci seharian.',
                style: t.textTheme.bodySmall),
            const SizedBox(height: 12),
            for (var d = 1; d <= 7; d++) ...[
              _DayCard(
                day: d,
                windows: _days[d]!,
                onAdd: () => _editWindow(d),
                onEdit: (i) => _editWindow(d, i),
                onDelete: (i) => setState(() => _days[d] = List.of(_days[d]!)..removeAt(i)),
                onClear: () => setState(() => _days[d] = []),
                onCopy: (targets) => _copyDay(d, targets),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final int day;
  final List<TimeWindow> windows;
  final VoidCallback onAdd;
  final void Function(int) onEdit;
  final void Function(int) onDelete;
  final VoidCallback onClear;
  final void Function(List<int>) onCopy;

  const _DayCard({
    required this.day,
    required this.windows,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onClear,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(dayNames[day - 1], style: t.textTheme.titleSmall)),
            if (windows.isEmpty)
              Text('Terkunci seharian', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
            PopupMenuButton<String>(
              tooltip: 'Salin / hapus',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => switch (v) {
                'all' => onCopy([1, 2, 3, 4, 5, 6, 7]),
                'weekday' => onCopy([1, 2, 3, 4, 5]),
                'weekend' => onCopy([6, 7]),
                'clear' => onClear(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Salin ke semua hari')),
                PopupMenuItem(value: 'weekday', child: Text('Salin ke Senin–Jumat')),
                PopupMenuItem(value: 'weekend', child: Text('Salin ke Sabtu–Minggu')),
                PopupMenuItem(value: 'clear', child: Text('Kosongkan hari ini')),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DayTimeline(windows: windows, showLabels: true),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (var i = 0; i < windows.length; i++)
              InputChip(
                label: Text(windows[i].toString()),
                onPressed: () => onEdit(i),
                onDeleted: () => onDelete(i),
              ),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Slot'), onPressed: onAdd),
          ]),
        ]),
      ),
    );
  }
}
