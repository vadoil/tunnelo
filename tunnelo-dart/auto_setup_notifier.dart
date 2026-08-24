import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/tunnelo/activation_service.dart';
import 'package:hiddify/utils/utils.dart';

final activationServiceProvider = Provider((ref) => ActivationService());

/// Состояние первичной настройки.
sealed class AutoSetupState {
  const AutoSetupState();
}

class AutoSetupIdle extends AutoSetupState {
  const AutoSetupIdle();
}

class AutoSetupRunning extends AutoSetupState {
  const AutoSetupRunning(this.message);
  final String message;
}

class AutoSetupDone extends AutoSetupState {
  const AutoSetupDone({required this.daysLeft});
  final int? daysLeft;
}

class AutoSetupFailed extends AutoSetupState {
  const AutoSetupFailed(this.message);
  final String message;
}

/// Автонастройка при первом запуске.
///
/// Пользователь не должен ничего вводить: приложение само активирует
/// промокод по умолчанию и подставляет подписку. Ручной ввод кода
/// остаётся отдельной кнопкой — для платных ключей.
class AutoSetupNotifier extends StateNotifier<AutoSetupState> with AppLogger {
  AutoSetupNotifier(this._ref) : super(const AutoSetupIdle());

  final Ref _ref;

  ActivationService get _activation => _ref.read(activationServiceProvider);

  /// Вызывается один раз при старте, если профилей ещё нет.
  Future<void> runIfNeeded() async {
    if (state is AutoSetupRunning) return;

    final profiles = await _ref.read(profilesProvider.future).catchError((_) => <dynamic>[]);
    if (profiles.isNotEmpty) {
      loggy.debug('профили уже есть, автонастройка не нужна');
      state = const AutoSetupDone(daysLeft: null);
      return;
    }

    final saved = await _activation.savedSubscription();
    if (saved != null) {
      loggy.debug('подписка уже сохранена, добавляю профиль');
      await _addProfile(saved);
      state = const AutoSetupDone(daysLeft: null);
      return;
    }

    await activate(Constants.defaultPromoCode, silent: true);
  }

  /// Активация промокода — и автоматическая, и по кнопке.
  Future<bool> activate(String code, {bool silent = false}) async {
    state = AutoSetupRunning(silent ? 'Настраиваем подключение…' : 'Проверяем промокод…');
    try {
      final result = await _activation.activate(code: code);
      loggy.info('активирован ключ ${result.key}, дней: ${result.daysLeft}');

      state = const AutoSetupRunning('Загружаем серверы…');
      await _addProfile(result.subscription);

      state = AutoSetupDone(daysLeft: result.daysLeft);
      return true;
    } on ActivationException catch (e) {
      loggy.warning('активация не удалась: ${e.message}');
      state = AutoSetupFailed(e.message);
      return false;
    } catch (e) {
      loggy.error('неожиданная ошибка активации', e);
      state = const AutoSetupFailed('Не удалось настроить подключение');
      return false;
    }
  }

  Future<void> _addProfile(String subscriptionUrl) async {
    await _ref.read(addProfileProvider.notifier).addClipboard(subscriptionUrl);
  }

  void clearError() {
    if (state is AutoSetupFailed) state = const AutoSetupIdle();
  }
}

final autoSetupProvider = StateNotifierProvider<AutoSetupNotifier, AutoSetupState>(
  AutoSetupNotifier.new,
);
