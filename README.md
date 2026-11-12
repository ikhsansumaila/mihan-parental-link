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
  lib/ui/child/…              ← login Google anak + checklist izin di HP anak
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
2. Aktifkan **Authentication** → provider **Google** dan **Email/Password**.
3. Buat database **Cloud Firestore** (mode production, lokasi `asia-southeast2` / Jakarta).
4. Hubungkan app:
   ```bash
   npm i -g firebase-tools && firebase login
   dart pub global activate flutterfire_cli
   cd app && flutterfire configure --platforms=android,web
   ```
   Perintah ini membuat `lib/firebase_options.dart` dan `android/app/google-services.json`.
   **Login Google di Android** butuh SHA-1 & SHA-256 dari keystore debug *dan* release terdaftar:
   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
   firebase apps:android:sha:create <ANDROID_APP_ID> <SHA>
   ```
   Setelah itu (dan setelah provider Google aktif) jalankan ulang `flutterfire configure` supaya
   `google-services.json` berisi OAuth client. Kalau login Google gagal dengan error `10`/`DEVELOPER_ERROR`,
   penyebabnya hampir selalu SHA yang belum terdaftar.
5. Deploy rules: `firebase deploy --only firestore` (dari folder root).

## Build & Deployment

Ringkasnya ada tiga hal yang di-deploy, masing-masing terpisah:

| Bagian | Perintah | Hasil |
|---|---|---|
| APK Android | `flutter build apk --release` (di `app/`) | `app/build/app/outputs/flutter-apk/app-release.apk` |
| Web dashboard | `flutter build web` lalu `firebase deploy --only hosting` | https://mihan-parental-link.web.app |
| Rules Firestore | `firebase deploy --only firestore` | rules & index aktif di database |

Semua perintah `firebase …` dijalankan dari **folder root** repo, semua perintah `flutter …` dari **`app/`**.

### 1. Development

```bash
cd app
flutter pub get
flutter run -d chrome          # dashboard web di localhost (login Google jalan di localhost)
flutter run                    # ke HP Android yang tersambung USB (USB debugging aktif)
```

Mode debug memakai keystore debug (`~/.android/debug.keystore`). SHA-nya harus terdaftar di Firebase
supaya login Google di Android jalan (lihat Setup → Firebase).

### 2. Tes (jalankan sebelum rilis)

```bash
cd app
flutter analyze                                    # lint, harus "No issues found!"
flutter test                                       # tes engine jadwal (Dart)
(cd android && ./gradlew :app:testDebugUnitTest)   # tes engine jadwal (Kotlin)
```

### 3. Build APK Android (release)

**Keystore rilis (sekali saja).** APK release ditandatangani dengan `app/android/octalink-release.jks`.
Passwordnya dibaca dari `app/android/key.properties`. File ini tidak di-commit, salin dari
`key.properties.example` lalu isi:

```properties
storeFile=octalink-release.jks
storePassword=...
keyAlias=octalink
keyPassword=...
```

> ⚠ **Backup keystore + password-nya** (mis. password manager / cloud pribadi). Kalau hilang, update APK
> tidak bisa di-install di atas versi lama (harus uninstall dulu → proteksi di HP anak terlepas), dan
> SHA baru harus didaftarkan ulang ke Firebase. Kalau `key.properties` tidak ada, build tetap jalan tapi
> ditandatangani dengan debug key (muncul peringatan di log Gradle).

**Naikkan versi** di `app/pubspec.yaml` setiap rilis. Angka setelah `+` (versionCode) **wajib naik**,
kalau tidak Android menolak update:

```yaml
version: 1.0.1+2   # versionName+versionCode
```

**Build:**

```bash
cd app
flutter build apk --release                    # satu APK untuk semua HP (~55 MB)
# atau, lebih kecil per HP:
flutter build apk --release --split-per-abi    # pakai app-arm64-v8a-release.apk untuk HP modern
```

**Install ke HP anak:**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk   # -r = update tanpa hapus data
```

Atau kirim file APK ke HP (Drive/WhatsApp/kabel), buka, izinkan *Install dari sumber tidak dikenal*.
Update di atas versi lama **tidak** melepas pairing maupun proteksi.

> Kalau nanti rilis lewat **Play Store**: build `flutter build appbundle --release`, lalu daftarkan juga
> SHA-1/SHA-256 dari *Play Console → App integrity → App signing key* ke Firebase. Tanpa itu login Google
> gagal di APK yang diunduh dari Play Store.

### 4. Deploy web dashboard (Firebase Hosting)

```bash
cd app && flutter build web --release && cd ..
firebase deploy --only hosting
```

- Hasilnya langsung live di https://mihan-parental-link.web.app (dan `.firebaseapp.com`).
- Kalau browser masih menampilkan versi lama: **Ctrl+Shift+R**.
- Domain hosting sudah otomatis masuk *Authorized domains* di Firebase Auth. Kalau memakai domain sendiri,
  tambahkan di *Authentication → Settings → Authorized domains*, kalau tidak login Google ditolak.
- Rollback: *Firebase Console → Hosting → Release history → ⋮ → Rollback*.

### 5. Deploy rules Firestore

