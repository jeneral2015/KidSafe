import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_core/kidsafe_core.dart';

void main() {
  test('session signal filtering never returns an endpoint own messages', () {
    const signals = [
      SessionSignal(id: 'offer', sender: SignalSender.guardian, kind: SessionSignalKind.offer, payload: {}),
      SessionSignal(id: 'answer', sender: SignalSender.child, kind: SessionSignalKind.answer, payload: {}),
      SessionSignal(id: 'end', sender: SignalSender.guardian, kind: SessionSignalKind.end, payload: {}),
    ];
    expect(peerSignals(signals, SignalSender.guardian).map((item) => item.kind), [SessionSignalKind.answer]);
    expect(peerSignals(signals, SignalSender.child).map((item) => item.kind), [SessionSignalKind.offer, SessionSignalKind.end]);
  });
}
