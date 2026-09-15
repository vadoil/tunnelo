import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Вход по логину и паролю. Без него приложение не работает.
///
/// Решение от 16.09.2026: подписка живёт на аккаунте, а не на телефоне.
/// Раньше ключ лежал на устройстве — сменил телефон, потерял доступ, и из
/// четырнадцати подписчиков входом по почте не воспользовался никто, потому
/// что он был необязателен.
///
/// Пару логин/пароль человек получает письмом: при оплате или при первом
/// входе по почте в кабинете. Поэтому здесь только две ссылки наружу —
/// «Ещё нет доступа» и «Забыли пароль», обе ведут на сайт.
class TunneloSignInPage extends HookConsumerWidget {
  const TunneloSignInPage({super.key, this.onSignedIn});

  /// Кого позвать, когда вход прошёл: главная перечитывает состояние.
  final VoidCallback? onSignedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(tunneloActivationProvider);
    final login = useTextEditingController();
    final password = useTextEditingController();
    final busy = useState(false);
    final hidden = useState(true);
    final error = useState<String?>(null);

    Future<void> submit() async {
      if (busy.value) return;
      if (login.text.trim().isEmpty || password.text.isEmpty) {
        error.value = 'Введите логин и пароль.';
        return;
      }
      busy.value = true;
      error.value = null;
      try {
        await api.signInWithPassword(login.text, password.text);
        onSignedIn?.call();
      } on ActivationException catch (e) {
        error.value = e.message;
      } catch (_) {
        error.value = 'Не дозвонились до сервера. Проверьте интернет.';
      } finally {
        busy.value = false;
      }
    }

    return TunneloBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  const Center(
                    child: Image(
                      image: AssetImage('assets/images/fox/lantern.png'),
                      height: 150,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Вход',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: TunneloColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Логин и пароль приходят письмом — при оплате или при первом '
                    'входе по почте. Подписка живёт на аккаунте: сменили телефон, '
                    'вошли и продолжили.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TunneloColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  TunneloGlass(
                    child: Column(
                      children: [
                        TextField(
                          controller: login,
                          enabled: !busy.value,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.emailAddress,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          ],
                          style: const TextStyle(color: TunneloColors.text),
                          decoration: const InputDecoration(
                            labelText: 'Логин или почта',
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(height: 1, color: TunneloColors.line),
                        TextField(
                          controller: password,
                          enabled: !busy.value,
                          obscureText: hidden.value,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => submit(),
                          style: const TextStyle(color: TunneloColors.text),
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            border: InputBorder.none,
                            suffixIcon: IconButton(
                              tooltip: hidden.value ? 'Показать пароль' : 'Скрыть пароль',
                              onPressed: () => hidden.value = !hidden.value,
                              icon: Icon(
                                hidden.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: TunneloColors.muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (error.value != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error.value!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: TunneloColors.alert),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy.value ? null : submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: TunneloColors.coral,
                      foregroundColor: TunneloColors.abyss,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: busy.value
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: busy.value
                        ? null
                        : () => UriUtils.tryLaunch(Uri.parse(TunneloConfig.forgotUrl)),
                    child: const Text(
                      'Забыли пароль? Пришлём ссылку на почту',
                      style: TextStyle(color: TunneloColors.sea),
                    ),
                  ),
                  TextButton(
                    onPressed: busy.value
                        ? null
                        : () => UriUtils.tryLaunch(Uri.parse(TunneloConfig.signUpUrl)),
                    child: const Text(
                      'Ещё нет доступа — завести аккаунт',
                      style: TextStyle(color: TunneloColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
