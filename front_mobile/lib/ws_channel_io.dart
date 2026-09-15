import 'package:web_socket_channel/io.dart' as io_ws;
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> openWsChannel(
    Uri uri, Map<String, String> headers) async {
  return io_ws.IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: const Duration(seconds: 20),
  );
}