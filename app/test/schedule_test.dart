import 'package:flutter_test/flutter_test.dart';
import 'package:mihan_parental_link/core/schedule.dart';

Schedule sched(
  String id, {
  String? start,
  String? end,
  int createdAt = 0,
  required Map<int, List<TimeWindow>> days,
}) =>
    Schedule(
      id: id,
      name: id,
      startDate: DateOnly.tryParse(start),
      endDate: DateOnly.tryParse(end),
      createdAt: createdAt,
      days: days,
    );

void main() {
  // 2026-11-16 adalah Senin.
  final monday = DateTime(2026, 11, 16);
  DateTime at(DateTime d, int h, [int m = 0]) => DateTime(d.year, d.month, d.day, h, m);

  group('multi slot per hari', () {
    final p = Policy(schedules: [
      sched('harian', days: {
        1: const [TimeWindow(6 * 60, 7 * 60), TimeWindow(12 * 60, 14 * 60), TimeWindow(19 * 60, 21 * 60)],
      }),
    ]);

    test('di dalam slot = terbuka', () {
      expect(PolicyEngine.lockedAt(p, at(monday, 6, 30)), false);
      expect(PolicyEngine.lockedAt(p, at(monday, 13)), false);
      expect(PolicyEngine.lockedAt(p, at(monday, 20, 59)), false);
    });

    test('di luar slot = terkunci (end eksklusif)', () {
      expect(PolicyEngine.lockedAt(p, at(monday, 7)), true);
      expect(PolicyEngine.lockedAt(p, at(monday, 15)), true);
      expect(PolicyEngine.lockedAt(p, at(monday, 21)), true);
    });

    test('hari tanpa slot di schedule aktif = terkunci seharian', () {
      expect(PolicyEngine.lockedAt(p, at(monday.add(const Duration(days: 1)), 13)), true);
    });

    test('nextChange menunjuk ke slot berikutnya', () {
      expect(PolicyEngine.nextChange(p, at(monday, 8)), at(monday, 12));
      expect(PolicyEngine.nextChange(p, at(monday, 12, 5)), at(monday, 14));
    });
  });

  group('masa aktif', () {
    final everyday = {for (var d = 1; d <= 7; d++) d: const [TimeWindow(0, 1440)]};
    final p = Policy(schedules: [
      sched('permanen', days: everyday),
      sched('ujian', start: '2026-11-01', end: '2026-11-30', days: {
        1: const [TimeWindow(19 * 60, 20 * 60)],
      }),
    ]);

    test('schedule berperiode menang saat periodenya berlaku', () {
      expect(PolicyEngine.activeSchedule(p, DateOnly.of(monday))!.id, 'ujian');
      expect(PolicyEngine.lockedAt(p, at(monday, 10)), true);
      expect(PolicyEngine.lockedAt(p, at(monday, 19, 30)), false);
    });

    test('setelah periode habis kembali ke permanen', () {
      final dec = DateTime(2026, 12, 7); // Senin
      expect(PolicyEngine.activeSchedule(p, DateOnly.of(dec))!.id, 'permanen');
      expect(PolicyEngine.lockedAt(p, at(dec, 10)), false);
    });

    test('periode lebih pendek menang', () {
      final p2 = Policy(schedules: [
        sched('bulan', start: '2026-11-01', end: '2026-11-30', days: everyday),
        sched('minggu', start: '2026-11-15', end: '2026-11-21', days: const {}),
      ]);
      expect(PolicyEngine.activeSchedule(p2, DateOnly.of(monday))!.id, 'minggu');
      expect(PolicyEngine.activeSchedule(p2, DateOnly(2026, 11, 10))!.id, 'bulan');
    });

    test('tanpa schedule mengikuti noScheduleMode', () {
      const empty = Policy(noScheduleMode: 'locked');
      expect(PolicyEngine.lockedAt(empty, at(monday, 10)), true);
      expect(PolicyEngine.lockedAt(const Policy(), at(monday, 10)), false);
    });

    test('schedule nonaktif diabaikan', () {
      final p3 = Policy(schedules: [
        sched('ujian', start: '2026-11-01', end: '2026-11-30', days: const {}).copyWith(enabled: false),
      ]);
      expect(PolicyEngine.activeSchedule(p3, DateOnly.of(monday)), isNull);
    });
  });

  group('override', () {
    final p = Policy(schedules: [
      sched('s', days: {1: const [TimeWindow(0, 1440)]}),
    ]);

    test('lock override menang lalu kedaluwarsa', () {
      final until = at(monday, 11).millisecondsSinceEpoch;
      final po = p.copyWith(override: Override('lock', until));
      expect(PolicyEngine.lockedAt(po, at(monday, 10)), true);
      expect(PolicyEngine.lockedAt(po, at(monday, 11)), false);
      expect(PolicyEngine.nextChange(po, at(monday, 10)), at(monday, 11));
    });

    test('unlock tanpa batas', () {
      final po = Policy(override: const Override('unlock', null), noScheduleMode: 'locked');
      expect(PolicyEngine.lockedAt(po, at(monday, 3)), false);
    });
  });

  test('serialisasi bolak-balik', () {
    final s = sched('x', start: '2026-11-01', end: '2026-11-30', createdAt: 5, days: {
      3: const [TimeWindow(60, 120), TimeWindow(600, 1440)],
    });
    final p = Policy(schedules: [s], override: const Override('lock', 99), noScheduleMode: 'locked');
    final back = Policy.fromJson(p.toJson());
    expect(back.toJson(), p.toJson());
  });
}
