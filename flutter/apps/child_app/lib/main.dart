import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kidsafe_android/kidsafe_android.dart';
import 'package:kidsafe_core/kidsafe_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'firebase_options.dart';

final childRepositoryProvider = Provider<FamilyRepository>((ref) => FamilyRepository());
final androidBridgeProvider = Provider<KidsafeAndroid>((ref) => KidsafeAndroid());
final safetyRepositoryProvider = Provider<SafetyRepository>((ref) => SafetyRepository());
final policyRepositoryProvider = Provider<PolicyRepository>((ref) => PolicyRepository());
final sessionRepositoryProvider = Provider<FamilySessionRepository>((ref) => FamilySessionRepository());

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: ChildApp()));
}

class ChildApp extends StatelessWidget {
  const ChildApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KidSafe Child',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff155EEF)), useMaterial3: true),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
        home: const ChildGate(),
      );
}

class ChildGate extends ConsumerWidget {
  const ChildGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        final user = auth.data;
        if (auth.connectionState == ConnectionState.waiting) return const ChildLoadingScreen();
        if (user == null) return const ChildPairingScreen();
        return FutureBuilder<ChildProfile?>(
          future: ref.read(childRepositoryProvider).readLinkedChildProfile(user.uid),
          builder: (context, child) {
            if (child.connectionState != ConnectionState.done) return const ChildLoadingScreen();
            return child.data == null ? const ChildPairingScreen() : ChildReadyScreen(profile: child.data!);
          },
        );
      },
    );
  }
}

class ChildPairingScreen extends ConsumerStatefulWidget {
  const ChildPairingScreen({super.key});

  @override
  ConsumerState<ChildPairingScreen> createState() => _ChildPairingScreenState();
}

class _ChildPairingScreenState extends ConsumerState<ChildPairingScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _claim(String code) async {
    setState(() { _busy = true; _message = null; });
    try {
      await ref.read(childRepositoryProvider).claimPairing(code);
    } catch (_) {
      setState(() => _message = 'تعذر ربط الجهاز. تحقق من الرمز أو اطلب رمزاً جديداً من الوالد.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ChildShell(
        title: 'إعداد جهاز الطفل',
        subtitle: 'اربط هذا الجهاز بعائلتك. بعد الربط ستظهر الأذونات والسياسات النشطة هنا بوضوح.',
        child: Column(children: [
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: const InputDecoration(labelText: 'رمز الاقتران (8 أرقام)', counterText: ''),
          ),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : () => _claim(_code.text),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_busy ? 'جارٍ الربط...' : 'ربط الجهاز'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () async {
              final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const PairingScannerScreen()));
              if (value != null && mounted) {
                final code = Uri.tryParse(value)?.queryParameters['code'] ?? value;
                _code.text = code;
                await _claim(code);
              }
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('مسح رمز QR'),
          ),
        ]),
      );
}

class PairingScannerScreen extends StatelessWidget {
  const PairingScannerScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مسح رمز الاقتران')),
        body: MobileScanner(
          onDetect: (capture) {
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null) Navigator.of(context).pop(value);
          },
        ),
      );
}

class ChildReadyScreen extends ConsumerStatefulWidget {
  const ChildReadyScreen({super.key, required this.profile});
  final ChildProfile profile;

  @override
  ConsumerState<ChildReadyScreen> createState() => _ChildReadyScreenState();
}

