import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kidsafe_core/kidsafe_core.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'firebase_options.dart';

final familyRepositoryProvider = Provider<FamilyRepository>((ref) => FamilyRepository());
final safetyRepositoryProvider = Provider<SafetyRepository>((ref) => SafetyRepository());
final policyRepositoryProvider = Provider<PolicyRepository>((ref) => PolicyRepository());
final sessionRepositoryProvider = Provider<FamilySessionRepository>((ref) => FamilySessionRepository());

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: GuardianApp()));
}

class GuardianApp extends StatelessWidget {
  const GuardianApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KidSafe Guardian',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff155EEF)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xffF7F9FC),
        ),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
        home: const GuardianGate(),
      );
}

class GuardianGate extends ConsumerWidget {
  const GuardianGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(familyRepositoryProvider);
    return StreamBuilder(
      stream: repository.authChanges,
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) return const LoadingScreen();
        final user = auth.data;
        if (user == null) return const GuardianAuthScreen();
        return FutureBuilder(
          future: repository.readGuardianProfile(user.uid),
          builder: (context, profile) {
            if (profile.connectionState != ConnectionState.done) return const LoadingScreen();
            return profile.data == null ? const FamilyBootstrapScreen() : GuardianDashboard(profile: profile.data!);
          },
        );
      },
    );
  }
}

class GuardianAuthScreen extends ConsumerStatefulWidget {
  const GuardianAuthScreen({super.key});

  @override
  ConsumerState<GuardianAuthScreen> createState() => _GuardianAuthScreenState();
}

class _GuardianAuthScreenState extends ConsumerState<GuardianAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _message = null; });
    try {
      final repository = ref.read(familyRepositoryProvider);
      if (_creating) {
        await repository.createAccount(email: _email.text, password: _password.text);
      } else {
        await repository.signIn(email: _email.text, password: _password.text);
      }
    } catch (_) {
      setState(() => _message = 'تعذر إكمال الدخول. تحقق من البريد وكلمة المرور والاتصال.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthShell(
        title: _creating ? 'أنشئ حساب الوالد' : 'مرحباً بك في KidSafe',
        subtitle: 'تُدار العائلة من حساب والد موثّق، وتظهر الجلسات الحساسة على جهاز الطفل بوضوح.',
        child: Column(children: [
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_busy ? 'جارٍ المعالجة...' : (_creating ? 'إنشاء الحساب' : 'تسجيل الدخول')),
          ),
          TextButton(onPressed: _busy ? null : () => setState(() => _creating = !_creating), child: Text(_creating ? 'لدي حساب بالفعل' : 'إنشاء حساب جديد')),
          TextButton(
            onPressed: _busy ? null : () async {
              if (_email.text.trim().isEmpty) { setState(() => _message = 'أدخل البريد أولاً لإرسال رابط الاستعادة.'); return; }
              try {
                await ref.read(familyRepositoryProvider).resetPassword(_email.text);
                if (mounted) setState(() => _message = 'أُرسل رابط استعادة كلمة المرور إلى بريدك.');
              } catch (_) {
                if (mounted) setState(() => _message = 'تعذر إرسال رسالة الاستعادة الآن.');
              }
            },
            child: const Text('استعادة كلمة المرور'),
          ),
        ]),
      );
}

class FamilyBootstrapScreen extends ConsumerStatefulWidget {
  const FamilyBootstrapScreen({super.key});

  @override
  ConsumerState<FamilyBootstrapScreen> createState() => _FamilyBootstrapScreenState();
}

