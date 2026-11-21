import 'dart:convert';

/// Одна загрузка подписки: проверяем и применяем именно полученный ответ.
class RemoteProfileSource {
  const RemoteProfileSource({required this.content, required this.headers});

  final String content;
  final Map<String, dynamic> headers;

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
    return jsonEncode([content, metadata]);
  }
}
