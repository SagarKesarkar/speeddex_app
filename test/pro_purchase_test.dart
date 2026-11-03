import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:speeddex/app/providers.dart';
import 'package:speeddex/core/config/app_config.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/domain/premium.dart';
import 'package:speeddex/features/pro/application/pro_controller.dart';

const _product = 'speeddex_pro_monthly';

/// The store, scripted: purchases are pushed onto [stream] by the test.
class _Store implements InAppPurchase {
  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String>[];
  PurchaseParam? bought;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) async =>
      ProductDetailsResponse(
        productDetails: [
          ProductDetails(
            id: _product,
            title: 'SpeedDex Pro',
            description: '',
            price: '\$4.99',
            rawPrice: 4.99,
            currencyCode: 'USD',
          ),
        ],
        notFoundIDs: const [],
      );

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought = purchaseParam;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase.verificationData.serverVerificationData);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Profiles implements ProfileRepository {
  final verified = <String>[];
  Object? failWith;

  @override
  Future<SubscriptionInfo> subscriptionInfo() async => const SubscriptionInfo(
    productIds: [_product],
    onGooglePlay: true,
    onAppStore: false,
    accountToken: 'acct-token-uuid',
    premium: Premium.none,
  );

  @override
  Future<Premium> verifySubscription({
    required String platform,
    required String productId,
    required String purchaseRef,
  }) async {
    if (failWith != null) throw failWith!;
    verified.add('$platform:$purchaseRef');
    return Premium(
      active: true,
      status: 'active',
      platform: platform,
      expiresAt: DateTime(2026, 12, 3),
      autoRenewing: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PurchaseDetails _purchase(String token, PurchaseStatus status) => PurchaseDetails(
  purchaseID: 'GPA.1234',
  productID: _product,
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '0',
  status: status,
)..pendingCompletePurchase = true;

void main() {
  late _Store store;
  late _Profiles profiles;
  late ProviderContainer c;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    store = _Store();
    profiles = _Profiles();
    c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.parse('https://api.example.com', allowLocalHttp: false),
        ),
        apiClientProvider.overrideWithValue(null),
        inAppPurchaseProvider.overrideWithValue(store),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );
    c.listen(proControllerProvider, (_, _) {});
    await c.read(proControllerProvider.notifier).load();
  });
  tearDown(() {
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> deliver(PurchaseDetails p) async {
    store.stream.add([p]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('shows the store’s price and buys for this account', () async {
    final s = c.read(proControllerProvider);
    expect(s.available, isTrue);
    expect(s.product!.price, '\$4.99');
    await c.read(proControllerProvider.notifier).subscribe();
    expect(store.bought!.applicationUserName, 'acct-token-uuid');
  });

  test('a purchase counts once the server confirms it, then is finished with the store', () async {
    await deliver(_purchase('tok-1', PurchaseStatus.purchased));
    expect(profiles.verified, ['google_play:tok-1']);
    expect(c.read(proControllerProvider).premium.active, isTrue);
    expect(store.completed, ['tok-1']);
  });

  test(
    'a network failure leaves the purchase unfinished, so the store delivers it again',
    () async {
      profiles.failWith = const NetworkFailure();
      await deliver(_purchase('tok-2', PurchaseStatus.purchased));
      expect(c.read(proControllerProvider).premium.active, isFalse);
      expect(store.completed, isEmpty);
      expect(c.read(proControllerProvider).message, isNotNull);
    },
  );

  test(
    'a purchase the server refuses (another account’s) is finished but grants nothing',
    () async {
      profiles.failWith = const RequestFailure(
        'This subscription belongs to another SpeedDex account.',
        code: 'PURCHASE_IN_USE',
      );
      await deliver(_purchase('tok-3', PurchaseStatus.restored));
      expect(c.read(proControllerProvider).premium.active, isFalse);
      expect(store.completed, ['tok-3']);
      expect(c.read(proControllerProvider).message, contains('another SpeedDex account'));
    },
  );

  test('a cancelled purchase asks the server nothing', () async {
    await deliver(_purchase('tok-4', PurchaseStatus.canceled));
    expect(profiles.verified, isEmpty);
    expect(c.read(proControllerProvider).busy, isFalse);
  });
}
