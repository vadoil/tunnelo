import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_subscription.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Вход по почте.
///
/// Пароля нет намеренно: его забывают и крадут, а восстанавливать всё равно
/// пришлось бы через ту же почту. Код из письма делает ту же работу одним
/// полем.
///
/// Спрашиваем почту не на первом запуске, а перед оплатой: до этого момента
/// человеку незачем её давать — он ещё ничего не купил. Зато после оплаты
/// подписка перестаёт быть привязанной к одному телефону.
class TunneloLoginPage extends HookConsumerWidget {
  const TunneloLoginPage({super.key, this.reason});

  /// Зачем мы спрашиваем почту именно сейчас. Показывается над полем.
  final String? reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(tunneloActivationProvider);
    final email = useTextEditingController();
    final code = useTextEditingController();
    final sent = useState(false);
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> run(Future<void> Function() action) async {
      busy.value = true;
      error.value = null;
      try {
        await action();
      } on ActivationException catch (e) {
        error.value = e.message;
      } catch (_) {
        error.value = 'Что-то пошло не так. Попробуйте ещё раз.';
      } finally {
        busy.value = false;
      }
    }

    return TunneloScaffold(
      title: sent.value ? 'Код из письма' : 'Вход',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Image.asset('assets/images/fox/waving.png', height: 150),
          ),
          const SizedBox(height: 20),
          if (reason != null && !sent.value) ...[
            TunneloGlass(
              child: Text(
                reason!,
                style: const TextStyle(
                  color: TunneloColors.text,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!sent.value) ...[
            const Text(
              'Ваша почта',
              style: TextStyle(color: TunneloColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _Field(
              controller: email,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              onSubmit: busy.value
                  ? null
                  : () => run(() async {
                      await api.requestLoginCode(email.text);
                      sent.value = true;
                    }),
            ),
          ] else ...[
            Text(
              'Отправили код на ${email.text.trim()}. Он действует 15 минут.',
              style: const TextStyle(
                color: TunneloColors.muted,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            _Field(
              controller: code,
              hint: '000000',
              keyboardType: TextInputType.number,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmit: busy.value ? null : () => _finish(context, ref, run, api, email, code),
            ),
          ],
          if (error.value != null) ...[
            const SizedBox(height: 12),
            Text(
              error.value!,
              style: const TextStyle(color: TunneloColors.alert, fontSize: 14),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy.value
                ? null
                : () {
                    if (sent.value) {
                      _finish(context, ref, run, api, email, code);
                    } else {
                      run(() async {
                        await api.requestLoginCode(email.text);
                        sent.value = true;
                      });
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: TunneloColors.sea,
              foregroundColor: TunneloColors.mistDeep,
              disabledBackgroundColor: TunneloColors.line,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: Text(
              busy.value
                  ? 'Подождите…'
                  : sent.value
                      ? 'Войти'
                      : 'Прислать код',
            ),
          ),
          if (sent.value) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: busy.value ? null : () => sent.value = false,
              style: TextButton.styleFrom(foregroundColor: TunneloColors.muted),
              child: const Text('Изменить почту'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Почта нужна, чтобы подписка не пропала вместе с телефоном и '
            'чтобы её можно было включить на втором устройстве. Пароль '
            'придумывать не нужно.',
            style: TextStyle(color: TunneloColors.muted, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(Future<void> Function()) run,
    TunneloActivation api,
    TextEditingController email,
    TextEditingController code,
  ) {
    return run(() async {
      await api.verifyLoginCode(email.text, code.text);
      ref.invalidate(tunneloSubscriptionProvider);
      if (context.mounted) Navigator.of(context).pop(true);
    });
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.keyboardType,
    required this.onSubmit,
    this.formatters,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final VoidCallback? onSubmit;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    inputFormatters: formatters,
    autocorrect: false,
    onSubmitted: (_) => onSubmit?.call(),
    style: const TextStyle(color: TunneloColors.text, fontSize: 17),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: TunneloColors.muted),
      filled: true,
      fillColor: TunneloColors.cardSolid,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TunneloColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TunneloColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TunneloColors.sea, width: 1.6),
      ),
    ),
  );
}
