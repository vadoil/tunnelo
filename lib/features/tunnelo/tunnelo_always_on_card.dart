import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// «Соединение без обрывов»: две системные настройки, которые приложение
/// не может включить за человека.
///
/// Приложение поднимает туннель после любого обрыва само, но у Android есть
/// две двери, ключи от которых только у хозяина телефона:
///
/// 1. «Постоянный VPN» — система сама держит туннель и поднимает его после
///    перезагрузки, даже если приложение убили. Узнать программно, включён
///    ли он, нельзя: публичного API нет. Поэтому просто показываем кнопку.
/// 2. Экономия батареи — пока приложение под ней, фоновые попытки
///    подключиться система режет. Это состояние прочитать можно.
///
/// Карточка прячется, когда человек нажал «Уже настроил»: навязываться
/// каждый запуск нельзя, а проверить первый пункт мы не умеем.
class TunneloAlwaysOnCard extends ConsumerWidget {
  const TunneloAlwaysOnCard({super.key});

  /// Человек сказал, что настроил. Больше не спрашиваем.
  static final dismissed = PreferencesNotifier.create<bool, bool>(
    'always_on_hint_dismissed',
    false,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    if (ref.watch(dismissed)) return const SizedBox.shrink();

    final batteryFree = ref.watch(batteryOptimizationNotifierProvider).valueOrNull ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: TunneloColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: TunneloColors.sea.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_moon_rounded, color: TunneloColors.sea, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Соединение без обрывов',
                  style: TextStyle(color: TunneloColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => ref.read(dismissed.notifier).update(true),
                icon: const Icon(Icons.close_rounded, size: 20, color: TunneloColors.muted),
                tooltip: 'Уже настроил',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Две настройки Android, которые приложение не может включить само. '
            'С ними туннель поднимается после перезагрузки телефона и не гаснет, '
            'когда система экономит батарею.',
            style: TextStyle(color: TunneloColors.muted, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 8),
          const _Step(
            text: 'Постоянный VPN: в открывшемся окне нажмите шестерёнку рядом с Tunnelo '
                'и включите «Постоянный VPN».',
            action: 'Открыть настройки VPN',
            onTap: openVpnSettings,
          ),
          if (!batteryFree)
            _Step(
              text: 'Работа в фоне: разрешите не экономить батарею, иначе система '
                  'обрывает попытки подключиться.',
              action: 'Разрешить',
              onTap: () => ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore(),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Работа в фоне уже разрешена.',
                style: TextStyle(color: TunneloColors.sea, fontSize: 13.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.text, required this.action, required this.onTap});

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(color: TunneloColors.muted, fontSize: 13.5, height: 1.35)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: TunneloColors.sea,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(action),
          ),
        ),
      ],
    ),
  );
}

/// Системный экран VPN: там за шестерёнкой живёт «Постоянный VPN».
Future<void> openVpnSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('com.hiddify.app/platform').invokeMethod<bool>('open_vpn_settings');
  } catch (_) {
    // Экран не открылся — на карточке написано, куда идти руками.
  }
}
