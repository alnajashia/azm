/// App entry password crypto (v1.0.4).
///
/// The entry password is an OPTIONAL, user-set alternative way to open
/// the app from the lock screen (alongside biometric / device
/// credential). It opens the app only — it never opens a recovery
/// session and can never loosen a restriction.
///
/// Storage discipline mirrors the native recovery-code store
/// (`security/RecoveryStore.kt`, ARCH §7.1): only a salted
/// PBKDF2-HMAC-SHA256 hash is persisted — 210,000 iterations, a 16-byte
/// per-password random salt, a 32-byte derived key, Base64 fields plus
/// the iteration count — and verification recomputes the derivation and
/// compares in constant time. The plaintext password is never stored,
/// logged or sent anywhere.
///
/// The KDF runs in Dart (the record lives in the Dart-side
/// SharedPreferences-backed config store, like every other UI/domain
/// setting), so SHA-256 / HMAC / PBKDF2 are implemented here from their
/// public specifications (FIPS 180-4, RFC 2104, RFC 8018) and pinned by
/// published test vectors in `test/entry_password_test.dart`. The HMAC
/// implementation caches the padded-key compression states, which
/// halves the per-iteration cost of PBKDF2 (the pad block of every
/// iteration is identical).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// The minimum entry-password length, in characters.
const int entryPasswordMinLength = 6;

/// Anti-guess delay after [failures] consecutive wrong entry-password
/// attempts: 2 s × failures, capped at 30 s. The failure count is
/// persisted (see `ConfigStore`), so the delay survives dialog
/// dismissal and process death — it is not a UI-only counter
/// (v1.0.5 audit B-3).
int entryPasswordDelaySeconds(int failures) {
  if (failures <= 0) return 0;
  final seconds = 2 * failures;
  return seconds > 30 ? 30 : seconds;
}

/// Whether a stored entry-password record exists and parses
/// (v1.0.5 audit B-9): a corrupt record is reported as [corrupt],
/// never silently treated as "no password set".
enum EntryPasswordRecordState { unset, set, corrupt }

// ------------------------------------------------------------------ SHA-256

const List<int> _sha256K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const List<int> _sha256Initial = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

/// One SHA-256 compression of the 64-byte block at [offset] in [block],
/// updating the running state [h] in place (FIPS 180-4 §6.2.2).
void _compress(Uint32List h, List<int> block, int offset) {
  final w = Uint32List(64);
  for (var i = 0; i < 16; i++) {
    final j = offset + i * 4;
    w[i] = (block[j] << 24) | (block[j + 1] << 16) | (block[j + 2] << 8) | block[j + 3];
  }
  for (var i = 16; i < 64; i++) {
    final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
  }
  var a = h[0], b = h[1], c = h[2], d = h[3];
  var e = h[4], f = h[5], g = h[6], hh = h[7];
  for (var i = 0; i < 64; i++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ (~e & g);
    final t1 = (hh + s1 + ch + _sha256K[i] + w[i]) & 0xFFFFFFFF;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (s0 + maj) & 0xFFFFFFFF;
    hh = g;
    g = f;
    f = e;
    e = (d + t1) & 0xFFFFFFFF;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & 0xFFFFFFFF;
  }
  h[0] = (h[0] + a) & 0xFFFFFFFF;
  h[1] = (h[1] + b) & 0xFFFFFFFF;
  h[2] = (h[2] + c) & 0xFFFFFFFF;
  h[3] = (h[3] + d) & 0xFFFFFFFF;
  h[4] = (h[4] + e) & 0xFFFFFFFF;
  h[5] = (h[5] + f) & 0xFFFFFFFF;
  h[6] = (h[6] + g) & 0xFFFFFFFF;
  h[7] = (h[7] + hh) & 0xFFFFFFFF;
}

/// Finishes a digest whose first [baseLength] bytes (a multiple of 64)
/// were already compressed into [baseState], by hashing [tail] with the
/// standard padding for the total length.
Uint8List _finishFromState(Uint32List baseState, int baseLength, List<int> tail) {
  final h = Uint32List.fromList(baseState);
  final totalLength = baseLength + tail.length;
  // Tail plus padding: 0x80, zeros, and the 64-bit big-endian bit
  // length — one or two final blocks.
  final paddedTailLength = ((tail.length + 9 + 63) ~/ 64) * 64;
  final padded = Uint8List(paddedTailLength);
  padded.setRange(0, tail.length, tail);
  padded[tail.length] = 0x80;
  ByteData.view(padded.buffer)
      .setUint64(paddedTailLength - 8, totalLength * 8, Endian.big);
  for (var offset = 0; offset < paddedTailLength; offset += 64) {
    _compress(h, padded, offset);
  }
  final out = Uint8List(32);
  final view = ByteData.view(out.buffer);
  for (var i = 0; i < 8; i++) {
    view.setUint32(i * 4, h[i], Endian.big);
  }
  return out;
}

/// SHA-256 (FIPS 180-4) over [data]; returns the 32-byte digest.
Uint8List sha256(List<int> data) =>
    _finishFromState(Uint32List.fromList(_sha256Initial), 0, data);

