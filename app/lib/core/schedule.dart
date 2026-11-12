/// Model jadwal & engine evaluasi.
///
/// Konsep:
/// - Sebuah [Schedule] berisi daftar slot waktu BOLEH PAKAI ([TimeWindow])
///   untuk tiap hari (Senin=1 … Minggu=7). Satu hari boleh punya banyak slot,
///   misal 06:00–07:00, 12:00–14:00, 19:00–21:00.
/// - Di luar slot, perangkat TERKUNCI.
/// - Schedule bisa punya masa aktif (startDate–endDate, inklusif), misal
///   "Jadwal Ujian" 1–30 Nov. Kosong = berlaku selamanya.
/// - Jika beberapa schedule aktif di tanggal yang sama, yang menang:
///   1. yang punya masa aktif (sementara) mengalahkan yang permanen,
///   2. masa aktif yang lebih pendek menang (lebih spesifik),
///   3. yang dibuat paling akhir menang.
/// - Override (Kunci sekarang / Buka sekarang) mengalahkan semua schedule
///   selama belum kedaluwarsa.
///
/// PENTING: logika ini diporting 1:1 ke Kotlin di
/// android/app/src/main/kotlin/com/mihan/parentallink/PolicyEngine.kt.
/// Kalau mengubah aturan di sini, ubah juga di sana.
library;

class TimeWindow {
  /// Menit sejak 00:00 (0..1439).
  final int start;

  /// Menit sejak 00:00, eksklusif (1..1440). 1440 = 24:00.
  final int end;

  const TimeWindow(this.start, this.end)
      : assert(start >= 0 && start < 1440),
        assert(end > start && end <= 1440);

  bool contains(int minute) => minute >= start && minute < end;

  Map<String, dynamic> toJson() => {'s': start, 'e': end};

  factory TimeWindow.fromJson(Map<String, dynamic> j) =>
      TimeWindow((j['s'] as num).toInt(), (j['e'] as num).toInt());

  static String fmt(int minute) {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  String toString() => '${fmt(start)}–${fmt(end)}';

  @override
  bool operator ==(Object other) =>
      other is TimeWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Tanggal tanpa jam, format 'YYYY-MM-DD'.
class DateOnly implements Comparable<DateOnly> {
  final int year, month, day;
  const DateOnly(this.year, this.month, this.day);

  factory DateOnly.of(DateTime t) => DateOnly(t.year, t.month, t.day);

  static DateOnly? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split('-');
    if (p.length != 3) return null;
    return DateOnly(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  DateTime toDateTime() => DateTime(year, month, day);

  /// Jumlah hari sejak epoch (untuk hitung panjang periode).
  int get epochDay => DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ 86400000;

  @override
  int compareTo(DateOnly o) => epochDay.compareTo(o.epochDay);

  bool operator <=(DateOnly o) => compareTo(o) <= 0;
  bool operator >=(DateOnly o) => compareTo(o) >= 0;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) => other is DateOnly && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay;
}

class Schedule {
  final String id;
  final String name;
  final bool enabled;
  final DateOnly? startDate;
  final DateOnly? endDate;
  final int createdAt;

  /// Key: ISO weekday 1 (Senin) .. 7 (Minggu).
  final Map<int, List<TimeWindow>> days;

  const Schedule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.startDate,
    this.endDate,
    required this.createdAt,
    required this.days,
  });

  bool get hasPeriod => startDate != null || endDate != null;

  /// Panjang periode dalam hari; null = tak terbatas di salah satu sisi.
  int? get periodLength =>
      (startDate != null && endDate != null) ? endDate!.epochDay - startDate!.epochDay + 1 : null;

  bool coversDate(DateOnly d) =>
      enabled && (startDate == null || startDate! <= d) && (endDate == null || d <= endDate!);

  List<TimeWindow> windowsFor(int weekday) => days[weekday] ?? const [];

  Schedule copyWith({
    String? name,
    bool? enabled,
    DateOnly? startDate,
    DateOnly? endDate,
    bool clearStart = false,
    bool clearEnd = false,
    Map<int, List<TimeWindow>>? days,
  }) =>
      Schedule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        startDate: clearStart ? null : (startDate ?? this.startDate),
        endDate: clearEnd ? null : (endDate ?? this.endDate),
        createdAt: createdAt,
        days: days ?? this.days,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'startDate': startDate?.toString(),
        'endDate': endDate?.toString(),
        'createdAt': createdAt,
        'days': {
          for (final e in days.entries)
            if (e.value.isNotEmpty) '${e.key}': e.value.map((w) => w.toJson()).toList(),
        },
      };

  factory Schedule.fromJson(Map<String, dynamic> j) {
    final rawDays = (j['days'] as Map?) ?? const {};
    return Schedule(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Jadwal',
      enabled: (j['enabled'] as bool?) ?? true,
      startDate: DateOnly.tryParse(j['startDate'] as String?),
      endDate: DateOnly.tryParse(j['endDate'] as String?),
      createdAt: ((j['createdAt'] as num?) ?? 0).toInt(),
      days: {
        for (final e in rawDays.entries)
          int.parse(e.key.toString()): ((e.value as List?) ?? const [])
              .map((w) => TimeWindow.fromJson(Map<String, dynamic>.from(w as Map)))
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start)),
      },
    );
  }
}

class Override {
  /// 'lock' atau 'unlock'.
  final String mode;

  /// Epoch millis; null = sampai dibatalkan manual.
  final int? until;

