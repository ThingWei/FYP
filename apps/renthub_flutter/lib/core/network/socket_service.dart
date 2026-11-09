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
  final _notifications = StreamController<dynamic>.broadcast();

  Stream<dynamic> get messages => _messages.stream;
  Stream<dynamic> get notifications => _notifications.stream;

  void connect() => _socket.connect();
  void join(String id) => _socket.emit('thread:join', id);
  void onMessage(void Function(dynamic) handler) => messages.listen(handler);
  void initializeListeners() {
    _socket.onConnect((_) => _notifications.add(null));
    _socket.on('message:new', (dynamic message) => _messages.add(message));
    _socket.on('notification:new', (dynamic note) => _notifications.add(note));
  }

  void dispose() {
    _messages.close();
    _notifications.close();
    _socket.dispose();
  }
}
