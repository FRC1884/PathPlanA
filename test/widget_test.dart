import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:pathplana_app/main.dart";

void main() {
  testWidgets("PathPlanA smoke test", (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const PathPlanAApp());
    await tester.pumpAndSettle();

    expect(find.text("PathPlanA"), findsOneWidget);
    expect(find.text("Auto Library"), findsOneWidget);
    expect(find.text("Library"), findsOneWidget);
  });
}
