import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:essential_guest/main.dart';

/// Tall phone-shaped test screen (400 x 1400 logical px) so the whole form is laid out.
void _phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the check-in form with purpose chips', (tester) async {
    _phoneScreen(tester);
    await tester.pumpWidget(const GuestApp());
    await tester.pumpAndSettle();
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('Site visit'), findsOneWidget);
    expect(find.text('Remember my details on this phone'), findsOneWidget);
  });

  testWidgets('validates name and mobile number', (tester) async {
    _phoneScreen(tester);
    await tester.pumpWidget(const GuestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check in'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Please enter your mobile number'), findsOneWidget);
  });

  testWidgets('choosing Other reveals a text box', (tester) async {
    _phoneScreen(tester);
    await tester.pumpWidget(const GuestApp());
    await tester.pumpAndSettle();
    expect(find.text("Tell us briefly why you're visiting"), findsNothing);
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(find.text("Tell us briefly why you're visiting"), findsOneWidget);
  });

  testWidgets('remembered guest sees welcome back and can forget', (tester) async {
    SharedPreferences.setMockInitialValues({
      'guest_remember_name': 'Priya Raman',
      'guest_remember_phone': '9876543210',
    });
    _phoneScreen(tester);
    await tester.pumpWidget(const GuestApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome back, Priya!'), findsOneWidget);
    await tester.tap(find.text('Not you?'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back, Priya!'), findsNothing);
  });

  testWidgets('fits a small phone without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({
      'guest_remember_name': 'Venkatanarayanan Subramaniam',
      'guest_remember_phone': '9876543210',
    });
    tester.view.physicalSize = const Size(960, 1920); // 320 x 640 logical
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GuestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
