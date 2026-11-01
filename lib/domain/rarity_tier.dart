import 'package:flutter/painting.dart';

/// Rarity tiers exactly as defined in the SpeedDex specification (§6.6),
/// ordered from most to least common. Tier assignment is a server decision;
/// the client only renders what it is given.
enum RarityTier {
  base('Base', Color(0xFF8C919B)),
  special('Special', Color(0xFF4AA6A8)),
  sporty('Sporty', Color(0xFF3F7FE6)),
  royal('Royal', Color(0xFF9361DB)),
  classic('Classic', Color(0xFFC48D4E)),
  rare('Rare', Color(0xFF2FB880)),
  elite('Elite', Color(0xFFE56B2C)),
  legendary('Legendary', Color(0xFFE9C25B)),
  mythic('Mythic', Color(0xFFE44D7E));

  const RarityTier(this.label, this.color);

  final String label;
  final Color color;

  /// Darker shade used for card frames and fills behind light text.
  Color get deep => Color.lerp(color, const Color(0xFF0B0C0F), 0.55)!;

  /// Higher tiers get a subtle foil sheen on the card frame.
  bool get isFoil => index >= RarityTier.rare.index;

  static RarityTier? tryParse(String? raw) {
    if (raw == null) return null;
    final key = raw.trim().toLowerCase();
    for (final t in values) {
      if (t.name == key) return t;
    }
    return null;
  }
}