class _FamilyBootstrapScreenState extends ConsumerState<FamilyBootstrapScreen> {
  final _familyName = TextEditingController(text: 'عائلتي');
  final _displayName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() { _familyName.dispose(); _displayName.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AuthShell(
        title: 'أنشئ عائلتك',
        subtitle: 'خطوة واحدة قبل ربط جهاز الطفل وتحديد قواعد الأمان.',
        child: Column(children: [
          TextField(controller: _familyName, decoration: const InputDecoration(labelText: 'اسم العائلة')),
          const SizedBox(height: 12),
          TextField(controller: _displayName, decoration: const InputDecoration(labelText: 'اسم الوالد الظاهر')),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : () async {
              setState(() => _busy = true);
              try {
                await ref.read(familyRepositoryProvider).createFamily(familyName: _familyName.text, displayName: _displayName.text);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_busy ? 'جارٍ إنشاء العائلة...' : 'إنشاء العائلة'),
          ),
        ]),
      );
}

class GuardianDashboard extends ConsumerWidget {
  const GuardianDashboard({super.key, required this.profile});
  final GuardianProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(familyRepositoryProvider);
    final safety = ref.watch(safetyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('عائلتي'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountAndFamilyScreen(profile: profile))),
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'الحساب وإدارة الأسرة',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddChildScreen(familyId: profile.familyId))),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة طفل'),
      ),
      body: StreamBuilder<List<ChildProfile>>(
        stream: repository.watchChildren(profile.familyId),
        builder: (context, snapshot) {
          final children = snapshot.data ?? const [];
          return StreamBuilder<List<FamilyAlert>>(
            stream: safety.watchRecentAlerts(profile.familyId),
            builder: (context, alertSnapshot) {
              final alerts = alertSnapshot.data ?? const <FamilyAlert>[];
              return RefreshIndicator(
                onRefresh: () async => await Future<void>.delayed(const Duration(milliseconds: 350)),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
                  FamilySummaryCard(
                    profile: profile,
                    childCount: children.length,
                    onManageFamily: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FamilyManagementScreen(profile: profile, children: children))),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(child: Text('الأطفال المسجلون', style: Theme.of(context).textTheme.titleLarge)),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddChildScreen(familyId: profile.familyId))),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
                  else if (children.isEmpty)
                    EmptyChildrenCard(onAddChild: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddChildScreen(familyId: profile.familyId))))
                  else
                    ...children.map((child) => ChildOverviewCard(
                          child: child,
                          onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChildSafetyScreen(familyId: profile.familyId, child: child))),
                          onPair: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PairingCodeScreen(familyId: profile.familyId, child: child))),
                        )),
                  const SizedBox(height: 24),
                  Text('التنبيهات الأخيرة', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (alerts.isEmpty)
                    const Card(child: ListTile(leading: Icon(Icons.notifications_none_outlined), title: Text('لا توجد تنبيهات جديدة'), subtitle: Text('ستظهر هنا تنبيهات الموقع والمناطق الآمنة وحالة أجهزة الأطفال.')))
                  else
                    ...alerts.map((alert) => AlertCard(alert: alert, childName: _childName(children, alert.childId))),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

String _childName(List<ChildProfile> children, String childId) {
  for (final child in children) {
    if (child.id == childId) return child.name;
  }
  return 'أحد الأطفال';
}

class FamilySummaryCard extends StatelessWidget {
  const FamilySummaryCard({super.key, required this.profile, required this.childCount, required this.onManageFamily});
  final GuardianProfile profile;
  final int childCount;
  final VoidCallback onManageFamily;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xffEAF2FF),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const CircleAvatar(radius: 25, backgroundColor: Color(0xff155EEF), child: Icon(Icons.family_restroom, color: Colors.white)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مرحباً ${profile.displayName?.trim().isNotEmpty == true ? profile.displayName : 'بك'}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(childCount == 0 ? 'ابدأ بإضافة جهاز طفل واحد.' : '$childCount ${childCount == 1 ? 'طفل مسجل' : 'أطفال مسجلون'}'),
            ])),
            IconButton(onPressed: onManageFamily, icon: const Icon(Icons.tune_outlined), tooltip: 'إدارة الأسرة'),
          ]),
        ),
      );
}

class EmptyChildrenCard extends StatelessWidget {
  const EmptyChildrenCard({super.key, required this.onAddChild});
  final VoidCallback onAddChild;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.person_add_alt_1_outlined, size: 34, color: Color(0xff155EEF)),
            const SizedBox(height: 10),
            Text('لا يوجد أطفال مسجلون بعد', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('أضف الطفل أولاً، ثم سيظهر رمز رقمي وQR لربط جهازه بخطوات بسيطة.'),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAddChild, icon: const Icon(Icons.add), label: const Text('إضافة أول طفل')),
          ]),
        ),
      );
}

