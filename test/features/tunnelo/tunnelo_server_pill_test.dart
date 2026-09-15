import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_server_pill.dart';

/// «Сервер не выбран · Нажмите, чтобы выбрать» человек читал как поломку,
/// хотя сервер подбирается сам. Пилюля обязана говорить правду.
void main() {
  const fi = '🇫🇮 Финляндия-2 · HY2-2 § 3';

  group('до подключения', () {
    test('автоподбор — так и сказано, без «не выбран»', () {
      for (final tag in <String?>[null, '', 'lowest', 'balance', 'select']) {
        expect(TunneloServerPill.idleTitleFor(tag), 'Сервер подберётся сам');
        expect(TunneloServerPill.subtitleFor(false, tag, 0),
            'Выберем быстрейший при подключении');
      }
    });

    test('выбранный вручную узел назван и помечен', () {
      expect(TunneloServerPill.idleTitleFor(fi), '🇫🇮 Финляндия-2');
      expect(TunneloServerPill.subtitleFor(false, fi, 0),
          'Выбран вручную · нажмите, чтобы изменить');
    });
  });

  group('после подключения', () {
    test('узел с флагом и номером плюс задержка', () {
      expect(TunneloServerPill.nodeFor(fi), '🇫🇮 Финляндия-2');
      expect(TunneloServerPill.subtitleFor(true, fi, 24), 'Подключено · 24 мс');
    });

    test('задержки нет или она бессмысленная — просто «Подключено»', () {
      expect(TunneloServerPill.subtitleFor(true, fi, 0), 'Подключено');
      expect(TunneloServerPill.subtitleFor(true, fi, 65000), 'Подключено');
    });

    test('балансировщик называется по-человечески', () {
      expect(TunneloServerPill.nodeFor('lowest'), 'Быстрейший сервер');
    });
  });
}
