import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/doh_fallback.dart';

/// Внутренний адаптер, который всегда падает заданной ошибкой.
class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter(this.error);
  final Object error;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    calls++;
    throw error;
  }

  @override
  void close({bool force = false}) {}
}

DioException _dnsError(RequestOptions options) => DioException.connectionError(
  requestOptions: options,
  reason: 'Failed host lookup',
  error: const SocketException("Failed host lookup: 'panel.amnez.online'"),
);

void main() {
  group('isDnsFailure', () {
    test('узнаёт отказ резолва и в чистом виде, и внутри DioException', () {
      const raw = SocketException("Failed host lookup: 'x' (OS Error: No address associated with hostname)");
      expect(DohFallback.isDnsFailure(raw), isTrue);
      expect(DohFallback.isDnsFailure(_dnsError(RequestOptions(path: 'https://x/'))), isTrue);
    });

    test('таймаут и отказ соединения — не про DNS', () {
      expect(DohFallback.isDnsFailure(const SocketException('Connection refused')), isFalse);
      expect(
        DohFallback.isDnsFailure(
          DioException.connectionTimeout(requestOptions: RequestOptions(path: 'https://x/'), timeout: Duration.zero),
        ),
        isFalse,
      );
    });
  });

  group('parseResponse', () {
    test('статус, заголовки в нижнем регистре, тело как есть', () {
      final raw = utf8.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: text/plain\r\n'
        'Subscription-Userinfo: upload=1; download=2; total=0; expire=0\r\n'
        'Set-Cookie: a=1\r\n'
        'Set-Cookie: b=2\r\n'
        '\r\n'
        'aHlzdGVyaWEy',
      );
      final r = DohFallback.parseResponse(raw);
      expect(r.statusCode, 200);
      expect(r.headers['subscription-userinfo'], ['upload=1; download=2; total=0; expire=0']);
      expect(r.headers['set-cookie'], ['a=1', 'b=2']);
      expect(utf8.decode(r.body), 'aHlzdGVyaWEy');
    });

    test('склеивает chunked-тело по байтам, а не по символам', () {
      // «Привет» — 12 байт в UTF-8, но 6 символов: размер куска считается в байтах.
      final body = utf8.encode('Привет');
      final raw = <int>[
        ...utf8.encode('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'),
        ...utf8.encode('${body.length.toRadixString(16)}\r\n'),
        ...body,
        ...utf8.encode('\r\n2\r\n!!\r\n0\r\n\r\n'),
      ];
      final r = DohFallback.parseResponse(raw);
      expect(utf8.decode(r.body), 'Привет!!');
    });

    test('без разделителя заголовков — ошибка, а не пустой успех', () {
      expect(() => DohFallback.parseResponse(utf8.encode('garbage')), throwsA(isA<HttpException>()));
    });
  });

  group('DohFallbackAdapter', () {
    final options = RequestOptions(
      path: 'https://panel.amnez.online/sub/abc',
      method: 'GET',
      headers: {'user-agent': 'Tunnelo/1.0'},
    );

    test('при отказе DNS резолвит через DoH и повторяет запрос по IP с заголовками', () async {
      final inner = _FailingAdapter(_dnsError(options));
      String? resolvedHost;
      Uri? requestedUri;
      String? requestedIp;
      Map<String, String>? sentHeaders;
      final adapter = DohFallbackAdapter(
        inner,
        probe: false,
        resolve: (host) {
          resolvedHost = host;
          return Future.value('78.17.33.149');
        },
        request: (uri, ip, {required method, required headers, body, connectTimeout, receiveTimeout}) {
          requestedUri = uri;
          requestedIp = ip;
          sentHeaders = headers;
          return Future.value(RawHttpResponse(
            statusCode: 200,
            headers: {
              'subscription-userinfo': ['upload=1; download=2; total=0; expire=0'],
            },
            body: Uint8List.fromList(utf8.encode('aHlzdGVyaWEy')),
          ));
        },
      );

      final rs = await adapter.fetch(options, null, null);
      expect(inner.calls, 1);
      expect(resolvedHost, 'panel.amnez.online');
      expect(requestedUri, Uri.parse('https://panel.amnez.online/sub/abc'));
      expect(requestedIp, '78.17.33.149');
      expect(sentHeaders?['user-agent'], 'Tunnelo/1.0');
      expect(rs.statusCode, 200);
      expect(rs.headers['subscription-userinfo'], ['upload=1; download=2; total=0; expire=0']);
      expect(utf8.decode(await rs.stream.fold<List<int>>([], (a, b) => a..addAll(b))), 'aHlzdGVyaWEy');
    });

    test('чужая ошибка уходит наверх, DoH не трогается', () async {
      final inner = _FailingAdapter(
        DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
          error: const SocketException('Connection refused'),
        ),
      );
      var resolves = 0;
      final adapter = DohFallbackAdapter(
        inner,
        probe: false,
        resolve: (_) {
          resolves++;
          return Future.value('1.2.3.4');
        },
        request: (uri, ip, {required method, required headers, body, connectTimeout, receiveTimeout}) =>
            throw StateError('не должно вызываться'),
      );
      await expectLater(adapter.fetch(options, null, null), throwsA(isA<DioException>()));
      expect(resolves, 0);
    });

    test('если DoH не нашёл адрес — исходная ошибка DNS уходит наверх', () async {
      final inner = _FailingAdapter(_dnsError(options));
      final adapter = DohFallbackAdapter(
        inner,
        probe: false,
        resolve: (_) => Future.value(),
        request: (uri, ip, {required method, required headers, body, connectTimeout, receiveTimeout}) =>
            throw StateError('не должно вызываться'),
      );
      await expectLater(adapter.fetch(options, null, null), throwsA(isA<DioException>()));
    });
  });

  group('проба системного DNS', () {
    final options = RequestOptions(path: 'https://panel.amnez.online/sub/abc', method: 'GET');
    final ok = RawHttpResponse(statusCode: 200, headers: const {}, body: Uint8List(0));

    test('резолв висит дольше лимита — обычный клиент не трогаем, сразу DoH', () async {
      final inner = _FailingAdapter(StateError('обычный клиент не должен вызываться'));
      var requests = 0;
      final adapter = DohFallbackAdapter(
        inner,
        probeTimeout: const Duration(milliseconds: 20),
        lookup: (_) => Completer<List<InternetAddress>>().future, // висит вечно
        resolve: (_) => Future.value('78.17.33.149'),
        request: (uri, ip, {required method, required headers, body, connectTimeout, receiveTimeout}) {
          requests++;
          return Future.value(ok);
        },
      );
      final rs = await adapter.fetch(options, null, null);
      expect(inner.calls, 0);
      expect(requests, 1);
      expect(rs.statusCode, 200);
    });

    test('резолв отвечает — идём обычным путём', () async {
      var innerCalls = 0;
      final adapter = DohFallbackAdapter(
        _CountingAdapter(() => innerCalls++),
        lookup: (_) => Future.value([InternetAddress('78.17.33.149')]),
        resolve: (_) => throw StateError('DoH не нужен'),
        request: (uri, ip, {required method, required headers, body, connectTimeout, receiveTimeout}) =>
            throw StateError('запрос по IP не нужен'),
      );
      final rs = await adapter.fetch(options, null, null);
      expect(innerCalls, 1);
      expect(rs.statusCode, 200);
    });

    test('хост задан IP-адресом — пробы нет', () async {
      var innerCalls = 0;
      final adapter = DohFallbackAdapter(
        _CountingAdapter(() => innerCalls++),
        lookup: (_) => throw StateError('резолвить IP незачем'),
      );
      await adapter.fetch(RequestOptions(path: 'https://1.1.1.1/dns-query'), null, null);
      expect(innerCalls, 1);
    });
  });
}

/// Внутренний адаптер, который считает вызовы и отвечает 200.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(this.onCall);
  final void Function() onCall;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    onCall();
    return Future.value(ResponseBody.fromBytes(Uint8List(0), 200));
  }

  @override
  void close({bool force = false}) {}
}
