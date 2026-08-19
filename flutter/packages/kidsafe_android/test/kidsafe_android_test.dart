import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_android/kidsafe_android.dart';
import 'package:kidsafe_android/kidsafe_android_platform_interface.dart';
import 'package:kidsafe_android/kidsafe_android_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockKidsafeAndroidPlatform
    with MockPlatformInterfaceMixin
    implements KidsafeAndroidPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final KidsafeAndroidPlatform initialPlatform = KidsafeAndroidPlatform.instance;

  test('$MethodChannelKidsafeAndroid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelKidsafeAndroid>());
  });

  test('getPlatformVersion', () async {
    KidsafeAndroid kidsafeAndroidPlugin = KidsafeAndroid();
    MockKidsafeAndroidPlatform fakePlatform = MockKidsafeAndroidPlatform();
    KidsafeAndroidPlatform.instance = fakePlatform;

    expect(await kidsafeAndroidPlugin.getPlatformVersion(), '42');
  });
}
