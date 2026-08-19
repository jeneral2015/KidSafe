// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:child_app/main.dart';

void main() {
  testWidgets('child pairing shell renders transparent setup content', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ChildShell(
        title: 'إعداد جهاز الطفل',
        subtitle: 'واجهة اختبار',
        child: Text('رمز الاقتران (8 أرقام)'),
      ),
    ));
    expect(find.text('إعداد جهاز الطفل'), findsOneWidget);
    expect(find.text('رمز الاقتران (8 أرقام)'), findsOneWidget);
  });
}
