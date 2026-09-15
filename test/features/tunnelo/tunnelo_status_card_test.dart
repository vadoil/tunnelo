import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/tunnelo/tunnelo_status_card.dart';

/// Главная без бухгалтерии: одна строка вместо трёх, тревога за три дня,
/// кнопки только когда пора. Проверяем решения, а не пиксели.
void main() {
  SubscriptionInfo sub({required int days, int total = 0, int used = 0}) =>
      SubscriptionInfo(
        upload: 0,
        download: used,
        total: total,
        expire: DateTime.now().add(Duration(days: days, hours: 1)),
      );

  group('одна строка вместо трёх', () {
    test('срок пишем датой, а не остатком дней', () {
      final line = TunneloStatusCard.headlineFor(sub(days: 20));
      expect(line, startsWith('Подписка до '));
      expect(line, isNot(contains('дн')));
    });

    test('последний день и просрочка называются своими словами', () {
      expect(TunneloStatusCard.headlineFor(sub(days: 0)),
          'Подписка кончается сегодня');
      expect(
        TunneloStatusCard.headlineFor(SubscriptionInfo(
          upload: 0,
          download: 0,
          total: 0,
          expire: DateTime.now().subtract(const Duration(days: 2)),
        )),
        'Подписка закончилась',
      );
    });
  });

  group('когда тревожиться', () {
    test('за три дня — тревога, за четыре — ещё нет', () {
      expect(TunneloStatusCard.alarmingFor(sub(days: 3)), isTrue);
      expect(TunneloStatusCard.alarmingFor(sub(days: 4)), isFalse);
    });

    test('кнопки появляются за семь дней, раньше не мешают', () {
      expect(TunneloStatusCard.needsActionFor(sub(days: 7)), isTrue);
      expect(TunneloStatusCard.needsActionFor(sub(days: 8)), isFalse);
    });

    test('просроченная подписка тревожна и требует действия', () {
      final past = SubscriptionInfo(
        upload: 0,
        download: 0,
        total: 0,
        expire: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(TunneloStatusCard.alarmingFor(past), isTrue);
      expect(TunneloStatusCard.needsActionFor(past), isTrue);
    });
  });

  group('полоска трафика', () {
    test('до пяти процентов не показываем — она ничего не говорит', () {
      expect(
        TunneloStatusCard.showTrafficFor(sub(days: 20, total: 1000, used: 40)),
        isFalse,
      );
      expect(
        TunneloStatusCard.showTrafficFor(sub(days: 20, total: 1000, used: 60)),
        isTrue,
      );
    });

    test('на безлимите полоски нет вовсе', () {
      expect(
        TunneloStatusCard.showTrafficFor(sub(days: 20, total: 0, used: 999)),
        isFalse,
      );
    });
  });
}
