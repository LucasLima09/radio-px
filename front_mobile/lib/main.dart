import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'di.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Canal de comunicação entre o TaskHandler (isolado do beacon) e a UI.
    FlutterForegroundTask.initCommunicationPort();
  }
  runApp(
    AppScope(
      deps: AppDependencies.production(),
      child: const RadioPxApp(),
    ),
  );
}
