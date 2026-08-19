import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'family_models.dart';
import 'pairing.dart';

class FamilyRepository {
  FamilyRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  static const _uuid = Uuid();

  Stream<User?> get authChanges => _auth.authStateChanges();

  Future<UserCredential> signIn({required String email, required String password}) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<UserCredential> createAccount({required String email, required String password}) =>
      _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> resetPassword(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  Future<GuardianProfile?> readGuardianProfile(String userId) async {
    final snapshot = await _firestore.doc('users/$userId').get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return GuardianProfile.fromMap(snapshot.id, snapshot.data()!);
  }

  Future<ChildProfile?> readLinkedChildProfile(String deviceUserId) async {
    final link = await _firestore.doc('childDevices/$deviceUserId').get();
    final linkData = link.data();
    if (!link.exists || linkData == null) return null;
    final familyId = linkData['familyId'] as String?;
    final childId = linkData['childId'] as String?;
    if (familyId == null || childId == null) return null;
    final child = await _firestore.doc('families/$familyId/children/$childId').get();
    if (!child.exists || child.data() == null) return null;
    return ChildProfile.fromMap(child.id, child.data()!);
  }

  Future<GuardianProfile> createFamily({required String familyName, String? displayName}) async {
    final user = _requireGuardian();
    final familyRef = _firestore.collection('families').doc();
    final memberRef = familyRef.collection('members').doc(user.uid);
    final userRef = _firestore.collection('users').doc(user.uid);
    final batch = _firestore.batch();
    batch.set(familyRef, {
      'name': familyName.trim(),
      'ownerId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(memberRef, {
      'role': FamilyRole.owner.name,
      'displayName': displayName?.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(userRef, {
      'familyId': familyRef.id,
      'role': FamilyRole.owner.name,
      'displayName': displayName?.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return GuardianProfile(id: user.uid, familyId: familyRef.id, role: FamilyRole.owner, displayName: displayName);
  }

  Stream<List<ChildProfile>> watchChildren(String familyId) => _firestore
      .collection('families/$familyId/children')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => ChildProfile.fromMap(doc.id, doc.data())).toList());

  Future<ChildProfile> addChild({required String familyId, required String name}) async {
    final user = _requireGuardian();
    final childRef = _firestore.collection('families/$familyId/children').doc();
    await childRef.set({
      'id': childRef.id,
      'familyId': familyId,
      'name': name.trim(),
      'deviceStatus': 'waiting_for_pairing',
      'deviceUserId': null,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ChildProfile(id: childRef.id, familyId: familyId, name: name.trim(), deviceStatus: 'waiting_for_pairing');
  }

  Future<void> renameChild({
    required String familyId,
    required String childId,
    required String name,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw ArgumentError.value(name, 'name', 'اسم الطفل مطلوب');
    return _firestore.doc('families/$familyId/children/$childId').update({
      'name': normalizedName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeChild({required String familyId, required String childId}) =>
      _firestore.doc('families/$familyId/children/$childId').delete();

  Future<String> createPairing({required String familyId, required String childId}) async {
    final user = _requireGuardian();
    final code = createPairingCode();
    await _firestore.doc('pairingSessions/$code').set({
      'familyId': familyId,
      'childId': childId,
      'createdBy': user.uid,
      'status': 'pending',
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10))),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  Future<ChildProfile> claimPairing(String code) async {
    if (!isValidPairingCode(code)) throw ArgumentError.value(code, 'code', 'رمز الاقتران غير صحيح');
    final credential = _auth.currentUser == null ? await _auth.signInAnonymously() : null;
    final childUser = credential?.user ?? _auth.currentUser!;
    final pairingRef = _firestore.doc('pairingSessions/${code.trim()}');
    late ChildProfile result;
    await _firestore.runTransaction((transaction) async {
      final pairing = await transaction.get(pairingRef);
      final data = pairing.data();
      if (!pairing.exists || data == null || data['status'] != 'pending') throw StateError('رمز الاقتران غير متاح');
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      if (expiresAt.isBefore(DateTime.now())) throw StateError('انتهت صلاحية رمز الاقتران');
      final familyId = data['familyId'] as String;
      final childId = data['childId'] as String;
      final childRef = _firestore.doc('families/$familyId/children/$childId');
      final childSnapshot = await transaction.get(childRef);
      final childData = childSnapshot.data() ?? <String, dynamic>{};
      transaction.update(pairingRef, {'status': 'claimed', 'claimedBy': childUser.uid, 'claimedAt': FieldValue.serverTimestamp()});
      transaction.update(childRef, {'deviceUserId': childUser.uid, 'deviceStatus': 'linked', 'lastSeenAt': FieldValue.serverTimestamp()});
      result = ChildProfile(
        id: childUser.uid,
        familyId: familyId,
        name: childData['name'] as String? ?? 'جهاز الطفل',
        deviceStatus: 'linked',
      );
      transaction.set(_firestore.doc('childDevices/${childUser.uid}'), {
        'familyId': familyId,
        'childId': childId,
        'pairingCode': code.trim(),
        'linkedAt': FieldValue.serverTimestamp(),
        'installationId': _uuid.v4(),
      });
    });
    return result;
  }

  User _requireGuardian() {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) throw StateError('يلزم تسجيل دخول الوالد أولاً');
    return user;
  }
}