/// HMAC-SHA-256 (RFC 2104) with cached padded-key states: constructing
/// one instance per PBKDF2 run makes every iteration cost two block
/// compressions instead of four.
class HmacSha256 {
  HmacSha256(List<int> key) {
    final effectiveKey = key.length > 64 ? sha256(key) : key;
    final innerBlock = Uint8List(64);
    final outerBlock = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      final k = i < effectiveKey.length ? effectiveKey[i] : 0;
      innerBlock[i] = k ^ 0x36;
      outerBlock[i] = k ^ 0x5C;
    }
    _innerBase = Uint32List.fromList(_sha256Initial);
    _compress(_innerBase, innerBlock, 0);
    _outerBase = Uint32List.fromList(_sha256Initial);
    _compress(_outerBase, outerBlock, 0);
  }

  late final Uint32List _innerBase;
  late final Uint32List _outerBase;

  /// The 32-byte MAC of [message] under this instance's key.
  Uint8List mac(List<int> message) {
    final innerHash = _finishFromState(_innerBase, 64, message);
    return _finishFromState(_outerBase, 64, innerHash);
  }
}

/// One-shot HMAC-SHA-256 (RFC 2104).
Uint8List hmacSha256(List<int> key, List<int> message) =>
    HmacSha256(key).mac(message);

/// PBKDF2-HMAC-SHA256 (RFC 8018 §5.2): derives [keyLength] bytes from
/// [password] and [salt] over [iterations] rounds.
Uint8List pbkdf2HmacSha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  required int keyLength,
}) {
  final prf = HmacSha256(password);
  final out = Uint8List(keyLength);
  var offset = 0;
  var blockIndex = 1;
  while (offset < keyLength) {
    // U1 = PRF(password, salt || INT32_BE(blockIndex))
    final first = Uint8List(salt.length + 4);
    first.setRange(0, salt.length, salt);
    ByteData.view(first.buffer).setUint32(salt.length, blockIndex, Endian.big);
    var u = prf.mac(first);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = prf.mac(u);
      for (var j = 0; j < 32; j++) {
        t[j] ^= u[j];
      }
    }
    final take = min(32, keyLength - offset);
    out.setRange(offset, offset + take, t);
    offset += take;
    blockIndex++;
  }
  return out;
}

/// Constant-time equality for byte lists (both sides here are
/// fixed-size derived keys; the byte comparison never short-circuits).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// ------------------------------------------------------------ stored record

/// The persisted form of an entry password: salt, derived key and the
/// iteration count, all Base64/ints — the exact field discipline of the
/// native `RecoveryStore` record, held as one JSON value in the config
/// store. There is deliberately no way to recover the password itself.
class EntryPasswordHash {
  const EntryPasswordHash({
    required this.saltBase64,
    required this.hashBase64,
    required this.iterations,
  });

  /// KDF parameters, mirroring `RecoveryStore.kt` (ITERATIONS /
  /// SALT_BYTES / KEY_BITS).
  static const int standardIterations = 210000;
  static const int saltBytes = 16;
  static const int keyBytes = 32;

  final String saltBase64;
  final String hashBase64;
  final int iterations;

  /// Hashes [password] with a fresh random salt. [iterations] exists so
  /// tests can use a cheap derivation; production callers take the
  /// standard count.
  factory EntryPasswordHash.create(
    String password, {
    int iterations = standardIterations,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final salt = Uint8List(saltBytes);
    for (var i = 0; i < saltBytes; i++) {
      salt[i] = rng.nextInt(256);
    }
    final hash = pbkdf2HmacSha256(
      password: utf8.encode(password),
      salt: salt,
      iterations: iterations,
      keyLength: keyBytes,
    );
    return EntryPasswordHash(
      saltBase64: base64.encode(salt),
      hashBase64: base64.encode(hash),
      iterations: iterations,
    );
  }

  /// The weakest stored record verification will honour (v1.0.5 audit
  /// B-8). Production records are always created at
  /// [standardIterations]; the floor exists so a tampered record — a
  /// truncated hash (which would shrink the derived-key space and make
  /// false accepts likely) or a stripped iteration count — can never
  /// verify at reduced strength.
  static const int minVerifyIterations = 100;
  static const int maxVerifyIterations = 1000000;

  /// Recomputes the derivation for [password] and compares it against
  /// the stored key in constant time. A malformed stored record simply
  /// fails verification, as does one whose KDF parameters fall outside
  /// the honoured bounds (exact salt/key sizes, iteration floor).
  bool verify(String password) {
    try {
      final salt = base64.decode(saltBase64);
      final expected = base64.decode(hashBase64);
      if (salt.length != saltBytes || expected.length != keyBytes) {
        return false;
      }
      if (iterations < minVerifyIterations ||
          iterations > maxVerifyIterations) {
        return false;
      }
      final actual = pbkdf2HmacSha256(
        password: utf8.encode(password),
        salt: salt,
        iterations: iterations,
        keyLength: expected.length,
      );
      return constantTimeEquals(expected, actual);
    } on FormatException {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'salt': saltBase64,
        'hash': hashBase64,
        'iterations': iterations,
      };

  factory EntryPasswordHash.fromJson(Map<String, dynamic> j) =>
      EntryPasswordHash(
        saltBase64: j['salt'] as String,
        hashBase64: j['hash'] as String,
        iterations: (j['iterations'] as num).toInt(),
      );
}
