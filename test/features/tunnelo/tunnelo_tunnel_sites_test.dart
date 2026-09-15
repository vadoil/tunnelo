import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_tunnel_sites.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// «Плюс» на главной: человек сам отправляет заблокированный сайт в туннель.
/// Разбор введённого — самое хрупкое место: люди вставляют ссылку целиком.
void main() {
  group('разбор адреса', () {
    test('ссылку целиком приводит к домену', () {
      expect(TunneloTunnelSites.normalize('https://www.Rutracker.ORG/forum/index.php'),
          'rutracker.org');
      expect(TunneloTunnelSites.normalize('  http://Example.RU/path?a=1#x  '),
          'example.ru');
      expect(TunneloTunnelSites.normalize('sub.domain.co.uk'), 'sub.domain.co.uk');
    });

    test('порт, логин и точка в конце отбрасываются', () {
      expect(TunneloTunnelSites.normalize('example.com:8443'), 'example.com');
      expect(TunneloTunnelSites.normalize('user@example.com'), 'example.com');
      expect(TunneloTunnelSites.normalize('example.com.'), 'example.com');
    });

    test('не адрес — пустая строка, а не мусорное правило', () {
      expect(TunneloTunnelSites.normalize(''), '');
      expect(TunneloTunnelSites.normalize('   '), '');
      expect(TunneloTunnelSites.normalize('localhost'), '');
      expect(TunneloTunnelSites.normalize('это не адрес'), '');
      expect(TunneloTunnelSites.normalize('-bad-.com'), '');
      expect(TunneloTunnelSites.normalize('http://'), '');
    });
  });

  testWidgets('карточка объясняет, зачем плюс, и показывает добавленное',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: TunneloTunnelSitesCard()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Сайт не открывается?'), findsOneWidget);
    expect(find.byTooltip('Добавить сайт в туннель'), findsOneWidget);
    expect(
      find.textContaining('Российские сайты идут мимо VPN'),
      findsOneWidget,
    );
  });
}
