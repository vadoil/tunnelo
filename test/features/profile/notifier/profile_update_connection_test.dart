import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Connection extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Connected());
  void setStatus(ConnectionStatus status) => state = AsyncData(status);
}

class _Repository implements ConnectionRepository {
  int restarts = 0;
  int stops = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity profile, bool disableMemoryLimit) => TaskEither(() async {
    restarts++;
    await gate?.future;
    return fail ? left(const ConnectionFailure.unexpected()) : right(unit);
  });
  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => TaskEither(() async {
    stops++;
    return right(unit);
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected operation: $invocation');
}

void main() {
  late ProviderContainer container;
  late _Connection connection;
  late _Repository repository;
  final profile = RemoteProfileEntity(
    id: 'profile',
    active: true,
    name: 'Servers',
    url: 'https://api.amnez.online/sub/test',
    lastUpdate: DateTime(2020),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({'started_by_user': true});
    repository = _Repository();
    connection = _Connection();
    container = ProviderContainer(
      overrides: [
        connectionNotifierProvider.overrideWith(() => connection),
        connectionRepositoryProvider.overrideWithValue(repository),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(Preferences.startedByUser.notifier).update(true);
    await container.read(connectionNotifierProvider.future);
  });
  tearDown(() => container.dispose());

  test('defers updates during connection transitions and retries when connected', () async {
    for (final status in [const Connecting(), const Disconnecting()]) {
      connection.setStatus(status);
      expect(await connection.applyProfileUpdate(profile), isFalse);
    }
    expect(repository.restarts, 0);
    connection.setStatus(const Connected());
    expect(await connection.applyProfileUpdate(profile), isTrue);
    expect(repository.restarts, 1);
  });

  test('returns failure without a dialog so a pending update can retry', () async {
    repository.fail = true;
    expect(await connection.applyProfileUpdate(profile), isFalse);
    expect(container.read(Preferences.startedByUser), isTrue);
    repository.fail = false;
    expect(await connection.applyProfileUpdate(profile), isTrue);
  });

  test('an update never enables a VPN the user has turned off', () async {
    await container.read(Preferences.startedByUser.notifier).update(false);
    expect(await connection.applyProfileUpdate(profile), isFalse);
    expect(repository.restarts, 0);
    connection.setStatus(const Disconnected());
    expect(await connection.applyProfileUpdate(profile), isTrue);
    expect(repository.restarts, 0);
  });

  test('turning off during a reload remains off after the reload finishes', () async {
    repository.gate = Completer<void>();
    final applying = connection.applyProfileUpdate(profile);
    while (repository.restarts == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await container.read(Preferences.startedByUser.notifier).update(false);
    repository.gate!.complete();
    expect(await applying, isFalse);
    expect(repository.stops, 1);
    expect(container.read(Preferences.startedByUser), isFalse);
  });
}
