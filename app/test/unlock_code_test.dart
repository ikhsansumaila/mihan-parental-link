import 'package:flutter_test/flutter_test.dart';
import 'package:mihan_parental_link/core/unlock_code.dart';

void main() {
  // Vektor acuan (dihitung dengan Python hmac). Kotlin memakai vektor yang sama: UnlockCodeTest.kt.
  test('kode sama dengan vektor acuan', () {
    expect(UnlockCode.code('test-secret-123', 5000000, 0), '729148');
    expect(UnlockCode.code('test-secret-123', 5000000, 3), '560662');
    expect(UnlockCode.code('AbCdEfGh0123456789xyzXYZ_-', 5912345, 1), '936705');
  });

  test('durasi berbeda → kode berbeda', () {
    final codes = {for (var i = 0; i < 4; i++) UnlockCode.code('s', 42, i)};
    expect(codes.length, 4);
  });

  test('secret acak 32 karakter', () {
    final a = UnlockCode.newSecret(), b = UnlockCode.newSecret();
    expect(a.length, 32);
    expect(a, isNot(b));
  });

  test('validUntil sekitar 10–15 menit ke depan', () {
    final now = DateTime(2026, 11, 12, 10, 2);
    final d = UnlockCode.validUntil(now).difference(now);
    expect(d.inMinutes, inInclusiveRange(10, 15));
  });
}
