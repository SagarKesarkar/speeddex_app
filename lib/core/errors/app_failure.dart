/// Typed, user-safe failures. Mirrors the `error.code` values of the API
/// error envelope (spec §5). Messages never include server internals,
/// tokens or personal data.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

  @override
  String toString() => '$runtimeType';
}

class NetworkFailure extends AppFailure {
  const NetworkFailure()
    : super('You appear to be offline. Check your connection and try again.', retryable: true);
}

class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure() : super('Your session has ended. Please sign in again.');
}

class InvalidCredentialsFailure extends AppFailure {
  // Deliberately generic to avoid account enumeration (spec §3.2).
  const InvalidCredentialsFailure() : super('That email and password combination did not work.');
}

class InsufficientCoinsFailure extends AppFailure {
  const InsufficientCoinsFailure({required this.required, required this.balance})
    : super('Not enough coins for this unlock.');

  final int required;
  final int balance;
}

class GarageFullFailure extends AppFailure {
  const GarageFullFailure() : super('Your Garage is full. Add capacity to keep this card.');
}

class DailyScanLimitFailure extends AppFailure {
  const DailyScanLimitFailure() : super("You've used today's free scans. More unlock tomorrow.");
}

class ServiceUnavailableFailure extends AppFailure {
  const ServiceUnavailableFailure(super.message) : super(retryable: true);
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'This card is no longer available.']);
}

/// Server-side validation or business-rule rejection with a user-safe message.
class RequestFailure extends AppFailure {
  const RequestFailure(super.message, {this.code, super.retryable, this.fieldErrors = const {}});

  /// API error code, e.g. `EMAIL_TAKEN`, for callers that branch on it.
  final String? code;
  final Map<String, String> fieldErrors;
}

class RateLimitedFailure extends AppFailure {
  const RateLimitedFailure()
    : super('Too many attempts. Please wait a moment and try again.', retryable: true);
}

/// The on-device face and plate check couldn't run, so the photo wasn't sent.
class PrivacyCheckFailure extends AppFailure {
  const PrivacyCheckFailure()
    : super(
        'We couldn’t check this photo for faces and number plates, so it wasn’t sent. Try again.',
        retryable: true,
      );
}

/// No more rewards from ads today (extra scans or ad unlocks).
class AdRewardLimitFailure extends AppFailure {
  const AdRewardLimitFailure(super.message);
}

class UnknownFailure extends AppFailure {
  const UnknownFailure() : super('Something went wrong. Please try again.', retryable: true);
}

extension FailureMessage on Object {
  /// Maps any error to a message that is safe to show the user.
  String get userMessage =>
      this is AppFailure ? (this as AppFailure).message : const UnknownFailure().message;
}
