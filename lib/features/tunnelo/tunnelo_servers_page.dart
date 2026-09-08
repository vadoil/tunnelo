import 'package:flutter/material.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Выбор сервера по-человечески.
///
/// Список Hiddify показывает теги вида «🇫🇮 Финляндия-2 · HY2-2 § 3» — это
/// внутреннее имя узла, человеку оно ничего не говорит. Здесь оставляем
/// страну и задержку: по ним и выбирают.
class TunneloServersPage extends ConsumerWidget {
  const TunneloServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(proxiesOverviewNotifierProvider).valueOrNull;

    return TunneloScaffold(
      title: 'Серверы',
      body: group == null
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final item in group.items)
                  _ServerTile(
                    name: _pretty(item.tag),
                    delay: item.urlTestDelay,
                    selected: item.tag == group.selected,
                    onTap: () => ref
                        .read(proxiesOverviewNotifierProvider.notifier)
                        .changeProxy(group.tag, item.tag),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(proxiesOverviewNotifierProvider.notifier)
                      .urlTest(group.tag),
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TunneloColors.sea,
                    side: const BorderSide(color: TunneloColors.line),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  label: const Text('Проверить скорость'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Быстрейший сервер выбирается сам. Менять вручную нужно '
                  'редко — например, если у провайдера проблемы с одной страной.',
                  style: TextStyle(
                    color: TunneloColors.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }

  /// Из тега узла оставляем то, что человеку понятно.
  ///
  /// «🇫🇮 Финляндия-2 · HY2-2 § 3» → «🇫🇮 Финляндия-2». Служебные хвосты
  /// после «·» и «§» — это имя инбаунда и его номер в панели.
  static String _pretty(String tag) {
    if (tag == 'lowest') return 'Быстрейший — выбрать самому';
    if (tag == 'balance') return 'По очереди между серверами';
    final name = tag.split('§').first.split('·').first.trim();
    return name.isEmpty ? tag : name;
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/fox/puzzled.png', height: 150),
        const SizedBox(height: 20),
        const Text(
          'Серверы появятся, когда подключение будет запущено.',
          textAlign: TextAlign.center,
          style: TextStyle(color: TunneloColors.muted, height: 1.4, fontSize: 15),
        ),
      ],
    ),
  );
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.name,
    required this.delay,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int delay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: TunneloGlass(
          highlight: selected,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          radius: 18,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: selected ? TunneloColors.seaDeep : TunneloColors.text,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              _Delay(delay),
              if (selected) ...[
                const SizedBox(width: 10),
                const Icon(
                  Icons.check_circle_rounded,
                  color: TunneloColors.sea,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Задержка. Цвет говорит больше числа, поэтому число сопровождаем цветом.
class _Delay extends StatelessWidget {
  const _Delay(this.ms);

  final int ms;

  @override
  Widget build(BuildContext context) {
    if (ms <= 0 || ms >= 65000) {
      return const Text(
        'нет ответа',
        style: TextStyle(color: TunneloColors.alert, fontSize: 13),
      );
    }
    final color = ms < 150
        ? TunneloColors.sea
        : ms < 400
            ? TunneloColors.seaDeep
            : TunneloColors.coral;
    return Text(
      '$ms мс',
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
