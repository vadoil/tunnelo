import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Приглашение друзей.
///
/// Код вводится руками, а не подхватывается из ссылки: приложение мы раздаём
/// мимо Google Play, а без него Android не передаёт источник установки.
/// Зато ручной ввод работает всегда и одинаково на всех платформах.
class TunneloFriendsPage extends ConsumerWidget {
  const TunneloFriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(tunneloSubscriptionProvider);

    return Scaffold(
      backgroundColor: TunneloColors.mist,
      appBar: AppBar(
        title: const Text('Друзья'),
        backgroundColor: TunneloColors.mist,
        surfaceTintColor: Colors.transparent,
      ),
      body: switch (sub) {
        AsyncData(value: final s?) when s.referralCode.isNotEmpty => _Body(sub: s),
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        _ => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Подписка ещё настраивается.\nЗагляните сюда через минуту.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TunneloColors.muted, height: 1.4),
            ),
          ),
        ),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.sub});

  final TunneloSubscription sub;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
    children: [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ваш код',
              style: TextStyle(color: TunneloColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SelectableText(
              sub.referralCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TunneloColors.seaDeep,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Друг вводит его в «Промокод» — и вам обоим прибавляется по 15 дней.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TunneloColors.muted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _share(sub.referralCode),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              style: FilledButton.styleFrom(
                backgroundColor: TunneloColors.sea,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              label: const Text('Поделиться'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: sub.referralCode));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Код скопирован')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              style: TextButton.styleFrom(foregroundColor: TunneloColors.seaDeep),
              label: const Text('Скопировать'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _Card(
        child: Row(
          children: [
            Expanded(
              child: _Stat(label: 'Пригласили', value: '${sub.invited}'),
            ),
            Container(width: 1, height: 38, color: TunneloColors.line),
            Expanded(
              child: _Stat(label: 'Начислено дней', value: '${sub.bonusDays}'),
            ),
          ],
        ),
      ),
      if (!sub.referralUsed) ...[
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Вам дали код?',
                style: TextStyle(
                  color: TunneloColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Введите код друга — по 15 дней получите оба. Сделать это '
                'можно один раз.',
                style: TextStyle(color: TunneloColors.muted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => context.pushNamed('promoCode'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TunneloColors.seaDeep,
                  side: const BorderSide(color: TunneloColors.line),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Ввести код друга'),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  void _share(String code) {
    Share.share(
      'Пользуюсь Tunnelo — VPN, который работает без настроек.\n'
      'Скачай ${TunneloConfig.siteUrl} и введи мой код $code — '
      'нам обоим дадут по 15 дней.',
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          color: TunneloColors.seaDeep,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(color: TunneloColors.muted, fontSize: 13),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: BoxDecoration(
      color: TunneloColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: TunneloColors.line),
    ),
    child: child,
  );
}
