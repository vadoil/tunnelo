import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки Tunnelo. Всё, что может поменяться на сервере, — здесь.
abstract class TunneloConfig {
  static const activateUrl = 'https://api.amnez.online/activate';
  static const statusUrl = 'https://api.amnez.online/status';
  static const defaultPromo = 'PARDAUTO';
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
  TunneloActivation({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

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
      final resp = await _dio.post<dynamic>(
        TunneloConfig.activateUrl,
        data: {
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

      final body = resp.data is String
          ? jsonDecode(resp.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(resp.data as Map);

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

  /// Сколько дней осталось. null — если ключа нет или сервис недоступен.
  Future<Map<String, dynamic>?> status() async {
    final key = await savedKey();
    if (key == null) return null;
    try {
      final resp = await _dio.get<dynamic>(
        '${TunneloConfig.statusUrl}/$key',
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
