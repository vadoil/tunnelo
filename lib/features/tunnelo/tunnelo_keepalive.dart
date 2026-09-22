import 'dart:async';

import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tunnelo_keepalive.g.dart';

/// Сторож подключения: туннель гаснет только по кнопке.
///
/// Соединение рвётся не только по желанию человека: падает узел, меняется
/// сеть, система усыпляет приложение, ядро умирает на ошибке. Раньше после
/// любого такого обрыва приложение просто оставалось выключенным — человек
/// узнавал об этом, когда не открывался сайт.
///
/// Теперь намерение живёт отдельно от состояния: пока человек не нажал
/// «отключить», сторож поднимает туннель заново. Паузы растут — 2, 4, 8…
/// до полуминуты: при лежащем узле частые попытки только жгут батарею.
/// Ещё он раз в минуту сверяется с состоянием — на случай, если обрыв
/// прошёл мимо потока событий (ядро умерло вместе с процессом).
class TunneloKeepAlive with InfraLogger {
  TunneloKeepAlive(this._ref);

  final Ref _ref;

  /// Паузы между попытками. Последняя повторяется, пока не выйдет.
  static const _backoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// Как часто сверяться с состоянием, даже когда событий нет.
  static const _heartbeat = Duration(minutes: 1);

  Timer? _retry;
  Timer? _pulse;
  int _attempt = 0;
  bool _stopped = false;

  void start() {
    _pulse = Timer.periodic(_heartbeat, (_) => _check(fromPulse: true));
    _ref.listen(connectionNotifierProvider, (_, next) {
      switch (next) {
        case AsyncData(value: Connected()):
          // Дошли: счётчик попыток обнуляем, иначе следующий обрыв начнёт
          // ждать сразу по полминуты.
          if (_attempt != 0) loggy.info("подключение восстановлено");
          _attempt = 0;
          _cancelRetry();
        case AsyncData(value: Disconnected()) || AsyncError():
          _scheduleRetry();
        default:
      }
    });
    // Приложение открыли, а туннель был включён до перезапуска — поднимаем.
    _check();
  }

  void dispose() {
    _stopped = true;
    _cancelRetry();
    _pulse?.cancel();
  }

  bool get _wantedOn => _ref.read(Preferences.startedByUser);

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
  }

  /// Сверка состояния с намерением. Нужна и при старте, и по таймеру:
  /// событие об обрыве могло не дойти — например, ядро упало вместе с
  /// процессом, и поток статусов оборвался молча.
  void _check({bool fromPulse = false}) {
    if (_stopped || !_wantedOn) return;
    final state = _ref.read(connectionNotifierProvider);
    switch (state) {
      case AsyncData(value: Disconnected()) || AsyncError():
        if (fromPulse) loggy.info("сверка: туннель выключен, а должен работать");
        _scheduleRetry();
      default:
    }
  }

  void _scheduleRetry() {
    if (_stopped || _retry != null) return;
    if (!_wantedOn) {
      // Выключено кнопкой — это единственная причина остаться выключенным.
      _attempt = 0;
      return;
    }
    final wait = _backoff[_attempt.clamp(0, _backoff.length - 1)];
    _attempt++;
    loggy.info("туннель упал, попытка $_attempt через ${wait.inSeconds} с");
    _retry = Timer(wait, () async {
      _retry = null;
      if (_stopped || !_wantedOn) return;
      final state = _ref.read(connectionNotifierProvider);
      if (state case AsyncData(value: Connected() || Connecting())) return;
      await _ref.read(connectionNotifierProvider.notifier).reconnectAfterDrop();
    });
  }
}

@Riverpod(keepAlive: true)
TunneloKeepAlive tunneloKeepAlive(Ref ref) {
  final keeper = TunneloKeepAlive(ref);
  ref.onDispose(keeper.dispose);
  keeper.start();
  return keeper;
}
