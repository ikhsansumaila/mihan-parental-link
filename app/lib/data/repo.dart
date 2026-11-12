import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/schedule.dart';

/// Struktur Firestore:
///
/// pairingCodes/{code}  { ownerUid, childName, expiresAt }
/// devices/{deviceId}   { ownerUid, childUid, name, model, pairingCode, createdAt,
///                        policy: {...Policy.toJson()},
///                        status: { locked, reason, nextChange, accessibility, admin,
///                                  battery, appVersion, tz },
///                        lastSeen }
class DeviceInfo {
  final String id;
  final String name;
  final String? model;
  final String ownerUid;
  final Policy policy;
  final Map<String, dynamic> status;
  final DateTime? lastSeen;
  final String? pairingCode;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.model,
    required this.ownerUid,
    required this.policy,
    required this.status,
    required this.lastSeen,
    required this.pairingCode,
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
      pairingCode: j['pairingCode'] as String?,
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
  CollectionReference<Map<String, dynamic>> get _codes => _db.collection('pairingCodes');

  // ---------------------------------------------------------------- parent

  Stream<List<DeviceInfo>> devicesOf(String uid) => _devices
      .where('ownerUid', isEqualTo: uid)
      .snapshots()
      .map((q) => q.docs.map(DeviceInfo.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));

  Stream<DeviceInfo?> device(String id) =>
      _devices.doc(id).snapshots().map((d) => d.exists ? DeviceInfo.fromDoc(d) : null);

  /// Buat kode pairing 6 digit yang berlaku 15 menit.
  Future<String> createPairingCode(String childName) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final rnd = Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = (100000 + rnd.nextInt(900000)).toString();
      final ref = _codes.doc(code);
      try {
        await ref.set({
          'ownerUid': uid,
          'childName': childName,
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 15))),
        });
        return code;
      } on FirebaseException catch (e) {
        // Kode bentrok dengan milik orang lain → rules menolak, coba lagi.
        if (e.code != 'permission-denied') rethrow;
      }
    }
    throw Exception('Gagal membuat kode pairing, coba lagi.');
  }

  Future<void> deletePairingCode(String code) => _codes.doc(code).delete();

  Future<void> savePolicy(String deviceId, Policy p) => _devices.doc(deviceId).update({
        'policy': p.toJson(),
        'policyUpdatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> setOverride(String deviceId, Override? o) => _devices.doc(deviceId).update({
        'policy.override': o?.toJson(),
        'policyUpdatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> renameDevice(String deviceId, String name) => _devices.doc(deviceId).update({'name': name});

  Future<void> deleteDevice(String deviceId) => _devices.doc(deviceId).delete();

  // ---------------------------------------------------------------- child

  /// Dipanggil di HP anak. Login anonim, validasi kode, buat dokumen device.
  Future<String> pairWithCode(String code, {required String model}) async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
    final uid = auth.currentUser!.uid;

    final codeDoc = await _codes.doc(code).get();
    if (!codeDoc.exists) throw Exception('Kode tidak ditemukan.');
    final c = codeDoc.data()!;
    final exp = (c['expiresAt'] as Timestamp).toDate();
    if (exp.isBefore(DateTime.now())) throw Exception('Kode sudah kedaluwarsa, minta kode baru.');

    final ref = _devices.doc();
    await ref.set({
      'ownerUid': c['ownerUid'],
      'childUid': uid,
      'name': c['childName'] ?? 'HP Anak',
      'model': model,
      'pairingCode': code,
      'createdAt': FieldValue.serverTimestamp(),
      'policy': const Policy().toJson(),
      'status': {'locked': false, 'reason': 'Baru dipasangkan'},
      'lastSeen': FieldValue.serverTimestamp(),
    });
    // Kode sekali pakai.
    await _codes.doc(code).delete().catchError((_) {});
    return ref.id;
  }
}
