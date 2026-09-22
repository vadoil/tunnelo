import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Кнопка подключения — фонарь в лапах лиса.
///
/// Смысл прямой: фонарь и есть свет в конце туннеля. Пока не нажали, он
/// тлеет; при подключении разгорается. Одна метафора на весь продукт лучше
/// круглой кнопки, которая ничего не значит.
class TunneloFoxButton extends HookConsumerWidget {
  const TunneloFoxButton({super.key, this.size = 260});

  /// Сторона квадрата с лисом. Свет и картинка масштабируются вместе с ним.
  final double size;

  /// Где на картинке фонарь. Подобрано по самому изображению: если лиса
  /// перерисуют, поправить нужно здесь.
  static const _lantern = Alignment(-0.67, 0.26);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    // valueOrNull, а не value: у AsyncError обращение к value бросает
    // исключение, и главный экран падал бы красным при любом сбое ядра.
    final state = status.valueOrNull;
    final connected = state is Connected;
    final busy = state is Connecting || state is Disconnecting;

    final pulse = useAnimationController(
      duration: const Duration(milliseconds: 2600),
    );
    // Запуск только в useEffect. Раньше repeat() стоял прямо в build и
    // срабатывал на каждой перерисовке — Flutter ругался «setState() called
    // during build», а дыхание сбивалось при любом изменении состояния.
    //
    // Пока идёт подключение — дышим вдвое чаще: это и есть индикатор работы.
    useEffect(() {
      pulse.duration = Duration(milliseconds: busy ? 900 : 2600);
      pulse.repeat(reverse: true);
      return null;
    }, [busy]);

