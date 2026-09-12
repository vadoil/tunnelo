import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/utils/custom_loggers.dart';

/// Разобранный HTTP-ответ, полученный по запасному пути.
class RawHttpResponse {
  const RawHttpResponse({required this.statusCode, required this.headers, required this.body});

  final int statusCode;

  /// Имена заголовков в нижнем регистре — как отдаёт их и обычный клиент.
  final Map<String, List<String>> headers;
  final Uint8List body;

  String get text => utf8.decode(body, allowMalformed: true);
}

typedef DohResolve = Future<String?> Function(String host);
typedef SystemLookup = Future<List<InternetAddress>> Function(String host);
typedef RawRequest =
    Future<RawHttpResponse> Function(
      Uri uri,
      String ip, {
      required String method,
      required Map<String, String> headers,
      List<int>? body,
      Duration? connectTimeout,
      Duration? receiveTimeout,
    });

/// Запасной путь для HTTP, когда системный DNS не отвечает.
///
/// Российские провайдеры режут UDP/53 к внешним резолверам, и приложение
/// падает с «Failed host lookup» ещё до всякого туннеля. Имя спрашиваем по
/// HTTPS у резолвера, заданного IP-адресом, а запрос отправляем на
/// полученный IP с правильным именем в TLS (SNI): обычный DNS в этой
/// цепочке не участвует вообще.
abstract class DohFallback {
  /// Адреса, добытые через DoH. Живут до перезапуска приложения.
  static final Map<String, String> _cache = {};

  static const _resolvers = ['https://1.1.1.1/dns-query', 'https://8.8.8.8/resolve'];

  /// Адрес, уже добытый через DoH для этого хоста, если был.
  static String? cached(String host) => _cache[host];

  /// Это отказ резолва имени, а не таймаут и не отказ соединения.
  static bool isDnsFailure(Object e) {
    final text = e is DioException ? '${e.message} ${e.error}' : e.toString();
    return text.contains('Failed host lookup') ||
        text.contains('No address associated with hostname') ||
        text.contains('nodename nor servname');
  }

  /// Резолв имени через DoH. null — ни один резолвер не ответил.
  static Future<String?> resolve(String host) async {
    final cached = _cache[host];
    if (cached != null) return cached;

    for (final resolver in _resolvers) {
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
            _cache[host] = ip;
            return ip;
          }
        }
      } catch (e) {
        debugPrint('[tunnelo-doh] резолвер $resolver не ответил: $e');
      }
    }
    return null;
  }

  /// Запрос к известному IP с правильным именем в TLS.
  ///
  /// Стандартный клиент Dart при подключении по IP не отправляет SNI —
  /// nginx на той стороне не понимает, какой сайт спрашивают, и отвечает
  /// «400 Bad Request» страницей. Поэтому соединение собираем руками:
  /// сокет на IP, TLS с именем хоста (сертификат проверяется как обычно),
  /// дальше обычный HTTP/1.1 с `Connection: close`.
  static Future<RawHttpResponse> request(
    Uri uri,
    String ip, {
    required String method,
    required Map<String, String> headers,
    List<int>? body,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) async {
    final plain = uri.scheme == 'http';
    final port = uri.hasPort ? uri.port : (plain ? 80 : 443);
    final socket = await Socket.connect(ip, port, timeout: connectTimeout ?? const Duration(seconds: 12));
    SecureSocket? secure;
    try {
      final Socket channel = plain ? socket : (secure = await SecureSocket.secure(socket, host: uri.host));

      final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      final head = StringBuffer()
        ..write('$method ${path.isEmpty ? '/' : path} HTTP/1.1\r\n')
        ..write('Host: ${uri.host}\r\n')
        ..write('Connection: close\r\n');
      var hasAccept = false;
      headers.forEach((name, value) {
        switch (name.toLowerCase()) {
          // Эти выставляем сами: длину считаем по телу, сжатие не просим —
          // распаковывать ответ здесь нечем.
          case 'host' || 'connection' || 'content-length' || 'accept-encoding':
            return;
          case 'accept':
            hasAccept = true;
        }
        head.write('$name: $value\r\n');
      });
      if (!hasAccept) head.write('Accept: */*\r\n');
      if (body != null) head.write('Content-Length: ${body.length}\r\n');
      head.write('\r\n');

      channel.add(utf8.encode(head.toString()));
      if (body != null) channel.add(body);
      await channel.flush();

      final bytes = BytesBuilder(copy: false);
      await channel.forEach(bytes.add).timeout(receiveTimeout ?? const Duration(seconds: 25));
      return parseResponse(bytes.takeBytes());
    } finally {
      try {
        await secure?.close();
      } catch (_) {}
      socket.destroy();
    }
  }

  static const _crlf = [13, 10];
  static const _crlfCrlf = [13, 10, 13, 10];

  /// Разбор сырого ответа HTTP/1.1: статус, заголовки, тело.
  ///
  /// Тело, разбитое на куски (`Transfer-Encoding: chunked`), склеивается
  /// по байтам — размер куска сервер считает в байтах, не в символах.
  @visibleForTesting
  static RawHttpResponse parseResponse(List<int> raw) {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final split = _indexOf(bytes, _crlfCrlf);
    if (split < 0) throw const HttpException('Пустой или оборванный ответ сервера');

    final lines = utf8.decode(bytes.sublist(0, split), allowMalformed: true).split('\r\n');
    final status = int.tryParse(RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(lines.first)?.group(1) ?? '') ?? 0;
    final headers = <String, List<String>>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers.putIfAbsent(line.substring(0, colon).trim().toLowerCase(), () => []).add(line.substring(colon + 1).trim());
    }

    var body = Uint8List.sublistView(bytes, split + 4);
    if ((headers['transfer-encoding'] ?? const []).any((v) => v.toLowerCase().contains('chunked'))) {
      body = _dechunk(body);
    }
    return RawHttpResponse(statusCode: status, headers: headers, body: body);
  }

  static Uint8List _dechunk(Uint8List data) {
    final out = BytesBuilder(copy: false);
    var pos = 0;
    while (true) {
      final eol = _indexOf(data, _crlf, pos);
      if (eol < 0) break;
      final sizeText = ascii.decode(data.sublist(pos, eol), allowInvalid: true).split(';').first.trim();
      final size = int.tryParse(sizeText, radix: 16);
      if (size == null || size == 0) break;
      final start = eol + 2;
      if (start + size > data.length) {
        // Оборванный кусок: отдаём, что дошло, — лучше, чем ничего.
        out.add(data.sublist(start));
        break;
      }
      out.add(data.sublist(start, start + size));
      pos = start + size + 2;
    }
    return out.takeBytes();
  }

  static int _indexOf(Uint8List hay, List<int> needle, [int from = 0]) {
    for (var i = from; i + needle.length <= hay.length; i++) {
      var j = 0;
      while (j < needle.length && hay[i + j] == needle[j]) {
        j++;
      }
      if (j == needle.length) return i;
    }
    return -1;
  }
}

