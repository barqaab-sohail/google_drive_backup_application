import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/app.dart';
import 'ui/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1240, 820),
        minimumSize: Size(950, 650),
        title: 'BARQAAB Drive Backup',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await windowManager.setPreventClose(true);
  }
  final controller = AppController();
  runApp(BackupApp(controller: controller));
  await controller.initialize();
}
