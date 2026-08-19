
import 'package:flutter/services.dart';

class ManagedDeviceStatus {
  const ManagedDeviceStatus({required this.isDeviceOwner, required this.managedAppCount, required this.message});

  final bool isDeviceOwner;
  final int managedAppCount;
  final String message;

  factory ManagedDeviceStatus.fromMap(Map<Object?, Object?> value) => ManagedDeviceStatus(
        isDeviceOwner: value['isDeviceOwner'] as bool? ?? false,
        managedAppCount: value['managedAppCount'] as int? ?? 0,
        message: value['message'] as String? ?? 'حالة الإدارة غير متاحة.',
      );
}

class InstalledManagedApp {
  const InstalledManagedApp({required this.packageName, required this.label});

  final String packageName;
  final String label;

  factory InstalledManagedApp.fromMap(Map<Object?, Object?> value) => InstalledManagedApp(
        packageName: value['packageName'] as String,
        label: value['label'] as String,
      );
}

class AppUsageSummary {
  const AppUsageSummary({required this.packageName, required this.foregroundMilliseconds});
  final String packageName;
  final int foregroundMilliseconds;

  factory AppUsageSummary.fromMap(Map<Object?, Object?> value) => AppUsageSummary(
        packageName: value['packageName'] as String,
        foregroundMilliseconds: value['foregroundMilliseconds'] as int? ?? 0,
      );
}

class KidsafeAndroid {
  static const _channel = MethodChannel('kidsafe_android');

  Future<String?> getPlatformVersion() {
    return _channel.invokeMethod<String>('getPlatformVersion');
  }

  Future<ManagedDeviceStatus> devicePolicyStatus() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('devicePolicyStatus');
    return ManagedDeviceStatus.fromMap(result ?? const {});
  }

  Future<List<InstalledManagedApp>> visibleLaunchableApps() async {
    final result = await _channel.invokeMethod<List<Object?>>('visibleLaunchableApps') ?? const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(InstalledManagedApp.fromMap)
        .toList(growable: false);
  }

  Future<void> applyAllowedApps(List<String> packages) => _channel.invokeMethod<void>('applyAllowedApps', {'packages': packages});

  Future<void> clearAllowedApps() => _channel.invokeMethod<void>('clearAllowedApps');

  Future<List<AppUsageSummary>> todayUsage() async {
    final result = await _channel.invokeMethod<List<Object?>>('todayUsage') ?? const [];
    return result.whereType<Map<Object?, Object?>>().map(AppUsageSummary.fromMap).toList(growable: false);
  }

  Future<void> openUsageAccessSettings() => _channel.invokeMethod<void>('openUsageAccessSettings');

  Future<void> applyBlockedApps(List<String> packages) => _channel.invokeMethod<void>('applyBlockedApps', {'packages': packages});

  /// Opens Android's system consent UI. Consent never starts an invisible capture.
  Future<bool> requestScreenShareConsent() async =>
      await _channel.invokeMethod<bool>('requestScreenShareConsent') ?? false;
}
