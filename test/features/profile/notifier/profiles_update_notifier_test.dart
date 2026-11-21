import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/model/remote_profile_source.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

class _Updater extends ForegroundProfilesUpdateNotifier {
  @override
  Stream<ProfileUpdateStatus?> build() => const Stream.empty();
}

class _Notifications extends InAppNotificationController {
  int shown = 0;
  @override
  ToastificationItem? showErrorToast(String message) {
    shown++;
    return null;
  }

  @override
  ToastificationItem? showSuccessToast(String message) {
    shown++;
    return null;
  }
}

class _Parser implements ProfileParser {
  _Parser(this.repository);
  final _Repository repository;
  int checks = 0;
  bool fail = false;
  Map<String, dynamic> headers = {};
  @override
  TaskEither<ProfileFailure, RemoteProfileSource> fetchRemoteSource(String url, {CancelToken? cancelToken}) =>
      TaskEither(() async {
        checks++;
        if (fail) return left(const ProfileFailure.unexpected());
        return right(RemoteProfileSource(content: repository.nextConfig, headers: Map.of(headers)));
      });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection extends ConnectionNotifier {
  final reconnected = <ProfileEntity?>[];
  bool canApply = true;

  @override
  Stream<ConnectionStatus> build() => Stream.value(const Connected());

  @override
  Future<bool> applyProfileUpdate(ProfileEntity profile) async {
    if (!canApply) return false;
    reconnected.add(profile);
    return true;
  }
}

class _Repository implements ProfileRepository {
  _Repository(this.profiles);

