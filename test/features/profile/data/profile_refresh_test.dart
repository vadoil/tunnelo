import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/remote_profile_source.dart';
import 'package:hiddify/features/settings/data/config_option_data_providers.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const oldConfig = '{"outbounds":[{"type":"hysteria2","tag":"DE","server":"old.example","server_port":443}]}';
const newConfig = '{"outbounds":[{"type":"hysteria2","tag":"DE","server":"new.example","server_port":8443}]}';

class _Core implements HiddifyCoreService {
  final paths = <String>[];
  Future<void> Function()? beforeValidate;

  @override
  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) =>
      TaskEither.tryCatch(() async {
        paths.add(path);
        await beforeValidate?.call();
        // Model the core parser's validated JSON output, including its acceptance
        // of an empty object; repository tests must reject that unsafe result.
        final data = jsonDecode(await File(tempPath).readAsString());
        await File(path).writeAsString(jsonEncode(data));
        return unit;
      }, (e, _) => e.toString());

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected runtime-core mutation: $invocation');
}

class _Dao extends ProfileDao {
  _Dao(super.db);
  bool failCommit = false;
  int failuresRemaining = 0;

  @override
  Future<bool> editIfUnchanged(
    ProfileEntry expected,
    ProfileEntriesCompanion entry,
    Future<void> Function() commitConfig,
  ) => transaction(() async {
    final applied = await super.editIfUnchanged(expected, entry, commitConfig);
    if (failCommit || failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('simulated database commit failure');
    }
    return applied;
  });
}

