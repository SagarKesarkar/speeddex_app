import 'rarity_tier.dart';

/// A point on the map, in degrees.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// A make and model caught in a [CarSpot]. Anonymous: no owner, no card.
class SpotCar {
  const SpotCar({
    required this.vehicleId,
    required this.make,
    required this.model,
    required this.tier,
    required this.sightings,
    required this.lastSeenAt,
    this.variant,
    this.xp,
    this.imageUrl,
  });

  final String vehicleId;
  final String make;
  final String model;
  final String? variant;
  final RarityTier tier;
  final int? xp;

  /// How many times it was caught in this spot.
  final int sightings;

  /// Rounded down to the hour by the server.
  final DateTime lastSeenAt;

  /// A catalogue photo of the model, not the player's own shot.
  final String? imageUrl;

  String get title => variant == null ? '$make $model' : '$make $model $variant';
}

/// An area of about 500 m where cars were caught. [point] is the centre of
/// that area, never the exact place a player stood.
class CarSpot {
  const CarSpot({
    required this.id,
    required this.point,
    required this.distanceKm,
    required this.lastSeenAt,
    required this.sightings,
    required this.cars,
  });

  final String id;
  final GeoPoint point;
  final double distanceKm;
  final DateTime lastSeenAt;
  final int sightings;
  final List<SpotCar> cars;

  /// The rarest car caught here: it colours the pin.
  RarityTier get topTier =>
      cars.map((c) => c.tier).fold(RarityTier.base, (a, b) => b.index > a.index ? b : a);
}