  List<ProfileEntity> profiles;
  final requested = <String>[];
  final appliedSources = <RemoteProfileSource?>[];
  String config = 'old servers';
  String nextConfig = 'old servers';
  bool fail = false;
  bool switchProfile = false;
  Completer<void>? pending;
  void Function()? afterApply;

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) => Stream.value(right(profiles));

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() =>
      Stream.value(right(profiles.where((p) => p.active).firstOrNull));

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) => TaskEither.right(config);

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) =>
      TaskEither.right(profiles.where((p) => p.id == id).firstOrNull);

  @override
  TaskEither<ProfileFailure, ProfileRefreshResult?> refreshRemote(
    RemoteProfileEntity expected, {
    CancelToken? cancelToken,
    RemoteProfileSource? source,
  }) => TaskEither(() async {
    final url = expected.url;
    requested.add(url);
    appliedSources.add(source);
    await pending?.future;
    if (fail) return left(const ProfileFailure.unexpected());
    final before = config;
    config = source?.content ?? nextConfig;
    profiles = [
      for (final p in profiles)
        if (p is RemoteProfileEntity && p.url == url)
          p.copyWith(lastUpdate: DateTime.now(), active: !switchProfile && p.active)
        else
          p,
    ];
    afterApply?.call();
    return right(
      ProfileRefreshResult(
        configurationChanged:
            RemoteProfileSource.configurationVersion(before) != RemoteProfileSource.configurationVersion(config),
      ),
    );
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RemoteProfileEntity _profile({
  String url = 'https://api.amnez.online/sub/test',
  Duration age = const Duration(days: 1),
  bool active = false,
  ProfileOptions? options,
  UserOverride? userOverride,
}) => RemoteProfileEntity(
  id: 'profile',
  active: active,
  name: 'Tunnelo',
  url: url,
  lastUpdate: DateTime.now().subtract(age),
  options: options,
  userOverride: userOverride,
);

void main() {
  late _Repository repository;
  late _Connection connection;
  late ProviderContainer container;
  late ForegroundProfilesUpdateNotifier updater;
  late _Parser parser;
  late _Notifications notifications;
  late DateTime now;

  setUp(() async {
    repository = _Repository([_profile()]);
    connection = _Connection();
    parser = _Parser(repository);
    notifications = _Notifications();
    now = DateTime.now();
    container = ProviderContainer(
      overrides: [
        foregroundProfilesUpdateNotifierProvider.overrideWith(_Updater.new),
        profileRepositoryProvider.overrideWith((ref) => repository),
        profileParserProvider.overrideWith((ref) => parser),
        translationsProvider.overrideWith((ref) => TranslationsEn()),
        inAppNotificationControllerProvider.overrideWithValue(notifications),
        connectionNotifierProvider.overrideWith(() => connection),
      ],
    );
    await container.read(translationsProvider.future);
    updater = container.read(foregroundProfilesUpdateNotifierProvider.notifier);
    updater.clock = () => now;
  });

  tearDown(() => container.dispose());

  test('обновляет старую подписку Tunnelo без интервала, затем ждёт 10 секунд', () async {
    await updater.updateProfiles();
    await updater.updateProfiles();
    expect(repository.requested, ['https://api.amnez.online/sub/test']);
  });

  test('поддерживает старые адреса подписки на домене панели', () async {
    for (final path in ['/sub/test', '/api/sub/test']) {
      repository.profiles = [_profile(url: 'https://panel.amnez.online$path')];
      await updater.updateProfiles();
    }
    expect(repository.requested, hasLength(2));
  });

  test('для Tunnelo проверяет серверы через 10 секунд даже с редким интервалом панели', () async {
    repository.profiles = [
      _profile(
        age: const Duration(seconds: 11),
        options: const ProfileOptions(updateInterval: Duration(days: 1)),
      ),
    ];
    await updater.updateProfiles();
    expect(repository.requested, hasLength(1));
  });

  test('соблюдает явное отключение и интервал, заданные пользователем', () async {
    repository.profiles = [_profile(userOverride: const UserOverride(isAutoUpdateDisable: true))];
    await updater.updateProfiles();
    repository.profiles = [
      _profile(age: const Duration(minutes: 30), userOverride: const UserOverride(updateInterval: 2)),
    ];
    await updater.updateProfiles();
    expect(repository.requested, isEmpty);
  });

  test('сохраняет правила обновления сторонних подписок', () async {
    repository.profiles = [_profile(url: 'https://example.com/sub/test')];
    await updater.updateProfiles();
    repository.profiles = [
      _profile(
        url: 'https://example.com/sub/test',
        options: const ProfileOptions(updateInterval: Duration(hours: 1)),
      ),
    ];
    await updater.updateProfiles();
    expect(repository.requested, ['https://example.com/sub/test']);
  });

  test('после ошибки сразу повторяет устаревшую подписку и сохраняет старый список', () async {
    repository.fail = true;
    await updater.updateProfiles();
    expect(repository.config, 'old servers');
    repository.fail = false;
    repository.nextConfig = 'new servers';
    await updater.updateProfiles();
    expect(repository.requested, hasLength(2));
    expect(repository.config, 'new servers');
  });

  test('не запускает параллельные загрузки при возврате в приложение', () async {
    repository.pending = Completer<void>();
    final firstUpdate = updater.updateProfiles();
    while (repository.requested.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await updater.updateProfiles();
    expect(repository.requested, hasLength(1));
    repository.pending!.complete();
    await firstUpdate;
  });

  test('применяет изменившийся список к активному туннелю', () async {
    repository.profiles = [_profile(active: true)];
    repository.nextConfig = 'new servers';
    await updater.updateProfiles();
    expect(connection.reconnected.single?.id, 'profile');
  });

  test('не переподключает туннель, когда список серверов не изменился', () async {
    repository.profiles = [_profile(active: true)];
    await updater.updateProfiles();
    expect(connection.reconnected, isEmpty);
  });

  test('не переключает обратно профиль, который пользователь сменил во время загрузки', () async {
    repository.profiles = [_profile(active: true)];
    repository.nextConfig = 'new servers';
    repository.switchProfile = true;
    await updater.updateProfiles();
    expect(connection.reconnected, isEmpty);
  });

  test('видит изменение через 10 секунд после успешного обновления', () async {
    repository.profiles = [_profile(active: true)];
    await updater.updateProfiles();
    now = now.add(const Duration(seconds: 11));
    repository.nextConfig = 'new address and servers';
    await updater.updateProfiles();
    expect(parser.checks, 2);
    expect(repository.config, 'new address and servers');
    expect(connection.reconnected, hasLength(1));
    expect(repository.appliedSources.last?.content, 'new address and servers');
  });

  test('не пересобирает и не перезапускает неизменившуюся подписку при частых проверках', () async {
    repository.profiles = [_profile(active: true)];
    await updater.updateProfiles();
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 11));
      await updater.updateProfiles();
    }
    expect(parser.checks, 4);
    expect(repository.requested, hasLength(1));
    expect(connection.reconnected, isEmpty);
    expect(notifications.shown, 0);
  });

  test('каждый плановый цикл проверяет подписку даже если предыдущая загрузка заняла время', () async {
    await updater.updateProfiles(scheduled: true);
    now = now.add(const Duration(seconds: 8));
    repository.nextConfig = 'changed after previous slow download';
    await updater.updateProfiles(scheduled: true);
    expect(parser.checks, 2);
    expect(repository.config, 'changed after previous slow download');
  });

  test('изменение срока подписки обновляет профиль, рост трафика не перезапускает ядро', () async {
    parser.headers = {'subscription-userinfo': 'upload=1; download=2; total=0; expire=2000000000'};
    await updater.updateProfiles();
    now = now.add(const Duration(seconds: 11));
    parser.headers = {'subscription-userinfo': 'upload=3; download=4; total=0; expire=2000000000'};
    await updater.updateProfiles();
    expect(repository.requested, hasLength(1));
    now = now.add(const Duration(seconds: 11));
    parser.headers = {'subscription-userinfo': 'upload=3; download=4; total=0; expire=2100000000'};
    await updater.updateProfiles();
    expect(repository.requested, hasLength(2));
  });

  test('ошибка проверки сохраняет рабочий список и повторяется в следующем цикле', () async {
    await updater.updateProfiles();
    now = now.add(const Duration(seconds: 11));
    parser.fail = true;
    repository.nextConfig = 'new servers';
    await updater.updateProfiles();
    expect(repository.config, 'old servers');
    parser.fail = false;
    await updater.updateProfiles();
    expect(repository.config, 'new servers');
    expect(notifications.shown, 0);
  });

  test('останавливает частые запросы в фоне', () async {
    updater.suspend();
    await updater.updateProfiles();
    expect(parser.checks, 0);
    expect(repository.requested, isEmpty);
  });

  test('применяет обновление после возврата, если Android свернул приложение во время записи', () async {
    SharedPreferences.setMockInitialValues({'intro_completed': true});
    await container.read(sharedPreferencesProvider.future);
    repository.profiles = [_profile(active: true)];
    repository.nextConfig = 'new servers';
    repository.afterApply = updater.suspend;
    await updater.updateProfiles();
    expect(repository.config, 'new servers');
    expect(connection.reconnected, isEmpty);
    repository.afterApply = null;
    await updater.refresh();
    await updater.updateProfiles();
    expect(connection.reconnected, hasLength(1));
    expect(repository.requested, hasLength(1));
  });

  test('не теряет обновление пока ядро подключается или предыдущая попытка не удалась', () async {
    repository.profiles = [_profile(active: true)];
    repository.nextConfig = 'new servers';
    connection.canApply = false;
    await updater.updateProfiles();
    expect(connection.reconnected, isEmpty);
    connection.canApply = true;
    await updater.updateProfiles();
    expect(connection.reconnected, hasLength(1));
    await updater.updateProfiles();
    expect(connection.reconnected, hasLength(1));
  });

  test('перестановка полей JSON не перезапускает туннель', () async {
    repository.profiles = [_profile(active: true)];
    repository.config = '{"server":"example.com","port":443}';
    repository.nextConfig = ' { "port": 443, "server": "example.com" } ';
    await updater.updateProfiles();
    expect(connection.reconnected, isEmpty);
  });

  test('возврат во время загрузки запрашивает один свежий ответ после её завершения', () async {
    SharedPreferences.setMockInitialValues({'intro_completed': true});
    await container.read(sharedPreferencesProvider.future);
    repository.pending = Completer<void>();
    final running = updater.updateProfiles();
    while (repository.requested.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    updater.suspend();
    await updater.refresh();
    parser.headers = {'profile-title': 'changed after resume'};
    repository.nextConfig = 'changed while resuming';
    repository.pending!.complete();
    await running;
    expect(parser.checks, 2);
    expect(repository.config, 'changed while resuming');
  });

  test('настоящий планировщик проверяет при запуске и сразу после возврата из фона', () async {
    SharedPreferences.setMockInitialValues({'intro_completed': true});
    repository.profiles = [_profile(age: Duration.zero)];
    final live = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => repository),
        profileParserProvider.overrideWith((ref) => parser),
        inAppNotificationControllerProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(live.dispose);
    await live.read(sharedPreferencesProvider.future);
    final worker = live.read(foregroundProfilesUpdateNotifierProvider.notifier);
    await live.read(foregroundProfilesUpdateNotifierProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(parser.checks, 1);
    worker.suspend();
    repository.nextConfig = 'changed while backgrounded';
    await worker.updateProfiles();
    expect(parser.checks, 1);
    await worker.refresh();
    expect(parser.checks, 2);
    expect(repository.config, 'changed while backgrounded');
  });
}
