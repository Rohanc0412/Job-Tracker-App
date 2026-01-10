import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/app.dart';

import 'support/fake_application_repo.dart';

void main() {
  testWidgets('app boots to dashboard', (tester) async {
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });

    final repo = FakeApplicationRepo();
    await tester.pumpWidget(JobTrackerApp(repo: repo));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
  });
}
