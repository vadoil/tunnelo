import 'dart:io';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/utils/utils.dart';

abstract interface class AppUpdateRepository {
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  });
}

class AppUpdateRepositoryImpl with ExceptionHandler, InfraLogger implements AppUpdateRepository {
  AppUpdateRepositoryImpl({required this.httpClient});

  final DioHttpClient httpClient;

  @override
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  }) {
    return exceptionHandler(() async {
      if (!release.allowCustomUpdateChecker) {
        throw Exception("custom update checkers are not supported");
      }
      // Tunnelo: релизов на GitHub нет, сборки лежат в /dl/ на нашем сервере,
      // а рядом latest.json с версией и ссылками по платформам.
      final response = await httpClient.get<Map<String, dynamic>>(Constants.latestVersionUrl);
      if (response.statusCode != 200 || response.data == null) {
        loggy.warning("failed to fetch latest version info");
        return left(const AppUpdateFailure.unexpected());
      }
      final latest = parseLatest(response.data!, platformKey);
      if (latest == null) {
        loggy.info("no download for this platform in latest.json");
        return left(const AppUpdateFailure.unexpected());
      }
      return right(latest);
    }, AppUpdateFailure.unexpected);
  }

  /// Ключ платформы в поле downloads файла latest.json.
  static String get platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'linux';
  }

  /// latest.json → версия. null, если для платформы нет ссылки на сборку:
  /// тогда и звать обновляться некуда.
  static RemoteVersionEntity? parseLatest(Map<String, dynamic> json, String platform) {
    final version = json['version'] as String?;
    if (version == null || version.isEmpty) return null;
    final downloads = json['downloads'];
    final url = downloads is Map ? downloads[platform] as String? : null;
    if (url == null || url.isEmpty) return null;
    return RemoteVersionEntity(
      version: version,
      buildNumber: (json['build'] ?? '').toString(),
      releaseTag: 'v$version',
      preRelease: false,
      url: url,
      publishedAt: DateTime.tryParse((json['published'] ?? '').toString()) ?? DateTime.now(),
      flavor: Environment.prod,
    );
  }
}
