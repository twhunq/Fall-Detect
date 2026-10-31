import 'dart:convert';

import 'package:bao_nga_iot/services/firebase_auth_client.dart';
import 'package:bao_nga_iot/services/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeStore extends SecureStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  test('restore clears a stale session when the store was emptied', () async {
    final store = FakeStore();
    store.data[TokenManager.storeKey] = jsonEncode(FirebaseSession(
      uid: 'u1',
      email: 'a@x.vn',
      idToken: 't',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ).toJson());
    final tm = TokenManager(FirebaseAuthClient(), store);
    expect((await tm.restore())?.uid, 'u1');
    expect(tm.signedIn, isTrue);

    final events = <FirebaseSession?>[];
    tm.changes.listen(events.add);
    store.data.clear();
    expect(await tm.restore(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(tm.signedIn, isFalse);
    expect(events, [null]);
  });
}
