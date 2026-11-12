import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Jembatan ke kode Kotlin (lihat MainActivity.kt). Hanya berfungsi di Android.
class Enforcer {
  static const _ch = MethodChannel('mihan_parental_link/enforcer');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// ID device yang tersimpan di native (null = belum dipasangkan sebagai HP anak).
  static Future<String?> deviceId() async {
    if (!supported) return null;
    return _ch.invokeMethod<String>('getDeviceId');
  }

  /// Simpan ID device dan nyalakan service penegak jadwal.
  static Future<void> activate(String deviceId) => _ch.invokeMethod('activate', {'deviceId': deviceId});

  static Future<String> model() async => (await _ch.invokeMethod<String>('getModel')) ?? 'Android';

  /// { accessibility, admin, battery, notifications, locked, reason, nextChange }
  static Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod<Map>('status') ?? const {});

  static Future<void> openAccessibility() => _ch.invokeMethod('openAccessibility');
  static Future<void> requestAdmin() => _ch.invokeMethod('requestAdmin');
  static Future<void> requestBattery() => _ch.invokeMethod('requestBattery');
  static Future<void> requestNotifications() => _ch.invokeMethod('requestNotifications');
}
