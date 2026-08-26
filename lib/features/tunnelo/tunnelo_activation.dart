import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
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

  /// Адреса, добытые через DoH. Живут до перезапуска приложения.
  static final Map<String, String> _dohCache = {};

  /// Резолв имени в обход системного DNS.
  ///
  /// Российские провайдеры режут UDP/53 к внешним резолверам — приложение
  /// тогда падает с «Failed host lookup» ещё до всякого туннеля. Спрашиваем
  /// адрес по HTTPS у резолвера, заданного IP-адресом: обычный DNS в этой
  /// цепочке не участвует вообще.
  static Future<String?> _resolveViaDoh(String host) async {
    final cached = _dohCache[host];
    if (cached != null) return cached;

    const resolvers = [
      'https://1.1.1.1/dns-query',
      'https://8.8.8.8/resolve',
    ];
    for (final resolver in resolvers) {
      try {
        final resp = await Dio().get<dynamic>(
          resolver,
          queryParameters: {'name': host, 'type': 'A'},
          options: Options(
            headers: {'accept': 'application/dns-json'},
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        final data = resp.data is String
            ? jsonDecode(resp.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(resp.data as Map);
        for (final answer in (data['Answer'] as List? ?? const [])) {
          final rec = Map<String, dynamic>.from(answer as Map);
          if (rec['type'] == 1) {
            final ip = rec['data'] as String;
            _dohCache[host] = ip;
            return ip;
          }
        }
      } catch (e) {
        debugPrint('[tunnelo-doh] резолвер $resolver не ответил: $e');
      }
    }
    return null;
  }

  /// Запрос к known-IP с правильным именем в TLS.
  ///
  /// Стандартный клиент Dart при подключении по IP не отправляет SNI —
  /// nginx на той стороне не понимает, какой сайт спрашивают, и отвечает
  /// «400 Bad Request» страницей. Поэтому соединение собираем руками:
  /// сокет на IP, TLS с именем хоста (сертификат проверяется как обычно),
  /// дальше обычный HTTP/1.1.
  static Future<Response<dynamic>> _requestViaIp(
    Uri uri,
    String ip, {
    Object? body,
  }) async {
    final port = uri.hasPort ? uri.port : 443;
    final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 12));
    SecureSocket? secure;
    try {
      secure = await SecureSocket.secure(socket, host: uri.host);

      final payload = body == null ? null : utf8.encode(jsonEncode(body));
      final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      final head = StringBuffer()
        ..write('${body == null ? 'GET' : 'POST'} $path HTTP/1.1\r\n')
        ..write('Host: ${uri.host}\r\n')
        ..write('User-Agent: Tunnelo\r\n')
        ..write('Accept: */*\r\n')
        ..write('Connection: close\r\n');
      if (payload != null) {
        head
          ..write('Content-Type: application/json\r\n')
          ..write('Content-Length: ${payload.length}\r\n');
      }
      head.write('\r\n');

      secure.add(utf8.encode(head.toString()));
      if (payload != null) secure.add(payload);
      await secure.flush();

      final bytes = <int>[];
      await secure.forEach(bytes.addAll).timeout(const Duration(seconds: 25));
      final raw = utf8.decode(bytes, allowMalformed: true);

      final split = raw.indexOf('\r\n\r\n');
      if (split < 0) throw const ActivationException('Пустой ответ сервера');
      final headers = raw.substring(0, split);
      var text = raw.substring(split + 4);
      if (headers.toLowerCase().contains('transfer-encoding: chunked')) {
        text = _dechunk(text);
      }
      final status = int.tryParse(
            RegExp(r'HTTP/1\.[01] (\d{3})').firstMatch(headers)?.group(1) ?? '',
          ) ??
          0;

      return Response<dynamic>(
        requestOptions: RequestOptions(path: uri.toString()),
        statusCode: status,
        data: text,
      );
    } finally {
      try {
        await secure?.close();
      } catch (_) {}
      socket.destroy();
    }
  }

  /// Сборка тела, разбитого на куски (Transfer-Encoding: chunked).
  static String _dechunk(String body) {
    final out = StringBuffer();
    var rest = body;
    while (true) {
      final eol = rest.indexOf('\r\n');
      if (eol <= 0) break;
      final size = int.tryParse(rest.substring(0, eol).trim(), radix: 16);
      if (size == null || size == 0) break;
      final start = eol + 2;
      if (start + size > rest.length) break;
      out.write(rest.substring(start, start + size));
      rest = rest.substring(start + size + 2);
    }
    final result = out.toString();
    return result.isEmpty ? body : result;
  }

  static bool _isDnsFailure(Object e) {
    final text = e.toString();
    return text.contains('Failed host lookup') ||
        text.contains('No address associated with hostname') ||
        text.contains('nodename nor servname');
  }

  /// Запрос с запасным путём: сначала как обычно, при отказе DNS —
  /// резолвим через DoH и повторяем по IP.
  Future<Response<dynamic>> _request(
    Uri uri, {
    Object? body,
    required Options options,
  }) async {
    try {
      return body == null
          ? await _dio.getUri<dynamic>(uri, options: options)
          : await _dio.postUri<dynamic>(uri, data: body, options: options);
    } catch (e) {
      debugPrint('[tunnelo-doh] прямой запрос к ${uri.host} упал: $e');
      if (!_isDnsFailure(e)) rethrow;
      final ip = await _resolveViaDoh(uri.host);
      if (ip == null) rethrow;
      return _requestViaIp(uri, ip, body: body);
    }
  }

  /// Скачать содержимое подписки самостоятельно.
  ///
  /// Нужно, когда системный DNS не работает: список серверов приходит
  /// текстом, и профиль создаётся из него, без обращения к имени хоста.
  Future<String?> fetchSubscription(String url) async {
    try {
      final resp = await _request(
        Uri.parse(url),
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 25),
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode != 200) return null;
      final text = resp.data?.toString();
      return (text == null || text.trim().isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }

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
