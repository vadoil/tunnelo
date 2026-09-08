import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Кнопка подключения — фонарь в лапах лиса.
///
/// Смысл прямой: фонарь и есть свет в конце туннеля. Пока не нажали, он
/// тлеет; при подключении разгорается. Одна метафора на весь продукт лучше
/// круглой кнопки, которая ничего не значит.
class TunneloFoxButton extends HookConsumerWidget {
  const TunneloFoxButton({super.key});

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
    )..repeat(reverse: true);
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
              return SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Свет фонаря. Он же — вся анимация состояния.
                    Align(
                      alignment: _lantern,
                      child: _Glow(
                        strength: connected ? 0.55 + 0.45 * t : 0.10 + 0.12 * t,
                        warm: connected,
                        size: connected ? 150 + 26 * t : 90 + 10 * t,
                      ),
                    ),
                    // Лис слегка покачивается — экран перестаёт быть мёртвым.
                    Transform.translate(
                      offset: Offset(0, -3 * math.sin(t * math.pi)),
                      child: Image.asset(
                        'assets/images/fox/lantern.png',
                        height: 240,
                        fit: BoxFit.contain,
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

/// Мягкое свечение фонаря.
class _Glow extends StatelessWidget {
  const _Glow({required this.strength, required this.warm, required this.size});

  final double strength;
  final bool warm;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = warm ? const Color(0xFFFFC46B) : TunneloColors.sea;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: strength.clamp(0.0, 1.0)),
              color.withValues(alpha: (strength * 0.35).clamp(0.0, 1.0)),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}
