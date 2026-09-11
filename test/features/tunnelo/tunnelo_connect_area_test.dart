import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_connect_area.dart';

void main() {
  test('на телефоне лис в полный размер', () {
    expect(foxSizeFor(914), 260);
  });

  test('в низком окне десктопа лис ужимается, чтобы карточка сервера была видна', () {
    expect(foxSizeFor(760), 200);
  });

  test('ниже 160 не ужимается — иначе не читается', () {
    expect(foxSizeFor(692), 160);
  });
}
