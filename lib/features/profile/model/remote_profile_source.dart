import 'dart:convert';

/// Одна загрузка подписки: проверяем и применяем именно полученный ответ.
class RemoteProfileSource {
  const RemoteProfileSource({required this.content, required this.headers});

  final String content;
  final Map<String, dynamic> headers;

  /// JSON formatting and object key order do not change a connection.
  /// Array order is meaningful (server priority and routing rules).
  static String configurationVersion(String content) {
    final trimmed = content.trim();
    try {
      return jsonEncode(_canonical(jsonDecode(trimmed)));
    } on FormatException {
      return trimmed;
    }
  }

  static dynamic _canonical(dynamic value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  /// A parser can accept an empty JSON object. It must never replace a
  /// working VPN subscription with a configuration containing no servers.
  static bool hasServers(String parsedConfig) {
    final config = jsonDecode(parsedConfig);
    if (config is! Map<String, dynamic>) return false;
    const virtualTypes = {'direct', 'block', 'dns', 'selector', 'urltest', 'loadbalance'};
    return [config['outbounds'], config['endpoints']]
        .whereType<List>()
        .expand((v) => v)
        .any((v) => v is Map && v['type'] is String && !virtualTypes.contains(v['type']));
  }

  /// Счётчики трафика меняются постоянно и не требуют перезапуска ядра.
  /// Срок, лимит, заголовок и настройки подключения входят в версию.
  String get fingerprint {
    final metadata = <String, dynamic>{};
    final keys = headers.keys.toList()..sort();
    for (final key in keys) {
      if (key == 'subscription-userinfo') {
        final parts = headers[key].toString().split(';').map((s) => s.trim()).where((s) {
          final name = s.split('=').first.trim();
          return name == 'total' || name == 'expire';
        }).toList()..sort();
        metadata[key] = parts;
      } else {
        metadata[key] = headers[key];
      }
    }
    return jsonEncode([configurationVersion(content), metadata]);
  }
}
