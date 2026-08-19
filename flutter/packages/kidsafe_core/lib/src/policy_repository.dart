import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceAppRecord {
  const DeviceAppRecord({required this.packageName, required this.label});
  final String packageName;
  final String label;

  factory DeviceAppRecord.fromMap(Map<String, dynamic> value) => DeviceAppRecord(
        packageName: value['packageName'] as String,
        label: value['label'] as String,
      );

  Map<String, dynamic> toMap() => {'packageName': packageName, 'label': label};
}

class FamilyAppPolicy {
  const FamilyAppPolicy({required this.allowedPackages, required this.dailyLimitMinutes, required this.blockedStartMinute, required this.blockedEndMinute, required this.updatedAt});
  final List<String> allowedPackages;
  final int dailyLimitMinutes;
  final int? blockedStartMinute;
  final int? blockedEndMinute;
  final DateTime? updatedAt;

  factory FamilyAppPolicy.fromMap(Map<String, dynamic>? value) => FamilyAppPolicy(
        allowedPackages: List<String>.from(value?['allowedPackages'] as List? ?? const []),
        dailyLimitMinutes: value?['dailyLimitMinutes'] as int? ?? 0,
        blockedStartMinute: value?['blockedStartMinute'] as int?,
        blockedEndMinute: value?['blockedEndMinute'] as int?,
        updatedAt: (value?['updatedAt'] as Timestamp?)?.toDate(),
      );

  bool isBlockedAt(DateTime time) {
    if (blockedStartMinute == null || blockedEndMinute == null || blockedStartMinute == blockedEndMinute) return false;
    final minute = time.hour * 60 + time.minute;
    return blockedStartMinute! < blockedEndMinute!
        ? minute >= blockedStartMinute! && minute < blockedEndMinute!
        : minute >= blockedStartMinute! || minute < blockedEndMinute!;
  }

  Map<String, dynamic> toMap() => {
        'schemaVersion': 1,
        'allowedPackages': allowedPackages,
        'dailyLimitMinutes': dailyLimitMinutes,
        'blockedStartMinute': blockedStartMinute,
        'blockedEndMinute': blockedEndMinute,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class PolicyRepository {
  PolicyRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _policyRef(String familyId, String childId) =>
      _firestore.doc('families/$familyId/children/$childId/policy/current');

  Stream<List<DeviceAppRecord>> watchInstalledApps(String familyId, String childId) => _firestore
      .collection('families/$familyId/children/$childId/installedApps')
      .orderBy('label')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => DeviceAppRecord.fromMap(doc.data())).toList());

  Stream<FamilyAppPolicy> watchPolicy(String familyId, String childId) => _policyRef(familyId, childId)
      .snapshots()
      .map((snapshot) => FamilyAppPolicy.fromMap(snapshot.data()));

  Future<void> syncInstalledApps({required String familyId, required String childId, required List<DeviceAppRecord> apps}) async {
    final batch = _firestore.batch();
    for (final app in apps) {
      batch.set(_firestore.doc('families/$familyId/children/$childId/installedApps/${app.packageName.replaceAll('/', '_')}'), {
        ...app.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> savePolicy({required String familyId, required String childId, required FamilyAppPolicy policy}) =>
      _policyRef(familyId, childId).set(policy.toMap(), SetOptions(merge: true));
}
