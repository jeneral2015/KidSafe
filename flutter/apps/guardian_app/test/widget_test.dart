// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kidsafe_core/kidsafe_core.dart';

import 'package:guardian_app/main.dart';

void main() {
  testWidgets('guardian authentication shell renders Arabic product content', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AuthShell(
        title: 'KidSafe Guardian',
        subtitle: 'واجهة اختبار',
        child: Text('مرحباً بك في KidSafe'),
      ),
    ));
    expect(find.text('KidSafe Guardian'), findsOneWidget);
    expect(find.text('مرحباً بك في KidSafe'), findsOneWidget);
  });

  testWidgets('family overview presents children and the add-child action clearly', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          FamilySummaryCard(
            profile: const GuardianProfile(id: 'guardian-1', familyId: 'family-1', role: FamilyRole.owner, displayName: 'محمود'),
            childCount: 1,
            onManageFamily: () {},
          ),
          const EmptyChildrenCard(onAddChild: _noop),
          ChildOverviewCard(
            child: const ChildProfile(id: 'child-1', familyId: 'family-1', name: 'آدم', deviceStatus: 'linked'),
            onOpen: _noop,
            onPair: _noop,
          ),
        ]),
      ),
    ));

    expect(find.text('مرحباً محمود'), findsOneWidget);
    expect(find.text('إضافة أول طفل'), findsOneWidget);
    expect(find.text('آدم'), findsOneWidget);
    expect(find.text('الجهاز مرتبط'), findsOneWidget);
  });
}

void _noop() {}
