import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/security/token_store.dart';
import '../data/api/api_client.dart';
import '../data/api/http_repositories.dart';
import '../data/api/json_mappers.dart';
import '../data/repositories.dart';
import '../dev/dev_backend.dart';
import '../domain/profile.dart';
import '../core/ads/ads.dart';

/// Composition root. With `--dart-define=API_BASE_URL=…` every repository
/// talks to the SpeedDex API; without it the app runs on the labelled
/// development backend. Presentation code depends only on the interfaces.
final appConfigProvider = Provider<AppConfig>((_) => AppConfig.fromEnvironment());

final tokenStoreProvider = Provider<TokenStore>((_) => TokenStore());

/// Null in development-data mode.
final apiClientProvider = Provider<ApiClient?>((ref) {
  final base = ref.watch(appConfigProvider).apiBaseUrl;
  return base == null ? null : ApiClient(baseUrl: base, tokens: ref.watch(tokenStoreProvider));
});

final _mappersProvider = Provider<ApiMappers>((ref) {
  final api = ref.watch(apiClientProvider);
  return ApiMappers((url) => api == null ? url : api.rebase(url).toString());
});

final _devStoreProvider = Provider<DevStore>((_) => DevStore());

T _pick<T>(
  Ref ref, {
  required T Function(ApiClient api, ApiMappers m) http,
  required T Function(DevStore s) dev,
}) {
  final api = ref.watch(apiClientProvider);
  return api != null ? http(api, ref.watch(_mappersProvider)) : dev(ref.watch(_devStoreProvider));
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => _pick(
    ref,
    http: (api, _) => HttpAuthRepository(api, ref.watch(tokenStoreProvider)),
    dev: (s) => DevAuthRepository(s, ref.watch(tokenStoreProvider)),
  ),
);
final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => _pick(ref, http: HttpFeedRepository.new, dev: DevFeedRepository.new),
);
final cardsRepositoryProvider = Provider<CardsRepository>(
  (ref) => _pick(ref, http: HttpCardsRepository.new, dev: DevCardsRepository.new),
);
final rankingRepositoryProvider = Provider<RankingRepository>(
  (ref) => _pick(ref, http: HttpRankingRepository.new, dev: DevRankingRepository.new),
);
final garageRepositoryProvider = Provider<GarageRepository>(
  (ref) => _pick(ref, http: HttpGarageRepository.new, dev: DevGarageRepository.new),
);
final adsRepositoryProvider = Provider<AdsRepository>(
  (ref) => _pick(ref, http: HttpAdsRepository.new, dev: DevAdsRepository.new),
);

/// Google Mobile Ads, started lazily after consent.
final adsServiceProvider = Provider<AdsService>((_) => AdsService(AdsConfig.fromEnvironment()));

final captureRepositoryProvider = Provider<CaptureRepository>(
  (ref) => _pick(ref, http: HttpCaptureRepository.new, dev: DevCaptureRepository.new),
);
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => _pick(ref, http: HttpProfileRepository.new, dev: DevProfileRepository.new),
);

final geoRepositoryProvider = Provider<GeoRepository>(
  (ref) => _pick(ref, http: HttpGeoRepository.new, dev: DevGeoRepository.new),
);
final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => _pick(ref, http: HttpUsersRepository.new, dev: DevUsersRepository.new),
);

/// Shared, read-mostly account state. Mutations elsewhere invalidate these.
final walletProvider = FutureProvider<Wallet>(
  (ref) => ref.watch(profileRepositoryProvider).wallet(),
);
final profileProvider = FutureProvider<UserProfile>(
  (ref) => ref.watch(profileRepositoryProvider).me(),
);
final garageSummaryProvider = FutureProvider<GarageSummary>(
  (ref) => ref.watch(garageRepositoryProvider).summary(),
);
