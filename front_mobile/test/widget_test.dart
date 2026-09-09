import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_mobile/main.dart';

void main() {
  testWidgets('App boot smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const RadioPxApp());
    await tester.pump();

    expect(find.text('Radio PX'), findsOneWidget);
  });
}