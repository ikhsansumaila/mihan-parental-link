import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Kode buka darurat offline (mirip OTP).
///
/// Dashboard dan HP anak sama-sama menyimpan `unlockSecret` (field di dokumen device).
/// Kode = HMAC-SHA256(secret, `unlock:{step}:{durasi}`) → 6 digit, step = 5 menit.
/// HP anak memverifikasi tanpa internet. Harus identik dengan UnlockCode.kt.
class UnlockCode {
  static const stepMs = 5 * 60 * 1000;

  /// Indeks durasi ikut di-hash, jadi kode 30 menit tidak bisa dipakai untuk 24 jam.
  static const durations = <(String, Duration)>[
    ('30 menit', Duration(minutes: 30)),
    ('1 jam', Duration(hours: 1)),
    ('3 jam', Duration(hours: 3)),
    ('24 jam', Duration(hours: 24)),
  ];

  /// HP anak menerima kode dari step ini sampai 2 step sebelumnya (≈10–15 menit),
  /// plus 1 step ke depan untuk toleransi beda jam.
  static const acceptPast = 2;
  static const acceptFuture = 1;

  static int stepAt(DateTime t) => t.millisecondsSinceEpoch ~/ stepMs;

  static String code(String secret, int step, int durationIndex) {
    final h = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('unlock:$step:$durationIndex')).bytes;
    final o = h[h.length - 1] & 0x0f;
    final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
    return (bin % 1000000).toString().padLeft(6, '0');
  }

  /// Kapan kode yang dibuat sekarang berhenti diterima HP anak.
  static DateTime validUntil(DateTime now) =>
      DateTime.fromMillisecondsSinceEpoch((stepAt(now) + acceptPast + 1) * stepMs);

  static String newSecret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
