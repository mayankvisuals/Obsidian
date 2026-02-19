import 'package:flutter_test/flutter_test.dart';
import 'package:obsidian/main.dart';

void main() {
  testWidgets('App launches with splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ObsidianApp());
    expect(find.text('Obsidian'), findsOneWidget);
  });
}
