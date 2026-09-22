import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('auth0.createAuth0Client')
external JSPromise<JSObject> _createAuth0Client(JSAny? options);

class Auth0Session {
  const Auth0Session({required this.accessToken});
  final String accessToken;
}

class Auth0Gateway {
  Auth0Gateway({
    required this.domain,
    required this.clientId,
    required this.audience,
    required this.callbackUrl,
  });

  final String domain;
  final String clientId;
  final String audience;
  final String callbackUrl;
  JSObject? _client;

  Future<JSObject> _initialize() async {
    if (_client != null) return _client!;
    _client = await _createAuth0Client({
      'domain': domain,
      'clientId': clientId,
      'authorizationParams': {
        'audience': audience,
        'redirect_uri': callbackUrl,
      },
      'cacheLocation': 'localstorage',
      'useRefreshTokens': true,
      'useRefreshTokensFallback': true,
    }.jsify())
        .toDart;
    return _client!;
  }

  Future<Auth0Session> login({bool signUp = false}) async {
    final client = await _initialize();
    await client
        .callMethod<JSPromise<JSAny?>>(
          'loginWithPopup'.toJS,
          {
            'authorizationParams': {
              'audience': audience,
              'redirect_uri': callbackUrl,
              if (signUp) 'screen_hint': 'signup',
            },
          }.jsify(),
        )
        .toDart;
    final accessToken = await token();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Auth0 did not return an API access token.');
    }
    return Auth0Session(accessToken: accessToken);
  }

  Future<String?> token() async {
    final client = await _initialize();
    final result = await client
        .callMethod<JSPromise<JSString>>(
          'getTokenSilently'.toJS,
          {
            'authorizationParams': {'audience': audience},
          }.jsify(),
        )
        .toDart;
    return result.toDart;
  }

  Future<void> logout() async {
    final client = await _initialize();
    await client
        .callMethod<JSPromise<JSAny?>>(
          'logout'.toJS,
          {
            'logoutParams': {'returnTo': callbackUrl},
          }.jsify(),
        )
        .toDart;
  }
}
