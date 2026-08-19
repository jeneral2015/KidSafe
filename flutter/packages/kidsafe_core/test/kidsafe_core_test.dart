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
}
