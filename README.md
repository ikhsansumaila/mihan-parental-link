# Mihan Parental Link

Aplikasi pengawasan HP anak (mirip Google Family Link) dengan dua fitur yang tidak ada di Family Link:

1. **Banyak slot waktu per hari**: misalnya Senin boleh pakai 05:30–06:30, 14:00–17:00, dan 19:30–21:00.
2. **Jadwal mingguan dengan masa aktif**: misalnya "Masa ujian" 1–30 Nov. Selama periode itu jadwal ini
   menggantikan jadwal permanen, lalu otomatis kembali ke jadwal permanen setelah periode habis.

Satu codebase Flutter:

| Platform | Mode |
|---|---|
| Android | **Orang tua** (atur jadwal) atau **Anak** (dikunci sesuai jadwal) |
| Web (desktop & mobile) | Orang tua saja |

## Arsitektur

```
app/
  lib/core/schedule.dart      ← model jadwal + engine evaluasi (dites: test/schedule_test.dart)
  lib/data/repo.dart          ← akses Firestore
  lib/ui/parent/…             ← dashboard orang tua (responsif: ≥900px dua panel)
  lib/ui/child/…              ← pairing + checklist izin di HP anak
  android/app/src/main/kotlin/com/mihan/parentallink/
    PolicyEngine.kt           ← port 1:1 engine Dart (dites: src/test/…/PolicyEngineTest.kt)
    EnforcerService.kt        ← foreground service: sinkron Firestore, evaluasi tiap 15 dtk, heartbeat
    GuardService.kt           ← Accessibility Service: overlay layar kunci + anti-tamper
    Receivers.kt              ← Device Admin (anti-uninstall, lockNow) + Boot receiver
firestore.rules               ← aturan keamanan (anak tidak bisa mengubah jadwal)
```

Penegakan jadwal di HP anak **berjalan offline**: policy terakhir disimpan lokal dan dievaluasi di
perangkat. Firestore hanya dipakai untuk mengirim perubahan dan status.

### Aturan prioritas jadwal

Jika beberapa jadwal berlaku di tanggal yang sama:
1. Jadwal **dengan masa aktif** mengalahkan jadwal permanen.
2. Masa aktif **lebih pendek** menang (lebih spesifik).
3. Kalau masih sama, jadwal **terbaru** menang.

Override "Kunci sekarang" / "Beri waktu tambahan" mengalahkan semua jadwal sampai waktunya habis.

## Setup

### 1. Prasyarat
- Flutter 3.38+
- **JDK 17 atau 21** (JDK 25 bawaan Android Studio terlalu baru untuk Gradle 8.14):
  `sudo apt install openjdk-21-jdk`, lalu `flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk-amd64`

### 2. Firebase
1. Buat project di https://console.firebase.google.com
2. Aktifkan **Authentication** → provider **Email/Password** dan **Anonymous**.
3. Buat database **Cloud Firestore** (mode production).
4. Hubungkan app:
   ```bash
   npm i -g firebase-tools && firebase login
   dart pub global activate flutterfire_cli
   cd app && flutterfire configure --platforms=android,web
   ```
   Perintah ini membuat `lib/firebase_options.dart` dan `android/app/google-services.json`.
5. Deploy rules: `firebase deploy --only firestore` (dari folder root).

### 3. Jalankan
```bash
cd app
flutter test                       # tes engine jadwal (Dart)
(cd android && ./gradlew :app:testDebugUnitTest)   # tes engine jadwal (Kotlin)
flutter run -d chrome              # dashboard web
flutter build apk --release        # APK Android
flutter build web && cd .. && firebase deploy --only hosting   # publish web
```

## Cara pakai
1. **Orang tua**: login di web atau di app Android (pilih "Orang tua") → *Tambah HP anak* → muncul kode 6 digit.
2. **HP anak**: install APK → pilih "Anak" → masukkan kode.
3. Di HP anak, aktifkan semua izin di checklist:
   - **Layanan aksesibilitas** (wajib). Di Android 13+ untuk APK yang di-sideload: buka
     *Info aplikasi → ⋮ → Izinkan setelan terbatas* dulu, baru aksesibilitas bisa dinyalakan.
   - **Admin perangkat** (mencegah uninstall).
   - **Abaikan optimasi baterai**. Di Xiaomi/Oppo/Vivo juga aktifkan *Autostart*.
4. Buat jadwal dari dashboard. Perubahan sampai ke HP anak dalam hitungan detik.

Untuk melepas HP anak: dashboard → ⚙ → *Lepaskan perangkat*. Proteksi otomatis mati dan
admin perangkat dicabut, jadi aplikasi bisa di-uninstall.

## Keterbatasan yang diketahui (MVP)
- **Jam HP diubah anak**: engine memakai jam lokal perangkat. Tamper guard menutup Settings yang
  menyebut Mihan Parental Link, tapi belum menutup halaman tanggal/jam. Rencana: pakai offset waktu server.
- **Safe mode / factory reset** tetap bisa mem-bypass. Proteksi penuh butuh mode *Device Owner*
  (provisioning via QR/adb saat HP baru di-reset). Itu pengembangan berikutnya.
- Belum ada: batas total menit per hari, blokir per-aplikasi, laporan pemakaian, notifikasi push ke orang tua.
- Overlay menutupi seluruh layar saat terkunci, termasuk app Mihan Parental Link sendiri. Kalau mau mengatur
  izin di HP anak saat jam terkunci, beri "waktu tambahan" dulu dari dashboard.
