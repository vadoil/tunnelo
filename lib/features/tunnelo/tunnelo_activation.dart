import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/http_client/doh_fallback.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки Tunnelo. Всё, что может поменяться на сервере, — здесь.
abstract class TunneloConfig {
  static const activateUrl = 'https://api.amnez.online/activate';
  static const statusUrl = 'https://api.amnez.online/status';
  static const redeemUrl = 'https://api.amnez.online/redeem';
  static const authRequestUrl = 'https://api.amnez.online/auth/request';
  static const authVerifyUrl = 'https://api.amnez.online/auth/verify';
  static const meUrl = 'https://api.amnez.online/me';
  static const defaultPromo = 'PARDAUTO';

  /// Оплата идёт на сайте, во внешнем браузере. Внутри приложения
  /// банковское подтверждение часто ломается, и магазины к такому
  /// относятся плохо.
  static const siteUrl = 'https://tunello.online';
}

/// Что получилось от введённого кода.
///
/// Код бывает трёх видов — промокод, код переноса с другого устройства и
/// код друга. Какой именно ввели, решает сервис: человеку незачем это знать,
/// а нам незачем гадать по виду строки.
class RedeemResult {
  const RedeemResult({
    required this.message,
    this.key,
    this.subscription,
    this.daysLeft,
    this.bonusDays,
  });

  final String message;
  final String? key;
  final String? subscription;
  final int? daysLeft;

  /// Начислено дней за код друга. null, если код был не реферальный.
  final int? bonusDays;
}

class ActivationResult {
  const ActivationResult({
    required this.key,
    required this.subscription,
    this.daysLeft,
    this.servers,
    this.reused = false,
  });

  final String key;
  final String subscription;
  final int? daysLeft;
  final int? servers;
  final bool reused;

  factory ActivationResult.fromJson(Map<String, dynamic> j) => ActivationResult(
        key: j['key'] as String,
        subscription: j['subscription'] as String,
        daysLeft: j['daysLeft'] as int?,
        servers: j['servers'] as int?,
        reused: j['reused'] as bool? ?? false,
      );
}

class ActivationException implements Exception {
  const ActivationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Клиент сервиса активации.
///
/// Токена панели в приложении нет — за подпиской ходим в свой сервис,
/// он уже общается с 3x-ui.
class TunneloActivation {
  /// Запасной путь при отказе DNS живёт в адаптере — см. [DohFallbackAdapter].
  TunneloActivation({Dio? dio}) : _dio = dio ?? (Dio()..httpClientAdapter = DohFallbackAdapter(IOHttpClientAdapter()));

  final Dio _dio;

  Future<Response<dynamic>> _request(Uri uri, {Object? body, required Options options}) =>
      body == null ? _dio.getUri<dynamic>(uri, options: options) : _dio.postUri<dynamic>(uri, data: body, options: options);

  static const _kDeviceId = 'tunnelo_device_id';
  static const _kSubKey = 'tunnelo_sub_key';
  static const _kSubUrl = 'tunnelo_sub_url';

  /// Стабильный идентификатор устройства: системный, иначе свой случайный.
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kDeviceId);
    if (saved != null && saved.length >= 8) return saved;

