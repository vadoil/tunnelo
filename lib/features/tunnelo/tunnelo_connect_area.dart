import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/tunnelo/tunnelo_fox_button.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Высота нижней панели с вкладками. Material 3 рисует её ровно такой.
const _navBarHeight = 80.0;

/// Сколько по вертикали занимает всё остальное на главной: шапка, карточка
/// подписки, карточка про российские сайты, подпись под лисом, индикатор
/// задержки и карточка сервера.
const _restOfScreen = 610.0;

/// Размер лиса под высоту окна. На телефоне — полные 260, в низком окне
/// меньше, чтобы карточка выбора сервера не уезжала под нижнюю панель.
///
/// Считаем от MediaQuery, а не LayoutBuilder: главная лежит в
/// SliverFillRemaining, которому нужна intrinsic-высота, а LayoutBuilder её
/// не даёт. Вычитаем и системные отступы с панелью вкладок — без них лис
/// получался максимальным, и карточка «Быстрейший сервер» срезалась пополам.
/// Ниже 160 лис уже не читается.
double foxSizeFor(double freeHeight) => (freeHeight - _restOfScreen).clamp(150.0, 260.0);

/// Та же высота, но посчитанная от окна: из него вычитаются системные
/// отступы и панель вкладок — без них лис выходил максимальным, и карточка
/// «Быстрейший сервер» срезалась пополам.
double foxSizeForWindow(BuildContext context) {
  final media = MediaQuery.of(context);
  return foxSizeFor(media.size.height - media.padding.top - media.padding.bottom - _navBarHeight);
}

/// Середина главного экрана: кнопка подключения — или причина, почему её нет.
///
/// Когда подписка кончилась, звать нажимать кнопку жестоко: она не сработает,
/// человек решит, что сломалось приложение. Показываем вместо неё то
/// единственное, что сейчас имеет смысл, — продление.
class TunneloConnectArea extends ConsumerWidget {
  const TunneloConnectArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(tunneloSubscriptionProvider).valueOrNull;

    if (sub != null && sub.expired) {
      return const _Expired();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TunneloFoxButton(size: foxSizeForWindow(context)),
        const ActiveProxyDelayIndicator(),
      ],
    );
  }
}

class _Expired extends StatelessWidget {
  const _Expired();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset('assets/images/fox/puzzled.png', height: 150),
        const SizedBox(height: 24),
        const Text(
          'Подписка кончилась',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TunneloColors.text,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Продлите — и подключение снова заработает. '
          'Ключ и настройки останутся прежними.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: TunneloColors.muted,
            fontSize: 15,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.pushNamed('plans'),
            style: FilledButton.styleFrom(
              backgroundColor: TunneloColors.coral,
              foregroundColor: TunneloColors.mistDeep,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Продлить'),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => context.pushNamed('promoCode'),
          style: TextButton.styleFrom(foregroundColor: TunneloColors.sea),
          child: const Text('У меня есть код'),
        ),
      ],
    ),
  );
}
