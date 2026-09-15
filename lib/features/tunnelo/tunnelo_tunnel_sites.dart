import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сайты, которые человек сам отправил в туннель.
///
/// По умолчанию всё российское идёт мимо VPN — так банк не просит
/// подтверждений, а маркетплейс показывает свои цены. Но часть российских
/// сервисов заблокирована, и им туннель как раз нужен. Угадать такие сайты
/// списком нельзя: у каждого он свой. Поэтому на главной есть «плюс» —
/// человек вписывает адрес, и этот адрес уходит через туннель.
///
/// Правило кладётся ВЫШЕ правила «Россия»: иначе домен .ru поймает
/// direct-правило первым, и кнопка ничего бы не меняла.
class TunneloTunnelSites extends StateNotifier<List<String>> {
  TunneloTunnelSites(this._ref) : super(const []) {
    _load();
  }

  final Ref _ref;

  static const _key = 'tunnelo_tunnel_sites';

  /// Имя правила. По нему же оно находится при обновлении — правило одно,
  /// а доменов в нём сколько угодно.
  static const ruleName = 'Через туннель';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_key) ?? const [];
  }

  /// Привести введённое к домену: «https://Example.RU/path?x=1» → «example.ru».
  /// Пустая строка означает, что вводу верить нельзя.
  static String normalize(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return '';
    s = s.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');
    s = s.split('/').first.split('?').first.split('#').first;
    s = s.split('@').last.split(':').first;
    if (s.startsWith('www.')) s = s.substring(4);
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    if (s.isEmpty || s.length > 253) return '';
    // Домен: метки из букв, цифр и дефисов, минимум одна точка.
    final ok = RegExp(r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?'
            r'(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$')
        .hasMatch(s);
    return ok ? s : '';
  }

  /// Добавить сайт. -> что пошло не так, или null, если всё хорошо.
  Future<String?> add(String input) async {
    final domain = normalize(input);
    if (domain.isEmpty) {
      return 'Похоже, это не адрес сайта. Пример: youtube.com';
    }
    if (state.contains(domain)) return 'Этот сайт уже идёт через туннель.';
    state = [...state, domain];
    await _save();
    return null;
  }

  Future<void> remove(String domain) async {
    if (!state.contains(domain)) return;
    state = state.where((d) => d != domain).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state);
    await _applyRule();
  }

  /// Переписать правило под текущий список и поднять его выше «России».
  Future<void> _applyRule() async {
    final rules = _ref.read(rulesNotifierProvider.notifier);
    final current = _ref.read(rulesNotifierProvider);
    final existing = current.where((r) => r.name == ruleName).firstOrNull;

    if (state.isEmpty) {
      if (existing != null) await rules.deleteRule(existing.listOrder);
      return;
    }

    if (existing == null) {
      await rules.addRule(
        Rule(name: ruleName, outbound: Outbound.proxy, domains: state),
      );
    } else {
      final updated = existing.deepCopy()
        ..domains.clear()
        ..domains.addAll(state);
      await rules.updateRule(updated);
    }
    await _liftAboveDirect();
  }

  /// Правило обязано стоять выше «России»: правила проверяются по порядку,
  /// и direct-правило по .ru перехватило бы адрес раньше.
  Future<void> _liftAboveDirect() async {
    final rules = _ref.read(rulesNotifierProvider.notifier);
    final list = _ref.read(rulesNotifierProvider);
    final mine = list.indexWhere((r) => r.name == ruleName);
    final direct = list.indexWhere(
      (r) => r.outbound == Outbound.direct && r.name != ruleName,
    );
    if (mine == -1 || direct == -1 || mine < direct) return;
    await rules.reorder(mine, direct);
  }
}

final tunneloTunnelSitesProvider =
    StateNotifierProvider<TunneloTunnelSites, List<String>>(
  TunneloTunnelSites.new,
);

/// Карточка на главной: «плюс» и список добавленных сайтов.
class TunneloTunnelSitesCard extends ConsumerWidget {
  const TunneloTunnelSitesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.watch(tunneloTunnelSitesProvider);

    return TunneloGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Сайт не открывается?',
                  style: TextStyle(
                    color: TunneloColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Добавить сайт в туннель',
                onPressed: () => _ask(context, ref),
                icon: const Icon(Icons.add_circle_outline,
                    color: TunneloColors.sea),
              ),
            ],
          ),
          const Text(
            'Российские сайты идут мимо VPN. Если какой-то из них заблокирован, '
            'добавьте его — он пойдёт через туннель.',
            style: TextStyle(color: TunneloColors.muted, fontSize: 13, height: 1.35),
          ),
          if (sites.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final site in sites)
                  Chip(
                    label: Text(site,
                        style: const TextStyle(color: TunneloColors.text)),
                    backgroundColor: TunneloColors.card,
                    side: const BorderSide(color: TunneloColors.line),
                    deleteIconColor: TunneloColors.muted,
                    onDeleted: () => ref
                        .read(tunneloTunnelSitesProvider.notifier)
                        .remove(site),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Изменения применятся при следующем подключении.',
              style: TextStyle(color: TunneloColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final error = ValueNotifier<String?>(null);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TunneloColors.cardSolid,
        title: const Text('Добавить сайт в туннель',
            style: TextStyle(color: TunneloColors.text)),
        content: ValueListenableBuilder<String?>(
          valueListenable: error,
          builder: (context, err, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                style: const TextStyle(color: TunneloColors.text),
                decoration: const InputDecoration(
                  hintText: 'например, rutracker.org',
                  hintStyle: TextStyle(color: TunneloColors.muted),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err, style: const TextStyle(color: TunneloColors.alert)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена',
                style: TextStyle(color: TunneloColors.muted)),
          ),
          FilledButton(
            onPressed: () async {
              final problem = await ref
                  .read(tunneloTunnelSitesProvider.notifier)
                  .add(controller.text);
              if (problem != null) {
                error.value = problem;
                return;
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}
