import 'package:flutter_test/flutter_test.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/main.dart';

void main() {
  test('retries only transient failures, at most three times', () {
    expect(providerRetry(0, const NetworkFailure()), const Duration(milliseconds: 500));
    expect(providerRetry(2, const NetworkFailure()), const Duration(milliseconds: 2000));
    expect(providerRetry(3, const NetworkFailure()), isNull);
    expect(providerRetry(0, const RequestFailure('Add your country')), isNull);
    expect(providerRetry(0, const InvalidCredentialsFailure()), isNull);
    expect(providerRetry(0, StateError('bug')), isNull);
  });
}
