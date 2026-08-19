import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'family_models.dart';
import 'safe_zone_engine.dart';

class SafetyRepository {
  SafetyRepository({FirebaseFirestore? firestore, FirebaseAuth? auth, http.Client? client})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  static const alertRelayUri = 'https://kidsafe-fcm-relay.jeneral2015.workers.dev';
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _client;

  Stream<List<SafeZone>> watchSafeZones(String familyId) => _firestore
      .collection('families/$familyId/safeZones')
      .orderBy('name')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => SafeZone.fromMap(doc.id, doc.data())).toList());

  Stream<ChildLocation?> watchChildLocation({required String familyId, required String childId}) => _firestore
      .doc('families/$familyId/children/$childId/location/current')
      .snapshots()
      .map((snapshot) {
        final value = snapshot.data();
        if (!snapshot.exists || value == null) return null;
        return ChildLocation(
          latitude: (value['latitude'] as num).toDouble(),
          longitude: (value['longitude'] as num).toDouble(),
          accuracyMeters: (value['accuracyMeters'] as num).toDouble(),
          recordedAt: (value['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });

  Future<void> saveSafeZone({required String familyId, required SafeZone zone}) =>
      _firestore.doc('families/$familyId/safeZones/${zone.id}').set(zone.toMap(), SetOptions(merge: true));

  Future<void> removeSafeZone({required String familyId, required String zoneId}) => _firestore.doc('families/$familyId/safeZones/$zoneId').delete();

  Future<void> saveChildLocation({required String familyId, required String childId, required ChildLocation location}) async {
    await _firestore.doc('families/$familyId/children/$childId/location/current').set(location.toMap());
    await recordAudit(
      familyId: familyId,
      childId: childId,
      type: 'location_update',
      message: 'تم تحديث موقع جهاز الطفل مع دقة ${location.accuracyMeters.round()} متر.',
    );
  }

  Future<void> recordAudit({required String familyId, required String childId, required String type, required String message, Map<String, dynamic>? metadata}) =>
      _firestore.collection('families/$familyId/auditEvents').add({
        'childId': childId,
        'type': type,
        'message': message,
        'metadata': metadata ?? const <String, dynamic>{},
        'actor': _auth.currentUser?.isAnonymous ?? false ? 'child-device' : 'guardian',
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> registerGuardianPushToken({required String familyId, required String token}) {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) throw StateError('يلزم حساب والد لتسجيل جهاز التنبيهات.');
    return _firestore.doc('families/$familyId/guardianDevices/${user.uid}').set({
      'token': token,
      'guardianId': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'platform': 'flutter',
    }, SetOptions(merge: true));
  }

  Future<void> requestSafeZoneExitAlert({required String familyId, required String childId, required SafeZone zone, required ChildLocation location}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('يلزم مستخدم مصادق عليه لإرسال تنبيه الخروج.');
    final idToken = await user.getIdToken();
    if (idToken == null) throw StateError('تعذر التحقق من جلسة الأسرة لإرسال التنبيه.');
    final response = await _client.post(
      Uri.parse(alertRelayUri),
      headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'familyId': familyId,
        'childId': childId,
        'eventType': 'safe_zone_exit',
        'title': 'تنبيه KidSafe: خروج من منطقة آمنة',
        'body': 'غادر جهاز الطفل منطقة ${zone.name}.',
        'latitude': location.latitude,
        'longitude': location.longitude,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('تعذر إرسال تنبيه الخروج الآن.');
  }

  Future<SafeZoneTransition> evaluateAndRecordZone({
    required String familyId,
    required String childId,
    required SafeZone zone,
    required ChildLocation location,
    required SafeZonePresence previous,
  }) async {
    final transition = evaluateSafeZoneTransition(zone: zone, location: location, previous: previous);
    if (transition.exited) {
      await recordAudit(
        familyId: familyId,
        childId: childId,
        type: 'safe_zone_exit',
        message: 'غادر جهاز الطفل المنطقة الآمنة: ${zone.name}.',
        metadata: {'zoneId': zone.id, 'latitude': location.latitude, 'longitude': location.longitude},
      );
      await requestSafeZoneExitAlert(familyId: familyId, childId: childId, zone: zone, location: location);
    } else if (transition.entered) {
      await recordAudit(familyId: familyId, childId: childId, type: 'safe_zone_enter', message: 'دخل جهاز الطفل المنطقة الآمنة: ${zone.name}.');
    }
    return transition;
  }
}
