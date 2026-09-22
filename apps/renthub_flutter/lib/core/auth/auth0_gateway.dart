export 'auth0_gateway_stub.dart'
    if (dart.library.io) 'auth0_gateway_native.dart'
    if (dart.library.js_interop) 'auth0_gateway_web.dart';
