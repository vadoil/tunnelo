import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Подписка целиком: срок, устройства и всё, что с ней можно сделать.
///
/// Узел маршрута — отсюда открываются тарифы, устройства и приглашения.
/// Ключ здесь не показываем: он нужен как код переноса и живёт на экране
/// «Устройства», где рядом объяснено, зачем он.
class TunneloSubscriptionPage extends ConsumerWidget {
  const TunneloSubscriptionPage({super.key, this.justPaid = false});

  /// Человек только что вернулся с оплаты.
  final bool justPaid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(tunneloSubscriptionProvider);

    return TunneloScaffold(
      title: 'Подписка',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(tunneloSubscriptionProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (justPaid) ...[const _PaidBanner(), const SizedBox(height: 12)],
            switch (sub) {
              AsyncData(value: final s?) => _Summary(sub: s),
              AsyncLoading() => const _Placeholder('Смотрим состояние подписки…'),
              _ => const _Placeholder(
                'Подписка ещё настраивается.\nЗагляните сюда через минуту.',
              ),
            },
            const SizedBox(height: 16),
            _Action(
              icon: Icons.card_membership_rounded,
              title: 'Продлить',
              subtitle: 'Тарифы и оплата',
              onTap: () => context.pushNamed('plans'),
            ),
            _Action(
              icon: Icons.devices_rounded,
              title: 'Устройства',
              subtitle: 'Подключить второй телефон или планшет',
              onTap: () => context.pushNamed('devices'),
            ),
            _Action(
              icon: Icons.card_giftcard_rounded,
              title: 'Пригласить друга',
              subtitle: 'По 15 дней вам обоим',
              onTap: () => context.pushNamed('friends'),
            ),
            _Action(
              icon: Icons.confirmation_number_outlined,
              title: 'Ввести код',
              subtitle: 'Промокод, код друга или перенос подписки',
              onTap: () => context.pushNamed('promoCode'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Сообщение после возврата с оплаты.
///
/// Подтверждение платежа приходит на сервер отдельным запросом и может
/// отстать на несколько секунд, поэтому не обещаем, что дни уже на месте —
/// говорим, что вот-вот появятся, и даём потянуть экран для обновления.
class _PaidBanner extends StatelessWidget {
  const _PaidBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      color: TunneloColors.sea.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: TunneloColors.sea.withValues(alpha: 0.35)),
    ),
    child: const Row(
      children: [
        Icon(Icons.check_circle_rounded, color: TunneloColors.sea, size: 22),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Оплачено. Дни появятся в течение минуты — '
            'потяните экран вниз, чтобы обновить.',
            style: TextStyle(color: TunneloColors.seaDeep, fontSize: 14, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: TunneloColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: TunneloColors.line),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: TunneloColors.muted, height: 1.4),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.sub});

  final TunneloSubscription sub;

  @override
  Widget build(BuildContext context) {
    final days = sub.daysLeft;
    final warn = sub.expired || sub.endingSoon;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TunneloColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: warn ? TunneloColors.coral : TunneloColors.line,
          width: warn ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sub.expired
                ? 'Подписка кончилась'
                : days == null
                    ? 'Подписка активна'
                    : 'Осталось ${_days(days)}',
            style: TextStyle(
              color: warn ? TunneloColors.coral : TunneloColors.seaDeep,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub.expired
                ? 'Продлите — и подключение снова заработает.'
                : sub.endingSoon
                    ? 'Самое время продлить, чтобы не остаться без связи.'
                    : 'Тариф: ${sub.deviceLimit == 1 ? "одно устройство" : "${sub.deviceLimit} устройства"}',
            style: const TextStyle(
              color: TunneloColors.muted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'Устройства',
                  value: '${sub.devices} из ${sub.deviceLimit}',
                ),
              ),
              Container(width: 1, height: 34, color: TunneloColors.line),
              Expanded(
                child: _Cell(label: 'Приглашено', value: '${sub.invited}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _days(int n) {
    final t = n % 100 >= 11 && n % 100 <= 14
        ? 'дней'
        : switch (n % 10) { 1 => 'день', 2 || 3 || 4 => 'дня', _ => 'дней' };
    return '$n $t';
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: TunneloColors.seaDeep,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: TunneloColors.muted, fontSize: 13)),
    ],
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: TunneloColors.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: TunneloColors.line),
    ),
    child: ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: TunneloColors.mist,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: TunneloColors.sea, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: TunneloColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: TunneloColors.muted, fontSize: 13),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: TunneloColors.muted,
      ),
    ),
  );
}
