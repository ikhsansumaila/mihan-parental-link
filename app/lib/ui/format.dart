import 'package:intl/intl.dart';

import '../core/schedule.dart';

const dayNames = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const dayShort = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

String fmtDate(DateOnly d) => DateFormat('d MMM yyyy', 'id_ID').format(d.toDateTime());

String fmtPeriod(Schedule s) {
  if (!s.hasPeriod) return 'Berlaku selamanya';
  if (s.startDate != null && s.endDate != null) {
    return '${fmtDate(s.startDate!)} – ${fmtDate(s.endDate!)} (${s.periodLength} hari)';
  }
  if (s.startDate != null) return 'Mulai ${fmtDate(s.startDate!)}';
  return 'Sampai ${fmtDate(s.endDate!)}';
}

/// "pukul 15:00", "besok 06:00", "Sen 06:00", atau tanggal lengkap.
String fmtWhen(DateTime t, [DateTime? now]) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final hm = DateFormat('HH:mm').format(t);
  if (diff == 0) return 'pukul $hm';
  if (diff == 1) return 'besok $hm';
  if (diff < 7) return '${DateFormat('EEEE', 'id_ID').format(t)} $hm';
  return DateFormat('d MMM HH:mm', 'id_ID').format(t);
}

String fmtAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

enum ScheduleState { active, upcoming, expired, disabled, standby }

/// Status schedule relatif ke hari ini & schedule yang sedang berlaku.
ScheduleState scheduleState(Schedule s, Schedule? current, DateOnly today) {
  if (!s.enabled) return ScheduleState.disabled;
  if (current?.id == s.id) return ScheduleState.active;
  if (s.endDate != null && s.endDate!.compareTo(today) < 0) return ScheduleState.expired;
  if (s.startDate != null && s.startDate!.compareTo(today) > 0) return ScheduleState.upcoming;
  return ScheduleState.standby; // berlaku tapi kalah prioritas
}
