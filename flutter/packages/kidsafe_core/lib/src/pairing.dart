import 'dart:math';

const _minimumPairingCodeLength = 8;

bool isValidPairingCode(String code) => RegExp(r'^\d{8}$').hasMatch(code.trim());

String createPairingCode([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(_minimumPairingCodeLength, (_) => source.nextInt(10)).join();
}

String pairingPayload({required String familyId, required String childId, required String code}) {
  if (!isValidPairingCode(code)) throw ArgumentError.value(code, 'code', 'يجب أن يحتوي الرمز على 8 أرقام');
  return 'kidsafe://pair?familyId=$familyId&childId=$childId&code=$code';
}
