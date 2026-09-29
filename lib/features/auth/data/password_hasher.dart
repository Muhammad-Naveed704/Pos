import 'dart:convert';
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
  final _algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );

  Future<PasswordDigest> hash(String password) async {
    if (password.length < 8) {
      throw ArgumentError('Password must contain at least 8 characters.');
    }
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return PasswordDigest(
      hash: base64Encode(await key.extractBytes()),
      salt: base64Encode(salt),
    );
  }

  Future<bool> verify({
    required String password,
    required String expectedHash,
    required String salt,
  }) async {
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Decode(salt),
    );
    final actual = await key.extractBytes();
    final expected = base64Decode(expectedHash);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual[index] ^ expected[index];
    }
    return difference == 0;
  }
}
