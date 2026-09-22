import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tunnelo/tunnelo_conflict_card.dart';
import 'package:hiddify/features/tunnelo/vpn_conflicts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  group('conflictsFromPackages', () {
    test('узнаёт известные пакеты и не трогает остальные', () {
      final found = conflictsFromPackages([
        (packageName: 'org.amnezia.vpn', name: 'AmneziaVPN'),
        (packageName: 'com.android.chrome', name: 'Chrome'),
        (packageName: 'com.v2ray.ang', name: 'v2rayNG'),
      ]);
      expect(found.map((c) => c.name), ['AmneziaVPN', 'v2rayNG']);
    });

    test('пусто, если чужих VPN нет', () {
      expect(conflictsFromPackages([(packageName: 'ru.yandex.searchplugin', name: 'Яндекс')]), isEmpty);
    });

    test('узнаёт клиента по названию, даже если пакет незнакомый', () {
      final found = conflictsFromPackages([
        (packageName: 'com.example.unknown', name: 'Happ'),
      ]);
      expect(found.map((c) => c.name), ['Happ']);
    });

    test('ловит всё, что называет себя VPN', () {
      final found = conflictsFromPackages([
        (packageName: 'com.some.client', name: 'Super VPN'),
      ]);
      expect(found.map((c) => c.name), ['Super VPN']);
    });

    test('не считает конфликтом себя и не ловит слово внутри другого', () {
      final found = conflictsFromPackages([
        (packageName: 'app.tunnelo.com', name: 'Tunnelo'),
        (packageName: 'com.happy.farm', name: 'Happy Farm'),
      ]);
      expect(found, isEmpty);
    });
  });

  group('conflictsFromNames', () {
    test('ловит программы и процессы без учёта регистра, каждый клиент один раз', () {
      final found = conflictsFromNames([
        'AmneziaVPN',
        'AmneziaVPN.exe',
        'outline.exe',
        'Google Chrome',
        'v2rayN',
        'psiphon3.exe',
      ]);
      expect(found.map((c) => c.name), ['AmneziaVPN', 'Outline', 'v2rayN', 'Psiphon']);
    });

    test('не принимает игры и похожие слова за VPN', () {
      expect(conflictsFromNames(['Clash of Clans', 'Happy Farm', 'Outlines Drawing']), isEmpty);
    });

    test('составные названия', () {
      expect(conflictsFromNames(['Clash Verge Rev', 'Proton VPN', 'Cloudflare WARP']).map((c) => c.name), [
        'Clash Verge',
        'Proton VPN',
        'Cloudflare WARP',
      ]);
    });
  });

  group('разбор вывода Windows', () {
    test('reg query: имена после REG_SZ', () {
      const out = '''
HKEY_LOCAL_MACHINE\\SOFTWARE\\...\\Uninstall\\{123}
    DisplayName    REG_SZ    AmneziaVPN

HKEY_LOCAL_MACHINE\\SOFTWARE\\...\\Uninstall\\Tunnelo_is1
    DisplayName    REG_SZ    Tunnelo
''';
      expect(displayNamesFromRegistry(out), ['AmneziaVPN', 'Tunnelo']);
    });

    test('tasklist CSV: первое поле', () {
      const csv = '"System Idle Process","0","Services","0","8 K"\n"outline.exe","4120","Console","1","52 000 K"\n';
      expect(imageNamesFromTasklist(csv), ['System Idle Process', 'outline.exe']);
    });
  });

  group('foreignTunnelUp', () {
    test('tun при нашем выключенном VPN — чужой', () {
      expect(foreignTunnelUp(['wlan0', 'tun0'], ourTunnelUp: false), isTrue);
    });
    test('tun при нашем включённом — наш', () {
      expect(foreignTunnelUp(['wlan0', 'tun0'], ourTunnelUp: true), isFalse);
    });
    test('без tun — никого', () {
      expect(foreignTunnelUp(['wlan0', 'rmnet0'], ourTunnelUp: false), isFalse);
    });
  });

  group('TunneloConflictCard', () {
    Widget wrap(Widget child, {required List<VpnConflict> conflicts, bool foreign = false}) => ProviderScope(
      overrides: [
        vpnConflictsProvider.overrideWith((ref) => Future.value(conflicts)),
        foreignVpnActiveProvider.overrideWith((ref) => Future.value(foreign)),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

    testWidgets('называет найденные клиенты и просит их убрать', (tester) async {
      await tester.pumpWidget(
        wrap(const TunneloConflictCard(), conflicts: const [VpnConflict(name: 'AmneziaVPN', id: 'org.amnezia.vpn')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Удалите другой VPN'), findsOneWidget);
      expect(find.textContaining('AmneziaVPN'), findsOneWidget);
      expect(find.textContaining('удалите'), findsOneWidget);
    });

    testWidgets('без конфликтов ничего не рисует', (tester) async {
      await tester.pumpWidget(wrap(const TunneloConflictCard(), conflicts: const []));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.text('Удалите другой VPN'), findsNothing);
    });

    testWidgets('чужой туннель без известных программ — отдельный текст', (tester) async {
      await tester.pumpWidget(wrap(const TunneloConflictCard(), conflicts: const [], foreign: true));
      await tester.pumpAndSettle();
      expect(find.text('Сейчас включён другой VPN'), findsOneWidget);
    });
  });
}
