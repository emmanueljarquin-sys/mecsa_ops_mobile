// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:mecsa_ops_mobile/main.dart';

void main() {
  testWidgets('Smoke test de inicio de app', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MecsaOpsApp());

    // Esperar a que se renderice todo
    await tester.pumpAndSettle();

    // Verificar que el dashboard carga buscando un texto conocido
    expect(find.text('Panel de control operativo'), findsOneWidget);
  });
}
