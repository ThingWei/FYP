import 'dart:convert';
import 'dart:typed_data';
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

  Future<String?> authenticationToken() async => tokenProvider?.call();

  String absoluteUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return value;
    return Uri.parse(baseUrl).resolve(value).toString();
  }

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

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required Uint8List bytes,
    required String filename,
    required String purpose,
  }) async {
    final token = await tokenProvider?.call();
    final additionalHeaders = await headersProvider?.call() ?? const {};
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        if (token != null) 'authorization': 'Bearer $token',
        ...additionalHeaders,
      })
      ..fields['purpose'] = purpose
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await request.send());
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded?['error']?['message'] ?? 'Upload failed',
        code: decoded?['error']?['code'],
        details: decoded?['error']?['details'],
      );
    }
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }
}
