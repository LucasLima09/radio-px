import 'package:flutter/material.dart';

import 'models/active_session.dart';
import 'models/channel.dart';
import 'views/screens/channel_list_screen.dart';
import 'views/screens/login_screen.dart';
import 'views/screens/register_screen.dart';
import 'views/screens/room_screen.dart';

/// Nomes das rotas do app.
class AppRoutes {
  const AppRoutes._();

  static const login = '/';
  static const register = '/register';
  static const channels = '/channels';
  static const room = '/room';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case register:
        final serverUrl = settings.arguments as String?;
        return _page(settings, (_) => RegisterScreen(serverUrl: serverUrl));
      case channels:
        final session = settings.arguments as ActiveSession;
        return _page(settings, (_) => ChannelListScreen(session: session));
      case room:
        final args = settings.arguments as RoomArgs;
        return _page(
          settings,
          (_) => RoomScreen(session: args.session, channel: args.channel),
        );
      case login:
      default:
        return _page(settings, (_) => const LoginScreen());
    }
  }

  static Route<dynamic> _page(RouteSettings settings, WidgetBuilder builder) =>
      MaterialPageRoute(builder: builder, settings: settings);
}

/// Argumentos da rota da sala.
class RoomArgs {
  const RoomArgs({required this.session, required this.channel});

  final ActiveSession session;
  final Channel channel;
}
