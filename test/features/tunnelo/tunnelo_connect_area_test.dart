import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_connect_area.dart';

/// Аргумент — свободная высота: окно минус системные отступы и панель вкладок.
/// Именно её считает foxSizeForWindow, и именно на ней ошибались раньше —
/// панель вкладок в расчёт не входила, и карточка сервера уходила под неё.
void main() {
  test('на телефоне лис в полный размер', () {
    expect(foxSizeFor(900), 260);
  });

  test('места меньше — лис ужимается, чтобы карточка сервера была видна', () {
    expect(foxSizeFor(810), 200);
  });

  test('ниже 150 не ужимается — иначе не читается', () {
    expect(foxSizeFor(700), 150);
  });
}
