import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/installed_apps.dart';

/// Чужой VPN-клиент, найденный на устройстве.
///
/// Два VPN спорят за трафик: второй перехватывает маршруты и DNS, и
/// соединение Tunnelo рвётся или не поднимается вовсе. Мы не чиним это за
/// человека — показываем, что нашли, и просим выключить или удалить.
class VpnConflict {
  const VpnConflict({required this.name, required this.id});

  /// Имя для человека: «AmneziaVPN», «Outline».
  final String name;

  /// Пакет на Android, имя программы или процесса на десктопе.
  final String id;

  @override
  bool operator ==(Object other) => other is VpnConflict && other.name == name && other.id == id;

  @override
  int get hashCode => Object.hash(name, id);

  @override
  String toString() => '$name ($id)';
}

/// Известные VPN-клиенты на Android: пакет → имя для человека.
const knownVpnPackages = <String, String>{
  'org.amnezia.vpn': 'AmneziaVPN',
  'org.outline.android.client': 'Outline',
  'com.wireguard.android': 'WireGuard',
  'net.openvpn.openvpn': 'OpenVPN Connect',
  'de.blinkt.openvpn': 'OpenVPN',
  'app.hiddify.com': 'Hiddify',
  'com.v2ray.ang': 'v2rayNG',
  'io.nekohasekai.sfa': 'sing-box',
  'moe.nb4a': 'NekoBox',
  'com.happproxy': 'Happ',
  'com.nordvpn.android': 'NordVPN',
  'com.expressvpn.vpn': 'ExpressVPN',
  'com.surfshark.vpnclient.android': 'Surfshark',
  'ch.protonvpn.android': 'Proton VPN',
  'com.kaspersky.secure.connection': 'Kaspersky VPN',
  'com.psiphon3': 'Psiphon',
  'com.cloudflare.onedotonedotonedotone': '1.1.1.1 (WARP)',
  'com.windscribe.vpn': 'Windscribe',
  'hotspotshield.android.vpn': 'Hotspot Shield',
  'com.tunnelbear.android': 'TunnelBear',
  'free.vpn.unblock.proxy.turbovpn': 'Turbo VPN',
  'com.freevpnplanet': 'Planet VPN',
  'org.browsec.vpn': 'Browsec',
};

/// Известные VPN-клиенты на десктопе: подстрока имени программы или процесса
/// (без учёта регистра, по границе слова) → имя для человека.
///
/// Слова подобраны так, чтобы не ловить постороннее: «clash» сам по себе
/// поймал бы Clash of Clans, поэтому только полные названия клиентов.
const knownVpnKeywords = <String, String>{
  'amneziavpn': 'AmneziaVPN',
  'amnezia vpn': 'AmneziaVPN',
  'amnezia': 'AmneziaVPN',
  'outline': 'Outline',
  'wireguard': 'WireGuard',
  'openvpn': 'OpenVPN',
  'hiddify': 'Hiddify',
  'v2rayn': 'v2rayN',
  'nekoray': 'Nekoray',
  'nekobox': 'NekoBox',
  'clash verge': 'Clash Verge',
  'clash for windows': 'Clash for Windows',
  'clash nyanpasu': 'Clash Nyanpasu',
  'flclash': 'FlClash',
  'happ': 'Happ',
  'nordvpn': 'NordVPN',
  'expressvpn': 'ExpressVPN',
  'surfshark': 'Surfshark',
  'proton vpn': 'Proton VPN',
  'protonvpn': 'Proton VPN',
  'psiphon': 'Psiphon',
  'cloudflare warp': 'Cloudflare WARP',
  'windscribe': 'Windscribe',
  'hotspot shield': 'Hotspot Shield',
  'tunnelbear': 'TunnelBear',
  'kaspersky vpn': 'Kaspersky VPN',
  'turbo vpn': 'Turbo VPN',
  'sing-box': 'sing-box',
  'streisand': 'Streisand',
  'v2box': 'V2Box',
  'karing': 'Karing',
  'planet vpn': 'Planet VPN',
  'browsec': 'Browsec',
};

/// Android: что из установленного — известный VPN.
///
/// Смотрим не только на имя пакета, но и на название приложения: пакеты
/// переименовывают, форки расходятся, и список никогда не будет полным.
/// Happ, например, встречается и как `com.happproxy`, и под другими именами —
/// по названию он находится в любом случае. Плюс ловим всё, что честно
/// называет себя VPN: чужой туннель мешает нам независимо от того, знаем мы
/// его или нет.
List<VpnConflict> conflictsFromPackages(Iterable<({String packageName, String name})> apps) {
  final seen = <String>{};
  final found = <VpnConflict>[];
  for (final app in apps) {
    if (app.packageName == 'app.tunnelo.com') continue;
    final known = knownVpnPackages[app.packageName];
    if (known != null) {
      if (seen.add(known)) found.add(VpnConflict(name: known, id: app.packageName));
      continue;
    }
    final lower = app.name.toLowerCase();
    String? byName;
    for (final entry in knownVpnKeywords.entries) {
      if (_matchesWord(lower, entry.key)) {
        byName = entry.value;
        break;
      }
    }
    // «VPN» отдельным словом в названии — почти всегда действительно VPN.
    byName ??= _matchesWord(lower, 'vpn') ? app.name : null;
    if (byName != null && seen.add(byName)) {
      found.add(VpnConflict(name: byName, id: app.packageName));
    }
  }
  return found;
}

