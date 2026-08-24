import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Результат активации промокода.
class ActivationResult {
  const ActivationResult({
    required this.key,
    required this.subscription,
    this.daysLeft,
    this.expires,
    this.reused = false,
  });

  final String key;
  final String subscription;
  final int? daysLeft;
  final String? expires;
  final bool reused;

  factory ActivationResult.fromJson(Map<String, dynamic> j) => ActivationResult(
        key: j['key'] as String,
        subscription: j['subscription'] as String,
        daysLeft: j['daysLeft'] as int?,
        expires: j['expires'] as String?,
        reused: j['reused'] as bool? ?? false,
      );
}

/// Ошибка активации с текстом, который не стыдно показать пользователю.
class ActivationException implements Exception {
  const ActivationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Клиент сервиса активации Tunnelo.
///
/// Токена панели в приложении нет и быть не должно — за ключами ходим
/// в свой сервис `/activate`, он уже общается с панелью.
class ActivationService {
  ActivationService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _kDeviceId = 'tunnelo_device_id';
  static const _kSubKey = 'tunnelo_sub_key';
  static const _kSubUrl = 'tunnelo_sub_url';
  static const _kActivated = 'tunnelo_activated_at';

  /// Стабильный идентификатор устройства.
  /// Сначала пробуем системный, иначе генерируем и храним локально —
  /// главное, чтобы он не менялся между запусками.
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

    final id = _sanitize(raw) ?? _randomId();
    await prefs.setString(_kDeviceId, id);
    return id;
  }

  /// Сервис принимает только [A-Za-z0-9_-]{8,64}.
  String? _sanitize(String? v) {
    if (v == null) return null;
    final cleaned = v.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
    if (cleaned.length < 8) return null;
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Сохранённая подписка, если уже активировались.
  Future<String?> savedSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSubUrl);
  }

  Future<String?> savedKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSubKey);
  }

  Future<void> _save(ActivationResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSubKey, r.key);
    await prefs.setString(_kSubUrl, r.subscription);
    await prefs.setString(_kActivated, DateTime.now().toIso8601String());
  }

  /// Сбросить активацию (для отладки и смены ключа).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSubKey);
    await prefs.remove(_kSubUrl);
    await prefs.remove(_kActivated);
  }

  /// Активировать промокод. Повторный вызов с тем же устройством
  /// вернёт тот же ключ — сервис не плодит пользователей.
  Future<ActivationResult> activate({String code = Constants.defaultPromoCode}) async {
    final device = await deviceId();
    try {
      final resp = await _dio.post<dynamic>(
        Constants.activationUrl,
        data: {'code': code.trim().toUpperCase(), 'device': device},
        options: Options(
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final body = resp.data is String
          ? jsonDecode(resp.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(resp.data as Map);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final result = ActivationResult.fromJson(body);
        await _save(result);
        return result;
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

  /// Статус подписки: сколько осталось дней.
  Future<Map<String, dynamic>?> status() async {
    final key = await savedKey();
    if (key == null) return null;
    try {
      final resp = await _dio.get<dynamic>(
        '${Constants.statusUrl}/$key',
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
