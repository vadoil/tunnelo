import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Состояние подписки, каким его отдаёт сервис активации.
///
/// Ключ здесь есть, но на экраны он выносится только там, где без него
/// нельзя — на «Устройства», как код переноса. На главной его быть не должно:
/// по ключу чужой клиент подключится к нашим узлам.
class TunneloSubscription {
  const TunneloSubscription({
    required this.active,
    required this.devices,
    required this.deviceLimit,
    required this.referralCode,
    required this.invited,
    required this.bonusDays,
    required this.referralUsed,
    this.daysLeft,
    this.key,
  });

  final bool active;
  final int devices;
  final int deviceLimit;
  final String referralCode;

  /// Сколько друзей ввели наш код.
  final int invited;

  /// Сколько дней это принесло.
  final int bonusDays;

  /// Мы сами уже вводили чей-то код. Ввести можно один раз.
  final bool referralUsed;

  final int? daysLeft;
  final String? key;

  /// Подписка заканчивается на днях — пора звать продлить.
  bool get endingSoon => daysLeft != null && daysLeft! <= 3 && daysLeft! > 0;

  /// Подписка кончилась.
  bool get expired => daysLeft != null && daysLeft! <= 0;

  /// Есть ли куда подключить ещё устройство.
  bool get hasFreeDeviceSlot => devices < deviceLimit;

  static int _int(Object? v, [int fallback = 0]) =>
      v is int ? v : (v is num ? v.toInt() : fallback);

  factory TunneloSubscription.fromJson(Map<String, dynamic> j, {String? key}) =>
      TunneloSubscription(
        active: j['active'] == true,
        devices: _int(j['devices'], 1),
        deviceLimit: _int(j['deviceLimit'], 1),
        referralCode: (j['referralCode'] as String?) ?? '',
        invited: _int(j['invited']),
        bonusDays: _int(j['bonusDays']),
        referralUsed: j['referralUsed'] == true,
        daysLeft: j['daysLeft'] is int ? j['daysLeft'] as int : null,
        key: key,
      );
}

/// Подписка целиком: срок, устройства, приглашения.
///
/// Возвращает null, пока ключа нет или сервис недоступен, — экраны в этом
/// случае показывают заглушку, а не ноль дней и не ошибку.
final tunneloSubscriptionProvider =
    FutureProvider<TunneloSubscription?>((ref) async {
  final api = ref.read(tunneloActivationProvider);
  final json = await api.status();
  if (json == null) return null;
  return TunneloSubscription.fromJson(json, key: await api.savedKey());
});