/// Десктоп: что из списка имён (программы, процессы) — известный VPN.
/// Один клиент считается один раз, даже если виден и в программах, и в процессах.
List<VpnConflict> conflictsFromNames(Iterable<String> names) {
  final seen = <String>{};
  final found = <VpnConflict>[];
  for (final raw in names) {
    final lower = raw.toLowerCase();
    for (final entry in knownVpnKeywords.entries) {
      if (_matchesWord(lower, entry.key) && seen.add(entry.value)) {
        found.add(VpnConflict(name: entry.value, id: raw));
      }
    }
  }
  return found;
}

/// Буквы a–z; цифры считаем границей, чтобы «psiphon» ловил «psiphon3.exe».
bool _isLetter(int code) => code >= 0x61 && code <= 0x7a;

/// Ключевое слово стоит по границе слова: «happ» ловит «Happ.exe», но не «Happy Farm».
bool _matchesWord(String lower, String keyword) {
  var from = 0;
  while (true) {
    final i = lower.indexOf(keyword, from);
    if (i < 0) return false;
    final before = i == 0 || !_isLetter(lower.codeUnitAt(i - 1));
    final end = i + keyword.length;
    final after = end >= lower.length || !_isLetter(lower.codeUnitAt(end));
    if (before && after) return true;
    from = i + 1;
  }
}

/// Имена программ из вывода `reg query <ключ> /s /v DisplayName`.
List<String> displayNamesFromRegistry(String output) {
  final names = <String>[];
  for (final line in output.split('\n')) {
    final i = line.indexOf('REG_SZ');
    if (i < 0) continue;
    final name = line.substring(i + 'REG_SZ'.length).trim();
    if (name.isNotEmpty) names.add(name);
  }
  return names;
}

/// Имена процессов из `tasklist /FO CSV /NH`: первое поле каждой строки.
List<String> imageNamesFromTasklist(String csv) {
  final names = <String>[];
  for (final line in csv.split('\n')) {
    final t = line.trim();
    if (!t.startsWith('"')) continue;
    final end = t.indexOf('"', 1);
    if (end > 1) names.add(t.substring(1, end));
  }
  return names;
}

/// Поднят ли чужой туннель: интерфейс tun* есть, а наш VPN выключен.
bool foreignTunnelUp(Iterable<String> interfaces, {required bool ourTunnelUp}) =>
    !ourTunnelUp && interfaces.any((n) => n.startsWith('tun'));

/// Чужие VPN-клиенты на этом устройстве. Пусто, если не нашли или платформа
/// не даёт посмотреть (iOS).
final vpnConflictsProvider = FutureProvider<List<VpnConflict>>((ref) async {
  try {
    if (Platform.isAndroid) {
      final apps = await InstalledApps.getInstalledApps();
      return conflictsFromPackages(apps.map((a) => (packageName: a.packageName, name: a.name)));
    }
    if (Platform.isWindows) {
      return conflictsFromNames([...await _windowsPrograms(), ...await _windowsProcesses()]);
    }
    if (Platform.isMacOS) return conflictsFromNames(await _macApps());
  } catch (_) {
    // Не смогли посмотреть — значит, не мешаем.
  }
  return const [];
});

/// Сейчас работает чужой VPN (Android): туннель есть, а наш выключен.
final foreignVpnActiveProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  final status = ref.watch(connectionNotifierProvider).valueOrNull;
  final ours = status is Connected || status is Connecting || status is Disconnecting;
  // Сразу после нашего отключения tun0 ещё пару секунд жив — не принимать
  // его за чужой.
  if (!ours) await Future<void>.delayed(const Duration(seconds: 3));
  try {
    final interfaces = await NetworkInterface.list();
    return foreignTunnelUp(interfaces.map((i) => i.name), ourTunnelUp: ours);
  } catch (_) {
    return false;
  }
});

Future<List<String>> _windowsPrograms() async {
  const keys = [
    r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
  ];
  final names = <String>[];
  for (final key in keys) {
    final r = await Process.run('reg', ['query', key, '/s', '/v', 'DisplayName']);
    names.addAll(displayNamesFromRegistry(r.stdout.toString()));
  }
  return names;
}

Future<List<String>> _windowsProcesses() async {
  final r = await Process.run('tasklist', ['/FO', 'CSV', '/NH']);
  return imageNamesFromTasklist(r.stdout.toString());
}

Future<List<String>> _macApps() async {
  final names = <String>[];
  final home = Platform.environment['HOME'];
  for (final dir in ['/Applications', if (home != null) '$home/Applications']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    await for (final e in d.list(followLinks: false)) {
      final base = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (base.endsWith('.app')) names.add(base.substring(0, base.length - 4));
    }
  }
  return names;
}

/// Открыть страницу приложения в системных настройках Android.
///
/// Оттуда чужой VPN удаляется в два касания. Пустой [packageName] открывает
/// общий список приложений — пригодится, если пакет нам неизвестен.
Future<void> openAppSettings([String packageName = '']) async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel(
      'com.hiddify.app/platform',
    ).invokeMethod<bool>('open_app_settings', {'package': packageName});
  } catch (_) {
    // Настройки не открылись — не беда: в карточке написано, куда идти руками.
  }
}
