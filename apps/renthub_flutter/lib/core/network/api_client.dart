import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  final String? code;
  final Object? details;
  ApiException(this.status, this.message, {this.code, this.details});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUrl, {this.tokenProvider, this.headersProvider});
  final String baseUrl;
  final Future<String?> Function()? tokenProvider;
  final Future<Map<String, String>> Function()? headersProvider;
  Future<dynamic> request(String method, String path, {Object? body}) async {
    final token = await tokenProvider?.call();
    final additionalHeaders = await headersProvider?.call() ?? const {};
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
        ...additionalHeaders,
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await request.send());
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded?['error']?['message'] ?? 'Request failed',
        code: decoded?['error']?['code'],
        details: decoded?['error']?['details'],
      );
    }
    return decoded?['data'];
  }
}
