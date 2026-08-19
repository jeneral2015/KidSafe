import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'kidsafe_android_method_channel.dart';

abstract class KidsafeAndroidPlatform extends PlatformInterface {
  /// Constructs a KidsafeAndroidPlatform.
  KidsafeAndroidPlatform() : super(token: _token);

  static final Object _token = Object();

  static KidsafeAndroidPlatform _instance = MethodChannelKidsafeAndroid();

  /// The default instance of [KidsafeAndroidPlatform] to use.
  ///
  /// Defaults to [MethodChannelKidsafeAndroid].
  static KidsafeAndroidPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [KidsafeAndroidPlatform] when
  /// they register themselves.
  static set instance(KidsafeAndroidPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