void main() {
  late Directory directory;
  late Db db;
  late _Dao dao;
  late _Core core;
  late ProfilePathResolver paths;
  late ProfileRepositoryImpl repository;
  late RemoteProfileEntity profile;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWith(
          (ref) => DioHttpClient(timeout: const Duration(seconds: 1), userAgent: 'test', debug: false),
        ),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    directory = await Directory.systemTemp.createTemp('tunnelo-refresh-');
    paths = ProfilePathResolver(directory);
    db = Db(NativeDatabase.memory());
    dao = _Dao(db);
    core = _Core();
    repository = ProfileRepositoryImpl(
      profileDataSource: dao,
      profilePathResolver: paths,
      singbox: core,
      configOptionRepository: container.read(configOptionRepositoryProvider),
      profileParser: container.read(profileParserProvider),
    );
    (await repository.init().run()).getOrElse((e) => throw e);
    profile = RemoteProfileEntity(
      id: 'id',
      active: true,
      name: 'Servers',
      populatedHeaders: const {},
      url: 'https://api.amnez.online/sub/test',
      lastUpdate: DateTime(2020),
    );
    await dao.insert(profile.toInsertEntry());
    await paths.file(profile.id).writeAsString(oldConfig);
    profile = (await dao.getById(profile.id))!.toEntity() as RemoteProfileEntity;
  });

  tearDown(() async {
    await db.close();
    container.dispose();
    await directory.delete(recursive: true);
  });

  Future<ProfileRefreshResult?> refresh(
    String content, {
    Map<String, dynamic> headers = const {},
    CancelToken? token,
  }) async =>
      (await repository
              .refreshRemote(
                profile,
                source: RemoteProfileSource(content: content, headers: headers),
                cancelToken: token,
              )
              .run())
          .getOrElse((e) => throw e);

  Future<void> expectNoStaging() async =>
      expect((await paths.directory.list().toList()).map((f) => f.path), [paths.file('id').path]);

  test('validates and atomically replaces server parameters without changing runtime options', () async {
    final result = await refresh(newConfig);
    expect(result?.configurationChanged, isTrue);
    expect(jsonDecode(await paths.file('id').readAsString()), jsonDecode(newConfig));
    expect((await dao.getById('id'))!.lastUpdate.isAfter(profile.lastUpdate), isTrue);
    await expectNoStaging();
  });

  test('formatting and metadata update the profile without rewriting its configuration', () async {
    final result = await refresh(
      const JsonEncoder.withIndent('  ').convert(jsonDecode(oldConfig)),
      headers: {'profile-title': 'New title'},
    );
    expect(result?.configurationChanged, isFalse);
    expect((await dao.getById('id'))!.name, 'New title');
    expect(await paths.file('id').readAsString(), oldConfig);
    await expectNoStaging();
  });

  for (final invalid in ['<html>gateway error</html>', '{}', '{"outbounds":[]}', '{"outbounds":[{"type":"direct"}]}']) {
    test('rejects an invalid or empty server response: $invalid', () async {
      final result = await repository
          .refreshRemote(
            profile,
            source: RemoteProfileSource(content: invalid, headers: const {}),
          )
          .run();
      expect(result.isLeft(), isTrue);
      expect(await paths.file('id').readAsString(), oldConfig);
      expect((await dao.getById('id'))!.lastUpdate, profile.lastUpdate);
      await expectNoStaging();
    });
  }

  test('does not recreate a profile deleted while validation was running', () async {
    core.beforeValidate = () async {
      (await repository.deleteById('id', false).run()).getOrElse((e) => throw e);
    };
    expect(await refresh(newConfig), isNull);
    expect(await dao.getById('id'), isNull);
    expect(await paths.directory.list().toList(), isEmpty);
  });

  test('discards an answer when the user changes settings while it is being validated', () async {
    core.beforeValidate = () =>
        dao.edit('id', ProfileEntriesCompanion(userOverride: Value(const UserOverride(name: 'My servers').toStr())));
    expect(await refresh(newConfig), isNull);
    expect(await paths.file('id').readAsString(), oldConfig);
    expect((await dao.getById('id'))!.toEntity().userOverride?.name, 'My servers');
    await expectNoStaging();
  });

  test('allows switching profiles without switching back after an update', () async {
    core.beforeValidate = () => dao.edit('id', const ProfileEntriesCompanion(active: Value(false)));
    expect((await refresh(newConfig))?.configurationChanged, isTrue);
    expect((await dao.getById('id'))!.active, isFalse);
  });

  test('rolls back the file if the database commit fails', () async {
    dao.failCommit = true;
    final result = await repository
        .refreshRemote(
          profile,
          source: const RemoteProfileSource(content: newConfig, headers: {}),
        )
        .run();
    expect(result.isLeft(), isTrue);
    expect(await paths.file('id').readAsString(), oldConfig);
    expect((await dao.getById('id'))!.lastUpdate, profile.lastUpdate);
    await expectNoStaging();
  });

  test('cancelling validation preserves the working configuration', () async {
    final token = CancelToken();
    core.beforeValidate = () async => token.cancel();
    final result = await repository
        .refreshRemote(
          profile,
          source: const RemoteProfileSource(content: newConfig, headers: {}),
          cancelToken: token,
        )
        .run();
    expect(result.isLeft(), isTrue);
    expect(await paths.file('id').readAsString(), oldConfig);
    await expectNoStaging();
  });

  test('concurrent refreshes use separate files and only one matching snapshot commits', () async {
    final gate = Completer<void>();
    core.beforeValidate = () => gate.future;
    final first = refresh(newConfig);
    final second = refresh(newConfig);
    while (core.paths.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(core.paths.toSet(), hasLength(2));
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results.whereType<ProfileRefreshResult>(), hasLength(1));
    expect(jsonDecode(await paths.file('id').readAsString()), jsonDecode(newConfig));
    await expectNoStaging();
  });

  test('rollback cannot overwrite a successful concurrent refresh', () async {
    dao.failuresRemaining = 1;
    final gate = Completer<void>();
    core.beforeValidate = () => gate.future;
    final first = repository
        .refreshRemote(
          profile,
          source: const RemoteProfileSource(content: oldConfig, headers: {'enable-fragment': 'true'}),
        )
        .run();
    final second = repository
        .refreshRemote(
          profile,
          source: const RemoteProfileSource(content: newConfig, headers: {}),
        )
        .run();
    while (core.paths.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results.where((r) => r.isLeft()), hasLength(1));
    expect(jsonDecode(await paths.file('id').readAsString()), jsonDecode(newConfig));
    await expectNoStaging();
  });

  test('manual import updates the exact existing subscription and preserves its ID', () async {
    final result = await repository
        .upsertRemote(
          profile.url,
          source: const RemoteProfileSource(content: newConfig, headers: {}),
        )
        .run();
    expect(result.isRight(), isTrue);
    expect((await dao.getByUrl(profile.url))?.id, 'id');
    expect(jsonDecode(await paths.file('id').readAsString()), jsonDecode(newConfig));
  });

  test('new subscription uses the same validated staging pipeline', () async {
    final result = await repository
        .upsertRemote(
          'https://api.amnez.online/sub/another',
          source: const RemoteProfileSource(content: newConfig, headers: {}),
        )
        .run();
    expect(result.isRight(), isTrue);
    final added = await dao.getByUrl('https://api.amnez.online/sub/another');
    expect(added, isNotNull);
    expect(added!.id, isNot('id'));
    expect(jsonDecode(await paths.file(added.id).readAsString()), jsonDecode(newConfig));
    expect(await paths.directory.list().toList(), hasLength(2));
  });

  test('URL lookup matches exact subscription keys including SQL wildcard characters', () async {
    expect(await dao.getByUrl('https://api.amnez.online/sub/tes'), isNull);
    expect(await dao.getByUrl('https://api.amnez.online/sub/te%'), isNull);
    expect((await dao.getByUrl(profile.url))?.id, 'id');
  });
}
