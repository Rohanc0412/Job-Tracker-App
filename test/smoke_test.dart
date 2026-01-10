import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/app.dart';

void main() {
  testWidgets('app boots to dashboard', (tester) async {
    await tester.pumpWidget(const JobTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
  });
}
