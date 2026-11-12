// Entry password (v1.0.4): KDF vectors, stored-record behaviour, and
// the ConfigStore set/verify/remove round-trip. The crypto is pinned
// against the published FIPS 180-4 / RFC 4231 / RFC 8018 test vectors —
// a hand-rolled KDF that cannot reproduce them does not ship.
import 'dart:convert';

import 'package:azm/data/config_store.dart';
import 'package:azm/data/privileged_channel.dart';
import 'package:azm/domain/entry_password.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SHA-256 (FIPS 180-4 vectors)', () {
    test('empty input', () {
      expect(
        hex(sha256(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
    test('"abc"', () {
      expect(
        hex(sha256(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
    test('56-byte two-block message', () {
      expect(
        hex(sha256(utf8.encode(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        ))),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });
    test('one million "a" (many blocks)', () {
      expect(
        hex(sha256(List.filled(1000000, 0x61))),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  group('HMAC-SHA-256 (RFC 4231 vectors)', () {
    test('case 1: 20-byte key', () {
      expect(
        hex(hmacSha256(List.filled(20, 0x0b), utf8.encode('Hi There'))),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });
    test('case 2: "Jefe"', () {
      expect(
        hex(hmacSha256(
          utf8.encode('Jefe'),
          utf8.encode('what do ya want for nothing?'),
        )),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });
    test('case 6: key longer than the block size is hashed first', () {
      expect(
        hex(hmacSha256(
          List.filled(131, 0xaa),
          utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'),
        )),
        '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
      );
    });
  });

  group('PBKDF2-HMAC-SHA256 (RFC 8018 vectors)', () {
    test('1 iteration', () {
      expect(
        hex(pbkdf2HmacSha256(
          password: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 1,
          keyLength: 32,
        )),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });
    test('2 iterations', () {
      expect(
        hex(pbkdf2HmacSha256(
          password: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 2,
          keyLength: 32,
        )),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });
    test('4096 iterations', () {
      expect(
        hex(pbkdf2HmacSha256(
          password: utf8.encode('password'),
          salt: utf8.encode('salt'),
          iterations: 4096,
          keyLength: 32,
        )),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('EntryPasswordHash record', () {
    test('create/verify round-trip; wrong password rejected', () {
      final record = EntryPasswordHash.create('hunter2!', iterations: 2000);
      expect(record.verify('hunter2!'), isTrue);
      expect(record.verify('hunter2'), isFalse);
      expect(record.verify('HUNTER2!'), isFalse);
      expect(record.verify(''), isFalse);
    });

    test('salts differ between records for the same password', () {
      final a = EntryPasswordHash.create('same-password', iterations: 500);
      final b = EntryPasswordHash.create('same-password', iterations: 500);
      expect(a.saltBase64, isNot(b.saltBase64));
      expect(a.hashBase64, isNot(b.hashBase64));
      expect(a.verify('same-password'), isTrue);
      expect(b.verify('same-password'), isTrue);
    });

    test('json round-trip preserves verification', () {
      final record = EntryPasswordHash.create('p@ssw0rd', iterations: 1500);
      final back = EntryPasswordHash.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
      );
      expect(back.iterations, 1500);
      expect(back.verify('p@ssw0rd'), isTrue);
      expect(back.verify('p@ssw0rd!'), isFalse);
    });

    test('a tampered stored hash never verifies', () {
      final record = EntryPasswordHash.create('secret1', iterations: 500);
      final tampered = EntryPasswordHash(
        saltBase64: record.saltBase64,
        hashBase64: base64.encode(List.filled(32, 7)),
        iterations: record.iterations,
      );
      expect(tampered.verify('secret1'), isFalse);
      const malformed = EntryPasswordHash(
        saltBase64: '!!!not-base64!!!',
        hashBase64: 'AAAA',
        iterations: 10,
      );
      expect(malformed.verify('secret1'), isFalse);
    });

    test('standard-strength derivation completes (benchmark)', () {
      final sw = Stopwatch()..start();
      final record = EntryPasswordHash.create('benchmark-password');
      final created = sw.elapsed;
      sw.reset();
      expect(record.verify('benchmark-password'), isTrue);
      // ignore: avoid_print
      print(
        'PBKDF2 210k iterations: create ${created.inMilliseconds} ms, '
        'verify ${sw.elapsed.inMilliseconds} ms (test VM)',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('ConfigStore entry password', () {
    const methodChannel = MethodChannel('azm/privileged');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final backing = <String, Object?>{};

    ConfigStore statefulStore() {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        final args = (call.arguments as Map).cast<String, Object?>();
        final slot = '${args['store']}/${args['key']}';
        switch (call.method) {
          case 'getSetting':
            return {'value': backing[slot]};
          case 'setSetting':
            backing[slot] = args['value'];
            return <String, Object?>{};
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
      return ConfigStore(PrivilegedChannel(methodChannel: methodChannel));
    }

    setUp(backing.clear);
    tearDown(() => messenger.setMockMethodCallHandler(methodChannel, null));

    test('set → isSet → verify correct/wrong → remove', () async {
      final store = statefulStore();
      expect(await store.isEntryPasswordSet(), isFalse);
      expect(await store.verifyEntryPassword('whatever1'), isFalse);

      await store.setEntryPassword('correct horse', iterations: 1000);
      expect(await store.isEntryPasswordSet(), isTrue);
      expect(await store.verifyEntryPassword('correct horse'), isTrue);
      expect(await store.verifyEntryPassword('correct hors'), isFalse);
      expect(await store.verifyEntryPassword(''), isFalse);

      // The stored value is a hash record — never the plaintext.
      final raw = backing['security_prefs/entry_password'] as String;
      expect(raw.contains('correct horse'), isFalse);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.keys, containsAll(['salt', 'hash', 'iterations']));

      await store.removeEntryPassword();
      expect(await store.isEntryPasswordSet(), isFalse);
      expect(await store.verifyEntryPassword('correct horse'), isFalse);
    });

    test('passwords shorter than the minimum are refused', () async {
      final store = statefulStore();
      await expectLater(
        store.setEntryPassword('12345', iterations: 100),
        throwsArgumentError,
      );
      expect(await store.isEntryPasswordSet(), isFalse);
      await store.setEntryPassword('123456', iterations: 100);
      expect(await store.isEntryPasswordSet(), isTrue);
    });

    test('setting a new password replaces the old one', () async {
      final store = statefulStore();
      await store.setEntryPassword('first-password', iterations: 800);
      await store.setEntryPassword('second-password', iterations: 800);
      expect(await store.verifyEntryPassword('first-password'), isFalse);
      expect(await store.verifyEntryPassword('second-password'), isTrue);
    });
  });
}
