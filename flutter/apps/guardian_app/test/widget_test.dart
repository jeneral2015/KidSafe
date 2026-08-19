// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
