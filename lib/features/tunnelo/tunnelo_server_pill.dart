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
class TunneloServerPill extends ConsumerWidget {
  const TunneloServerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(
          connectionNotifierProvider.select((v) => v.valueOrNull),
        ) ==
        const Connected();
    final proxy = ref.watch(activeProxyNotifierProvider.select((v) => v.valueOrNull));

    final country = _country(proxy?.tag);
    final delay = proxy?.urlTestDelay ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Material(
        color: TunneloColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.pushNamed('proxies'),
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
                        country,
                        style: const TextStyle(
                          color: TunneloColors.seaDeep,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(connected, delay),
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

  /// Из тега узла («🇫🇮 Финляндия-2 · HY2-2 § 3») оставляем страну.
  static String _country(String? tag) {
    if (tag == null || tag.trim().isEmpty) return 'Сервер не выбран';
    var name = tag.split('§').first.split('·').first.trim();
    name = name.replaceAll(RegExp(r'[-–]\s*\d+$'), '').trim();
    return name.isEmpty ? 'Сервер не выбран' : name;
  }

  static String _subtitle(bool connected, int delay) {
    if (!connected) return 'Нажмите, чтобы выбрать';
    if (delay > 0 && delay < 65000) return 'Подключено · $delay мс';
    return 'Подключено';
  }
}
