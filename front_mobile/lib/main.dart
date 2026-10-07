import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    // Canal de comunicação entre o TaskHandler (isolado do beacon) e a UI.
    FlutterForegroundTask.initCommunicationPort();
  }
  runApp(const RadioPxApp());
}

class RadioPxApp extends StatefulWidget {
  const RadioPxApp({super.key});

  @override
  State<RadioPxApp> createState() => _RadioPxAppState();
}

class _RadioPxAppState extends State<RadioPxApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tela fica acesa enquanto o app está visível. Em segundo plano, quem
    // mantém a CPU trabalhando é o wake lock do próprio serviço de foreground,
    // sem manter a tela acesa.
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radio PX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}