class _ChildReadyScreenState extends ConsumerState<ChildReadyScreen> {
  ManagedDeviceStatus? _policyStatus;
  String? _actionMessage;
  final Map<String, SafeZonePresence> _zonePresence = {};
  StreamSubscription<FamilyAppPolicy>? _policySubscription;
  StreamSubscription<Position>? _backgroundLocationSubscription;
  Timer? _policyTimer;
  FamilyAppPolicy? _activePolicy;
  List<AppUsageSummary> _todayUsage = const [];
  bool _backgroundLocationActive = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _syncInstalledApps();
    _listenForPolicy();
    _loadUsage();
    _policyTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (_activePolicy != null) _enforcePolicy(_activePolicy!); });
  }

  @override
  void dispose() {
    _policySubscription?.cancel();
    _backgroundLocationSubscription?.cancel();
    _policyTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await ref.read(androidBridgeProvider).devicePolicyStatus();
      if (mounted) setState(() => _policyStatus = status);
    } catch (_) {
      if (mounted) setState(() => _actionMessage = 'حالة الإدارة الكاملة لا تتاح إلا على Android.');
    }
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();
    if (statuses[Permission.locationWhenInUse]?.isGranted ?? false) {
      await Permission.locationAlways.request();
    }
    if (mounted) setState(() => _actionMessage = 'تمت مراجعة الأذونات. يمكنك دائماً التحقق من حالتها من إعدادات Android.');
  }

  Future<void> _shareScreen() async {
    try {
      final accepted = await ref.read(androidBridgeProvider).requestScreenShareConsent();
      if (mounted) setState(() => _actionMessage = accepted ? 'تمت الموافقة على مشاركة الشاشة. يظهر إشعار KidSafe أثناء الجلسة.' : 'لم تبدأ مشاركة الشاشة لأن موافقة Android لم تُمنح.');
    } catch (_) {
      if (mounted) setState(() => _actionMessage = 'تعذر فتح طلب مشاركة الشاشة. افتح هذه الصفحة من جهاز Android.');
    }
  }

  Future<void> _shareCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _actionMessage = 'خدمات الموقع مغلقة. افتحها من إعدادات Android ثم أعد المحاولة.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _actionMessage = 'لا يمكن تحديث الموقع قبل منح إذن الموقع.');
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition();
      await _recordPosition(position);
      if (mounted) setState(() => _actionMessage = 'تمت مشاركة الموقع الآن بدقة ${position.accuracy.round()} متر، مع مراجعة المناطق الآمنة.');
    } catch (_) {
      if (mounted) setState(() => _actionMessage = 'تعذر تحديث الموقع الآن. تحقق من GPS والاتصال.');
    }
  }

  Future<void> _recordPosition(Position position) async {
    final location = ChildLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      recordedAt: DateTime.now(),
    );
    final safety = ref.read(safetyRepositoryProvider);
    await safety.saveChildLocation(familyId: widget.profile.familyId, childId: widget.profile.id, location: location);
    final zones = await safety.watchSafeZones(widget.profile.familyId).first;
    for (final zone in zones) {
      final transition = await safety.evaluateAndRecordZone(
        familyId: widget.profile.familyId,
        childId: widget.profile.id,
        zone: zone,
        location: location,
        previous: _zonePresence[zone.id] ?? SafeZonePresence.unknown,
      );
      _zonePresence[zone.id] = transition.current;
    }
  }

  Future<void> _toggleBackgroundLocation() async {
    if (_backgroundLocationActive) {
      await _backgroundLocationSubscription?.cancel();
      _backgroundLocationSubscription = null;
      if (mounted) setState(() { _backgroundLocationActive = false; _actionMessage = 'توقفت متابعة الموقع في الخلفية. لن يُرسل الموقع مجدداً حتى تُفعّلها.'; });
      return;
    }
    final allowed = await Permission.locationAlways.request();
    if (!allowed.isGranted) {
      setState(() => _actionMessage = 'تحتاج المتابعة الخلفية إلى إذن الموقع الدائم الذي يوضحه Android.');
      return;
    }
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'KidSafe يحدّث موقع العائلة',
        notificationText: 'تتبع الموقع مفعل ويظهر بإشعار دائم على هذا الجهاز.',
        enableWakeLock: true,
      ),
    );
    _backgroundLocationSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) async => _recordPosition(position),
      onError: (_) { if (mounted) setState(() => _actionMessage = 'توقفت متابعة الموقع. راجع GPS أو الإذن من إعدادات Android.'); },
    );
    if (mounted) setState(() { _backgroundLocationActive = true; _actionMessage = 'بدأت متابعة الموقع في الخلفية. يظهر إشعار KidSafe دائماً أثناء تشغيلها.'; });
  }

  Future<void> _syncInstalledApps() async {
    try {
      final installed = await ref.read(androidBridgeProvider).visibleLaunchableApps();
      await ref.read(policyRepositoryProvider).syncInstalledApps(
        familyId: widget.profile.familyId,
        childId: widget.profile.id,
        apps: installed.map((app) => DeviceAppRecord(packageName: app.packageName, label: app.label)).toList(),
      );
      if (mounted) setState(() => _actionMessage = 'تمت مزامنة ${installed.length} تطبيقاً مثبتاً ليتمكن الوالد من إعداد السياسة.');
    } catch (_) {
      if (mounted) setState(() => _actionMessage = 'تُزامن قائمة التطبيقات على جهاز Android فقط.');
    }
  }

  void _listenForPolicy() {
    _policySubscription = ref.read(policyRepositoryProvider).watchPolicy(widget.profile.familyId, widget.profile.id).listen((policy) async {
      _activePolicy = policy;
      await _enforcePolicy(policy);
    });
  }

  Future<void> _enforcePolicy(FamilyAppPolicy policy) async {
    try {
      final bridge = ref.read(androidBridgeProvider);
      final status = await bridge.devicePolicyStatus();
      if (!status.isDeviceOwner) return;
      final apps = await bridge.visibleLaunchableApps();
      final usedMinutes = _todayUsage.fold<int>(0, (total, usage) => total + (usage.foregroundMilliseconds / 60000).round());
      final scheduleBlocked = policy.isBlockedAt(DateTime.now());
      final dailyLimitReached = policy.dailyLimitMinutes > 0 && usedMinutes >= policy.dailyLimitMinutes;
      final blockedPackages = (scheduleBlocked || dailyLimitReached)
          ? apps.map((app) => app.packageName).toList()
          : apps.where((app) => !policy.allowedPackages.contains(app.packageName)).map((app) => app.packageName).toList();
      await bridge.applyAllowedApps(policy.allowedPackages);
      await bridge.applyBlockedApps(blockedPackages);
      if (mounted) {
        setState(() => _actionMessage = scheduleBlocked
            ? 'فترة المنع اليومية نشطة الآن. تظهر سياسة KidSafe على الجهاز المُدار.'
            : dailyLimitReached
                ? 'تم بلوغ الحد اليومي المحدد. تظهر سياسة KidSafe على الجهاز المُدار.'
                : 'تم تطبيق سياسة الأسرة المرئية: ${policy.allowedPackages.length} تطبيقات مسموحة، والباقي محظور في وضع الإدارة الكاملة.');
      }
    } catch (_) {
      // Quick Setup Mode stores the policy transparently without claiming Device Owner enforcement.
    }
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await ref.read(androidBridgeProvider).todayUsage();
      if (mounted) setState(() => _todayUsage = usage);
      if (_activePolicy != null) await _enforcePolicy(_activePolicy!);
    } catch (_) {
      if (mounted) setState(() => _actionMessage = 'راجع إذن «الوصول إلى الاستخدام» من Android لعرض تقرير التطبيقات اليومي.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('KidSafe على جهاز الطفل')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Card(
            color: const Color(0xffEAF2FF),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.visibility_outlined, color: Color(0xff155EEF)),
                const SizedBox(height: 8),
                Text('أنت متصل بعائلة KidSafe', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                const Text('تظهر هنا أي جلسة موقع أو صوت أو كاميرا أو شاشة. لا يبدأ البث الحساس من دون حالة واضحة وموافقة Android المطلوبة.'),
              ]),
            ),
          ),
          StreamBuilder<List<FamilySession>>(
            stream: ref.read(sessionRepositoryProvider).watchChildSessions(familyId: widget.profile.familyId, childId: widget.profile.id),
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? const <FamilySession>[];
              return Column(children: sessions.map((session) => Card(
                color: const Color(0xffFFF7E6),
                child: ListTile(
                  leading: Icon(session.kind == FamilySessionKind.video ? Icons.videocam_outlined : Icons.call_outlined),
                  title: const Text('جلسة عائلية ظاهرة'),
                  subtitle: Text('${session.childVisibleLabel}\n${session.reason}'),
                  isThreeLine: true,
                  trailing: FilledButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChildFamilySessionScreen(session: session))),
                    child: const Text('مراجعة'),
                  ),
                ),
              )).toList());
            },
          ),
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('الموقع والمناطق الآمنة'),
            subtitle: Text(_backgroundLocationActive ? 'متابعة الخلفية مفعّلة بإشعار KidSafe دائم.' : 'تحديث واضح للموقع ومراجعة مناطق الأسرة الآمنة.'),
            trailing: Wrap(spacing: 4, children: [
              IconButton(onPressed: _shareCurrentLocation, icon: const Icon(Icons.my_location), tooltip: 'تحديث الآن'),
              FilledButton.tonal(onPressed: _toggleBackgroundLocation, child: Text(_backgroundLocationActive ? 'إيقاف' : 'تشغيل')),
            ]),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('مراجعة أذونات السلامة'),
            subtitle: const Text('الكاميرا والميكروفون والإشعارات والموقع في الخلفية عند منحه.'),
            trailing: FilledButton.tonal(onPressed: _requestPermissions, child: const Text('مراجعة')),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.screen_share_outlined),
            title: const Text('مشاركة الشاشة المعلنة'),
            subtitle: const Text('يفتح Android شاشة موافقة صريحة لكل جلسة.'),
            trailing: FilledButton.tonal(onPressed: _shareScreen, child: const Text('طلب الموافقة')),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('حالة الإدارة العائلية'),
            subtitle: Text(_policyStatus?.message ?? 'جارٍ فحص وضع الجهاز المُدار...'),
            trailing: IconButton(onPressed: _loadStatus, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.apps_outage_outlined),
            title: const Text('تطبيقات الجهاز وسياسة الأسرة'),
            subtitle: const Text('تُزامن قائمة التطبيقات مع الوالد. يفرض وضع الإدارة الكاملة السياسة عندما يكون مفعلاً.'),
            trailing: FilledButton.tonal(onPressed: _syncInstalledApps, child: const Text('مزامنة')),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('استخدام التطبيقات اليوم'),
            subtitle: Text(_todayUsage.isEmpty ? 'امنح إذن الوصول إلى الاستخدام لعرض التقرير اليومي.' : '${_todayUsage.length} تطبيقات لها استخدام اليوم.'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: _loadUsage, icon: const Icon(Icons.refresh), tooltip: 'تحديث التقرير'),
              IconButton(onPressed: () => ref.read(androidBridgeProvider).openUsageAccessSettings(), icon: const Icon(Icons.settings), tooltip: 'إذن الاستخدام'),
            ]),
          ),
          if (_todayUsage.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._todayUsage.take(5).map((usage) => ListTile(
              dense: true,
              title: Text(usage.packageName),
              trailing: Text('${(usage.foregroundMilliseconds / 60000).round()} دقيقة'),
            )),
          ],
          if (_actionMessage != null) Padding(padding: const EdgeInsets.only(top: 18), child: Text(_actionMessage!)),
        ]),
      );
}

