import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('App starts and renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.byType(MyApp), findsOneWidget);
    // You can add more specific assertions here if needed,
    // for example, to check for the presence of key widgets on the dashboard.
  });
}
