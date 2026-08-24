import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Ввод промокода. При первом запуске код применяется сам —
/// сюда заходят те, у кого платный ключ.
class PromoCodePage extends HookConsumerWidget {
  const PromoCodePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final setup = ref.watch(tunneloSetupProvider);
    final theme = Theme.of(context);
    final busy = setup is SetupRunning;

    ref.listen<SetupState>(tunneloSetupProvider, (prev, next) {
      if (next is SetupDone && context.mounted) {
        final d = next.daysLeft;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(d != null ? 'Подписка активна: $d дн.' : 'Подписка активна'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).maybePop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Промокод')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Введите промокод',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Код активирует подписку на этом устройстве.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                enabled: !busy,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: TunneloConfig.defaultPromo,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  errorText: setup is SetupFailed ? setup.message : null,
                ),
                onChanged: (_) => ref.read(tunneloSetupProvider.notifier).clearError(),
                onSubmitted: busy ? null : (v) => _submit(ref, v),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : () => _submit(ref, controller.text),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: busy
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Активировать'),
              ),
              if (busy) ...[
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    setup.message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _submit(WidgetRef ref, String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    ref.read(tunneloSetupProvider.notifier).activate(code);
  }
}
