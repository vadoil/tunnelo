import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_account_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('без аккаунта — зовёт войти по почте', (tester) async {
    var logins = 0;
    await tester.pumpWidget(wrap(TunneloAccountRow(email: null, onLogin: () => logins++, onLogout: () {})));
    expect(find.text('Войти по почте'), findsOneWidget);
    expect(find.text('Выйти'), findsNothing);
    await tester.tap(find.text('Войти по почте'));
    expect(logins, 1);
  });

  testWidgets('с аккаунтом — показывает почту и «Выйти»', (tester) async {
    var logouts = 0;
    await tester.pumpWidget(wrap(TunneloAccountRow(email: 'a@b.ru', onLogin: () {}, onLogout: () => logouts++)));
    expect(find.text('a@b.ru'), findsOneWidget);
    expect(find.text('Войти по почте'), findsNothing);
    await tester.tap(find.text('Выйти'));
    expect(logouts, 1);
  });
}
