import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Экран промокода.
///
/// При первом запуске код применяется сам — сюда заходят те, у кого
/// платный ключ. Кольца туннеля показывают, что происходит: спокойно
/// дышат, бегут к центру при проверке, вспыхивают при успехе.
class PromoCodePage extends HookConsumerWidget {
  const PromoCodePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final setup = ref.watch(tunneloSetupProvider);
    final busy = setup is SetupRunning;

    final tunnel = switch (setup) {
      SetupRunning() => TunnelState.working,
      SetupDone() => TunnelState.success,
      SetupFailed() => TunnelState.error,
      _ => TunnelState.idle,
    };

    ref.listen<SetupState>(tunneloSetupProvider, (prev, next) {
      if (next is SetupDone && context.mounted) {
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 800), () {
          if (context.mounted) Navigator.of(context).maybePop();
        });
      } else if (next is SetupFailed && context.mounted) {
        HapticFeedback.heavyImpact();
      }
    });

    return Scaffold(
      backgroundColor: TunneloColors.abyss,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.35),
                  radius: 1.1,
                  colors: [Color(0xFF16224A), TunneloColors.abyss],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded,
                            color: TunneloColors.muted),
                        tooltip: 'Закрыть',
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 4, 28, 32),
                    child: Column(
                      children: [
                        TunnelRings(state: tunnel, size: 204),
                        const SizedBox(height: 36),
                        _Headline(state: setup),
                        const SizedBox(height: 28),
                        _CodeField(
                          controller: controller,
                          enabled: !busy,
                          error: setup is SetupFailed ? setup.message : null,
                          onChanged: (_) =>
                              ref.read(tunneloSetupProvider.notifier).clearError(),
                          onSubmit: busy ? null : () => _submit(ref, controller.text),
                        ),
                        const SizedBox(height: 20),
                        _ActivateButton(
                          busy: busy,
                          done: setup is SetupDone,
                          onPressed: busy ? null : () => _submit(ref, controller.text),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submit(WidgetRef ref, String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    HapticFeedback.selectionClick();
    ref.read(tunneloSetupProvider.notifier).activate(code);
  }
}

/// Заголовок меняется вместе с состоянием — он и есть индикатор прогресса.
class _Headline extends StatelessWidget {
  const _Headline({required this.state});
  final SetupState state;

  @override
  Widget build(BuildContext context) {
    final (String title, String subtitle) = switch (state) {
      SetupRunning(:final message) => (message, 'Секунду'),
      SetupDone(:final daysLeft, :final servers) => (
          'Готово',
          [
            if (daysLeft != null) 'Подписка на $daysLeft дн.',
            if (servers != null) '$servers ${_plural(servers)}',
          ].join(' · '),
        ),
      SetupFailed() => ('Код не подошёл', 'Проверьте его и попробуйте ещё раз'),
      _ => ('Введите код', 'Он откроет доступ на этом устройстве'),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: Column(
        key: ValueKey(title),
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TunneloColors.core,
              fontSize: 27,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TunneloColors.muted,
              fontSize: 14.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'сервер';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'сервера';
    return 'серверов';
  }
}

/// Поле кода набрано широким трекингом — у ключа своя типографика,
/// он не должен выглядеть как обычный текст.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.enabled,
    required this.error,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: TunneloColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasError
                  ? TunneloColors.alert.withValues(alpha: 0.7)
                  : TunneloColors.surfaceHi,
              width: 1.2,
            ),
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: TunneloColors.ringNear,
            inputFormatters: [
              UpperCaseFormatter(),
              LengthLimitingTextInputFormatter(32),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
            ],
            style: const TextStyle(
              color: TunneloColors.core,
              fontSize: 21,
              fontWeight: FontWeight.w600,
              letterSpacing: 5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              hintText: TunneloConfig.defaultPromo,
              hintStyle: TextStyle(
                color: TunneloColors.muted.withValues(alpha: 0.4),
                fontSize: 21,
                letterSpacing: 5,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            ),
            onChanged: onChanged,
            onSubmitted: (_) => onSubmit?.call(),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 10, left: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 15, color: TunneloColors.alert),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: TunneloColors.alert,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ActivateButton extends StatelessWidget {
  const _ActivateButton({
    required this.busy,
    required this.done,
    required this.onPressed,
  });

  final bool busy;
  final bool done;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: done ? const Color(0xFF2E8B57) : TunneloColors.ringNear,
          foregroundColor: TunneloColors.abyss,
          disabledBackgroundColor: TunneloColors.surfaceHi,
          disabledForegroundColor: TunneloColors.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: TunneloColors.muted,
                ),
              )
            : Text(done ? 'Готово' : 'Активировать'),
      ),
    );
  }
}

/// Промокоды всегда в верхнем регистре — приводим на лету,
/// чтобы человек не думал про раскладку.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue now) =>
      TextEditingValue(
        text: now.text.toUpperCase(),
        selection: now.selection,
        composing: TextRange.empty,
      );
}
