import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/auth/data/password_hasher.dart';

void main() {
  test('hashes with a salt and verifies in constant-time code path', () async {
    final hasher = PasswordHasher();
    final digest = await hasher.hash('a secure password');

    expect(digest.hash, isNotEmpty);
    expect(digest.salt, isNotEmpty);
    expect(
      await hasher.verify(
        password: 'a secure password',
        expectedHash: digest.hash,
        salt: digest.salt,
      ),
      isTrue,
    );
    expect(
      await hasher.verify(
        password: 'wrong password',
        expectedHash: digest.hash,
        salt: digest.salt,
      ),
      isFalse,
    );
  });
}
