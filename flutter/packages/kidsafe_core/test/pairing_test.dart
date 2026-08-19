import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_core/kidsafe_core.dart';

void main() {
  test('pairing code contains exactly eight digits', () {
    expect(isValidPairingCode(createPairingCode(Random(7))), isTrue);
    expect(isValidPairingCode('1234567'), isFalse);
    expect(isValidPairingCode('1234567A'), isFalse);
  });

  test('pairing payload includes family, child, and valid code', () {
    expect(
      pairingPayload(familyId: 'family-1', childId: 'child-1', code: '12345678'),
      'kidsafe://pair?familyId=family-1&childId=child-1&code=12345678',
    );
  });
}
