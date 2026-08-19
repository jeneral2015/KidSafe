package com.jeneral2015.kidsafe_android

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** KidsafeAndroidPlugin */
class KidsafeAndroidPlugin : FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var pendingConsentResult: Result? = null
    private val requestScreenShare = 4821

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "kidsafe_android")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "devicePolicyStatus" -> result.success(devicePolicyStatus())
            "visibleLaunchableApps" -> result.success(visibleLaunchableApps())
            "todayUsage" -> result.success(todayUsage())
            "openUsageAccessSettings" -> {
                context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "applyAllowedApps" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                runCatching { applyAllowedApps(packages); Unit }
                    .onSuccess { result.success(null) }
                    .onFailure { result.error("policy-unavailable", it.message, null) }
            }
            "clearAllowedApps" -> {
                runCatching { applyAllowedApps(emptyList()); Unit }
                    .onSuccess { result.success(null) }
                    .onFailure { result.error("policy-unavailable", it.message, null) }
            }
            "applyBlockedApps" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                runCatching { applyBlockedApps(packages); Unit }
                    .onSuccess { result.success(null) }
                    .onFailure { result.error("policy-unavailable", it.message, null) }
            }
            "requestScreenShareConsent" -> requestScreenShareConsent(result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() { activity = null }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != requestScreenShare) return false
        val approved = resultCode == Activity.RESULT_OK && data != null
        if (approved) {
            val serviceIntent = Intent(context, VisibleScreenShareService::class.java)
            context.startForegroundService(serviceIntent)
        }
        pendingConsentResult?.success(approved)
        pendingConsentResult = null
        return true
    }

    private fun requestScreenShareConsent(result: Result) {
        val host = activity
        if (host == null) {
            result.error("activity-unavailable", "يجب فتح طلب مشاركة الشاشة من واجهة الطفل الظاهرة.", null)
            return
        }
        if (pendingConsentResult != null) {
            result.error("consent-in-progress", "طلب الموافقة ظاهر بالفعل.", null)
            return
        }
        pendingConsentResult = result
        val manager = context.getSystemService(MediaProjectionManager::class.java)
        host.startActivityForResult(manager.createScreenCaptureIntent(), requestScreenShare)
    }

    private fun devicePolicyStatus(): Map<String, Any> {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        val owner = dpm.isDeviceOwnerApp(context.packageName)
        val admin = ComponentName(context, KidSafeDeviceAdminReceiver::class.java)
        val count = if (owner) dpm.getLockTaskPackages(admin).count { it != context.packageName } else 0
        val message = if (owner) {
            "هذا الجهاز مُدار عائلياً عبر KidSafe. توجد $count تطبيقات ضمن سياسة العائلة."
        } else {
            "وضع الإدارة الكاملة غير مفعّل. تعمل KidSafe فقط ضمن الأذونات الممنوحة والظاهرة."
        }
        return mapOf("isDeviceOwner" to owner, "managedAppCount" to count, "message" to message)
    }

    private fun visibleLaunchableApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            .map { info -> mapOf("packageName" to info.activityInfo.packageName, "label" to info.loadLabel(context.packageManager).toString()) }
            .distinctBy { it["packageName"] }
            .sortedBy { it["label"] }
    }

    private fun todayUsage(): List<Map<String, Any>> {
        val usage = context.getSystemService(UsageStatsManager::class.java)
        val now = System.currentTimeMillis()
        val dayStart = now - (24L * 60L * 60L * 1000L)
        return usage.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, now)
            .filter { it.totalTimeInForeground > 0 }
            .map { mapOf("packageName" to it.packageName, "foregroundMilliseconds" to it.totalTimeInForeground) }
            .sortedByDescending { it["foregroundMilliseconds"] as Long }
    }

    private fun applyAllowedApps(packages: List<String>) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        check(dpm.isDeviceOwnerApp(context.packageName)) { "يتطلب تطبيق سياسة التطبيقات وضع Device Owner." }
        val admin = ComponentName(context, KidSafeDeviceAdminReceiver::class.java)
        dpm.setShortSupportMessage(admin, "هذا جهاز طفل مُدار عائلياً عبر KidSafe. راجع التطبيق لمعرفة السياسة الفعالة.")
        dpm.setLongSupportMessage(admin, "تظهر سياسة KidSafe وسجلها للطفل. لا تبدأ هذه السياسة كاميرا أو ميكروفون أو مشاركة شاشة.")
        dpm.setDeviceOwnerLockScreenInfo(admin, "هذا جهاز طفل مُدار عائلياً عبر KidSafe.")
        dpm.setLockTaskPackages(admin, (packages + context.packageName).distinct().toTypedArray())
    }

    private fun applyBlockedApps(packages: List<String>) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        check(dpm.isDeviceOwnerApp(context.packageName)) { "يتطلب حظر التطبيقات وضع Device Owner." }
        val admin = ComponentName(context, KidSafeDeviceAdminReceiver::class.java)
        visibleLaunchableApps().filter { it["packageName"] != context.packageName }.forEach { app ->
            dpm.setApplicationHidden(admin, app["packageName"]!!, packages.contains(app["packageName"]))
        }
    }
}
