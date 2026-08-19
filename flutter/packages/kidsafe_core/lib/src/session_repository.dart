import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'family_models.dart';

enum SignalSender { guardian, child }
enum SessionSignalKind { offer, answer, iceCandidate, acknowledgement, end }

class SessionSignal {
  const SessionSignal({required this.id, required this.sender, required this.kind, required this.payload});
  final String id;
  final SignalSender sender;
  final SessionSignalKind kind;
  final Map<String, dynamic> payload;

  factory SessionSignal.fromMap(String id, Map<String, dynamic> value) => SessionSignal(
        id: id,
        sender: SignalSender.values.byName(value['sender'] as String),
        kind: SessionSignalKind.values.byName(value['kind'] as String),
        payload: Map<String, dynamic>.from(value['payload'] as Map? ?? const {}),
      );
}

List<SessionSignal> peerSignals(Iterable<SessionSignal> signals, SignalSender ownRole) =>
    signals.where((signal) => signal.sender != ownRole).toList(growable: false);

class FamilySessionRepository {
  FamilySessionRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _sessions(String familyId) => _firestore.collection('families/$familyId/sessions');

  Future<FamilySession> createRequest({
    required String familyId,
    required String childId,
    required FamilySessionKind kind,
    required String reason,
  }) async {
    final guardian = _auth.currentUser;
    if (guardian == null || guardian.isAnonymous) throw StateError('يلزم حساب والد مصادق عليه لطلب جلسة عائلية.');
    final ref = _sessions(familyId).doc();
    final label = switch (kind) {
      FamilySessionKind.audio => 'الوالد يطلب جلسة صوت عائلية.',
      FamilySessionKind.video => 'الوالد يطلب جلسة فيديو عائلية.',
      FamilySessionKind.screen => 'الوالد يطلب مشاركة شاشة مرئية.',
    };
    await ref.set({
      'familyId': familyId,
      'childId': childId,
      'kind': kind.name,
      'status': FamilySessionStatus.requested.name,
      'reason': reason,
      'childVisibleLabel': label,
      'requestedBy': guardian.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return FamilySession(id: ref.id, familyId: familyId, childId: childId, kind: kind, status: FamilySessionStatus.requested, childVisibleLabel: label, reason: reason);
  }

  Stream<List<FamilySession>> watchChildSessions({required String familyId, required String childId}) => _sessions(familyId)
      .where('childId', isEqualTo: childId)
      .where('status', whereIn: [FamilySessionStatus.requested.name, FamilySessionStatus.acknowledged.name, FamilySessionStatus.active.name])
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => FamilySession.fromMap(doc.id, doc.data())).toList());

  Stream<List<FamilySession>> watchGuardianSessions(String familyId) => _sessions(familyId)
      .where('status', whereIn: [FamilySessionStatus.requested.name, FamilySessionStatus.acknowledged.name, FamilySessionStatus.active.name])
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => FamilySession.fromMap(doc.id, doc.data())).toList());

  Future<void> setStatus({required String familyId, required String sessionId, required FamilySessionStatus status}) =>
      _sessions(familyId).doc(sessionId).update({'status': status.name, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> sendSignal({required String familyId, required String sessionId, required SignalSender sender, required SessionSignalKind kind, required Map<String, dynamic> payload}) =>
      _sessions(familyId).doc(sessionId).collection('signals').add({
        'sender': sender.name,
        'kind': kind.name,
        'payload': payload,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Stream<List<SessionSignal>> watchPeerSignals({required String familyId, required String sessionId, required SignalSender ownRole}) =>
      _sessions(familyId).doc(sessionId).collection('signals').snapshots().map((snapshot) => peerSignals(snapshot.docs.map((doc) => SessionSignal.fromMap(doc.id, doc.data())), ownRole));

  Future<void> acknowledge({required String familyId, required String sessionId, required SignalSender sender}) async {
    await sendSignal(familyId: familyId, sessionId: sessionId, sender: sender, kind: SessionSignalKind.acknowledgement, payload: const {'accepted': true});
    await setStatus(familyId: familyId, sessionId: sessionId, status: FamilySessionStatus.acknowledged);
  }

  Future<void> end({required String familyId, required String sessionId, required SignalSender sender}) async {
    await sendSignal(familyId: familyId, sessionId: sessionId, sender: sender, kind: SessionSignalKind.end, payload: const {'reason': 'ended_by_family'});
    await setStatus(familyId: familyId, sessionId: sessionId, status: FamilySessionStatus.ended);
  }
}