    return GestureDetector(
      onTap: () => _toggle(context, ref, status),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(pulse.value);
              final k = size / 260;
              // Фонарь — индикатор VPN: выключен, пока туннеля нет; горит и
              // чуть подрагивает, как живой огонь, когда подключено; пока
              // поднимаем туннель — слабо дышит.
              final flame = connected ? _flicker(pulse.value) : 0.0;
              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (connected) ...[
                      // Три слоя огня: широкое зарево заливает всё вокруг
                      // фонаря, средний ореол держит форму, яркое ядро дышит
                      // быстрее остальных. Один слой давал ровное пятно —
                      // с тремя свет живёт.
                      Align(
                        alignment: _lantern,
                        child: _Glow(
                          strength: 0.30 + 0.22 * flame,
                          warm: true,
                          size: (300 + 60 * flame) * k,
                        ),
                      ),
                      Align(
                        alignment: _lantern,
                        child: _Glow(
                          strength: 0.62 + 0.38 * flame,
                          warm: true,
                          size: (170 + 34 * flame) * k,
                        ),
                      ),
                      Align(
                        alignment: _lantern,
                        child: _Glow(
                          strength: 0.85 + 0.15 * _flicker(1 - pulse.value),
                          warm: true,
                          size: (74 + 16 * flame) * k,
                          core: true,
                        ),
                      ),
                    ] else if (busy)
                      Align(
                        alignment: _lantern,
                        child: _Glow(strength: 0.10 + 0.12 * t, warm: false, size: (90 + 10 * t) * k),
                      ),
                    // Лис слегка покачивается — экран перестаёт быть мёртвым.
                    Transform.translate(
                      offset: Offset(0, -3 * math.sin(t * math.pi)),
                      child: Image.asset(
                        'assets/images/fox/lantern.png',
                        height: size - 20,
                        fit: BoxFit.contain,
                      ),
                    ),
                    // Без туннеля фонарь погашен: на картинке он всегда горит,
                    // поэтому гасим его тёмным пятном поверх стекла.
                    if (!connected)
                      Align(
                        alignment: _lantern,
                        child: Transform.translate(
                          offset: Offset(0, -3 * math.sin(t * math.pi)),
                          child: _Shade(size: 46 * k),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            switch (state) {
              Connected() => 'Подключено',
              Connecting() => 'Поднимаем туннель…',
              Disconnecting() => 'Отключаемся…',
              _ => 'Нажмите на фонарь',
            },
            style: TextStyle(
              color: connected ? TunneloColors.seaDeep : TunneloColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          // Три слова под фонарём отвечают на три вопроса, с которыми чаще
          // всего приходят в поддержку: подключено ли, через какую страну и
          // сколько дней осталось. Раньше здесь было только «Подключено».
          if (connected) const _ConnectedDetails(),
        ],
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ConnectionStatus> status,
  ) async {
    final notifier = ref.read(connectionNotifierProvider.notifier);
    switch (status) {
      case AsyncData(value: Connected()):
        await notifier.toggleConnection();
      case AsyncData(value: Disconnected()) || AsyncError():
        if (ref.read(activeProfileProvider).valueOrNull == null) {
          await ref.read(dialogNotifierProvider.notifier).showNoActiveProfile();
          ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
          return;
        }
        await notifier.toggleConnection();
      default:
        break;
    }
  }
}

/// Дрожание огня: несколько несовпадающих волн поверх дыхания контроллера,
/// чтобы свет не пульсировал метрономом, а подрагивал. Возвращает 0…1.
double _flicker(double v) {
  final w = v * 2 * math.pi;
  final x = 0.55 + 0.25 * math.sin(w) + 0.12 * math.sin(3.7 * w + 1.3) + 0.08 * math.sin(9.1 * w + 2.1);
  return x.clamp(0.0, 1.0);
}

/// Погашенное стекло фонаря: полупрозрачная тень поверх картинки.
class _Shade extends StatelessWidget {
  const _Shade({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            TunneloColors.mistDeep.withValues(alpha: 0.72),
            TunneloColors.mistDeep.withValues(alpha: 0.55),
            TunneloColors.mistDeep.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    ),
  );
}

/// Мягкое свечение фонаря.
class _Glow extends StatelessWidget {
  const _Glow({required this.strength, required this.warm, required this.size, this.core = false});

  final double strength;
  final bool warm;
  final double size;

  /// Ядро пламени: почти белое в середине — так огонь читается горячим,
  /// а не просто оранжевым пятном.
  final bool core;

  @override
  Widget build(BuildContext context) {
    final color = warm ? const Color(0xFFFFC46B) : TunneloColors.sea;
    final middle = core ? const Color(0xFFFFB347) : color;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              (core ? const Color(0xFFFFF3D0) : color).withValues(alpha: strength.clamp(0.0, 1.0)),
              middle.withValues(alpha: (strength * (core ? 0.75 : 0.35)).clamp(0.0, 1.0)),
              color.withValues(alpha: 0),
            ],
            stops: core ? const [0.0, 0.32, 1.0] : const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Страна и остаток дней под надписью «Подключено».
class _ConnectedDetails extends ConsumerWidget {
  const _ConnectedDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxy = ref.watch(activeProxyNotifierProvider.select((v) => v.valueOrNull));
    final sub = ref.watch(tunneloSubscriptionProvider).valueOrNull;

    final parts = <String>[
      if (_country(proxy?.tag) case final String c) c,
      if (sub?.daysLeft case final int d when d > 0) '$d ${_pluralDays(d)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join(' · '),
        style: const TextStyle(color: TunneloColors.muted, fontSize: 14),
      ),
    );
  }

  /// Из тега узла оставляем страну без номера: номер уже виден в карточке
  /// сервера, а здесь важнее короткая строка.
  static String? _country(String? tag) {
    if (tag == null || tag.trim().isEmpty) return null;
    if (tag == 'lowest' || tag == 'balance' || tag == 'select') return null;
    var name = tag.split('§').first.split('·').first.trim();
    name = name.replaceAll(RegExp(r'[-–]\s*\d+$'), '').trim();
    return name.isEmpty ? null : name;
  }

  static String _pluralDays(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}
