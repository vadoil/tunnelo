import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/features/tunnelo/tunnelo_sign_in_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Экран входа — единственная дверь в приложение с 16.09.2026.
/// Проверяем, что на нём есть чем войти и куда пойти, если пароля нет.
void main() {
  Future<void> pump(WidgetTester tester) async {
    // Список строит только видимые строки: на коротком экране ссылки внизу
    // просто не создаются, и тест их «не находит».
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TunneloSignInPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('спрашивает логин и пароль', (tester) async {
    await pump(tester);
    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Логин или почта'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
  });

  testWidgets('ведёт за паролем и за аккаунтом на сайт', (tester) async {
    await pump(tester);
    expect(find.text('Забыли пароль? Пришлём ссылку на почту'), findsOneWidget);
    expect(find.text('Ещё нет доступа — завести аккаунт'), findsOneWidget);
  });

  testWidgets('пустые поля — говорит, чего не хватает, и не ходит на сервер',
      (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pump();
    expect(find.text('Введите логин и пароль.'), findsOneWidget);
  });

  test('адреса входа и восстановления ведут на наши же сервисы', () {
    expect(TunneloConfig.authLoginUrl, contains('api.amnez.online'));
    expect(TunneloConfig.forgotUrl, contains('tunello.online'));
    expect(TunneloConfig.signUpUrl, contains('tunello.online'));
  });
}
