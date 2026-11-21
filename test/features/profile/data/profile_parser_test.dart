import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class _SourceClient implements DioHttpClient {
  int requests = 0;
  bool? usedDirect;
  String content = 'hysteria2://test@server.example:443?sni=server.example#New';
  @override
  Future<Response<T>> get<T>(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
    bool directOnly = false,
  }) async {
    requests++;
    usedDirect = directOnly;
    return Response<T>(
      requestOptions: RequestOptions(path: url),
      statusCode: 200,
      data: content as T,
      headers: Headers.fromMap({
        'profile-title': ['New servers'],
        'profile-update-interval': ['1'],
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected second network request');
}

void main() {
  const validBaseUrl = "https://example.com/configurations/user1/filename.yaml";
  const validExtendedUrl = "https://example.com/configurations/user1/filename.yaml?test#b";
  const validSupportUrl = "https://example.com/support";

  test('применяет полученную подписку с заголовками без повторной загрузки', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _SourceClient();
    final container = ProviderContainer(overrides: [httpClientProvider.overrideWith((ref) => client)]);
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    final parser = container.read(profileParserProvider);
    final source = (await parser.fetchRemoteSource('https://api.amnez.online/sub/test').run()).getOrElse(
      (e) => throw e,
    );
    final temp = await Directory.systemTemp.createTemp('tunnelo-subscription-test-');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/profile';
    final result = await parser
        .updateRemote(
          rp: RemoteProfileEntity(
            id: 'id',
            active: true,
            name: 'Old',
            url: 'https://api.amnez.online/sub/test',
            lastUpdate: DateTime(2020),
          ),
          tempFilePath: path,
          source: source,
        )
        .run();
    final entry = result.getOrElse((e) => throw e);
    expect(client.requests, 1);
    expect(client.usedDirect, isTrue);
    expect(await File(path).readAsString(), source.content);
    expect(entry.name.value, 'New servers');
    expect(entry.updateInterval.value, const Duration(hours: 1));
  });

  test('пустой ответ сервера не принимается как новая подписка', () async {
    SharedPreferences.setMockInitialValues({});
    final client = _SourceClient()..content = '';
    final container = ProviderContainer(overrides: [httpClientProvider.overrideWith((ref) => client)]);
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    final result = await container
        .read(profileParserProvider)
        .fetchRemoteSource('https://api.amnez.online/sub/test')
        .run();
    expect(result.isLeft(), isTrue);
  });

  group('адрес загрузки подписки', () {
    test('исправляет сохранённые адреса Tunnelo, которые теперь отвечают 404', () {
      for (final host in ['panel.amnez.online', 'api.amnez.online']) {
        expect(
          ProfileParser.subscriptionDownloadUrl('https://$host/api/sub/test_key-1'),
          'https://$host/sub/test_key-1',
        );
      }
    });

    test('сохраняет параметры, название профиля и завершающий слеш', () {
      expect(
        ProfileParser.subscriptionDownloadUrl(' https://panel.amnez.online/api/sub/test/?all=1#Tunnelo '),
        'https://panel.amnez.online/sub/test/?all=1#Tunnelo',
      );
    });

    test('сохраняет работающие адреса и ссылки других провайдеров', () {
      for (final url in [
        'https://api.amnez.online/sub/test',
        'https://panel.amnez.online/sub/test',
        'https://example.com/api/sub/test',
        'https://panel.amnez.online:54629/api/sub/test',
        'https://panel.amnez.online/another/api/sub/test',
      ]) {
        expect(ProfileParser.subscriptionDownloadUrl(url), url);
      }
    });
  });

  group("parse", () {
    test("Should use filename in url with no headers and fragment", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validBaseUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("filename"));
            expect(rp.url, equals(validBaseUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use fragment in url with no headers", () {
      final profile = ProfileParser.parse(
        tempFilePath: '',
        profile: ProfileEntity.remote(
          id: const Uuid().v4(),
          active: true,
          name: '',
          url: validExtendedUrl,
          lastUpdate: DateTime.now(),
        ),
      );
      expect(profile.isRight(), true);
      profile.match((l) {}, (r) {
        expect(r is RemoteProfileEntity, true);
        r.map(
          remote: (rp) {
            expect(rp.name, equals("b"));
            expect(rp.url, equals(validExtendedUrl));
            expect(rp.options, isNull);
            expect(rp.subInfo, isNull);
          },
          local: (lp) {},
        );
      });
    });

    test("Should use base64 title in headers", () {
      final headers = <String, List<String>>{
        "profile-title": ["base64:ZXhhbXBsZVRpdGxl"],
        "profile-update-interval": ["1"],
        "connection-test-url": [validBaseUrl],
        "remote-dns-address": [validBaseUrl],
        "subscription-userinfo": ["upload=0;download=1024;total=10240.5;expire=1704054600.55"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: ProfileEntity.remote(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validExtendedUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.name, equals("exampleTitle"));
              expect(rp.url, equals(validExtendedUrl));
              expect(rp.options, equals(const ProfileOptions(updateInterval: Duration(hours: 1))));
              expect(
                rp.subInfo,
                equals(
                  SubscriptionInfo(
                    upload: 0,
                    download: 1024,
                    total: 10240,
                    expire: DateTime.fromMillisecondsSinceEpoch(1704054600 * 1000),
                    webPageUrl: validBaseUrl,
                    supportUrl: validSupportUrl,
                  ),
                ),
              );
            },
            local: (lp) {},
          );
        });
      });
    });

    test("Should use infinite when given 0 for subscription properties", () {
      final headers = <String, List<String>>{
        "profile-title": ["title"],
        "profile-update-interval": ["1"],
        "subscription-userinfo": ["upload=0;download=1024;total=0;expire=0"],
        "profile-web-page-url": [validBaseUrl],
        "support-url": [validSupportUrl],
      };
      // This fix occurs in the _downloadProfile method within ProfileParser, and the fixed headers are passed to populateHeaders
      final fixedHeaders = headers.map((key, value) {
        if (value.length == 1) return MapEntry(key, value.first);
        return MapEntry(key, value);
      });
      final allHeaders = ProfileParser.populateHeaders(content: '', remoteHeaders: fixedHeaders);
      expect(allHeaders.isRight(), true);
      allHeaders.match((l) {}, (r) {
        final profile = ProfileParser.parse(
          tempFilePath: '',
          profile: RemoteProfileEntity(
            id: const Uuid().v4(),
            active: true,
            name: '',
            url: validBaseUrl,
            lastUpdate: DateTime.now(),
            populatedHeaders: r,
          ),
        );
        expect(profile.isRight(), true);
        profile.match((l) {}, (r) {
          expect(r is RemoteProfileEntity, true);
          r.map(
            remote: (rp) {
              expect(rp.subInfo, isNotNull);
              expect(rp.subInfo!.total, equals(ProfileParser.infiniteTrafficThreshold + 1));
              expect(
                rp.subInfo!.expire,
                equals(DateTime.fromMillisecondsSinceEpoch(ProfileParser.infiniteTimeThreshold * 1000)),
              );
            },
            local: (lp) {},
          );
        });
      });
    });
  });
}
