import 'package:flutter/material.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
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
    final profile = ref.watch(activeProfileProvider).value;
    final info = profile is RemoteProfileEntity ? profile.subInfo : null;
    if (info == null) return const SizedBox.shrink();

    final devices = ref.watch(tunneloDevicesProvider).value;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: TunneloColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TunneloColors.surfaceHi),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Label('Трафик'),
              Text(
                _traffic(info),
                style: const TextStyle(
                  color: TunneloColors.core,
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
              backgroundColor: TunneloColors.surfaceHi,
              valueColor: const AlwaysStoppedAnimation(TunneloColors.ringNear),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Label('Осталось'),
              Text(
                _daysLeft(info),
                style: const TextStyle(
                  color: TunneloColors.core,
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
                _Label('Устройства'),
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
        ],
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
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: TunneloColors.muted, fontSize: 14),
  );
}
