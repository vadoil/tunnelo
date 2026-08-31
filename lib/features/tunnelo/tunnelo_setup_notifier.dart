import 'dart:io';

import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/per_app_proxy/data/selected_data_provider.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/tunnelo/tunnelo_activation.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final tunneloActivationProvider = Provider((ref) => TunneloActivation());

/// Сколько устройств занято из разрешённых.
///
/// Данные берём у сервиса активации (/status). Пока он их не отдаёт,
/// провайдер возвращает null и строка «Устройства» просто не рисуется.
class TunneloDevices {
  const TunneloDevices({required this.used, required this.limit});
  final int used;
  final int limit;
}

final tunneloDevicesProvider = FutureProvider<TunneloDevices?>((ref) async {
  final status = await ref.read(tunneloActivationProvider).status();
  if (status == null) return null;
  final used = status['devices'] ?? status['devicesUsed'] ?? status['ips'];
  final limit = status['deviceLimit'] ?? status['limitIp'] ?? status['maxDevices'];
  if (used is! int || limit is! int || limit <= 0) return null;
  return TunneloDevices(used: used, limit: limit);
});

sealed class SetupState {
  const SetupState();
}

class SetupIdle extends SetupState {
  const SetupIdle();
}

class SetupRunning extends SetupState {
  const SetupRunning(this.message);
  final String message;
}

class SetupDone extends SetupState {
  const SetupDone({this.daysLeft, this.servers});
  final int? daysLeft;
  final int? servers;
}

class SetupFailed extends SetupState {
  const SetupFailed(this.message);
  final String message;
}

/// Первичная настройка Tunnelo.
///
/// Пользователь при первом запуске ничего не вводит: приложение само
/// активирует промокод, добавляет подписку и включает правила для
/// российских сайтов, чтобы Ozon и Госуслуги шли мимо VPN.
class TunneloSetupNotifier extends StateNotifier<SetupState> with AppLogger {
  TunneloSetupNotifier(this._ref) : super(const SetupIdle());

  final Ref _ref;
  static const _kRulesApplied = 'tunnelo_ru_rules_v1';

  TunneloActivation get _api => _ref.read(tunneloActivationProvider);

  /// Вызывается один раз при старте приложения.
  Future<void> runIfNeeded() async {
    if (state is SetupRunning) return;
    try {
      await _ensureRuRules();
      await _ensureAppsOutsideTunnel();

      final profiles = await _ref.read(profilesNotifierProvider.future);
      if (profiles.isNotEmpty) {
        loggy.debug('профили уже есть');
        state = const SetupDone();
        return;
      }

      final saved = await _api.savedSubscription();
      if (saved != null) {
        loggy.debug('подписка сохранена, добавляю профиль');
        state = const SetupRunning('Загружаем серверы…');
        await _addProfile(saved);
        state = const SetupDone();
        return;
      }

      await activate(null, silent: true);
    } catch (e) {
      loggy.error('автонастройка не удалась: $e');
      state = const SetupFailed('Не удалось настроить подключение');
    }
  }

  /// Активация: автоматическая при первом запуске или по кнопке.
  Future<bool> activate(String? code, {bool silent = false}) async {
    state = SetupRunning(silent ? 'Настраиваем подключение…' : 'Проверяем промокод…');
    try {
      final r = await _api.activate(code: code);
      loggy.info('ключ ${r.key}, серверов ${r.servers}, дней ${r.daysLeft}');

      state = const SetupRunning('Загружаем серверы…');
      await _addProfile(r.subscription);

      state = SetupDone(daysLeft: r.daysLeft, servers: r.servers);
      return true;
    } on ActivationException catch (e) {
      loggy.warning('активация: ${e.message}');
      state = SetupFailed(e.message);
      return false;
    } catch (e) {
      loggy.error('активация упала: $e');
      state = const SetupFailed('Не удалось настроить подключение');
      return false;
    }
  }

  /// Добавить профиль по ссылке подписки.
  ///
  /// Если системный DNS не работает (провайдер режет запросы к внешним
  /// резолверам), ссылку скачать нечем — тогда забираем список серверов
  /// сами, через DoH, и создаём профиль из готового текста.
  Future<void> _addProfile(String url) async {
    final notifier = _ref.read(addProfileNotifierProvider.notifier);

    // Если имя не резолвится, обычный загрузчик всё равно не справится,
    // а ждать его таймаут — почти минута тишины на экране. Проверяем
    // заранее и сразу идём своим путём.
    if (await _dnsWorks(url)) {
      await notifier.addClipboard(url);
      if (!_ref.read(addProfileNotifierProvider).hasError) return;
      loggy.warning('ссылка подписки не открылась, пробую забрать список сам');
    } else {
      loggy.warning('DNS не отвечает, забираю список серверов напрямую');
    }

    final content = await _api.fetchSubscription(url);
    if (content == null) {
      throw const ActivationException(
        'Не удалось загрузить список серверов. Проверьте интернет.',
      );
    }
    await notifier.addClipboard(content);
  }

