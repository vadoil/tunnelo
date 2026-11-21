import 'package:dio/dio.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/remote_profile_source.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const interval = Duration(seconds: 10);

  static bool _isManaged(RemoteProfileEntity profile) {
    final uri = Uri.tryParse(profile.url);
    return uri != null &&
        (uri.host == 'panel.amnez.online' || uri.host == 'api.amnez.online') &&
        (uri.path.startsWith('/sub/') || uri.path.startsWith('/api/sub/'));
  }

  /// Подписки Tunnelo проверяем часто; сторонние сохраняют свои интервалы.
  static Duration? _updateIntervalFor(RemoteProfileEntity profile) {
    if (profile.userOverride?.isAutoUpdateDisable ?? false) return null;
    final userInterval = profile.userOverride?.updateInterval;
    if (userInterval != null && userInterval > 0) return Duration(hours: userInterval);

    if (_isManaged(profile)) return interval;
    return profile.options?.updateInterval;
  }

  @override
  Stream<ProfileUpdateStatus?> build() {
    _foreground = true;
    _refreshManagedNextRun = true;
    var cycleCount = 0;
    final scheduler = _scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: interval,
      minCycle: const Duration(seconds: 1),
      maxCycle: const Duration(seconds: 5),
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    ref.onDispose(() async {
      _foreground = false;
      _pollCancelToken?.cancel();
      if (identical(_scheduler, scheduler)) _scheduler = null;
      await scheduler.stop();
    });

    if (ref.watch(Preferences.introCompleted)) {
      loggy.debug("intro done, starting");
      _scheduler?.start();
    } else {
      loggy.debug("intro in process, skipping");
    }
    return const Stream.empty();
  }

  NeatPeriodicTaskScheduler? _scheduler;
  bool _forceNextRun = false;
  bool _updating = false;
  bool _foreground = true;
  bool _refreshManagedNextRun = false;
  CancelToken? _pollCancelToken;
  final _sources = <String, ({String url, String version, String? userOverride})>{};
  final _lastChecks = <String, DateTime>{};

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  void suspend() {
    _foreground = false;
    _pollCancelToken?.cancel();
  }

  /// При возврате из фона проверяем Tunnelo сразу, даже после свежей проверки.
  Future<void> refresh() async {
    _foreground = true;
    if (!ref.read(Preferences.introCompleted)) return;
    _refreshManagedNextRun = true;
    await _scheduler?.trigger();
  }

  Future<void> trigger() async {
    loggy.debug("triggering update");
    _forceNextRun = true;
    await _scheduler?.trigger();
  }

  @visibleForTesting
  Future<void> updateProfiles() async {
    if (_updating || !_foreground) return;
    _updating = true;
    final force = _forceNextRun;
    final refreshManaged = _refreshManagedNextRun;
    _forceNextRun = false;
    _refreshManagedNextRun = false;

    try {
      // Репозиторий при старте ещё может загружаться. Не теряем первый цикл.
      final repository = await ref.read(profileRepositoryProvider.future);
      final remoteProfiles = await repository
          .watchAll()
          .map(
            (event) => event
                .getOrElse((f) {
                  loggy.error("error getting profiles");
                  throw f;
                })
                .whereType<RemoteProfileEntity>()
                .toList(),
          )
          .first;

      final ids = remoteProfiles.map((p) => p.id).toSet();
      _sources.removeWhere((id, _) => !ids.contains(id));
      _lastChecks.removeWhere((id, _) => !ids.contains(id));
      for (final profile in remoteProfiles) {
        if (!_foreground) return;
        final managed = _isManaged(profile);
        final updateInterval = _updateIntervalFor(profile);
        final checked = _lastChecks[profile.id];
        final lastCheck = checked != null && checked.isAfter(profile.lastUpdate) ? checked : profile.lastUpdate;
        final previousSource = _sources[profile.id];
        final sourceChanged =
            managed &&
            previousSource != null &&
            (previousSource.url != profile.url || previousSource.userOverride != profile.userOverride?.toStr());
        final due =
            updateInterval != null &&
            (refreshManaged && managed || sourceChanged || updateInterval <= clock().difference(lastCheck));
        if (force || due) {
          RemoteProfileSource? source;
          if (managed) {
            final cancelToken = _pollCancelToken = CancelToken();
            final fetched = await ref
                .read(profileParserProvider)
                .fetchRemoteSource(profile.url, cancelToken: cancelToken)
                .run();
            if (!_foreground || cancelToken.isCancelled) return;
            source = fetched.match<RemoteProfileSource?>((failure) {
              loggy.debug('subscription check failed for [${profile.id}]', failure);
              _report(profile, success: false, notify: force);
              return null;
            }, (value) => value);
            if (source == null) continue;
            final cached = _sources[profile.id];
            if (!force &&
                cached != null &&
                cached.url == profile.url &&
                cached.version == source.fingerprint &&
                cached.userOverride == profile.userOverride?.toStr()) {
              _lastChecks[profile.id] = clock();
              continue;
            }
            final current = (await repository.getById(profile.id).run()).getOrElse((_) => null);
            if (current is! RemoteProfileEntity || current.url != profile.url) continue;
          }
          final previousConfig = profile.active ? await repository.getRawConfig(profile.id).run() : null;
          final result = await repository
              .upsertRemote(profile.url, source: source, cancelToken: _pollCancelToken)
              .run();
          if (!_foreground) return;
          result.match(
            (l) {
              loggy.debug("error updating profile [${profile.id}]", l);
              _report(profile, success: false, notify: force);
            },
            (_) {
              loggy.debug("profile [${profile.id}] updated successfully");
              _report(profile, success: true, notify: force);
            },
          );

          if (result.isRight() && source != null) {
            _sources[profile.id] = (
              url: profile.url,
              version: source.fingerprint,
              userOverride: profile.userOverride?.toStr(),
            );
            _lastChecks[profile.id] = clock();
          }

          // Список на экране берётся из работающего ядра. Одной записи на
          // диск недостаточно: применяем изменившийся профиль к туннелю.
          if (result.isRight() && previousConfig != null) {
            final currentConfig = await repository.getRawConfig(profile.id).run();
            if (currentConfig.isRight() && previousConfig != currentConfig) {
              final active = await repository.watchActiveProfile().first;
              final activeProfile = active.getOrElse((_) => null);
              if (activeProfile?.id == profile.id) {
                await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
              }
            }
          }
        } else {
          loggy.debug(
            "skipping profile [${profile.id}] update. last successful update: [${profile.lastUpdate}] - interval: [${profile.options?.updateInterval}]",
          );
        }
      }
    } finally {
      // Неудачная попытка не сдвигает срок следующего обновления: он
      // считается по lastUpdate, записанному только после успешной загрузки.
      _updating = false;
      _pollCancelToken = null;
    }
  }

  void _report(RemoteProfileEntity profile, {required bool success, required bool notify}) {
    state = AsyncData((name: profile.name, success: success));
    if (!notify) return;
    final t = ref.read(translationsProvider).requireValue;
    final notifications = ref.read(inAppNotificationControllerProvider);
    if (success) {
      notifications.showSuccessToast(t.pages.profiles.msg.update.successNamed(name: profile.name));
    } else {
      notifications.showErrorToast(t.pages.profiles.msg.update.failureNamed(name: profile.name));
    }
  }
}
