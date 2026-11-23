import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'routes.dart';
import 'theme/app_theme.dart';

/// Raiz do app.
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
    // A tela fica acesa enquanto o app está visível. Em segundo plano, quem
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
      theme: AppTheme.dark,
      initialRoute: AppRoutes.login,
      onGenerateRoute: AppRoutes.onGenerateRoute,
    );
  }
}
