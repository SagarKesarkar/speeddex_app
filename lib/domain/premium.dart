/// SpeedDex Pro, as the server last confirmed it with the store.
class Premium {
  const Premium({
    required this.active,
    this.status,
    this.platform,
    this.expiresAt,
    this.autoRenewing = false,
  });

  static const none = Premium(active: false);

  /// Entitled now: no ads, every card unlocked, unlimited Garage and scans.
  final bool active;

  /// active, canceled (paid up, won't renew), grace, on_hold, expired, …
  final String? status;

  /// google_play or app_store.
  final String? platform;

  /// End of the paid period (renews then, unless cancelled).
  final DateTime? expiresAt;
  final bool autoRenewing;
}

/// What the app needs to sell the subscription.
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.productIds,
    required this.onGooglePlay,
    required this.onAppStore,
    required this.accountToken,
    required this.premium,
  });

  final List<String> productIds;

  /// The server can confirm purchases from this store.
  final bool onGooglePlay;
  final bool onAppStore;

  /// Attached to the purchase, so it can only ever serve this account.
  final String accountToken;
  final Premium premium;
}
