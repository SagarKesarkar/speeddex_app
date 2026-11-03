import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:speeddex/core/config/app_config.dart';
import 'package:speeddex/core/errors/app_failure.dart';
import 'package:speeddex/core/security/token_store.dart';
import 'package:speeddex/data/api/api_client.dart';
import 'package:speeddex/data/api/http_repositories.dart';
import 'package:speeddex/data/repositories.dart';
import 'package:speeddex/data/api/json_mappers.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object> _err(String code, [String message = 'msg', Map<String, Object>? details]) => {
  'error': {
    'code': code,
    'message': message,
    'requestId': 'r',
    'retryable': false,
    'details': ?details,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenStore tokens;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tokens = TokenStore();
    await tokens.save(access: 'old-access', refresh: 'old-refresh');
  });

  ApiClient client(MockClientHandler h, {void Function()? onExpired}) => ApiClient(
    baseUrl: Uri.parse('https://api.example.com'),
    tokens: tokens,
    client: MockClient(h),
    onSessionExpired: onExpired,
  );

  group('AppConfig', () {
    test('requires https, except a local server in debug builds', () {
      expect(AppConfig.parse('', allowLocalHttp: false).usesDevData, isTrue);
      expect(
        AppConfig.parse('https://api.speeddex.app/', allowLocalHttp: false).apiBaseUrl.toString(),
        'https://api.speeddex.app',
      );
      expect(
        () => AppConfig.parse('http://api.speeddex.app', allowLocalHttp: true),
        throwsStateError,
      );
      expect(
        () => AppConfig.parse('http://10.0.2.2:8080', allowLocalHttp: false),
        throwsStateError,
      );
      expect(AppConfig.parse('http://10.0.2.2:8080', allowLocalHttp: true).usesDevData, isFalse);
    });
  });

  group('ApiClient', () {
    test('sends the bearer token and /v1 prefix', () async {
      late http.Request seen;
      final api = client((r) async {
        seen = r;
        return _json(200, {'ok': true});
      });
      await api.get('/wallet', query: {'a': '1', 'b': null});
      expect(seen.url.toString(), 'https://api.example.com/v1/wallet?a=1');
      expect(seen.headers['authorization'], 'Bearer old-access');
    });

    test('refreshes once on expiry, retries, and stores rotated tokens', () async {
      var refreshes = 0;
      final api = client((r) async {
        if (r.url.path == '/v1/auth/refresh') {
          refreshes++;
          expect(jsonDecode(r.body)['refreshToken'], 'old-refresh');
          return _json(200, {'accessToken': 'new-access', 'refreshToken': 'new-refresh'});
        }
        return r.headers['authorization'] == 'Bearer new-access'
            ? _json(200, {'ok': true})
            : _json(401, _err('AUTH_TOKEN_EXPIRED'));
      });
      // Two concurrent calls share one refresh.
      await Future.wait([api.get('/a'), api.get('/b')]);
      expect(refreshes, 1);
      expect(await tokens.readAccess(), 'new-access');
      expect(await tokens.readRefresh(), 'new-refresh');
    });

    test('signs out when the refresh token is rejected', () async {
      var expired = false;
      final api = client(
        (r) async => r.url.path == '/v1/auth/refresh'
            ? _json(401, _err('AUTH_SESSION_REVOKED'))
            : _json(401, _err('AUTH_TOKEN_EXPIRED')),
        onExpired: () => expired = true,
      );
      await expectLater(api.get('/x'), throwsA(isA<SessionExpiredFailure>()));
      expect(expired, isTrue);
      expect(await tokens.hasSession(), isFalse);
    });

    test('maps API error codes to typed failures', () async {
      Future<Object> fail(http.Response res) async {
        try {
          await client((_) async => res).post('/x');
        } catch (e) {
          return e;
        }
        throw StateError('expected failure');
      }

      expect(
        await fail(_json(409, _err('INSUFFICIENT_COINS', 'm', {'required': 5, 'balance': 2}))),
        isA<InsufficientCoinsFailure>().having((f) => f.balance, 'balance', 2),
      );
      expect(await fail(_json(409, _err('GARAGE_CAPACITY_REACHED'))), isA<GarageFullFailure>());
      expect(await fail(_json(429, _err('DAILY_SCAN_LIMIT'))), isA<DailyScanLimitFailure>());
      expect(
        await fail(_json(503, _err('FEATURE_NOT_CONFIGURED', 'Ads are not available yet.'))),
        isA<ServiceUnavailableFailure>().having(
          (f) => f.message,
          'message',
          'Ads are not available yet.',
        ),
      );
      expect(
        await fail(_json(409, _err('EMAIL_TAKEN', 'Taken'))),
        isA<RequestFailure>().having((f) => f.code, 'code', 'EMAIL_TAKEN'),
      );
      // Server internals never reach the user.
      expect(await fail(http.Response('<html>stack trace</html>', 500)), isA<UnknownFailure>());
    });

    test('reports network errors as NetworkFailure', () async {
      final api = client((_) async => throw http.ClientException('offline'));
      await expectLater(api.get('/x'), throwsA(isA<NetworkFailure>()));
    });

    test('rebases server URLs onto the configured host, keeping the signature', () {
      final api = client((_) async => _json(200, {}));
      expect(
        api.rebase('http://10.0.2.2:8080/v1/media/captures/u1/c2.jpg?exp=1&sig=abc').toString(),
        'https://api.example.com/v1/media/captures/u1/c2.jpg?exp=1&sig=abc',
      );
    });

    test('leaves photos published on the website alone', () {
      final api = client((_) async => _json(200, {}));
      const url = 'https://speeddexgame.com/catalog/variants/112-front.jpg';
      expect(api.rebase(url).toString(), url);
    });
  });

  group('ApiMappers', () {
    const m = ApiMappers(_identity);

    test('reads whether the email is confirmed; servers that do not say count as confirmed', () {
      Map<String, dynamic> me([Map<String, dynamic> extra = const {}]) => {
        'userId': 7,
        'username': 'apex',
        'displayName': 'Apex',
        'email': 'a@b.co',
        ...extra,
      };
      expect(m.profile(me({'emailVerified': false})).emailVerified, isFalse);
      expect(m.profile(me({'emailVerified': true})).emailVerified, isTrue);
      expect(m.profile(me()).emailVerified, isTrue);
      expect(m.profile(me()).email, 'a@b.co');
    });
    // Shape of a real API card for a CarDex vehicle.
    Map<String, dynamic> cardJson({Object? hidden, bool owned = false, Object? about}) => {
      'cardId': 7,
      'serial': 'SDX-00007',
      'vehicleId': 3,
      'make': 'Maruti Suzuki',
      'model': 'Swift',
      'variant': 'Fourth generation',
      'yearLabel': '2023–present',
      'category': 'Hatchback',
      'origin': 'India/Japan',
      'bodyStyle': 'hatch',
      'rarity': 'base',
      'specs': {
        'topSpeedMph': null,
        'horsepower': 81,
        'zeroToSixtySeconds': null,
        'engine': '1.2 L I3',
        'displacementCc': 1197,
        'fuelType': 'Petrol, CNG',
      },
      'hidden': hidden,
      'hiddenUnlocked': hidden != null,
      'ownedByViewer': owned,
      'capturedAt': '2026-10-28T10:00:00Z',
      'locationLabel': null,
      'conditionRating': null,
      'xp': 100,
      'imageUrl': 'https://x/v1/media/a.jpg?sig=1',
      'about': ?about,
    };

    test('maps a locked card, keeping missing figures null rather than zero', () {
      final c = m.card(cardJson());
      expect(c.id, '7');
      expect(c.hidden, isNull);
      expect(c.hiddenUnlocked, isFalse);
      expect(c.ownedByViewer, isFalse);
      expect(c.tier.name, 'base');
      expect(c.specs.topSpeedMph, isNull);
      expect(c.specs.zeroToSixtySeconds, isNull);
      expect(c.specs.horsepower, 81);
      expect(c.specs.displacementCc, 1197);
      expect(c.specs.fuelType, 'Petrol, CNG');
    });

    test('maps an owned card with its metric spec sheet', () {
      final c = m.card(
        cardJson(
          owned: true,
          hidden: {
            'torqueNm': 112,
            'curbWeightKg': 910,
            'drivetrain': 'FWD',
            'transmission': '5-speed Manual / AMT',
            'lengthMm': 3860,
            'widthMm': null,
            'msrp': null,
          },
        ),
      );
      expect(c.ownedByViewer, isTrue);
      expect(c.hidden!.curbWeightKg, 910);
      expect(c.hidden!.transmission, '5-speed Manual / AMT');
      expect(c.hidden!.widthMm, isNull);
    });

    test('maps attributed About text', () {
      final c = m.card(
        cardJson(
          about: {
            'summary': 'The Suzuki Swift is a supermini car.',
            'sourceUrl': 'https://en.wikipedia.org/wiki/Suzuki_Swift',
            'license': 'CC BY-SA 4.0',
          },
        ),
      );
      expect(c.about!.license, 'CC BY-SA 4.0');
      expect(m.card(cardJson()).about, isNull);
    });
  });

  test('Google sign-in sends the ID token and keeps the session it gets back', () async {
    Map<String, dynamic>? sent;
    final repo = HttpAuthRepository(
      client((req) async {
        expect(req.url.path, '/v1/auth/google');
        expect(req.headers['authorization'], isNull);
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json(200, {
          'accessToken': 'g-access',
          'refreshToken': 'g-refresh',
          'user': {'userId': 42},
        });
      }),
      tokens,
    );
    final session = await repo.signInWithGoogle('google-id-token-xyz');
    expect(sent, {'idToken': 'google-id-token-xyz'});
    expect(session.userId, '42');
    expect(await tokens.readAccess(), 'g-access');
  });

  group('HttpAuthRepository password reset', () {
    test('sends the code, then the new password with the token it was exchanged for', () async {
      final bodies = <String, Map<String, dynamic>>{};
      final repo = HttpAuthRepository(
        client((req) async {
          bodies[req.url.path] = jsonDecode(req.body) as Map<String, dynamic>;
          // Public calls never carry the stored session.
          expect(req.headers['authorization'], isNull);
          return switch (req.url.path) {
            '/v1/auth/password/verify-code' => _json(200, {
              'resetToken': 'rt-1',
              'expiresInSeconds': 900,
            }),
            _ => _json(200, {'reset': true}),
          };
        }),
        tokens,
      );
      expect(await repo.verifyResetCode('a@b.co', '012345'), 'rt-1');
      await repo.resetPassword('rt-1', 'newpass2026');
      expect(bodies['/v1/auth/password/verify-code'], {'email': 'a@b.co', 'code': '012345'});
      expect(bodies['/v1/auth/password/reset'], {'token': 'rt-1', 'password': 'newpass2026'});
    });

    test('a wrong code comes back as a message for the code field', () async {
      final repo = HttpAuthRepository(
        client(
          (_) async => _json(400, {
            'error': {
              'code': 'VALIDATION_FAILED',
              'message': 'That code is not right or has expired.',
              'fieldErrors': [
                {'field': 'code', 'message': 'That code is not right or has expired.'},
              ],
            },
          }),
        ),
        tokens,
      );
      await expectLater(
        repo.verifyResetCode('a@b.co', '999999'),
        throwsA(
          isA<RequestFailure>().having((e) => e.fieldErrors['code'], 'code error', isNotNull),
        ),
      );
    });
  });

  group('HttpCaptureRepository', () {
    final candidate = {
      'cardId': null,
      'vehicleId': 7,
      'make': 'Hyundai',
      'model': 'Creta',
      'yearLabel': '2015–present',
      'rarity': 'base',
      'specs': <String, Object>{},
    };

    test('"Try again" after a dropped connection continues the same capture', () async {
      final calls = <String>[];
      var identifyAttempts = 0;
      final api = client((req) async {
        calls.add('${req.method} ${req.url.path}');
        return switch ((req.method, req.url.path)) {
          ('POST', '/v1/captures/upload-session') => _json(201, {
            'captureId': 41,
            'upload': {'url': 'https://api.example.com/v1/uploads/k.jpg?sig=s'},
          }),
          ('PUT', _) => _json(200, {'captureId': 41, 'status': 'uploaded'}),
          // The first identify request never gets an answer.
          ('POST', '/v1/captures/41/identify') when identifyAttempts++ == 0 =>
            throw http.ClientException('connection reset'),
          ('POST', '/v1/captures/41/identify') => _json(202, {'status': 'processing'}),
          ('GET', '/v1/captures/41') => _json(200, {
            'captureId': 41,
            'status': 'identified',
            'confidence': 0.93,
            'candidate': candidate,
          }),
          _ => _json(404, _err('RESOURCE_NOT_FOUND')),
        };
      });
      final repo = HttpCaptureRepository(api, const ApiMappers(_identity));
      final photo = Uint8List.fromList([1, 2, 3]);

      await expectLater(repo.identify(photo, localPath: '/tmp/a.jpg'), throwsA(isA<AppFailure>()));
      final outcome = await repo.identify(photo, localPath: '/tmp/a.jpg');

      expect(outcome, isA<Identified>());
      // One upload only: the retry asked the server to identify capture 41 again.
      expect(calls.where((c) => c.endsWith('upload-session')), hasLength(1));
      expect(calls.where((c) => c.startsWith('PUT')), hasLength(1));
      expect(calls.where((c) => c.endsWith('/41/identify')), hasLength(2));
    });

    test('reads the result when the earlier identify already went through', () async {
      final api = client(
        (req) async => switch ((req.method, req.url.path)) {
          ('POST', '/v1/captures/upload-session') => _json(201, {
            'captureId': 5,
            'upload': {'url': 'https://api.example.com/v1/uploads/k.jpg?sig=s'},
          }),
          ('PUT', _) => _json(200, {'status': 'uploaded'}),
          ('POST', '/v1/captures/5/identify') => _json(409, _err('CAPTURE_STATE_CONFLICT')),
          ('GET', '/v1/captures/5') => _json(200, {
            'captureId': 5,
            'status': 'identified',
            'confidence': 0.9,
            'candidate': candidate,
          }),
          _ => _json(404, _err('RESOURCE_NOT_FOUND')),
        },
      );
      final repo = HttpCaptureRepository(api, const ApiMappers(_identity));
      final outcome = await repo.identify(Uint8List(3), localPath: '/tmp/b.jpg');
      expect((outcome as Identified).candidate.model, 'Creta');
    });

    test('uploads the thumbnail before the photo; a failed thumbnail is skipped', () async {
      final puts = <String>[];
      final api = client(
        (req) async => switch ((req.method, req.url.path)) {
          ('POST', '/v1/captures/upload-session') => _json(201, {
            'captureId': 6,
            'upload': {'url': 'https://api.example.com/v1/uploads/k.jpg?sig=s'},
            'thumbnailUpload': {'url': 'https://api.example.com/v1/uploads/k_t.jpg?sig=t'},
          }),
          ('PUT', final path) when path.endsWith('_t.jpg') => () {
            puts.add(path);
            return _json(500, _err('INTERNAL'));
          }(),
          ('PUT', final path) => () {
            puts.add(path);
            return _json(200, {'status': 'uploaded'});
          }(),
          ('POST', '/v1/captures/6/identify') => _json(202, {'status': 'processing'}),
          ('GET', '/v1/captures/6') => _json(200, {
            'captureId': 6,
            'status': 'identified',
            'confidence': 0.9,
            'candidate': candidate,
          }),
          _ => _json(404, _err('RESOURCE_NOT_FOUND')),
        },
      );
      final repo = HttpCaptureRepository(api, const ApiMappers(_identity));
      final outcome = await repo.identify(
        Uint8List(3),
        localPath: '/tmp/c.jpg',
        thumbnail: Uint8List(2),
      );
      expect(outcome, isA<Identified>());
      expect(puts, ['/v1/uploads/k_t.jpg', '/v1/uploads/k.jpg']);
    });
  });
}

String _identity(String s) => s;