class ChildOverviewCard extends StatelessWidget {
  const ChildOverviewCard({super.key, required this.child, required this.onOpen, required this.onPair});
  final ChildProfile child;
  final VoidCallback onOpen;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final linked = child.deviceStatus == 'linked';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(backgroundColor: linked ? const Color(0xffDCFCE7) : const Color(0xffFEF3C7), child: Icon(linked ? Icons.shield_outlined : Icons.link_outlined, color: linked ? const Color(0xff067647) : const Color(0xffB54708))),
              const SizedBox(width: 12),
              Expanded(child: Text(child.name, style: Theme.of(context).textTheme.titleMedium)),
              Icon(Icons.chevron_left, color: Theme.of(context).colorScheme.outline),
            ]),
            const SizedBox(height: 14),
            _StatusBadge(linked: linked),
            const SizedBox(height: 14),
            Row(children: [
              OutlinedButton.icon(onPressed: onOpen, icon: const Icon(Icons.visibility_outlined), label: const Text('عرض الطفل')),
              const SizedBox(width: 10),
              if (!linked) FilledButton.tonal(onPressed: onPair, child: const Text('رمز الربط')),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.linked});
  final bool linked;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: linked ? const Color(0xffECFDF3) : const Color(0xffFFF7ED), borderRadius: BorderRadius.circular(99)),
        child: Text(linked ? 'الجهاز مرتبط' : 'بانتظار الربط', style: TextStyle(color: linked ? const Color(0xff067647) : const Color(0xffB54708), fontWeight: FontWeight.w600)),
      );
}

class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.alert, required this.childName});
  final FamilyAlert alert;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final isUrgent = alert.type == 'safe_zone_exit';
    final icon = isUrgent ? Icons.warning_amber_rounded : Icons.notifications_none_outlined;
    final color = isUrgent ? const Color(0xffB42318) : const Color(0xff155EEF);
    return Card(child: ListTile(leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)), title: Text(childName), subtitle: Text(alert.message), trailing: alert.createdAt == null ? null : Text(_compactTime(alert.createdAt!), style: Theme.of(context).textTheme.labelSmall)));
  }
}

String _compactTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _create() async {
    final value = _name.text.trim();
    if (value.isEmpty) { setState(() => _error = 'اكتب اسم الطفل أولاً.'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final child = await ref.read(familyRepositoryProvider).addChild(familyId: widget.familyId, name: value);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PairingCodeScreen(familyId: widget.familyId, child: child, createdNow: true)));
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إنشاء الطفل الآن. تحقق من الاتصال ثم حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إضافة طفل')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Icon(Icons.person_add_alt_1_outlined, size: 48, color: Color(0xff155EEF)),
            const SizedBox(height: 16),
            Text('لنربط جهاز الطفل', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('بعد حفظ الاسم، سنعرض رمزاً رقمياً وQR لمسحه من تطبيق KidSafe Child.'),
            const SizedBox(height: 28),
            TextField(controller: _name, autofocus: true, textInputAction: TextInputAction.done, onSubmitted: (_) => _create(), decoration: const InputDecoration(labelText: 'اسم الطفل', hintText: 'مثال: أحمد')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Color(0xffB42318)))),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: _saving ? null : _create, icon: const Icon(Icons.qr_code_2), label: Text(_saving ? 'جارٍ الإنشاء...' : 'إنشاء رمز الربط'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
          ]),
        ),
      );
}

class PairingCodeScreen extends ConsumerStatefulWidget {
  const PairingCodeScreen({super.key, required this.familyId, required this.child, this.createdNow = false});
  final String familyId;
  final ChildProfile child;
  final bool createdNow;

  @override
  ConsumerState<PairingCodeScreen> createState() => _PairingCodeScreenState();
}

