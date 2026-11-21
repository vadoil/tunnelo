import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const interval = Duration(minutes: 15);

  /// Старые подписки Tunnelo могли сохраниться без интервала обновления.
  /// Проверяем их каждые 15 минут, даже если панель не прислала заголовок.
  static Duration? _updateIntervalFor(RemoteProfileEntity profile) {
    if (profile.userOverride?.isAutoUpdateDisable ?? false) return null;
    final userInterval = profile.userOverride?.updateInterval;
    if (userInterval != null && userInterval > 0) return Duration(hours: userInterval);

    final uri = Uri.tryParse(profile.url);
    if (uri != null &&
        (uri.host == 'panel.amnez.online' || uri.host == 'api.amnez.online') &&
        (uri.path.startsWith('/sub/') || uri.path.startsWith('/api/sub/'))) {
      return interval;
    }
    return profile.options?.updateInterval;
  }

  @override
  Stream<ProfileUpdateStatus?> build() {
    var cycleCount = 0;
    final scheduler = _scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: interval,
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    ref.onDispose(() async {
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

  /// При возврате из фона сразу проверяем срок обновления каждой подписки.
  Future<void> refresh() async {
    if (!ref.read(Preferences.introCompleted)) return;
    await _scheduler?.trigger();
  }

  Future<void> trigger() async {
    loggy.debug("triggering update");
    _forceNextRun = true;
    await _scheduler?.trigger();
  }

  @visibleForTesting
  Future<void> updateProfiles() async {
    if (_updating) return;
    _updating = true;
    final force = _forceNextRun;
    _forceNextRun = false;

    try {
      // Репозиторий при старте ещё может загружаться. Не теряем первый цикл.
      final repository = await ref.read(profileRepositoryProvider.future);
      final remoteProfiles = await repository
          .watchAll()
          .map(
            (event) => event.getOrElse((f) {
              loggy.error("error getting profiles");
              throw f;
            }).whereType<RemoteProfileEntity>(),
          )
          .first;

      await for (final profile in Stream.fromIterable(remoteProfiles)) {
        final updateInterval = _updateIntervalFor(profile);
        if (force || updateInterval != null && updateInterval <= DateTime.now().difference(profile.lastUpdate)) {
          final previousConfig = profile.active ? await repository.getRawConfig(profile.id).run() : null;
          final t = ref.read(translationsProvider).requireValue;
          final result = await repository.upsertRemote(profile.url).run();
          result.match(
            (l) {
              loggy.debug("error updating profile [${profile.id}]", l);
              ref
                  .read(inAppNotificationControllerProvider)
                  .showErrorToast(t.pages.profiles.msg.update.failureNamed(name: profile.name));
              state = AsyncData((name: profile.name, success: false));
            },
            (_) {
              loggy.debug("profile [${profile.id}] updated successfully");
              ref
                  .read(inAppNotificationControllerProvider)
                  .showSuccessToast(t.pages.profiles.msg.update.successNamed(name: profile.name));
              state = AsyncData((name: profile.name, success: true));
            },
          );

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
    }
  }
}
