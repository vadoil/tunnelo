import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Устройства на подписке и код переноса.
///
/// Регистрации у нас нет, поэтому код переноса — единственный способ
/// подключить второй телефон и единственная страховка при смене устройства.
/// Прятать его нельзя.
class TunneloDevicesPage extends ConsumerWidget {
  const TunneloDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(tunneloSubscriptionProvider);

    return TunneloScaffold(
      title: 'Устройства',
      body: switch (sub) {
        AsyncData(value: final s?) => _Body(sub: s),
        AsyncError() => const _Unavailable(),
        AsyncData() => const _Unavailable(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(
      child: Text(
        'Подписка ещё настраивается.\nЗагляните сюда через минуту.',
        textAlign: TextAlign.center,
        style: TextStyle(color: TunneloColors.muted, height: 1.4),
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.sub});

  final TunneloSubscription sub;

  @override
  Widget build(BuildContext context) {
    final key = sub.key ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Card(
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Подключено устройств',
                  style: TextStyle(color: TunneloColors.text, fontSize: 15),
                ),
              ),
              Text(
                '${sub.devices} из ${sub.deviceLimit}',
                style: const TextStyle(
                  color: TunneloColors.seaDeep,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (sub.hasFreeDeviceSlot && key.isNotEmpty)
          _TransferCode(code: key)
        else if (key.isNotEmpty)
          _NoSlots(limit: sub.deviceLimit),
      ],
    );
  }
}

class _TransferCode extends StatelessWidget {
  const _TransferCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Подключить ещё одно устройство',
          style: TextStyle(
            color: TunneloColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'На втором устройстве откройте Tunnelo, нажмите «Промокод» '
          'и введите этот код.',
          style: TextStyle(color: TunneloColors.muted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TunneloColors.line),
            ),
            child: QrImageView(
              data: code,
              size: 168,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: TunneloColors.seaDeep,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: TunneloColors.seaDeep,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          code,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: TunneloColors.seaDeep,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Код скопирован')),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: TunneloColors.seaDeep,
            side: const BorderSide(color: TunneloColors.line),
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          label: const Text('Скопировать код'),
        ),
      ],
    ),
  );
}

class _NoSlots extends StatelessWidget {
  const _NoSlots({required this.limit});

  final int limit;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          limit == 1
              ? 'В вашем тарифе одно устройство'
              : 'Все устройства тарифа заняты',
          style: const TextStyle(
            color: TunneloColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          limit == 1
              ? 'Чтобы подключить второе, перейдите на тариф с двумя устройствами.'
              : 'Больше устройств на один ключ подключить нельзя.',
          style: const TextStyle(
            color: TunneloColors.muted,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        if (limit == 1) ...[
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => context.pushNamed('plans'),
            style: FilledButton.styleFrom(
              backgroundColor: TunneloColors.sea,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Смотреть тарифы'),
          ),
        ],
      ],
    ),
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
