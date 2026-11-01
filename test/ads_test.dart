import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:speeddex/core/ads/ads.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/core/security/token_store.dart';
import 'package:speeddex/data/api/api_client.dart';
import 'package:speeddex/data/api/http_repositories.dart';
import 'package:speeddex/data/api/json_mappers.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/features/ads/feed_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('feed ad slots', () {
    test('one ad in each block of 20 posts, after post 1 to 20 of that block', () {
      for (var seed = 0; seed < 200; seed++) {
        final slots = feedAdSlots(60, seed: seed);
        expect(slots, hasLength(3));
        for (final (block, after) in slots.indexed) {
          expect(after, inInclusiveRange(block * 20 + 1, block * 20 + 20));
        }
      }
    });

    test('stays put as more posts load, and never points past the end', () {
      final early = feedAdSlots(25, seed: 7);
      final later = feedAdSlots(80, seed: 7);
      expect(later.take(early.length), early);
      for (var n = 0; n < 45; n++) {
        expect(feedAdSlots(n, seed: 3).every((a) => a <= n), isTrue);
      }
      expect(feedAdSlots(0, seed: 1), isEmpty);
    });

    test('a short feed that has ended still gets its ad, after the last post at the latest', () {
      for (var seed = 0; seed < 100; seed++) {
        final slots = feedAdSlots(6, seed: seed, ended: true);
        expect(slots, hasLength(1));
        expect(slots.single, inInclusiveRange(1, 6));
      }
    });

    test('positions differ between sessions', () {
      final firsts = {
        for (var seed = 0; seed < 50; seed++) feedAdSlots(20, seed: seed).firstOrNull,
      };
      expect(firsts.length, greaterThan(5));
    });
  });

  group('ad units', () {
    test('Google test ads unless the build asks for live ones', () {
      final config = AdsConfig.fromEnvironment();
      expect(config.mode, AdsMode.test);
      expect(config.feedBannerUnit, startsWith('ca-app-pub-3940256099942544/'));
      expect(config.rewardedUnit, startsWith('ca-app-pub-3940256099942544/'));
    });
  });

  group('HttpAdsRepository', () {
    late TokenStore tokens;
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      tokens = TokenStore();
      await tokens.save(access: 'a', refresh: 'r');
    });

    HttpAdsRepository repo(
      Map<String, dynamic> Function(Map<String, dynamic> body) answer, {
      int status = 200,
    }) => HttpAdsRepository(
      ApiClient(
        baseUrl: Uri.parse('https://api.example.com'),
        tokens: tokens,
        client: MockClient((req) async {
          expect(req.url.path, '/v1/ads/reward/verify');
          return http.Response(
            jsonEncode(answer(jsonDecode(req.body) as Map<String, dynamic>)),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
      const ApiMappers(_identity),
    );

    test('sends the placement, reference and card; reads a granted scan', () async {
      Map<String, dynamic>? sent;
      final r = await repo((b) {
        sent = b;
        return {
          'status': 'granted',
          'placement': 'extra_scan',
          'scansToday': 5,
          'dailyScanLimit': 6,
        };
      }).claim(placement: RewardPlacement.extraScan, ref: 'abc12345');
      expect(sent, {'placement': 'extra_scan', 'ref': 'abc12345'});
      expect(r, isA<ScanRewardGranted>().having((g) => g.dailyScanLimit, 'limit', 6));
    });

    test('the daily cap is a final answer, not something to retry', () async {
      final r = repo(
        (_) => {
          'error': {
            'code': 'AD_REWARD_LIMIT',
            'message': 'You have used all 5 extra scans from ads today.',
            'retryable': false,
          },
        },
        status: 409,
      ).claim(placement: RewardPlacement.extraScan, ref: 'abc12345');
      await expectLater(
        r,
        throwsA(isA<AdRewardLimitFailure>().having((f) => f.retryable, 'retryable', isFalse)),
      );
    });

    test('pending until AdMob confirms', () async {
      final r = await repo(
        (_) => {'status': 'pending', 'retryAfterSeconds': 2},
        status: 202,
      ).claim(placement: RewardPlacement.cardUnlock, ref: 'abc12345', cardId: '42');
      expect(r, isA<RewardPending>());
    });
  });
}

String _identity(String url) => url;