  const Override(this.mode, this.until);

  bool activeAt(DateTime t) => until == null || t.millisecondsSinceEpoch < until!;

  Map<String, dynamic> toJson() => {'mode': mode, 'until': until};

  static Override? fromJson(dynamic j) {
    if (j is! Map) return null;
    return Override(j['mode'] as String, (j['until'] as num?)?.toInt());
  }
}

class Policy {
  final List<Schedule> schedules;

  /// Perilaku jika tidak ada schedule yang berlaku hari itu: 'unlocked' / 'locked'.
  final String noScheduleMode;
  final Override? override;

  /// Blok halaman Settings yang bisa mematikan proteksi.
  final bool tamperGuard;

  const Policy({
    this.schedules = const [],
    this.noScheduleMode = 'unlocked',
    this.override,
    this.tamperGuard = true,
  });

  Map<String, dynamic> toJson() => {
        'schedules': schedules.map((s) => s.toJson()).toList(),
        'noScheduleMode': noScheduleMode,
        'override': override?.toJson(),
        'tamperGuard': tamperGuard,
      };

  factory Policy.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Policy();
    return Policy(
      schedules: ((j['schedules'] as List?) ?? const [])
          .map((s) => Schedule.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      noScheduleMode: (j['noScheduleMode'] as String?) ?? 'unlocked',
      override: Override.fromJson(j['override']),
      tamperGuard: (j['tamperGuard'] as bool?) ?? true,
    );
  }

  Policy copyWith({
    List<Schedule>? schedules,
    String? noScheduleMode,
    Override? override,
    bool clearOverride = false,
    bool? tamperGuard,
  }) =>
      Policy(
        schedules: schedules ?? this.schedules,
        noScheduleMode: noScheduleMode ?? this.noScheduleMode,
        override: clearOverride ? null : (override ?? this.override),
        tamperGuard: tamperGuard ?? this.tamperGuard,
      );
}

class Decision {
  final bool locked;

  /// Penjelasan singkat untuk UI.
  final String reason;

  /// Schedule yang berlaku (jika ada).
  final Schedule? schedule;

  /// Kapan status berikutnya berubah (null = tidak diketahui / >7 hari).
  final DateTime? nextChange;

  const Decision(this.locked, this.reason, this.schedule, this.nextChange);
}

class PolicyEngine {
  /// Pilih schedule yang berlaku pada tanggal [d].
  static Schedule? activeSchedule(Policy p, DateOnly d) {
    final c = p.schedules.where((s) => s.coversDate(d)).toList();
    if (c.isEmpty) return null;
    c.sort((a, b) {
      // 1) yang punya periode menang
      if (a.hasPeriod != b.hasPeriod) return a.hasPeriod ? -1 : 1;
      // 2) periode lebih pendek menang (null = tak terbatas = paling panjang)
      final la = a.periodLength ?? 1 << 30, lb = b.periodLength ?? 1 << 30;
      if (la != lb) return la.compareTo(lb);
      // 3) yang terbaru menang
      return b.createdAt.compareTo(a.createdAt);
    });
    return c.first;
  }

  /// Status terkunci berdasarkan schedule saja (tanpa override).
  static bool _scheduleLocked(Policy p, DateTime t) {
    final s = activeSchedule(p, DateOnly.of(t));
    if (s == null) return p.noScheduleMode == 'locked';
    final m = t.hour * 60 + t.minute;
    return !s.windowsFor(t.weekday).any((w) => w.contains(m));
  }

  static bool lockedAt(Policy p, DateTime t) {
    final o = p.override;
    if (o != null && o.activeAt(t)) return o.mode == 'lock';
    return _scheduleLocked(p, t);
  }

  /// Cari waktu terdekat (> [now]) di mana status berubah, maksimal 8 hari ke depan.
  static DateTime? nextChange(Policy p, DateTime now) {
    final current = lockedAt(p, now);
    final candidates = <DateTime>{};
    final o = p.override;
    if (o?.until != null) {
      candidates.add(DateTime.fromMillisecondsSinceEpoch(o!.until!));
    }
    final today = DateTime(now.year, now.month, now.day);
    for (var i = 0; i <= 8; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      candidates.add(day);
      final s = activeSchedule(p, DateOnly.of(day));
      if (s == null) continue;
      for (final w in s.windowsFor(day.weekday)) {
        candidates.add(day.add(Duration(minutes: w.start)));
        if (w.end < 1440) candidates.add(day.add(Duration(minutes: w.end)));
      }
    }
    final sorted = candidates.where((t) => t.isAfter(now)).toList()..sort();
    for (final t in sorted) {
      if (lockedAt(p, t) != current) return t;
    }
    return null;
  }

  static Decision evaluate(Policy p, DateTime now) {
    final locked = lockedAt(p, now);
    final o = p.override;
    final s = activeSchedule(p, DateOnly.of(now));
    String reason;
    if (o != null && o.activeAt(now)) {
      reason = o.mode == 'lock' ? 'Dikunci manual oleh orang tua' : 'Dibuka manual oleh orang tua';
    } else if (s == null) {
      reason = p.noScheduleMode == 'locked'
          ? 'Tidak ada jadwal aktif (default: kunci)'
          : 'Tidak ada jadwal aktif (bebas)';
    } else {
      reason = locked ? 'Di luar jam pakai "${s.name}"' : 'Jam pakai "${s.name}"';
    }
    return Decision(locked, reason, s, nextChange(p, now));
  }
}
