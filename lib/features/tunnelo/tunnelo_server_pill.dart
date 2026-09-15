import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Текущий сервер внизу главного экрана.
///
/// Показывает страну и задержку — то, что человеку понятно. Технические
/// подробности вроде имени балансировщика и тега узла остаются в логах.
/// Нажатие открывает выбор сервера.
///
/// До подключения здесь было «Сервер не выбран · Нажмите, чтобы выбрать».
/// Человек читал это как поломку и шёл искать, что выбрать, хотя сервер
/// подбирается сам. Теперь до подключения пилюля так и говорит, а после
/// показывает конкретный узел и задержку — «Финляндия-2 · 24 мс».
class TunneloServerPill extends ConsumerWidget {
  const TunneloServerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(
          connectionNotifierProvider.select((v) => v.valueOrNull),
        ) ==
        const Connected();
    final proxy = ref.watch(activeProxyNotifierProvider.select((v) => v.valueOrNull));

    final tag = proxy?.tag;
    final delay = proxy?.urlTestDelay ?? 0;
    final title = connected ? nodeFor(tag) : idleTitleFor(tag);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Material(
        color: TunneloColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.pushNamed('servers'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (connected ? TunneloColors.sea : TunneloColors.muted).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    connected ? Icons.public_rounded : Icons.public_off_rounded,
                    size: 20,
                    color: connected ? TunneloColors.sea : TunneloColors.muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: TunneloColors.seaDeep,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleFor(connected, tag, delay),
                        style: const TextStyle(color: TunneloColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: TunneloColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Автоподбор: никакого конкретного узла ещё нет.
  static bool auto(String? tag) =>
      tag == null ||
      tag.trim().isEmpty ||
      tag == 'lowest' ||
      tag == 'balance' ||
      tag == 'select';

  /// Что показать до подключения. Сервера ещё нет — и это нормально.
  static String idleTitleFor(String? tag) =>
      auto(tag) ? 'Сервер подберётся сам' : nodeFor(tag);

  /// Из тега узла («🇫🇮 Финляндия-2 · HY2-2 § 3») оставляем имя узла с
  /// номером: после подключения человеку полезно видеть, куда он попал.
  static String nodeFor(String? tag) {
    if (auto(tag)) return 'Быстрейший сервер';
    final name = tag!.split('§').first.split('·').first.trim();
    return name.isEmpty ? 'Быстрейший сервер' : name;
  }

  static String subtitleFor(bool connected, String? tag, int delay) {
    if (!connected) {
      return auto(tag)
          ? 'Выберем быстрейший при подключении'
          : 'Выбран вручную · нажмите, чтобы изменить';
    }
    if (delay > 0 && delay < 65000) return 'Подключено · $delay мс';
    return 'Подключено';
  }
}
