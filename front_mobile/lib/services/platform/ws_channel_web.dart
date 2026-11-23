import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> openWsChannel(
    Uri uri, Map<String, String> headers) async {
  return WebSocketChannel.connect(uri);
}