class _PairingCodeScreenState extends ConsumerState<PairingCodeScreen> {
  String? _code;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _createCode(); }

  Future<void> _createCode() async {
    setState(() { _loading = true; _error = null; });
    try {
      final code = await ref.read(familyRepositoryProvider).createPairing(familyId: widget.familyId, childId: widget.child.id);
      if (mounted) setState(() => _code = code);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر إنشاء الرمز. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final payload = code == null ? null : pairingPayload(familyId: widget.familyId, childId: widget.child.id, code: code);
    return Scaffold(
      appBar: AppBar(title: Text('ربط جهاز ${widget.child.name}')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(widget.createdNow ? 'تمت إضافة ${widget.child.name}' : 'رمز ربط ${widget.child.name}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('على جهاز الطفل، افتح KidSafe Child، واختر «جهاز الطفل»، ثم امسح QR أو أدخل الرمز التالي.'),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _loading
                  ? const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()))
                  : _error != null
                      ? SizedBox(height: 250, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _createCode, child: const Text('إعادة المحاولة'))])))
                      : Column(children: [
                          QrImageView(data: payload!, size: 210),
                          const SizedBox(height: 16),
                          SelectableText(code!, style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 5, fontWeight: FontWeight.bold)),
                        ]),
            ),
          ),
          const SizedBox(height: 14),
          const ListTile(leading: Icon(Icons.timer_outlined), title: Text('الرمز صالح لمدة 10 دقائق'), subtitle: Text('يمكن إنشاء رمز جديد من بطاقة الطفل إذا انتهت المدة.')),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(onPressed: _loading ? null : _createCode, icon: const Icon(Icons.refresh), label: const Text('إنشاء رمز جديد')),
        ]),
      ),
    );
  }
}

class AccountAndFamilyScreen extends ConsumerWidget {
  const AccountAndFamilyScreen({super.key, required this.profile});
  final GuardianProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('الحساب والأسرة')),
        body: StreamBuilder<List<ChildProfile>>(
          stream: ref.watch(familyRepositoryProvider).watchChildren(profile.familyId),
          builder: (context, snapshot) {
            final children = snapshot.data ?? const <ChildProfile>[];
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(profile.displayName?.trim().isNotEmpty == true ? profile.displayName! : 'حساب الوالد'), subtitle: const Text('حساب إدارة KidSafe'))),
              GuardianPushEnrollment(profile: profile),
              const SizedBox(height: 8),
              Card(child: ListTile(leading: const Icon(Icons.manage_accounts_outlined), title: const Text('إدارة الأطفال'), subtitle: Text('${children.length} أطفال مسجلون — تعديل الاسم أو إزالة جهاز من العائلة.'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FamilyManagementScreen(profile: profile, children: children))))),
              Card(child: ListTile(leading: const Icon(Icons.logout), title: const Text('تسجيل الخروج'), onTap: () async => await ref.read(familyRepositoryProvider).signOut())),
            ]);
          },
        ),
      );
}

class FamilyManagementScreen extends ConsumerWidget {
  const FamilyManagementScreen({super.key, required this.profile, required this.children});
  final GuardianProfile profile;
  final List<ChildProfile> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('إدارة الأطفال')),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddChildScreen(familyId: profile.familyId))), icon: const Icon(Icons.person_add_alt_1), label: const Text('إضافة طفل')),
        body: children.isEmpty
            ? EmptyChildrenCard(onAddChild: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddChildScreen(familyId: profile.familyId))))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 92), children: [
                const Text('يمكنك تعديل اسم الطفل أو إزالة سجله من العائلة. الإزالة لا تتم إلا بعد تأكيد صريح.'),
                const SizedBox(height: 14),
                ...children.map((child) => Card(child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.child_care_outlined)),
                      title: Text(child.name),
                      subtitle: Text(child.deviceStatus == 'linked' ? 'الجهاز مرتبط' : 'بانتظار الربط'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: () => _editChild(context, ref, child), icon: const Icon(Icons.edit_outlined), tooltip: 'تعديل الاسم'),
                        IconButton(onPressed: () => _confirmRemove(context, ref, child), icon: const Icon(Icons.delete_outline, color: Color(0xffB42318)), tooltip: 'إزالة الطفل'),
                      ]),
                    ))),
              ]),
      );

  Future<void> _editChild(BuildContext context, WidgetRef ref, ChildProfile child) async {
    final name = TextEditingController(text: child.name);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تعديل اسم ${child.name}'),
        content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم الطفل')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () async { await ref.read(familyRepositoryProvider).renameChild(familyId: profile.familyId, childId: child.id, name: name.text); if (dialogContext.mounted) Navigator.pop(dialogContext); }, child: const Text('حفظ')),
        ],
      ),
    );
    name.dispose();
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, ChildProfile child) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Color(0xffB42318)),
        title: Text('إزالة ${child.name}؟'),
        content: const Text('سيُزال الطفل من لوحة العائلة ولن يعود جهازه قادراً على تحديث بيانات هذه الأسرة. لا يمكن التراجع عن هذه العملية من التطبيق.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () async { await ref.read(familyRepositoryProvider).removeChild(familyId: profile.familyId, childId: child.id); if (dialogContext.mounted) Navigator.pop(dialogContext); }, style: FilledButton.styleFrom(backgroundColor: const Color(0xffB42318)), child: const Text('إزالة الطفل')),
        ],
      ),
    );
  }
}

