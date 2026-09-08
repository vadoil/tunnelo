import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Тариф. Идентификаторы совпадают с теми, что понимает сайт.
class TunneloPlan {
  const TunneloPlan({
    required this.id,
    required this.devices,
    required this.months,
    required this.price,
  });

  final String id;
  final int devices;
  final int months;
  final int price;

  int get perMonth => (price / months).round();
}

const _monthly = [
  TunneloPlan(id: '1d-1m', devices: 1, months: 1, price: 299),
  TunneloPlan(id: '2d-1m', devices: 2, months: 1, price: 499),
];

const _yearly = [
  TunneloPlan(id: '1d-12m', devices: 1, months: 12, price: 1794),
  TunneloPlan(id: '2d-12m', devices: 2, months: 12, price: 2994),
];

/// Выбор тарифа.
///
/// Сама оплата идёт на сайте, во внешнем браузере: банковское подтверждение
/// внутри приложения часто ломается, и магазины к такому относятся плохо.
/// После оплаты сайт возвращает человека сюда по ссылке tunnelo://paid.
class TunneloPlansPage extends HookConsumerWidget {
  const TunneloPlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Год выбран по умолчанию: он вдвое выгоднее, и это стоит показать сразу.
    final yearly = useState(true);
    final sub = ref.watch(tunneloSubscriptionProvider).valueOrNull;

    return TunneloScaffold(
      title: 'Тарифы',
      body: Builder(
        builder: (context) {
          final plans = yearly.value ? _yearly : _monthly;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: Image.asset('assets/images/fox/coins.png', height: 140),
              ),
              const SizedBox(height: 8),
              _TermSwitch(
                yearly: yearly.value,
                onChanged: (v) => yearly.value = v,
              ),
              const SizedBox(height: 16),
              for (final p in plans) ...[
                _PlanCard(
                  plan: p,
                  current: sub?.deviceLimit == p.devices,
                  onTap: () => _pay(context, ref, p, sub?.key),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              const Text(
                'Оплата проходит на сайте tunello.online. После оплаты вы '
                'вернётесь сюда, а подписка продлится сама.',
                style: TextStyle(color: TunneloColors.muted, fontSize: 13, height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Перед оплатой заводим аккаунт.
  ///
  /// Без него подписка остаётся привязанной к одному телефону: потерял его —
  /// потерял оплаченное, и на второе устройство не войти. Спрашиваем почту
  /// именно здесь, а не на первом запуске: до оплаты человеку незачем её
  /// давать, он ещё ничего не купил.
  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    TunneloPlan plan,
    String? key,
  ) async {
    final api = ref.read(tunneloActivationProvider);
    if (await api.savedToken() == null) {
      if (!context.mounted) return;
      final ok = await context.pushNamed<bool>(
        'login',
        extra: 'Перед оплатой заведём аккаунт на вашу почту. '
            'Тогда подписка не пропадёт вместе с телефоном, и её можно '
            'будет включить на втором устройстве.',
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    _openPayment(context, plan, key ?? await api.savedKey());
  }

  void _openPayment(BuildContext context, TunneloPlan plan, String? key) {
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подписка ещё настраивается. Попробуйте через минуту.'),
        ),
      );
      return;
    }
    UriUtils.tryLaunch(
      Uri.parse('${TunneloConfig.siteUrl}/pay?plan=${plan.id}&key=$key&app=1'),
    );
  }
}

class _TermSwitch extends StatelessWidget {
  const _TermSwitch({required this.yearly, required this.onChanged});

  final bool yearly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: TunneloColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: TunneloColors.line),
    ),
    child: Row(
      children: [
        _seg('На месяц', !yearly, () => onChanged(false)),
        _seg('На год · −50%', yearly, () => onChanged(true)),
      ],
    ),
  );

  Widget _seg(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? TunneloColors.sea : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : TunneloColors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.current, required this.onTap});

  final TunneloPlan plan;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final devices = plan.devices == 1 ? 'Одно устройство' : 'Два устройства';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: TunneloColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: current ? TunneloColors.sea : TunneloColors.line,
          width: current ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  devices,
                  style: const TextStyle(
                    color: TunneloColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (current)
                const Text(
                  'ваш тариф',
                  style: TextStyle(color: TunneloColors.sea, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.months == 1
                ? '${plan.price} ₽ в месяц'
                : '${plan.price} ₽ за год · ${plan.perMonth} ₽ в месяц',
            style: const TextStyle(
              color: TunneloColors.seaDeep,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: TunneloColors.sea,
              foregroundColor: TunneloColors.mistDeep,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Оплатить'),
          ),
        ],
      ),
    );
  }
}
