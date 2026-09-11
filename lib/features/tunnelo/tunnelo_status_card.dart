import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_account_row.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Состояние подписки на главном экране.
///
/// Намеренно НЕ показывает ни ключ, ни ссылку подписки, ни меню профиля:
/// это данные, по которым чужой клиент может подключиться к нашим узлам.
/// Человеку нужны три вещи — сколько трафика, сколько дней и сколько
/// устройств занято.
class TunneloStatusCard extends ConsumerWidget {
  const TunneloStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final info = profile is RemoteProfileEntity ? profile.subInfo : null;
    // Пока подписки нет, человеку нужны ровно две вещи: оплатить
    // или ввести промокод. Прятать их в настройки нельзя.
    if (info == null) return const _NotActivatedCard();

    final devices = ref.watch(tunneloDevicesProvider).valueOrNull;

    // Карточка целиком ведёт на экран подписки: это то, за что платят,
    // и добираться до него через настройки человек не должен.
    return GestureDetector(
      onTap: () => context.pushNamed('subscription'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: TunneloColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TunneloColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Label('Трафик'),
                Text(
                  _traffic(info),
                  style: const TextStyle(
                    color: TunneloColors.seaDeep,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: info.total > 0 ? info.ratio : 0,
                minHeight: 6,
                backgroundColor: TunneloColors.line,
                valueColor: const AlwaysStoppedAnimation(TunneloColors.sea),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Label('Осталось'),
                Text(
                  _daysLeft(info),
                  style: const TextStyle(
                    color: TunneloColors.seaDeep,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (devices != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _Label('Устройства'),
                  Text(
                    '${devices.used} из ${devices.limit}',
                    style: const TextStyle(
                      color: TunneloColors.core,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const _Actions(),
            const Divider(height: 22, color: TunneloColors.line),
            const _AccountRow(),
          ],
        ),
      ),
    );
  }

  static String _traffic(SubscriptionInfo info) {
    if (info.total <= 0) return 'Безлимит';
    return '${_gb(info.consumption)} из ${_gb(info.total)}';
  }

  static String _gb(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 100) return '${gb.round()} ГБ';
    if (gb >= 10) return '${gb.toStringAsFixed(1)} ГБ';
    return '${gb.toStringAsFixed(2)} ГБ';
  }

  static String _daysLeft(SubscriptionInfo info) {
    if (info.isExpired) return 'Подписка истекла';
    final days = info.remaining.inDays;
    if (days < 1) return 'Меньше суток';
    return '$days ${_pluralDays(days)}';
  }

  static String _pluralDays(int n) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: TunneloColors.muted, fontSize: 14));
}

/// Вход и выход из аккаунта прямо на главной — иначе человек ищет
/// «где войти» по настройкам. Отдельной регистрации нет: аккаунт появляется
/// при первом входе по коду из письма.
class _AccountRow extends ConsumerWidget {
  const _AccountRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(tunneloAccountProvider).valueOrNull;
    return TunneloAccountRow(
      email: email,
      onLogin: () => context.pushNamed(
        'login',
        extra: 'Введите почту — пришлём код. Пароль придумывать не нужно.',
      ),
      onLogout: () async {
        await ref.read(tunneloActivationProvider).signOut();
        ref
          ..invalidate(tunneloAccountProvider)
          ..invalidate(tunneloSubscriptionProvider);
      },
    );
  }
}

/// Действия подписки: продлить и ввести ключ.
class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FilledButton(
          onPressed: () => context.pushNamed('plans'),
          style: FilledButton.styleFrom(
            backgroundColor: TunneloColors.coral,
            foregroundColor: TunneloColors.mistDeep,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          child: const Text('Продлить'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton(
          onPressed: () => context.pushNamed('promoCode'),
          style: OutlinedButton.styleFrom(
            foregroundColor: TunneloColors.sea,
            side: const BorderSide(color: TunneloColors.line, width: 1.4),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          child: const Text('Промокод'),
        ),
      ),
    ],
  );
}

/// Экран до активации: подписки ещё нет.
class _NotActivatedCard extends StatelessWidget {
  const _NotActivatedCard();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
    decoration: BoxDecoration(
      color: TunneloColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: TunneloColors.line),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Подписка не активна',
          style: TextStyle(color: TunneloColors.seaDeep, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 6),
        Text(
          'Оплатите доступ или введите промокод, если он у вас есть.',
          style: TextStyle(color: TunneloColors.muted, fontSize: 14, height: 1.35),
        ),
        SizedBox(height: 16),
        _Actions(),
        Divider(height: 22, color: TunneloColors.line),
        _AccountRow(),
      ],
    ),
  );
}