class GuardianPushEnrollment extends ConsumerStatefulWidget {
  const GuardianPushEnrollment({super.key, required this.profile});
  final GuardianProfile profile;

  @override
  ConsumerState<GuardianPushEnrollment> createState() => _GuardianPushEnrollmentState();
}

class _GuardianPushEnrollmentState extends ConsumerState<GuardianPushEnrollment> {
  String _status = 'جارٍ التحقق من تنبيهات السلامة على جهاز الوالد...';

  @override
  void initState() {
    super.initState();
    _register();
  }

  Future<void> _register() async {
    if (kIsWeb) {
      if (mounted) setState(() => _status = 'تنبيهات المتصفح تحتاج مفتاح Web Push قبل تفعيلها. تعمل لوحة الويب لإدارة الأسرة الآن.');
      return;
    }
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || settings.authorizationStatus == AuthorizationStatus.denied) {
        if (mounted) setState(() => _status = 'لم يُمنح إذن التنبيهات. يمكنك تفعيله من إعدادات Android لتلقي تنبيه الخروج فوراً.');
        return;
      }
      await ref.read(safetyRepositoryProvider).registerGuardianPushToken(familyId: widget.profile.familyId, token: token);
      if (mounted) setState(() => _status = 'تنبيهات السلامة مفعّلة على هذا الجهاز.');
    } catch (_) {
      if (mounted) setState(() => _status = 'تعذر تسجيل التنبيهات الآن. تحقق من الاتصال وإذن الإشعارات.');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(child: ListTile(leading: const Icon(Icons.notifications_active_outlined), title: const Text('تنبيهات السلامة'), subtitle: Text(_status))),
      );
}

