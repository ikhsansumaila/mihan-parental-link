import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/schedule.dart';
import '../core/unlock_code.dart';

/// Struktur Firestore:
///
/// children/{gmail}     { ownerUid, ownerEmail, name, email, createdAt }
///                      Didaftarkan orang tua. ID dokumen = Gmail anak (huruf kecil).
/// devices/{deviceId}   { ownerUid, childUid, childEmail, name, model, createdAt,
///                        policy: {...Policy.toJson()},
///                        status: { locked, reason, nextChange, accessibility, admin,
///                                  battery, appVersion, tz },
///                        lastSeen }
/// Pesan dari HP anak: devices/{id}/messages/{msgId} { text, createdAt, read }
class ChildMessage {
  final String id;
  final String text;
  final DateTime? createdAt;
  final bool read;
  ChildMessage({required this.id, required this.text, required this.createdAt, required this.read});

  factory ChildMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return ChildMessage(
      id: d.id,
      text: (j['text'] as String?) ?? '',
      createdAt: (j['createdAt'] as Timestamp?)?.toDate(),
      read: j['read'] == true,
    );
  }
}

class ChildInfo {
  final String email;
  final String name;
  ChildInfo({required this.email, required this.name});

  factory ChildInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) =>
      ChildInfo(email: d.id, name: (d.data()?['name'] as String?) ?? d.id);
}

class DeviceInfo {
  final String id;
  final String name;
  final String? model;
  final String ownerUid;
  final Policy policy;
  final Map<String, dynamic> status;
  final DateTime? lastSeen;
  final String? childEmail;
  final String? unlockSecret;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.model,
    required this.ownerUid,
    required this.policy,
    required this.status,
    required this.lastSeen,
    required this.childEmail,
    required this.unlockSecret,
  });

  factory DeviceInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? const {};
    return DeviceInfo(
      id: d.id,
      name: (j['name'] as String?) ?? 'Perangkat',
      model: j['model'] as String?,
      ownerUid: (j['ownerUid'] as String?) ?? '',
      policy: Policy.fromJson((j['policy'] as Map?)?.cast<String, dynamic>()),
      status: (j['status'] as Map?)?.cast<String, dynamic>() ?? const {},
      lastSeen: (j['lastSeen'] as Timestamp?)?.toDate(),
      childEmail: j['childEmail'] as String?,
      unlockSecret: j['unlockSecret'] as String?,
    );
  }

  bool get online => lastSeen != null && DateTime.now().difference(lastSeen!) < const Duration(minutes: 3);
  bool get protectionOk => status['accessibility'] == true;
}

class Repo {
  Repo._();
  static final instance = Repo._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _devices => _db.collection('devices');
  CollectionReference<Map<String, dynamic>> get _children => _db.collection('children');

  static String normEmail(String e) => e.trim().toLowerCase();

  // ---------------------------------------------------------------- parent

