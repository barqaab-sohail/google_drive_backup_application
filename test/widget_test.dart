import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barqaab_google_drive_backup/services/settings.dart';
import 'package:barqaab_google_drive_backup/ui/app.dart';
import 'package:barqaab_google_drive_backup/ui/app_controller.dart';

void main() {
  testWidgets('all desktop screens render and dashboard guides setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AppController(settings: AppSettings(File('unused-settings.json')))
      ..loading = false;
    await tester.pumpWidget(BackupApp(controller: c));
    expect(find.text('Start Backup'), findsOneWidget);
    expect(
      find.text('No sources selected. Open Sources after connecting Google.'),
      findsOneWidget,
    );
    for (final label in [
      'Sources',
      'Backup progress',
      'History',
      'Restore',
      'Settings',
      'Dashboard',
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Start Backup'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Connect Google in Settings first.'),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
