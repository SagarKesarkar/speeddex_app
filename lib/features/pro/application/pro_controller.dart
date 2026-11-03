import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../domain/premium.dart';

/// The platform's store, behind a provider so tests can stand in for it.
final inAppPurchaseProvider = Provider<InAppPurchase>((_) => InAppPurchase.instance);

class ProState {
  const ProState({
    this.loading = true,
    this.available = false,
    this.product,
    this.busy = false,
    this.message,
    this.premium = Premium.none,
  });

  final bool loading;

  /// The store is reachable and the server can confirm its purchases.
  final bool available;

  /// The subscription as the store sells it here (price in local currency).
  final ProductDetails? product;

  /// A purchase or restore is in progress.
  final bool busy;

  /// Something to tell the player (a failure, or "nothing to restore").
  final String? message;
  final Premium premium;

  ProState copyWith({
    bool? loading,
    bool? available,
    ProductDetails? product,
    bool? busy,
    String? message,
    bool clearMessage = false,
    Premium? premium,
  }) => ProState(
    loading: loading ?? this.loading,
    available: available ?? this.available,
    product: product ?? this.product,
    busy: busy ?? this.busy,
    message: clearMessage ? null : (message ?? this.message),
    premium: premium ?? this.premium,
  );
}

/// Buying and restoring SpeedDex Pro. A purchase counts only once the server
/// has confirmed it with the store; only then is it finished with the store,
/// so a purchase interrupted by a network failure is delivered again later.
class ProController extends Notifier<ProState> {
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  SubscriptionInfo? _info;

  InAppPurchase get _iap => ref.read(inAppPurchaseProvider);

  String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'app_store' : 'google_play';

  @override
  ProState build() {
    ref.onDispose(() => _purchases?.cancel());
    Future.microtask(load);
    return const ProState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearMessage: true);
    try {
      final info = await ref.read(profileRepositoryProvider).subscriptionInfo();
      _info = info;
      state = state.copyWith(premium: info.premium);
      final storeReady = !ref.read(appConfigProvider).usesDevData && await _iap.isAvailable();
      final serverReady = _platform == 'app_store' ? info.onAppStore : info.onGooglePlay;
      if (!storeReady || !serverReady || info.productIds.isEmpty) {
        state = state.copyWith(loading: false, available: false);
        return;
      }
      _purchases ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object _) {});
      final found = await _iap.queryProductDetails(info.productIds.toSet());
      state = state.copyWith(
        loading: false,
        available: found.productDetails.isNotEmpty,
        product: found.productDetails.isEmpty ? null : found.productDetails.first,
      );
    } catch (e) {
      state = state.copyWith(loading: false, available: false, message: e.userMessage);
    }
  }

  Future<void> subscribe() async {
    final product = state.product;
    final info = _info;
    if (product == null || info == null || state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      // The account token ties the purchase to this SpeedDex account.
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: info.accountToken,
        ),
      );
      if (!started) state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(
        busy: false,
        message: 'The store couldn’t start the purchase. Try again.',
      );
    }
  }

  /// "Restore purchases": the store re-delivers active subscriptions.
  Future<void> restore() async {
    if (state.busy || _info == null) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await _iap.restorePurchases(applicationUserName: _info!.accountToken);
      // Restored purchases arrive on the stream; if none do, say so.
      await Future<void>.delayed(const Duration(seconds: 4));
      if (state.busy) {
        state = state.copyWith(
          busy: false,
          message: state.premium.active
              ? null
              : 'No SpeedDex Pro subscription found on this account.',
        );
      }
    } catch (_) {
      state = state.copyWith(busy: false, message: 'Couldn’t reach the store. Try again.');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    final ids = _info?.productIds ?? const [];
    for (final p in list.where((p) => ids.contains(p.productID))) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(busy: true, message: 'Waiting for the payment to go through…');
        case PurchaseStatus.canceled:
          state = state.copyWith(busy: false, clearMessage: true);
          await _finish(p);
        case PurchaseStatus.error:
          state = state.copyWith(
            busy: false,
            message: 'The purchase didn’t go through. You haven’t been charged.',
          );
          await _finish(p);
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await _confirm(p);
      }
    }
  }

  Future<void> _confirm(PurchaseDetails p) async {
    // Google: the purchase token; Apple: the transaction ID.
    final purchaseRef = _platform == 'google_play'
        ? p.verificationData.serverVerificationData
        : p.purchaseID;
    if (purchaseRef == null || purchaseRef.isEmpty) return;
    try {
      final premium = await ref
          .read(profileRepositoryProvider)
          .verifySubscription(
            platform: _platform,
            productId: p.productID,
            purchaseRef: purchaseRef,
          );
      state = state.copyWith(busy: false, premium: premium, clearMessage: true);
      ref
        ..invalidate(profileProvider)
        ..invalidate(garageSummaryProvider);
      await _finish(p);
    } on RequestFailure catch (f) {
      // Not this account's (or not a real) purchase: done with it either way.
      state = state.copyWith(busy: false, message: f.message);
      await _finish(p);
    } catch (e) {
      // Network or store trouble: leave it unfinished so it's delivered again.
      state = state.copyWith(busy: false, message: e.userMessage);
    }
  }

  Future<void> _finish(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
  }
}

final proControllerProvider = NotifierProvider<ProController, ProState>(ProController.new);