class ChildSafetyScreen extends ConsumerWidget {
  const ChildSafetyScreen({super.key, required this.familyId, required this.child});
  final String familyId;
  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('سلامة ${child.name}'), actions: [
        IconButton(
          onPressed: () => _startSession(context, ref, FamilySessionKind.screen),
          icon: const Icon(Icons.screen_share_outlined),
          tooltip: 'طلب مشاركة شاشة معلن',
        ),
        IconButton(
          onPressed: () => _startSession(context, ref, FamilySessionKind.video),
          icon: const Icon(Icons.videocam_outlined),
          tooltip: 'جلسة فيديو عائلية معلنة',
        ),
        IconButton(
          onPressed: () => _startSession(context, ref, FamilySessionKind.audio),
          icon: const Icon(Icons.call_outlined),
          tooltip: 'جلسة صوت عائلية معلنة',
        ),
        IconButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppPolicyScreen(familyId: familyId, child: child))),
          icon: const Icon(Icons.apps_outage_outlined),
          tooltip: 'سياسات التطبيقات',
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showZoneEditor(context, ref),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('منطقة آمنة'),
      ),
      body: StreamBuilder<List<SafeZone>>(
        stream: safety.watchSafeZones(familyId),
        builder: (context, zonesSnapshot) => StreamBuilder<ChildLocation?>(
          stream: safety.watchChildLocation(familyId: familyId, childId: child.id),
          builder: (context, locationSnapshot) {
            final zones = zonesSnapshot.data ?? const <SafeZone>[];
            final location = locationSnapshot.data;
            final center = location == null ? const LatLng(30.0444, 31.2357) : LatLng(location.latitude, location.longitude);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 280,
                  child: FlutterMap(
                    options: MapOptions(initialCenter: center, initialZoom: location == null ? 10 : 15),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.app.kidsafeguardian'),
                      if (location != null) MarkerLayer(markers: [Marker(point: center, width: 50, height: 50, child: const Icon(Icons.location_on, color: Colors.red, size: 42))]),
                      if (zones.isNotEmpty) CircleLayer(circles: zones.map((zone) => CircleMarker(point: LatLng(zone.latitude, zone.longitude), radius: zone.radiusMeters, useRadiusInMeter: true, color: const Color(0xff155EEF).withValues(alpha: .14), borderColor: const Color(0xff155EEF), borderStrokeWidth: 2)).toList()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(child: ListTile(
                leading: const Icon(Icons.my_location_outlined),
                title: Text(location == null ? 'لا يوجد موقع حديث بعد' : 'آخر تحديث للموقع: ${location.recordedAt.toLocal()}'),
                subtitle: Text(location == null ? 'افتح KidSafe على جهاز الطفل وامنح إذن الموقع ثم اختر «تحديث الآن».' : 'الدقة: ${location.accuracyMeters.round()} متر'),
              )),
              const SizedBox(height: 14),
              Text('المناطق الآمنة', style: Theme.of(context).textTheme.titleLarge),
              if (zones.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('لم تُضف مناطق آمنة بعد. أضف المنزل أو المدرسة بإحداثياته ونطاقه.')),
              ...zones.map((zone) => Card(child: ListTile(
                leading: const Icon(Icons.fence_outlined),
                title: Text(zone.name),
                subtitle: Text('النطاق: ${zone.radiusMeters.round()} متر • ${zone.enabled ? 'مفعّلة' : 'متوقفة'}'),
                trailing: IconButton(onPressed: () => safety.removeSafeZone(familyId: familyId, zoneId: zone.id), icon: const Icon(Icons.delete_outline), tooltip: 'حذف المنطقة'),
              ))),
              const SizedBox(height: 88),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _showZoneEditor(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(text: 'المنزل');
    final latitude = TextEditingController(text: '30.0444');
    final longitude = TextEditingController(text: '31.2357');
    final radius = TextEditingController(text: '150');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة منطقة آمنة'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(controller: latitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط العرض')),
          TextField(controller: longitude, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'خط الطول')),
          TextField(controller: radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'النطاق بالمتر')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final lat = double.tryParse(latitude.text);
              final lon = double.tryParse(longitude.text);
              final meters = double.tryParse(radius.text);
              if (lat == null || lon == null || meters == null || meters <= 0) return;
              await ref.read(safetyRepositoryProvider).saveSafeZone(
                familyId: familyId,
                zone: SafeZone(id: 'zone-${DateTime.now().millisecondsSinceEpoch}', name: name.text.trim(), latitude: lat, longitude: lon, radiusMeters: meters, enabled: true),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('حفظ المنطقة'),
          ),
        ],
      ),
    );
    name.dispose(); latitude.dispose(); longitude.dispose(); radius.dispose();
  }

  Future<void> _startSession(BuildContext context, WidgetRef ref, FamilySessionKind kind) async {
    final session = await ref.read(sessionRepositoryProvider).createRequest(
      familyId: familyId,
      childId: child.id,
      kind: kind,
      reason: switch (kind) {
        FamilySessionKind.video => 'جلسة عائلية مرئية من الوالد.',
        FamilySessionKind.audio => 'جلسة عائلية صوتية من الوالد.',
        FamilySessionKind.screen => 'مراجعة ومشاركة شاشة جهاز الطفل بصورة ظاهرة.',
      },
    );
    if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuardianFamilySessionScreen(session: session)));
  }
}

class GuardianFamilySessionScreen extends ConsumerStatefulWidget {
  const GuardianFamilySessionScreen({super.key, required this.session});
  final FamilySession session;

  @override
  ConsumerState<GuardianFamilySessionScreen> createState() => _GuardianFamilySessionScreenState();
}

