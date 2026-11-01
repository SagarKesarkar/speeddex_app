import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/repositories.dart';
import '../../../domain/car_card.dart';
import '../../../domain/rarity_tier.dart';

enum GarageLayout { grid, list }

class GarageQueryController extends Notifier<GarageQuery> {
  @override
  GarageQuery build() => const GarageQuery();

  void setTier(RarityTier? t) => state = state.copyWith(tier: () => t);
  void setMake(String? m) => state = state.copyWith(make: () => m);
  void setSort(GarageSort s) => state = state.copyWith(sort: s);
  void clear() => state = GarageQuery(sort: state.sort);
}

final garageQueryProvider = NotifierProvider<GarageQueryController, GarageQuery>(
  GarageQueryController.new,
);

class GarageLayoutController extends Notifier<GarageLayout> {
  @override
  GarageLayout build() => GarageLayout.grid;
  void set(GarageLayout l) => state = l;
}

final garageLayoutProvider = NotifierProvider<GarageLayoutController, GarageLayout>(
  GarageLayoutController.new,
);

final garageCardsProvider = FutureProvider<List<CarCard>>((ref) {
  // Refetch whenever the summary is invalidated (e.g. after a scan adds a card).
  ref.watch(garageSummaryProvider);
  return ref.watch(garageRepositoryProvider).cards(ref.watch(garageQueryProvider));
});

final garageMakesProvider = FutureProvider<List<String>>((ref) {
  ref.watch(garageSummaryProvider);
  return ref.watch(garageRepositoryProvider).makes();
});

/// Captures awaiting the user: approved and ready to add, or still in review.
final pendingCapturesProvider = FutureProvider<List<IdentifyOutcome>>((ref) {
  ref.watch(garageSummaryProvider);
  return ref.watch(captureRepositoryProvider).pending();
});
