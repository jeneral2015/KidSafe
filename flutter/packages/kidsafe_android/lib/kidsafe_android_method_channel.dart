import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'kidsafe_android_platform_interface.dart';

/// An implementation of [KidsafeAndroidPlatform] that uses method channels.
class MethodChannelKidsafeAndroid extends KidsafeAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('kidsafe_android');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
