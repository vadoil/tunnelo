import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/app_update/data/app_update_repository.dart';

void main() {
  final json = <String, dynamic>{
    'version': '1.0.27',
    'build': 10027,
    'published': '2026-09-14T15:00:00+00:00',
    'downloads': {
      'android': 'https://api.amnez.online/dl/Tunnelo-1.0.27.apk',
      'windows': 'https://api.amnez.online/dl/Tunnelo-Setup-1.0.27.exe',
    },
  };

  test('latest.json → версия и ссылка своей платформы', () {
    final v = AppUpdateRepositoryImpl.parseLatest(json, 'windows')!;
    expect(v.version, '1.0.27');
    expect(v.buildNumber, '10027');
    expect(v.url, 'https://api.amnez.online/dl/Tunnelo-Setup-1.0.27.exe');
    expect(v.preRelease, isFalse);
    expect(v.presentVersion, '1.0.27');
  });

  test('нет ссылки для платформы — обновляться некуда', () {
    expect(AppUpdateRepositoryImpl.parseLatest(json, 'ios'), isNull);
  });

  test('без версии — ничего', () {
    expect(AppUpdateRepositoryImpl.parseLatest({'downloads': {}}, 'android'), isNull);
  });
}
