import 'dart:math' as math;

import 'family_models.dart';

enum SafeZonePresence { unknown, inside, outside }

class SafeZoneTransition {
  const SafeZoneTransition({required this.previous, required this.current, required this.zone});

  final SafeZonePresence previous;
  final SafeZonePresence current;
  final SafeZone zone;

  bool get entered => previous != SafeZonePresence.inside && current == SafeZonePresence.inside;
  bool get exited => previous == SafeZonePresence.inside && current == SafeZonePresence.outside;
}

double distanceInMeters({required double fromLatitude, required double fromLongitude, required double toLatitude, required double toLongitude}) {
  const earthRadiusMeters = 6371000.0;
  final latitudeDelta = _radians(toLatitude - fromLatitude);
  final longitudeDelta = _radians(toLongitude - fromLongitude);
  final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(_radians(fromLatitude)) * math.cos(_radians(toLatitude)) * math.sin(longitudeDelta / 2) * math.sin(longitudeDelta / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

SafeZonePresence safeZonePresence(SafeZone zone, ChildLocation location) {
  if (!zone.enabled) return SafeZonePresence.unknown;
  final distance = distanceInMeters(
    fromLatitude: zone.latitude,
    fromLongitude: zone.longitude,
    toLatitude: location.latitude,
    toLongitude: location.longitude,
  );
  return distance <= zone.radiusMeters ? SafeZonePresence.inside : SafeZonePresence.outside;
}

SafeZoneTransition evaluateSafeZoneTransition({required SafeZone zone, required ChildLocation location, required SafeZonePresence previous}) =>
    SafeZoneTransition(previous: previous, current: safeZonePresence(zone, location), zone: zone);

double _radians(double degrees) => degrees * math.pi / 180;
