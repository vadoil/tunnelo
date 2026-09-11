import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_setup_overlay.dart';
import 'package:hiddify/features/tunnelo/tunnelo_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Running extends TunneloSetupNotifier {
  _Running(super.ref) {
    state = const SetupRunning('Загружаем серверы…');
  }
}

void main() {
  testWidgets('шторка первого запуска закрывает весь экран, а не ширину текста', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tunneloSetupProvider.overrideWith((ref) => _Running(ref))],
        child: const MaterialApp(home: TunneloSetupOverlay(child: SizedBox.expand())),
      ),
    );
    await tester.pump();
    final screen = tester.getSize(find.byType(TunneloSetupOverlay));
    final curtain = find.byWidgetPredicate((w) => w is Material && w.color == TunneloColors.abyss);
    expect(curtain, findsOneWidget);
    expect(tester.getSize(curtain), screen);
  });
}
