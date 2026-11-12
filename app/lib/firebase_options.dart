// PLACEHOLDER — file ini akan ditimpa otomatis oleh:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure --platforms=android,web
//
// Selama belum dikonfigurasi, aplikasi menampilkan layar "Firebase belum dikonfigurasi".
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
        'Firebase belum dikonfigurasi. Jalankan `flutterfire configure` di folder app/.',
      );
}
