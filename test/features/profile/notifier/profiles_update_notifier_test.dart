import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

class _Updater extends ForegroundProfilesUpdateNotifier {
  @override
  Stream<ProfileUpdateStatus?> build() => const Stream.empty();
}

class _Notifications extends InAppNotificationController {
  @override
  ToastificationItem? showErrorToast(String message) => null;

  @override
  ToastificationItem? showSuccessToast(String message) => null;
}

class _Connection extends ConnectionNotifier {
  final reconnected = <ProfileEntity?>[];

  @override
  Stream<ConnectionStatus> build() => Stream.value(const Connected());

  @override
  Future<void> reconnect(ProfileEntity? profile) async => reconnected.add(profile);
}

class _Repository implements ProfileRepository {
  _Repository(this.profiles);

  List<ProfileEntity> profiles;
  final requested = <String>[];
  String config = 'old servers';
  String nextConfig = 'old servers';
  bool fail = false;
  bool switchProfile = false;
  Completer<void>? pending;

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
  TaskEither<ProfileFailure, Unit> upsertRemote(String url, {UserOverride? userOverride, CancelToken? cancelToken}) =>
      TaskEither(() async {
        requested.add(url);
        await pending?.future;
        if (fail) return left(const ProfileFailure.unexpected());
        config = nextConfig;
        profiles = [
          for (final p in profiles)
            if (p is RemoteProfileEntity && p.url == url)
              p.copyWith(lastUpdate: DateTime.now(), active: !switchProfile && p.active)
            else
              p,
        ];
        return right(unit);
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

  setUp(() async {
    repository = _Repository([_profile()]);
    connection = _Connection();
    container = ProviderContainer(
      overrides: [
        foregroundProfilesUpdateNotifierProvider.overrideWith(_Updater.new),
        profileRepositoryProvider.overrideWith((ref) => repository),
        translationsProvider.overrideWith((ref) => TranslationsEn()),
        inAppNotificationControllerProvider.overrideWithValue(_Notifications()),
        connectionNotifierProvider.overrideWith(() => connection),
      ],
    );
    await container.read(translationsProvider.future);
    updater = container.read(foregroundProfilesUpdateNotifierProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('обновляет старую подписку Tunnelo без интервала, затем ждёт 15 минут', () async {
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

  test('для Tunnelo проверяет серверы через 15 минут даже с редким интервалом панели', () async {
    repository.profiles = [
      _profile(
        age: const Duration(minutes: 16),
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
}
