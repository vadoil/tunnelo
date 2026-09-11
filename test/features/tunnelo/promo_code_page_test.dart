import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/promo_code_page.dart';

void main() {
  TextEditingValue probe(String text, void Function(bool) onProbe) =>
      NonLatinProbe(onProbe).formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

  test('кириллица помечается — её отрежет фильтр следом', () {
    bool? flagged;
    final out = probe('РОМАН1', (v) => flagged = v);
    expect(flagged, isTrue);
    expect(out.text, 'РОМАН1', reason: 'сам ничего не режет, только сообщает');
  });

  test('латиница в любом регистре проходит без пометки', () {
    bool? flagged;
    probe('roman1', (v) => flagged = v);
    expect(flagged, isFalse);
  });

  test('пробел тоже помечается', () {
    bool? flagged;
    probe('ROMAN 1', (v) => flagged = v);
    expect(flagged, isTrue);
  });
}