    String? raw;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        raw = (await info.androidInfo).id;
      } else if (Platform.isIOS) {
        raw = (await info.iosInfo).identifierForVendor;
      } else if (Platform.isWindows) {
        raw = (await info.windowsInfo).deviceId;
      } else if (Platform.isMacOS) {
        raw = (await info.macOsInfo).systemGUID;
      } else if (Platform.isLinux) {
        raw = (await info.linuxInfo).machineId;
      }
    } catch (_) {
      raw = null;
    }

    final id = _clean(raw) ?? _random();
    await prefs.setString(_kDeviceId, id);
    return id;
  }

  String? _clean(String? v) {
    if (v == null) return null;
    final c = v.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
    if (c.length < 8) return null;
    return c.length > 64 ? c.substring(0, 64) : c;
  }

  String _random() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<String?> savedSubscription() async =>
      (await SharedPreferences.getInstance()).getString(_kSubUrl);

  Future<String?> savedKey() async =>
      (await SharedPreferences.getInstance()).getString(_kSubKey);

  Future<void> _save(ActivationResult r) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSubKey, r.key);
    await p.setString(_kSubUrl, r.subscription);
  }

  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSubKey);
    await p.remove(_kSubUrl);
  }

  /// Активировать промокод. Повтор с того же устройства вернёт тот же ключ.
  Future<ActivationResult> activate({String? code}) async {
    final device = await deviceId();
    try {
      final resp = await _request(
        Uri.parse(TunneloConfig.activateUrl),
        body: {
          'code': (code ?? TunneloConfig.defaultPromo).trim().toUpperCase(),
          'device': device,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final Map<String, dynamic> body;
      try {
        body = resp.data is String
            ? jsonDecode(resp.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(resp.data as Map);
      } catch (e) {
        final preview = resp.data?.toString() ?? '';
        debugPrint('[tunnelo-doh] ответ ${resp.statusCode} не JSON: '
            '${preview.substring(0, preview.length.clamp(0, 200))}');
        throw const ActivationException(
          'Сервер активации ответил неожиданным образом. Попробуйте позже.',
        );
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final r = ActivationResult.fromJson(body);
        await _save(r);
        return r;
      }

      throw ActivationException(
        (body['message'] as String?) ??
            switch (resp.statusCode) {
              404 => 'Промокод не найден',
              409 => 'Промокод больше не действует',
              400 => 'Некорректный промокод',
              _ => 'Не удалось активировать (${resp.statusCode})',
            },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const ActivationException(
          'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
        );
      }
      throw ActivationException('Ошибка сети: ${e.message ?? e.type.name}');
    }
  }

  /// Попросить выслать код входа на почту.
  Future<String> requestLoginCode(String email) async {
    final resp = await _request(
      Uri.parse(TunneloConfig.authRequestUrl),
      body: {'email': email.trim().toLowerCase()},
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final body = _json(resp.data);
    if (resp.statusCode == 200) {
      return (body['message'] as String?) ?? 'Код отправлен на почту.';
    }
    throw ActivationException(
      (body['message'] as String?) ?? 'Не удалось отправить код',
    );
  }

  /// Обменять код на вход. Ключ с устройства привязывается к аккаунту,
  /// чтобы у человека не завелась вторая подписка.
  Future<String> verifyLoginCode(String email, String code) async {
    final resp = await _request(
      Uri.parse(TunneloConfig.authVerifyUrl),
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'device': await deviceId(),
        'key': await savedKey() ?? '',
      },
      options: Options(
        contentType: Headers.jsonContentType,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final body = _json(resp.data);
    if (resp.statusCode != 200) {
      throw ActivationException(
        (body['message'] as String?) ?? 'Код не подошёл',
      );
    }
    final token = body['token'] as String?;
    if (token == null) throw const ActivationException('Сервер не выдал доступ');
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kEmail, email.trim().toLowerCase());
    final key = body['key'] as String?;
    final sub = body['subscription'] as String?;
    if (key != null && sub != null) {
      await _save(ActivationResult(key: key, subscription: sub));
    }
    return token;
  }

  static const _kToken = 'tunnelo_token';
  static const _kEmail = 'tunnelo_email';

  Future<String?> savedToken() async =>
      (await SharedPreferences.getInstance()).getString(_kToken);

  Future<String?> savedEmail() async =>
      (await SharedPreferences.getInstance()).getString(_kEmail);

  Future<void> signOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kEmail);
  }

  Map<String, dynamic> _json(Object? data) {
    try {
      return data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : Map<String, dynamic>.from(data! as Map);
    } catch (_) {
      throw const ActivationException(
        'Сервер ответил неожиданным образом. Попробуйте позже.',
      );
    }
  }

  /// Ввести код: промокод, код переноса или код друга.
  ///
  /// Все три идут одним запросом. Если код оказался переносом, подписка
  /// сохраняется поверх текущей — устройство переезжает на общий ключ.
  Future<RedeemResult> redeem(String code) async {
    final device = await deviceId();
    final key = await savedKey();
    try {
      final resp = await _request(
        Uri.parse(TunneloConfig.redeemUrl),
        body: {'code': code.trim(), 'device': device, 'key': key ?? ''},
        options: Options(
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final Map<String, dynamic> body;
      try {
        body = resp.data is String
            ? jsonDecode(resp.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(resp.data as Map);
      } catch (_) {
        throw const ActivationException(
          'Сервер ответил неожиданным образом. Попробуйте позже.',
        );
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final newKey = body['key'] as String?;
        final sub = body['subscription'] as String?;
        if (newKey != null && sub != null) {
          await _save(ActivationResult(key: newKey, subscription: sub));
        }
        final days = body['days'] as int?;
        return RedeemResult(
          message: (body['message'] as String?) ??
              (days != null
                  ? 'Начислено $days дней'
                  : 'Готово, подписка подключена'),
          key: newKey,
          subscription: sub,
          daysLeft: body['daysLeft'] as int?,
          bonusDays: days,
        );
      }

      throw ActivationException(
        (body['message'] as String?) ??
            switch (resp.statusCode) {
              404 => 'Такого кода нет',
              409 => 'Этот код уже использован',
              400 => 'Код введён неверно',
              _ => 'Не удалось применить код (${resp.statusCode})',
            },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const ActivationException(
          'Нет связи с сервером. Проверьте интернет и попробуйте снова.',
        );
      }
      throw ActivationException('Ошибка сети: ${e.message ?? e.type.name}');
    }
  }

  /// Сколько дней осталось. null — если ключа нет или сервис недоступен.
  Future<Map<String, dynamic>?> status() async {
    final key = await savedKey();
    if (key == null) return null;
    try {
      final resp = await _request(
        Uri.parse('${TunneloConfig.statusUrl}/$key'),
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode != 200) return null;
      return resp.data is String
          ? jsonDecode(resp.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(resp.data as Map);
    } catch (_) {
      return null;
    }
  }
}
