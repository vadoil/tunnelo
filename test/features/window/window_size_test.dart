import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';

void main() {
  test('сохранённый размер меньше минимума поднимается до минимума', () {
    final s = clampWindowSize(const Size(868, 668));
    expect(s.height, minimumWindowSize.height);
    expect(s.width, 868, reason: 'ширина и так больше минимума — не трогаем');
  });

  test('размер больше минимума остаётся как был', () {
    expect(clampWindowSize(const Size(1200, 900)), const Size(1200, 900));
  });
}