class ChildFamilySessionScreen extends ConsumerStatefulWidget {
  const ChildFamilySessionScreen({super.key, required this.session});
  final FamilySession session;

  @override
  ConsumerState<ChildFamilySessionScreen> createState() => _ChildFamilySessionScreenState();
}

class _ChildFamilySessionScreenState extends ConsumerState<ChildFamilySessionScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  DirectFamilyConnection? _connection;
  StreamSubscription<List<SessionSignal>>? _signals;
  String _status = 'راجع سبب الجلسة قبل تشغيل الكاميرا أو الميكروفون.';
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _accept() async {
    final repository = ref.read(sessionRepositoryProvider);
    try {
      await repository.acknowledge(familyId: widget.session.familyId, sessionId: widget.session.id, sender: SignalSender.child);
      final connection = DirectFamilyConnection(
        kind: widget.session.kind,
        writeSignal: (kind, payload) => repository.sendSignal(familyId: widget.session.familyId, sessionId: widget.session.id, sender: SignalSender.child, kind: kind, payload: payload),
        onRemoteStream: (stream) {
          _remoteRenderer.srcObject = stream;
          if (mounted) setState(() => _status = 'بث الوالد متصل. تظهر الجلسة كحالة معلنة على الجهاز.');
        },
      );
      _connection = connection;
      await connection.initialize();
      _localRenderer.srcObject = connection.localStream;
      _signals = repository.watchPeerSignals(familyId: widget.session.familyId, sessionId: widget.session.id, ownRole: SignalSender.child).listen((signals) async {
        for (final signal in signals) {
          await connection.applyPeerSignal(signal);
        }
      });
      await repository.setStatus(familyId: widget.session.familyId, sessionId: widget.session.id, status: FamilySessionStatus.active);
      if (mounted) setState(() { _active = true; _status = widget.session.kind == FamilySessionKind.screen ? 'فتح Android الآن طلب الموافقة على مشاركة الشاشة. تظهر المشاركة كحالة معلنة أثناء الجلسة.' : 'الجلسة مفعلة. الكاميرا والميكروفون يعملان فقط أثناء هذه الحالة المرئية.'; });
    } catch (_) {
      if (mounted) setState(() => _status = 'تعذر تفعيل الجلسة. تحقق من أذونات الكاميرا والميكروفون والاتصال.');
    }
  }

  Future<void> _end() async {
    await ref.read(sessionRepositoryProvider).end(familyId: widget.session.familyId, sessionId: widget.session.id, sender: SignalSender.child);
    await _connection?.dispose();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _signals?.cancel();
    _connection?.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('جلسة KidSafe العائلية')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(color: const Color(0xffFFF7E6), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.session.childVisibleLabel, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('السبب: ${widget.session.reason}'),
            const SizedBox(height: 10),
            Text(_status),
          ]))),
          const SizedBox(height: 16),
          if (widget.session.kind == FamilySessionKind.video) ...[
            Text('معاينة الكاميرا على هذا الجهاز', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 180, child: RTCVideoView(_localRenderer, mirror: true)),
            const SizedBox(height: 12),
            Text('بث الوالد', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 200, child: RTCVideoView(_remoteRenderer)),
          ],
          if (widget.session.kind == FamilySessionKind.screen) ...[
            Text('مشاركة شاشة هذا الجهاز', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 220, child: RTCVideoView(_localRenderer)),
          ],
          const SizedBox(height: 18),
          if (!_active) FilledButton.icon(onPressed: _accept, icon: const Icon(Icons.play_arrow), label: const Text('تفعيل الجلسة الظاهرة')),
          if (_active) FilledButton.icon(onPressed: _end, icon: const Icon(Icons.stop_circle_outlined), label: const Text('إنهاء الجلسة')),
        ]),
      );
}

class ChildShell extends StatelessWidget {
  const ChildShell({super.key, required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.shield_outlined, size: 48, color: Color(0xff155EEF)),
                        const SizedBox(height: 16),
                        Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(subtitle, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class ChildLoadingScreen extends StatelessWidget {
  const ChildLoadingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
