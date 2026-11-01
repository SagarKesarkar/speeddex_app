import 'rarity_tier.dart';

/// Body style drives the fallback silhouette when no capture image exists.
enum BodyStyle { sedan, hatch, coupe, suv, pickup, van }

/// Public figures, always visible on a card (spec §3.3). Any of them may be
/// null: the catalogue only holds what its source states, and the card shows
/// only the figures that exist.
class VehicleSpecs {
  const VehicleSpecs({
    this.topSpeedMph,
    this.horsepower,
    this.zeroToSixtySeconds,
    this.engine,
    this.displacementCc,
    this.fuelType,
  });

  final int? topSpeedMph;
  final int? horsepower;
  final double? zeroToSixtySeconds;

  /// e.g. "1.2 L I4 turbo" or "Electric motor".
  final String? engine;
  final int? displacementCc;

  /// e.g. "Petrol, CNG".
  final String? fuelType;
}

/// The spec sheet behind the 5-coin unlock (spec §3.3, §4.2). Only ever
/// populated after the server confirms an entitlement; fields may be null
/// where the catalogue has no figure.
class HiddenSpecs {
  const HiddenSpecs({
    this.manufacturer,
    this.parentCompany,
    this.productionStatus,
    this.cylinders,
    this.induction,
    this.torqueNm,
    this.curbWeightKg,
    this.drivetrain,
    this.transmission,
    this.lengthMm,
    this.widthMm,
    this.heightMm,
    this.wheelbaseMm,
    this.seating,
    this.doors,
    this.batteryKwh,
    this.evRangeMiles,
    this.msrp,
  });

  /// Legal name of the maker, e.g. "Maruti Suzuki India Limited".
  final String? manufacturer;
  final String? parentCompany;

  /// "In Production" or "Discontinued".
  final String? productionStatus;
  final int? cylinders;

  /// e.g. "Turbocharged".
  final String? induction;
  final int? torqueNm;
  final int? curbWeightKg;
  final String? drivetrain;

  /// e.g. "6-speed Manual / AMT".
  final String? transmission;
  final int? lengthMm;
  final int? widthMm;
  final int? heightMm;
  final int? wheelbaseMm;
  final int? seating;
  final int? doors;
  final double? batteryKwh;
  final int? evRangeMiles;
  final double? msrp;
}

/// What was recorded when this card was caught, beyond time and place.
/// Like [HiddenSpecs], only sent to the owner or after an unlock.
class CaptureFacts {
  const CaptureFacts({this.color, this.aiConfidence, this.addedAt});

  /// Body colour as the recogniser saw it, e.g. "Pearl White".
  final String? color;

  /// 0–1. Null when a reviewer, not the model, made the match.
  final double? aiConfidence;

  /// When the card went into the Garage.
  final DateTime? addedAt;
}

/// Attributed source text for a model (Wikipedia summaries are CC BY-SA 4.0).
class CarAbout {
  const CarAbout({required this.summary, this.sourceUrl, this.license});

  final String summary;
  final String? sourceUrl;
  final String? license;
}

/// A collected (or candidate) Car Card.
class CarCard {
  const CarCard({
    required this.id,
    required this.vehicleId,
    required this.serial,
    required this.make,
    required this.model,
    required this.yearLabel,
    required this.category,
    required this.origin,
    required this.bodyStyle,
    required this.tier,
    required this.specs,
    required this.capturedAt,
    this.variant,
    this.hidden,
    this.capture,
    this.hiddenUnlocked = false,
    this.ownedByViewer = false,
    this.locationLabel,
    this.conditionRating,
    this.xp = 0,
    this.imagePath,
    this.imageUrl,
    this.about,
  });

  /// This card instance. Two players catching the same car get different ids.
  final String id;

  /// Canonical catalog vehicle, used for duplicate detection.
  final String vehicleId;

  /// Human-readable card serial, e.g. `SDX-00413`.
  final String serial;
  final String make;
  final String model;
  final String? variant;

  /// Production span, e.g. `2012–present`.
  final String yearLabel;
  final String category;
  final String origin;
  final BodyStyle bodyStyle;
  final RarityTier tier;
  final VehicleSpecs specs;
  final HiddenSpecs? hidden;
  final CaptureFacts? capture;

  /// Server-confirmed entitlement to the spec sheet. Always true for the
  /// owner of the card; other viewers need a 5-coin unlock.
  final bool hiddenUnlocked;

  /// True when the signed-in user captured this card.
  final bool ownedByViewer;
  final DateTime capturedAt;
  final String? locationLabel;

  /// 1.0–10.0 per spec §6.6. Null until the condition model has run.
  final double? conditionRating;
  final int xp;

  /// Local file path for a capture taken on this device.
  final String? imagePath;

  /// Controlled delivery URL from the backend (never a private original).
  final String? imageUrl;

  /// Model summary with attribution; present on detail responses only.
  final CarAbout? about;

  String get displayName => '$make $model';

  CarCard copyWith({
    String? id,
    String? serial,
    bool? ownedByViewer,
    HiddenSpecs? hidden,
    bool? hiddenUnlocked,
    String? imagePath,
    DateTime? capturedAt,

    /// Drops the spec sheet, as the API does for viewers without an entitlement.
    bool clearHidden = false,
  }) => CarCard(
    vehicleId: vehicleId,
    ownedByViewer: ownedByViewer ?? this.ownedByViewer,
    id: id ?? this.id,
    serial: serial ?? this.serial,
    make: make,
    model: model,
    variant: variant,
    yearLabel: yearLabel,
    category: category,
    origin: origin,
    bodyStyle: bodyStyle,
    tier: tier,
    specs: specs,
    hidden: clearHidden ? null : (hidden ?? this.hidden),
    capture: clearHidden ? null : capture,
    hiddenUnlocked: hiddenUnlocked ?? this.hiddenUnlocked,
    capturedAt: capturedAt ?? this.capturedAt,
    locationLabel: locationLabel,
    conditionRating: conditionRating,
    xp: xp,
    imagePath: imagePath ?? this.imagePath,
    imageUrl: imageUrl,
    about: about,
  );
}