Wajib setiap kali `firestore.rules` atau `firestore.indexes.json` berubah:

```bash
firebase deploy --only firestore
```

Rules lama tetap aktif sampai deploy berhasil, jadi deploy rules **sebelum** merilis APK/web yang
bergantung pada rules baru. Tes rules tanpa menyentuh data asli bisa dilakukan dengan emulator:
`firebase emulators:start --only firestore`.

### 6. Konfigurasi Firebase berubah?

Jalankan ulang ini setelah menambah SHA, mengaktifkan provider login baru, atau mengganti application ID:

```bash
cd app && flutterfire configure --platforms=android,web
```

Lalu build ulang APK dan web. File yang diperbarui (`google-services.json`, `firebase_options.dart`)
boleh di-commit, karena isinya bukan rahasia (keamanan dijaga rules Firestore).

### Checklist rilis

1. `flutter analyze` + `flutter test` + tes Kotlin lolos.
2. Naikkan `version` di `pubspec.yaml`.
3. `firebase deploy --only firestore` (kalau rules berubah).
4. `flutter build web` → `firebase deploy --only hosting`.
5. `flutter build apk --release` → install ke HP anak (`adb install -r …`).
6. Commit + tag: `git tag v1.0.1 && git push --tags`.

### Troubleshooting

| Gejala | Penyebab / solusi |
|---|---|
| Login Google di Android error `10` / `DEVELOPER_ERROR` | SHA keystore yang dipakai build belum terdaftar. Daftarkan, lalu `flutterfire configure` ulang. |
| Login Google error "CredentialManager requires a serverClientId" | `google-services.json` belum berisi OAuth client web. Aktifkan provider Google, lalu `flutterfire configure` ulang. |
| "Metode login ini belum diaktifkan" | Provider (Google / Email/Password) belum *Enabled* di Firebase Console. |
| Web: login popup langsung tertutup | Domain belum ada di *Authorized domains*, atau popup diblokir browser. |
| `permission-denied` setelah update | Rules baru belum di-deploy: `firebase deploy --only firestore`. |
| APK tidak bisa di-install di atas versi lama | Keystore berbeda (mis. build tanpa `key.properties`) atau versionCode tidak naik. |
| Gradle gagal "Unsupported class file major version" | JDK terlalu baru, pakai JDK 17/21 (lihat Prasyarat). |

## Cara pakai
1. **Orang tua**: login (Google atau email) di web atau di app Android (pilih "Orang tua") →
   *Tambah anak* → isi nama dan **Gmail anak**.
2. **HP anak**: install APK → pilih "Anak" → *Masuk dengan Google* → pilih Gmail anak →
   konfirmasi email orang tua yang muncul. Kalau app diinstal ulang di HP yang sama, cukup login lagi;
   jadwal lama tetap dipakai.
3. Di HP anak, aktifkan semua izin di checklist:
   - **Layanan aksesibilitas** (wajib). Di Android 13+ untuk APK yang di-sideload: buka
     *Info aplikasi → ⋮ → Izinkan setelan terbatas* dulu, baru aksesibilitas bisa dinyalakan.
   - **Admin perangkat** (mencegah uninstall).
   - **Abaikan optimasi baterai**. Di Xiaomi/Oppo/Vivo juga aktifkan *Autostart*.
4. Buat jadwal dari dashboard. Perubahan sampai ke HP anak dalam hitungan detik.
5. **Pesan dari anak**: saat terkunci, anak bisa menekan *Kirim pesan ke orang tua* di layar kunci
   (pesan cepat atau tulis sendiri, maks. 300 karakter, jeda 30 detik antar pesan). Pesan muncul di
   dashboard dengan badge di daftar perangkat. Dari kartu pesan, orang tua bisa langsung *Beri waktu*.
   Layar pesan tertutup otomatis kalau anak pindah aplikasi atau setelah 3 menit, lalu layar kunci kembali.
6. **Saat terkunci** yang masih bisa dipakai hanya: telepon/darurat, kirim pesan ke orang tua, dan
   **Pilih Wi-Fi** (mis. pindah ke tethering HP orang tua saat di luar rumah). Mode Wi-Fi hanya
   mengizinkan halaman Wi-Fi di Settings, maksimal 3 menit; pindah ke halaman/aplikasi lain → terkunci lagi.
   Panel notifikasi & quick settings otomatis ditutup (Android 12+).
7. **Kode buka darurat (offline)**: dashboard → perangkat → *Kode buka darurat* → pilih durasi
   (30 menit / 1 jam / 3 jam / 24 jam) → bacakan kode 6 digit ke anak (mis. lewat telepon). Di HP anak:
   layar kunci → *Masukkan kode orang tua*. Verifikasi dilakukan di HP (HMAC dengan `unlockSecret`
   per perangkat), jadi **tidak butuh internet** di kedua sisi. Kode berganti tiap 5 menit, berlaku ±10–15
   menit, sekali pakai; salah 5× → keypad dikunci 5 menit. Perintah orang tua yang dikirim setelah kode
   dipakai (mis. *Kunci sekarang*) membatalkan kode. Syarat: HP anak sudah pernah online dengan versi
   aplikasi yang punya fitur ini (untuk menerima `unlockSecret`).

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
