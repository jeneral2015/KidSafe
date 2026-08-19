import 'package:cloud_firestore/cloud_firestore.dart';

enum FamilyRole { owner, guardian, child }

enum FamilySessionKind { audio, video, screen }

enum FamilySessionStatus { requested, acknowledged, active, ended }

class GuardianProfile {
  const GuardianProfile({required this.id, required this.familyId, required this.role, this.displayName});

  final String id;
  final String familyId;
  final FamilyRole role;
  final String? displayName;

  factory GuardianProfile.fromMap(String id, Map<String, dynamic> value) => GuardianProfile(
        id: id,
        familyId: value['familyId'] as String,
        role: FamilyRole.values.byName(value['role'] as String),
        displayName: value['displayName'] as String?,
      );
}

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.familyId,
    required this.name,
    required this.deviceStatus,
    this.lastSeenAt,
  });

  final String id;
  final String familyId;
  final String name;
  final String deviceStatus;
  final DateTime? lastSeenAt;

  factory ChildProfile.fromMap(String id, Map<String, dynamic> value) => ChildProfile(
        id: id,
        familyId: value['familyId'] as String,
        name: value['name'] as String? ?? 'جهاز الطفل',
        deviceStatus: value['deviceStatus'] as String? ?? 'unknown',
        lastSeenAt: (value['lastSeenAt'] as Timestamp?)?.toDate(),
      );
}

class SafeZone {
  const SafeZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.enabled,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool enabled;

  Map<String, dynamic> toMap() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'enabled': enabled,
      };

  factory SafeZone.fromMap(String id, Map<String, dynamic> value) => SafeZone(
        id: id,
        name: value['name'] as String? ?? 'منطقة آمنة',
        latitude: (value['latitude'] as num).toDouble(),
        longitude: (value['longitude'] as num).toDouble(),
        radiusMeters: (value['radiusMeters'] as num).toDouble(),
        enabled: value['enabled'] as bool? ?? true,
      );
}

class ChildLocation {
  const ChildLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime recordedAt;

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'recordedAt': Timestamp.fromDate(recordedAt),
      };
}

class FamilySession {
  const FamilySession({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.kind,
    required this.status,
    required this.childVisibleLabel,
    required this.reason,
  });

  final String id;
  final String familyId;
  final String childId;
  final FamilySessionKind kind;
  final FamilySessionStatus status;
  final String childVisibleLabel;
  final String reason;

  factory FamilySession.fromMap(String id, Map<String, dynamic> value) => FamilySession(
        id: id,
        familyId: value['familyId'] as String,
        childId: value['childId'] as String,
        kind: FamilySessionKind.values.byName(value['kind'] as String),
        status: FamilySessionStatus.values.byName(value['status'] as String),
        childVisibleLabel: value['childVisibleLabel'] as String,
        reason: value['reason'] as String,
      );
}
