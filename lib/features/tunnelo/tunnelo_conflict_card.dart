import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hiddify/features/tunnelo/vpn_conflicts.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Карточка на главной: найден чужой VPN — просим выключить или удалить.
///
/// Показывается, пока конфликт есть, и без кнопки «скрыть»: два VPN на одном
/// устройстве ломают друг друга, и человеку лучше это знать каждый раз, чем
/// гадать, почему не открывается сайт. После возвращения в приложение список
/// перечитывается: удалили — карточка исчезла.
class TunneloConflictCard extends ConsumerStatefulWidget {
  const TunneloConflictCard({super.key});

  @override
  ConsumerState<TunneloConflictCard> createState() => _TunneloConflictCardState();
}

class _TunneloConflictCardState extends ConsumerState<TunneloConflictCard> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(vpnConflictsProvider);
      ref.invalidate(foreignVpnActiveProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = ref.watch(vpnConflictsProvider).valueOrNull ?? const <VpnConflict>[];
    final foreignActive = ref.watch(foreignVpnActiveProvider).valueOrNull ?? false;
    if (conflicts.isEmpty && !foreignActive) return const SizedBox.shrink();

    final names = conflicts.map((c) => c.name).join(', ');
    final title = conflicts.isEmpty ? 'Сейчас включён другой VPN' : 'Удалите другой VPN';
    final body = conflicts.isEmpty
        ? 'Выключите его, иначе Tunnelo не сможет подключиться.'
        : 'Найдено: $names. Два VPN спорят за трафик: соединение рвётся или не '
              'поднимается вовсе. Для надёжной работы удалите их — Tunnelo '
              'заменяет их полностью и настраивается сам.';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: TunneloColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: TunneloColors.alert.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: TunneloColors.alert, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: TunneloColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: TunneloColors.muted, fontSize: 14, height: 1.35)),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (Platform.isAndroid)
              // Кнопка на каждый найденный VPN: открывает его страницу в
              // настройках, где есть «Удалить». Искать приложение в общем
              // списке человеку незачем.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final conflict in conflicts)
                    TextButton(
                      onPressed: () => openAppSettings(conflict.id),
                      style: TextButton.styleFrom(
                        foregroundColor: TunneloColors.sea,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: Text('Удалить ${conflict.name}'),
                    ),
                ],
              )
            else if (Platform.isWindows || Platform.isMacOS)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => UriUtils.tryLaunch(
                    Platform.isWindows ? Uri.parse('ms-settings:appsfeatures') : Uri.file('/Applications'),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: TunneloColors.sea,
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Открыть список программ'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
