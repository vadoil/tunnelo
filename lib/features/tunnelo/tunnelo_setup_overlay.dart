import 'package:flutter/material.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Экран первого запуска.
///
/// Показывается поверх приложения, пока идёт автоактивация: человек
/// ничего не вводит, просто видит, что происходит. Исчезает сам,
/// когда серверы загружены.
class TunneloSetupOverlay extends ConsumerWidget {
  const TunneloSetupOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(tunneloSetupProvider);
    final visible = setup is SetupRunning || setup is SetupFailed;

    return Stack(
      children: [
        child,
        IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 320),
            child: _Curtain(state: setup),
          ),
        ),
      ],
    );
  }
}

class _Curtain extends ConsumerWidget {
  const _Curtain({required this.state});
  final SetupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = state is SetupFailed;

    return Material(
      color: TunneloColors.abyss,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.0,
            colors: [Color(0xFF16224A), TunneloColors.abyss],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TunnelRings(
                  state: failed ? TunnelState.error : TunnelState.working,
                  size: 176,
                ),
                const SizedBox(height: 40),
                Text(
                  failed ? 'Не удалось подключиться' : 'Tunnelo',
                  style: const TextStyle(
                    color: TunneloColors.core,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: failed ? -0.3 : 3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  switch (state) {
                    SetupRunning(:final message) => message,
                    SetupFailed(:final message) => message,
                    _ => '',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: TunneloColors.muted,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () =>
                          ref.read(tunneloSetupProvider.notifier).runIfNeeded(),
                      style: FilledButton.styleFrom(
                        backgroundColor: TunneloColors.ringNear,
                        foregroundColor: TunneloColors.abyss,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        textStyle: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Повторить'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        ref.read(tunneloSetupProvider.notifier).clearError(),
                    style: TextButton.styleFrom(
                      foregroundColor: TunneloColors.muted,
                    ),
                    child: const Text('Настроить позже'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
