import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class PasswordDigest {
  const PasswordDigest({required this.hash, required this.salt});

  final String hash;
  final String salt;
}

class PasswordHasher {
  PasswordHasher({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Future<PasswordDigest> hash(String password) async {
    if (password.length < 8) {
      throw ArgumentError('Password must contain at least 8 characters.');
    }
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    return PasswordDigest(
      hash: base64Encode(await _derive(password, salt)),
      salt: base64Encode(salt),
    );
  }

  Future<bool> verify({
    required String password,
    required String expectedHash,
    required String salt,
  }) async {
    final actual = await _derive(password, base64Decode(salt));
    final expected = base64Decode(expectedHash);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }
}

/// PBKDF2-HMAC-SHA256 with 210,000 iterations takes a noticeable fraction of
/// a second in Dart, so it runs on a background isolate to keep sign-in,
/// unlock and user screens responsive.
Future<List<int>> _derive(String password, List<int> salt) =>
    Isolate.run(() => _deriveSync(password, salt));

Future<List<int>> _deriveSync(String password, List<int> salt) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  return key.extractBytes();
}
