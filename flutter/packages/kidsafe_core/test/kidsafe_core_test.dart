import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_core/kidsafe_core.dart';

void main() {
  test('safe zones preserve the transparent control boundary', () {
    const zone = SafeZone(
      id: 'home',
      name: 'المنزل',
      latitude: 30.0,
      longitude: 31.0,
      radiusMeters: 150,
      enabled: true,
    );
    expect(zone.toMap()['enabled'], isTrue);
    expect(zone.toMap()['radiusMeters'], 150);
  });

  test('family alert preserves child context and creation time', () {
    final createdAt = DateTime.utc(2026, 8, 19, 10, 30);
    final alert = FamilyAlert.fromMap('alert-1', {
      'childId': 'child-1',
      'type': 'safe_zone_exit',
      'message': 'غادر جهاز الطفل المنطقة الآمنة: المنزل.',
      'createdAt': Timestamp.fromDate(createdAt),
    });

    expect(alert.childId, 'child-1');
    expect(alert.type, 'safe_zone_exit');
    expect(alert.message, contains('المنطقة الآمنة'));
    expect(alert.createdAt?.millisecondsSinceEpoch, createdAt.millisecondsSinceEpoch);
  });
}
