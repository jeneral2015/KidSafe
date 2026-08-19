import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_core/kidsafe_core.dart';

void main() {
  test('family policy preserves only explicit allowed packages and time limit', () {
    final policy = FamilyAppPolicy(allowedPackages: const ['com.example.school'], dailyLimitMinutes: 90, blockedStartMinute: 1320, blockedEndMinute: 420, updatedAt: null);
    expect(policy.toMap()['allowedPackages'], ['com.example.school']);
    expect(policy.toMap()['dailyLimitMinutes'], 90);
    expect(policy.isBlockedAt(DateTime(2026, 1, 1, 23)), isTrue);
    expect(policy.isBlockedAt(DateTime(2026, 1, 1, 6)), isTrue);
    expect(policy.isBlockedAt(DateTime(2026, 1, 1, 12)), isFalse);
  });
}