class _GuardianFamilySessionScreenState extends ConsumerState<GuardianFamilySessionScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  DirectFamilyConnection? _connection;
  StreamSubscription<List<SessionSignal>>? _signals;
  String _status = 'جارٍ تجهيز جلسة KidSafe المعلنة...';
  bool _ready = false;

  @override
  void initState() { super.initState(); _start(); }

  Future<void> _start() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    final repository = ref.read(sessionRepositoryProvider);
    final connection = DirectFamilyConnection(
      kind: widget.session.kind,
      writeSignal: (kind, payload) => repository.sendSignal(familyId: widget.session.familyId, sessionId: widget.session.id, sender: SignalSender.guardian, kind: kind, payload: payload),
      onRemoteStream: (stream) { _remoteRenderer.srcObject = stream; if (mounted) setState(() => _status = 'تم ربط بث جهاز الطفل بصورة ظاهرة.'); },
    );
    _connection = connection;
    try {
      await connection.initialize();
      _localRenderer.srcObject = connection.localStream;
      _signals = repository.watchPeerSignals(familyId: widget.session.familyId, sessionId: widget.session.id, ownRole: SignalSender.guardian).listen((signals) async {
        for (final signal in signals) { await connection.applyPeerSignal(signal); }
      });
      await repository.setStatus(familyId: widget.session.familyId, sessionId: widget.session.id, status: FamilySessionStatus.active);
      await connection.startOffer();
      if (mounted) setState(() { _ready = true; _status = 'تم إرسال طلب الجلسة. يظهر على جهاز الطفل سبب الجلسة وحالتها.'; });
    } catch (_) {
      if (mounted) setState(() => _status = 'تعذر بدء الوسائط. تحقق من إذن الكاميرا أو الميكروفون والاتصال.');
    }
  }

  Future<void> _end() async {
    await ref.read(sessionRepositoryProvider).end(familyId: widget.session.familyId, sessionId: widget.session.id, sender: SignalSender.guardian);
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
        appBar: AppBar(title: const Text('جلسة عائلية معلنة')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(color: const Color(0xffEAF2FF), child: Padding(padding: const EdgeInsets.all(16), child: Text(_status))),
          const SizedBox(height: 16),
          if (widget.session.kind == FamilySessionKind.video) ...[
            Text('معاينة الوالد', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 180, child: RTCVideoView(_localRenderer, mirror: true)),
            const SizedBox(height: 16),
            Text('بث جهاز الطفل', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 220, child: RTCVideoView(_remoteRenderer)),
          ] else if (widget.session.kind == FamilySessionKind.screen) ...[
            Text('مشاركة شاشة جهاز الطفل', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(height: 360, child: RTCVideoView(_remoteRenderer)),
          ] else
            const ListTile(leading: Icon(Icons.volume_up_outlined), title: Text('جلسة صوت عائلية'), subtitle: Text('يظهر تشغيل الميكروفون على جهاز الطفل كحالة معلنة.')),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _ready ? _end : null, icon: const Icon(Icons.call_end), label: const Text('إنهاء الجلسة')),
        ]),
      );
}

class AppPolicyScreen extends ConsumerWidget {
  const AppPolicyScreen({super.key, required this.familyId, required this.child});
  final String familyId;
  final ChildProfile child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policies = ref.watch(policyRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text('تطبيقات ${child.name}')),
      body: StreamBuilder<FamilyAppPolicy>(
        stream: policies.watchPolicy(familyId, child.id),
        builder: (context, policySnapshot) => StreamBuilder<List<DeviceAppRecord>>(
          stream: policies.watchInstalledApps(familyId, child.id),
          builder: (context, appsSnapshot) {
            final policy = policySnapshot.data ?? const FamilyAppPolicy(allowedPackages: [], dailyLimitMinutes: 0, blockedStartMinute: null, blockedEndMinute: null, updatedAt: null);
            final apps = appsSnapshot.data ?? const <DeviceAppRecord>[];
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('سياسة العائلة', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('التطبيقات المسموحة: ${policy.allowedPackages.length} • الحد اليومي: ${policy.dailyLimitMinutes == 0 ? 'غير محدد' : '${policy.dailyLimitMinutes} دقيقة'}'),
                if (policy.blockedStartMinute != null) Text('فترة المنع اليومية: ${_formatMinute(policy.blockedStartMinute!)} إلى ${_formatMinute(policy.blockedEndMinute!)}'),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: apps.isEmpty ? null : () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => AppPolicyEditor(familyId: familyId, childId: child.id, apps: apps, initialPolicy: policy)), icon: const Icon(Icons.tune), label: const Text('تعديل السياسة')),
              ]))),
              const SizedBox(height: 14),
              Text('التطبيقات المزامنة من جهاز الطفل', style: Theme.of(context).textTheme.titleLarge),
              if (apps.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('لم تصل قائمة التطبيقات بعد. على جهاز الطفل، افتح KidSafe واختر «مزامنة» في قسم التطبيقات.')),
              ...apps.map((app) => Card(child: ListTile(
                leading: const Icon(Icons.android_outlined),
                title: Text(app.label),
                subtitle: Text(app.packageName),
                trailing: Icon(policy.allowedPackages.contains(app.packageName) ? Icons.check_circle : Icons.remove_circle_outline, color: policy.allowedPackages.contains(app.packageName) ? Colors.green : null),
              ))),
            ]);
          },
        ),
      ),
    );
  }
}

