import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_core/kidsafe_core.dart';

void main() {
  const home = SafeZone(id: 'home', name: 'المنزل', latitude: 30.0444, longitude: 31.2357, radiusMeters: 150, enabled: true);
  final inside = ChildLocation(latitude: 30.0445, longitude: 31.2358, accuracyMeters: 8, recordedAt: DateTime(2026));
  final outside = ChildLocation(latitude: 30.0520, longitude: 31.2357, accuracyMeters: 8, recordedAt: DateTime(2026));

  test('safe-zone engine identifies inside and outside coordinates', () {
    expect(safeZonePresence(home, inside), SafeZonePresence.inside);
    expect(safeZonePresence(home, outside), SafeZonePresence.outside);
  });

  test('safe-zone engine emits an exit only after an inside presence', () {
    final transition = evaluateSafeZoneTransition(zone: home, location: outside, previous: SafeZonePresence.inside);
    expect(transition.exited, isTrue);
    expect(transition.entered, isFalse);
  });
}