  Stream<List<DeviceInfo>> devicesOf(String uid) => _devices
      .where('ownerUid', isEqualTo: uid)
      .snapshots()
      .map((q) => q.docs.map(DeviceInfo.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  Stream<DeviceInfo?> device(String id) =>
      _devices.doc(id).snapshots().map((d) => d.exists ? DeviceInfo.fromDoc(d) : null);

  Stream<List<ChildInfo>> childrenOf(String uid) => _children
      .where('ownerUid', isEqualTo: uid)
      .snapshots()
      .map((q) => q.docs.map(ChildInfo.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  /// Daftarkan Gmail anak. HP anak yang login dengan Gmail ini akan otomatis terhubung.
  Future<void> addChild({required String name, required String email}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final id = normEmail(email);
    if (id == normEmail(user.email ?? '')) {
      throw Exception('Itu Gmail akun orang tua. Masukkan Gmail milik anak.');
    }
    try {
      await _children.doc(id).set({
        'ownerUid': user.uid,
        'ownerEmail': user.email,
        'name': name,
        'email': id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      // Dokumen sudah ada milik orang tua lain → rules menolak update.
      if (e.code == 'permission-denied') {
        throw Exception('Gmail ini sudah didaftarkan oleh akun orang tua lain.');
      }
      rethrow;
    }
  }

  Future<void> removeChild(String email) => _children.doc(normEmail(email)).delete();

  Future<void> savePolicy(String deviceId, Policy p) =>
      _devices.doc(deviceId).update({'policy': p.toJson(), 'policyUpdatedAt': FieldValue.serverTimestamp()});

  Future<void> setOverride(String deviceId, Override? o) =>
      _devices.doc(deviceId).update({'policy.override': o?.toJson(), 'policyUpdatedAt': FieldValue.serverTimestamp()});

  /// Device lama (sebelum fitur kode) belum punya secret → buatkan. HP anak menerimanya saat online.
  Future<String> ensureUnlockSecret(DeviceInfo d) async {
    if (d.unlockSecret != null) return d.unlockSecret!;
    final s = UnlockCode.newSecret();
    await _devices.doc(d.id).update({'unlockSecret': s});
    return s;
  }

  Future<void> renameDevice(String deviceId, String name) => _devices.doc(deviceId).update({'name': name});

  /// Hapus pesan dulu (sub-koleksi tidak ikut terhapus otomatis), lalu device.
  Future<void> deleteDevice(String deviceId) async {
    final msgs = await _messages(deviceId).get();
    for (var i = 0; i < msgs.docs.length; i += 400) {
      final b = _db.batch();
      for (final d in msgs.docs.skip(i).take(400)) {
        b.delete(d.reference);
      }
      await b.commit();
    }
    await _devices.doc(deviceId).delete();
  }

  // ---------------------------------------------------------------- pesan anak

  CollectionReference<Map<String, dynamic>> _messages(String deviceId) =>
      _devices.doc(deviceId).collection('messages');

  Stream<List<ChildMessage>> messages(String deviceId, {int limit = 30}) => _messages(deviceId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(ChildMessage.fromDoc).toList());

  Stream<int> unreadCount(String deviceId) =>
      _messages(deviceId).where('read', isEqualTo: false).snapshots().map((q) => q.size);

  Future<void> markRead(String deviceId, Iterable<String> ids) async {
    final b = _db.batch();
    for (final id in ids) {
      b.update(_messages(deviceId).doc(id), {'read': true});
    }
    await b.commit();
  }

  // ---------------------------------------------------------------- child

  /// Dipanggil di HP anak setelah login Google. Mencari pendaftaran Gmail ini
  /// oleh orang tua, lalu memakai ulang dokumen device lama (instal ulang) atau membuat baru.
  ///
  /// Langkah 1: [findMyRegistration] → tampilkan email orang tua untuk dikonfirmasi.
  /// Langkah 2: [pairCurrentGoogleUser].
  Future<({String ownerEmail, String childName})> findMyRegistration() async {
    final c = await _myRegistration();
    return (ownerEmail: (c['ownerEmail'] as String?) ?? '?', childName: (c['name'] as String?) ?? 'HP Anak');
  }

  Future<Map<String, dynamic>> _myRegistration() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) throw Exception('Belum login dengan Google.');
    final email = normEmail(user.email!);
    DocumentSnapshot<Map<String, dynamic>>? childDoc;
    try {
      childDoc = await _children.doc(email).get();
    } on FirebaseException catch (e) {
      // Dokumen tidak ada → rules menolak (supaya Gmail tidak bisa dicek dari luar).
      if (e.code != 'permission-denied') rethrow;
    }
    if (childDoc == null || !childDoc.exists) {
      throw Exception(
        'Gmail $email belum didaftarkan orang tua.\n'
        'Minta orang tua menekan "Tambah anak" di aplikasi atau web Mihan Parental Link, '
        'lalu memasukkan Gmail ini.',
      );
    }
    return childDoc.data()!;
  }

  Future<String> pairCurrentGoogleUser({required String model}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final email = normEmail(user.email!);
    final c = await _myRegistration();
    final ownerUid = c['ownerUid'] as String;

    // Instal ulang di HP yang sama → pakai dokumen lama supaya jadwal tetap.
    final mine = await _devices.where('childUid', isEqualTo: user.uid).get();
    for (final d in mine.docs) {
      if (d.data()['ownerUid'] == ownerUid && d.data()['model'] == model) {
        await d.reference.update({'lastSeen': FieldValue.serverTimestamp()});
        return d.id;
      }
    }

    final ref = _devices.doc();
    await ref.set({
      'ownerUid': ownerUid,
      'childUid': user.uid,
      'childEmail': email,
      'name': c['name'] ?? 'HP Anak',
      'model': model,
      // Kunci untuk kode buka darurat offline (lib/core/unlock_code.dart).
      'unlockSecret': UnlockCode.newSecret(),
      'createdAt': FieldValue.serverTimestamp(),
      'policy': const Policy().toJson(),
      'status': {'locked': false, 'reason': 'Baru dipasangkan'},
      'lastSeen': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }
}
