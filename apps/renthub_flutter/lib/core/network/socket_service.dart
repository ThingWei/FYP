import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  SocketService(String url)
      : _socket = io.io(url, {
          'transports': ['websocket'],
          'autoConnect': false,
        });
  final io.Socket _socket;
  void connect() => _socket.connect();
  void join(String id) => _socket.emit('thread:join', id);
  void send(Map<String, dynamic> message) =>
      _socket.emit('message:new', message);
  void onMessage(void Function(dynamic) handler) =>
      _socket.on('message:new', handler);
  void dispose() => _socket.dispose();
}
