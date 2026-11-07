import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/spots.dart';

/// Where the device is, with how sure the reading is.
class GeoFix {
  const GeoFix(this.point, {this.accuracyMeters});
  final GeoPoint point;
  final double? accuracyMeters;
}

enum LocationAccess {
  granted,

  /// Not allowed yet; asking again can still show the system prompt.
  denied,

  /// Blocked: only the system settings can change it.
  blocked,

  /// Location is switched off for the whole phone.
  serviceOff,
}

/// Foreground location only, used to tag captures and centre the Radar map.
abstract interface class LocationService {
  Future<LocationAccess> access();

  /// Shows the system prompt if it still can.
  Future<LocationAccess> request();

  /// A fix for a capture, or null when location isn't available. Asks for
  /// permission at most once per app run, and never waits longer than a few
  /// seconds: a capture is never held up by GPS.
  Future<GeoFix?> captureFix();

  /// Live position while the Radar is open.
  Stream<GeoFix> watch();

  Future<void> openSettings(LocationAccess access);
}

class GeolocatorLocationService implements LocationService {
  bool _askedThisRun = false;

  static LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.blocked,
    _ => LocationAccess.denied,
  };

  static GeoFix _fix(Position p) =>
      GeoFix(GeoPoint(p.latitude, p.longitude), accuracyMeters: p.accuracy);

  @override
  Future<LocationAccess> access() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    _askedThisRun = true;
    return _map(await Geolocator.requestPermission());
  }

  @override
  Future<GeoFix?> captureFix() async {
    try {
      var a = await access();
      if (a == LocationAccess.denied && !_askedThisRun) a = await request();
      if (a != LocationAccess.granted) return null;
      try {
        return _fix(
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 6),
            ),
          ),
        );
      } on TimeoutException {
        // Indoors or a cold GPS: a recent last-known reading still says where.
        final last = await Geolocator.getLastKnownPosition();
        if (last == null ||
            DateTime.now().difference(last.timestamp) > const Duration(minutes: 5)) {
          return null;
        }
        return _fix(last);
      }
    } catch (_) {
      // No plugin (tests), no GPS hardware, or the platform said no.
      return null;
    }
  }

  @override
  Stream<GeoFix> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
  ).map(_fix);

  @override
  Future<void> openSettings(LocationAccess access) async {
    if (access == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
