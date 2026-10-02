import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  SocketService(
    String url, {
    String? userId,
    Future<String?> Function()? tokenProvider,
  }) : _socket = io.io(url, {
          'transports': ['websocket'],
          'autoConnect': false,
          if (tokenProvider != null)
            'auth': (void Function(Map<dynamic, dynamic>) callback) {
              tokenProvider().then(
                (token) => callback({
                  if (token != null) 'token': token,
                  if (token == null && userId != null) 'userId': userId,
                }),
                onError: (_) => callback({
                  if (userId != null) 'userId': userId,
                }),
              );
            }
          else if (userId != null)
            'auth': {'userId': userId},
        });
  final io.Socket _socket;
  final _messages = StreamController<dynamic>.broadcast();

  Stream<dynamic> get messages => _messages.stream;

  void connect() => _socket.connect();
  void join(String id) => _socket.emit('thread:join', id);
  void onMessage(void Function(dynamic) handler) => messages.listen(handler);
  void initializeListeners() =>
      _socket.on('message:new', (dynamic message) => _messages.add(message));
  void dispose() {
    _messages.close();
    _socket.dispose();
  }
}