  /// Быстрая проверка: резолвится ли имя хоста подписки.
  Future<bool> _dnsWorks(String url) async {
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return false;
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Приложения, которые нельзя пускать в туннель.
  ///
  /// MAX проверяет, поднят ли VPN, и отказывается работать, даже если
  /// трафик идёт напрямую. Единственное лечение — увести его мимо
  /// туннеля целиком: тогда для него сети выглядят обычными.
  static const _kAppsExcluded = 'tunnelo_apps_excluded_v1';
  static const _appsOutsideTunnel = <String>[
    'ru.oneme.app', // МАКС: общение, звонки, сервисы
  ];

  Future<void> _ensureAppsOutsideTunnel() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kAppsExcluded) ?? false) return;
    try {
      await _ref.read(Preferences.perAppProxyMode.notifier).update(PerAppProxyMode.exclude);
      final source = _ref.read(appProxyDataSourceProvider);
      for (final pkg in _appsOutsideTunnel) {
        await source.updatePkg(pkg: pkg, mode: AppProxyMode.exclude);
      }
      await prefs.setBool(_kAppsExcluded, true);
      loggy.info('MAX выведен из туннеля');
    } catch (e) {
      loggy.warning('не удалось исключить приложения из туннеля: $e');
    }
  }

  /// Российские сайты — мимо VPN.
  ///
  /// Правило исполняется в клиенте: решение «в туннель или напрямую»
  /// принимается до входа в туннель, на сервере это сделать невозможно.
  /// Правила добавляются один раз, пользователь потом может их править.
  Future<void> _ensureRuRules() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kRulesApplied) ?? false) return;

    final rules = _ref.read(rulesNotifierProvider.notifier);
    final existing = _ref.read(rulesNotifierProvider);

    Future<void> add(
      String name,
      Outbound out, {
      List<String> sets = const [],
      List<String> domains = const [],
    }) async {
      if (existing.any((r) => r.name == name)) return;
      await rules.addRule(
        Rule(name: name, outbound: out, ruleSets: sets, domains: domains),
      );
    }

    // порядок важен: сначала блокировка, потом direct, остальное уходит в прокси
    await add('Реклама', Outbound.block, sets: ['geosite-category-ads-all']);
    await add('Локальная сеть', Outbound.direct,
        sets: ['geosite-private', 'geoip-private']);
    // geosite покрывает основную массу российских сайтов…
    await add('Россия', Outbound.direct, sets: ['geosite-category-ru', 'geoip-ru']);
    // …а список доменов страхует на случай, если rule-set не подтянется
    await add('Российские сервисы', Outbound.direct, domains: _ruDomains);

    await prefs.setBool(_kRulesApplied, true);
    loggy.info('правила RU-маршрутизации добавлены');
  }

  /// Страховка на случай, если rule-set не скачался: ключевые российские
  /// сервисы идут напрямую по имени домена.
  static const _ruDomains = <String>[
    'ru', 'su', 'xn--p1ai',
    'ozon.ru', 'wildberries.ru', 'wb.ru', 'avito.ru',
    'gosuslugi.ru', 'mos.ru', 'nalog.ru', 'nalog.gov.ru',
    'sberbank.ru', 'sber.ru', 'tinkoff.ru', 'tbank.ru',
    'alfabank.ru', 'vtb.ru', 'gazprombank.ru', 'raiffeisen.ru',
    'yandex.ru', 'yandex.net', 'ya.ru', 'yastatic.net',
    'vk.com', 'vk.ru', 'userapi.com', 'mail.ru', 'ok.ru',
    'max.ru', 'rutube.ru', 'kinopoisk.ru', 'dzen.ru',
    'mts.ru', 'megafon.ru', 'beeline.ru', 'tele2.ru', 'rt.ru',
    'rzd.ru', '2gis.ru', 'dns-shop.ru', 'mvideo.ru', 'citilink.ru',
  ];

  void clearError() {
    if (state is SetupFailed) state = const SetupIdle();
  }
}

final tunneloSetupProvider =
    StateNotifierProvider<TunneloSetupNotifier, SetupState>(TunneloSetupNotifier.new);