/// Адаптер Dio: обычный путь, а при отказе DNS — [DohFallback].
///
/// Через него ходят и загрузчик профилей, и клиент активации. Подписка
/// скачивается вместе с заголовками (`subscription-userinfo` и прочими),
/// поэтому профиль остаётся удалённым — с данными подписки и обновлением
/// по расписанию, а не слепком списка серверов.
///
/// Ждать, пока обычный клиент сам упадёт на DNS, нельзя: когда UDP/53
/// режут, резолв не отказывает, а висит — дольше таймаута соединения, и
/// наружу выходит «timed out», а не «Failed host lookup». Поэтому при
/// [probe] адаптер сперва сам пробует резолв с коротким лимитом и при
/// отказе сразу идёт через DoH. Для клиентов, которые ходят через локальный
/// прокси, пробу выключают: там имя резолвит прокси.
class DohFallbackAdapter with InfraLogger implements HttpClientAdapter {
  DohFallbackAdapter(
    this._inner, {
    this.probe = true,
    this.probeTimeout = const Duration(seconds: 4),
    SystemLookup? lookup,
    DohResolve? resolve,
    RawRequest? request,
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _resolve = resolve ?? DohFallback.resolve,
       _request = request ?? DohFallback.request;

  final HttpClientAdapter _inner;
  final bool probe;

  /// Здоровый резолв укладывается в доли секунды; четыре — с запасом.
  final Duration probeTimeout;
  final SystemLookup _lookup;
  final DohResolve _resolve;
  final RawRequest _request;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final host = options.uri.host;
    if (probe && InternetAddress.tryParse(host) == null && !await _systemDnsWorks(host)) {
      final ip = await _resolve(host);
      if (ip != null) return _viaIp(options, requestStream, ip);
      loggy.warning('DoH не нашёл $host — пусть обычный путь упадёт своей ошибкой');
    }

    try {
      return await _inner.fetch(options, requestStream, cancelFuture);
    } catch (e) {
      if (!DohFallback.isDnsFailure(e)) rethrow;
      loggy.info('DNS не ответил для $host, иду через DoH');
      final ip = await _resolve(host);
      if (ip == null) rethrow;
      return _viaIp(options, requestStream, ip);
    }
  }

  Future<bool> _systemDnsWorks(String host) async {
    // Уже знаем, что системный DNS тут не помог: не ждём его снова.
    if (DohFallback.cached(host) != null) return false;
    try {
      final result = await _lookup(host).timeout(probeTimeout);
      return result.isNotEmpty;
    } catch (e) {
      loggy.info('системный резолв $host не ответил ($e), иду через DoH');
      return false;
    }
  }

  Future<ResponseBody> _viaIp(RequestOptions options, Stream<Uint8List>? requestStream, String ip) async {
    loggy.info('${options.method} ${options.uri.host} → $ip по DoH');
    // Тело запроса ещё не тронуто: обычный клиент падает на соединении,
    // до отправки данных.
    final body = requestStream == null ? null : await _collect(requestStream);
    final headers = <String, String>{
      for (final h in options.headers.entries)
        if (h.value != null) h.key: h.value.toString(),
    };
    final r = await _request(
      options.uri,
      ip,
      method: options.method,
      headers: headers,
      body: body,
      connectTimeout: options.connectTimeout,
      receiveTimeout: options.receiveTimeout,
    );
    return ResponseBody.fromBytes(r.body, r.statusCode, headers: r.headers);
  }

  static Future<Uint8List> _collect(Stream<Uint8List> stream) async {
    final out = BytesBuilder(copy: false);
    await stream.forEach(out.add);
    return out.takeBytes();
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
