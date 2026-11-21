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
  final _caseUpdates = StreamController<dynamic>.broadcast();
  final Map<String, int> _cases = {};

  Stream<dynamic> get messages => _messages.stream;
  Stream<dynamic> get notifications => _notifications.stream;
  Stream<dynamic> get caseUpdates => _caseUpdates.stream;
  void joinCase(String id) {
    _cases[id] = (_cases[id] ?? 0) + 1;
    _socket.emit('case:join', id);
  }

  void leaveCase(String id) {
    final count = (_cases[id] ?? 0) - 1;
    if (count > 0) {
      _cases[id] = count;
    } else {
      _cases.remove(id);
      _socket.emit('case:leave', id);
    }
  }

  void connect() => _socket.connect();
  void join(String id) => _socket.emit('thread:join', id);
  void onMessage(void Function(dynamic) handler) => messages.listen(handler);
  void initializeListeners() {
    _socket.onConnect((_) {
      _notifications.add(null);
      for (final id in _cases.keys) {
        _socket.emit('case:join', id);
      }
      _caseUpdates.add(null);
    });
    _socket.on('case:update', (dynamic update) => _caseUpdates.add(update));
    _socket.on('message:new', (dynamic message) => _messages.add(message));
    _socket.on('notification:new', (dynamic note) => _notifications.add(note));
  }

  void dispose() {
    _messages.close();
    _notifications.close();
    _caseUpdates.close();
    _socket.dispose();
  }
}