String _formatMinute(int minute) => '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class AppPolicyEditor extends ConsumerStatefulWidget {
  const AppPolicyEditor({super.key, required this.familyId, required this.childId, required this.apps, required this.initialPolicy});
  final String familyId;
  final String childId;
  final List<DeviceAppRecord> apps;
  final FamilyAppPolicy initialPolicy;

  @override
  ConsumerState<AppPolicyEditor> createState() => _AppPolicyEditorState();
}

class _AppPolicyEditorState extends ConsumerState<AppPolicyEditor> {
  late final Set<String> _allowed = widget.initialPolicy.allowedPackages.toSet();
  late final TextEditingController _dailyLimit = TextEditingController(text: widget.initialPolicy.dailyLimitMinutes == 0 ? '' : '${widget.initialPolicy.dailyLimitMinutes}');
  late TimeOfDay _blockedStart = TimeOfDay(hour: (widget.initialPolicy.blockedStartMinute ?? 1320) ~/ 60, minute: (widget.initialPolicy.blockedStartMinute ?? 1320) % 60);
  late TimeOfDay _blockedEnd = TimeOfDay(hour: (widget.initialPolicy.blockedEndMinute ?? 420) ~/ 60, minute: (widget.initialPolicy.blockedEndMinute ?? 420) % 60);
  bool _saving = false;

  @override
  void dispose() { _dailyLimit.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: .86,
            minChildSize: .5,
            maxChildSize: .95,
            builder: (context, controller) => Column(children: [
              Text('تعديل سياسة التطبيقات', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              TextField(controller: _dailyLimit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد الاستخدام اليومي بالدقائق (اختياري)')),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('فترة منع يومية'),
                subtitle: Text('${_blockedStart.format(context)} إلى ${_blockedEnd.format(context)} — تُنفذ في وضع الإدارة الكاملة.'),
                trailing: TextButton(
                  onPressed: () async {
                    final start = await showTimePicker(context: context, initialTime: _blockedStart);
                    if (start == null || !mounted) return;
                    final end = await showTimePicker(context: this.context, initialTime: _blockedEnd);
                    if (end != null && mounted) setState(() { _blockedStart = start; _blockedEnd = end; });
                  },
                  child: const Text('تعديل'),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: ListView.builder(
                controller: controller,
                itemCount: widget.apps.length,
                itemBuilder: (context, index) {
                  final app = widget.apps[index];
                  return CheckboxListTile(
                    value: _allowed.contains(app.packageName),
                    onChanged: (value) => setState(() { if (value ?? false) { _allowed.add(app.packageName); } else { _allowed.remove(app.packageName); } }),
                    title: Text(app.label),
                    subtitle: Text(app.packageName),
                  );
                },
              )),
              FilledButton(
                onPressed: _saving ? null : () async {
                  setState(() => _saving = true);
                  await ref.read(policyRepositoryProvider).savePolicy(
                    familyId: widget.familyId,
                    childId: widget.childId,
                    policy: FamilyAppPolicy(
                      allowedPackages: _allowed.toList()..sort(),
                      dailyLimitMinutes: int.tryParse(_dailyLimit.text) ?? 0,
                      blockedStartMinute: _blockedStart.hour * 60 + _blockedStart.minute,
                      blockedEndMinute: _blockedEnd.hour * 60 + _blockedEnd.minute,
                      updatedAt: DateTime.now(),
                    ),
                  );
                  if (mounted) Navigator.of(this.context).pop();
                },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ السياسة'),
              ),
            ]),
          ),
        ),
      );
}

class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.title, required this.subtitle, required this.child});
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
                        const Icon(Icons.shield_moon_outlined, size: 48, color: Color(0xff155EEF)),
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

class SafetyHero extends StatelessWidget {
  const SafetyHero({super.key});
  @override
  Widget build(BuildContext context) => Card(color: const Color(0xffEAF2FF), child: const Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.family_restroom, color: Color(0xff155EEF)), SizedBox(height: 8), Text('أمان العائلة بوضوح', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), SizedBox(height: 6), Text('الموقع والسياسات والجلسات الحساسة تُسجّل للعائلة، وتظهر على جهاز الطفل عند تشغيلها.')]))) ;
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
