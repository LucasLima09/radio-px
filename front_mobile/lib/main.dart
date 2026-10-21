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
          seedColor: const Color(0xFFB9B2FF),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFFB9B2FF),
          onPrimary: const Color(0xFF101116),
          surface: const Color(0xFF101116),
        ),
        scaffoldBackgroundColor: const Color(0xFF101116),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101116),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFFF0F0F5),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 15, color: Color(0xFFF0F0F5)),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFD0D1DC)),
          titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF181920),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF2B2D36)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF2B2D36)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFB9B2FF)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF2B2D36),
          thickness: 1,
          space: 1,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
