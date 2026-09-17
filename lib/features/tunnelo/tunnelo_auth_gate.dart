import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_sign_in_page.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Без входа приложения нет — ни главной, ни настроек.
///
/// Замок стоит вокруг всей оболочки с вкладками: раньше он был только на
/// главной, и «Настройки» открывались рядом с экраном входа — там и профиль
/// подписки, и маршрутизация, и логи. Одно место на все платформы: Android,
/// iOS, Windows и macOS рисуют оболочку одним и тем же виджетом.
class TunneloAuthGate extends HookConsumerWidget {
  const TunneloAuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Токен читаем с диска один раз за жизнь виджета. Пока читаем — держим
    // пустой фон: мигать экраном входа перед вошедшим человеком нельзя.
    final signedIn = useState<bool?>(null);
    final reread = useState(0);
    final api = ref.read(tunneloActivationProvider);
    useEffect(() {
      var alive = true;
      api.savedToken().then((token) {
        if (alive) signedIn.value = token != null && token.isNotEmpty;
      });
      return () => alive = false;
    }, [reread.value]);

    if (signedIn.value == null) {
      return const TunneloBackground(child: Scaffold(backgroundColor: Colors.transparent));
    }
    if (signedIn.value == false) {
      return TunneloSignInPage(onSignedIn: () => reread.value++);
    }
    return child;
  }
}
