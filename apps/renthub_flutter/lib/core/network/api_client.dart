import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  ApiClient(this.baseUrl,
      {this.tokenProvider,
      this.headersProvider,
      this.downloadClient,
      this.client});
  final String baseUrl;
  final Future<String?> Function()? tokenProvider;
  final Future<Map<String, String>> Function()? headersProvider;
  final http.Client? downloadClient;
  final http.Client? client;

  dynamic _decode(http.Response response) {
    try {
      if (response.statusCode == 204 && response.body.isEmpty) {
        return {'data': null};
      }
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (decoded != null && decoded is! Map) {
        throw const FormatException();
      }
      if (response.statusCode < 400 && decoded is! Map) {
        throw const FormatException();
      }
      if (response.statusCode < 400 && !(decoded as Map).containsKey('data')) {
        throw const FormatException();
      }
      return decoded;
    } on FormatException {
      throw ApiException(response.statusCode >= 400 ? response.statusCode : 502,
          'Unexpected response from RentHub',
          code: 'INVALID_RESPONSE');
    }
  }

  static String get _clientDescription =>
      'RentHub ${kIsWeb ? 'Web' : 'App'} on ${defaultTargetPlatform.name}';

  Future<String?> authenticationToken() async => tokenProvider?.call();

  String absoluteUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return value;
    return Uri.parse(baseUrl).resolve(value).toString();
  }

  Future<dynamic> request(String method, String path, {Object? body}) =>
      _request(method, path, body: body, authenticated: true);

  Future<dynamic> requestUnauthenticated(
    String method,
    String path, {
    Object? body,
  }) =>
      _request(method, path, body: body, authenticated: false);

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    required bool authenticated,
  }) async {
    final token = authenticated ? await tokenProvider?.call() : null;
    final additionalHeaders = authenticated
        ? await headersProvider?.call() ?? const {}
        : const <String, String>{};
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'content-type': 'application/json',
        'x-renthub-client': _clientDescription,
        if (token != null) 'authorization': 'Bearer $token',
        ...additionalHeaders,
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
        await (client?.send(request) ?? request.send()));
    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      final payload = decoded?['error'];
      final errorPayload = payload is Map ? payload : const <String, dynamic>{};
      final rawMessage =
          errorPayload['message']?.toString() ?? 'Request failed';
      final errorDetails = errorPayload['details'];
      String message = rawMessage;
      if (errorDetails is List && errorDetails.isNotEmpty) {
        final parts = errorDetails
            .map((item) {
              if (item is Map) {
                final field = item['field']?.toString();
                final detail = item['message']?.toString();
                if ((field ?? '').isNotEmpty && (detail ?? '').isNotEmpty) {
                  return '$field: $detail';
                }
                if ((detail ?? '').isNotEmpty) return detail!;
              }
              return item.toString();
            })
            .where((item) => item.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          message = '$rawMessage (${parts.join('; ')})';
        }
      }
      throw ApiException(
        response.statusCode,
        message,
        code: errorPayload['code']?.toString(),
        details: errorDetails,
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
        'x-renthub-client': _clientDescription,
        if (token != null) 'authorization': 'Bearer $token',
        ...additionalHeaders,
      })
      ..fields['purpose'] = purpose
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(
        await (client?.send(request) ?? request.send()));
    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded?['error'] is Map
            ? decoded['error']['message']?.toString() ?? 'Upload failed'
            : 'Upload failed',
        code: decoded?['error'] is Map
            ? decoded['error']['code']?.toString()
            : null,
        details: decoded?['error'] is Map ? decoded['error']['details'] : null,
      );
    }
    if (decoded?['data'] is! Map) {
      throw ApiException(502, 'Unexpected upload response',
          code: 'INVALID_RESPONSE');
    }
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Uint8List> downloadBytes(String value) async {
    final target = Uri.parse(absoluteUrl(value));
    final api = Uri.parse(baseUrl);
    if (!{'http', 'https'}.contains(target.scheme)) {
      throw ApiException(400, 'Unsupported image URL.');
    }
    // Public storage URLs must never receive RentHub session credentials.
    final trusted = target.scheme == api.scheme &&
        target.host == api.host &&
        target.port == api.port &&
        target.path.startsWith('${api.path.replaceAll(RegExp(r'/+$'), '')}/');
    final token = trusted ? await tokenProvider?.call() : null;
    final additionalHeaders = trusted
        ? await headersProvider?.call() ?? const <String, String>{}
        : const <String, String>{};
    final headers = <String, String>{
      'x-renthub-client': _clientDescription,
      if (token != null) 'authorization': 'Bearer $token',
      ...additionalHeaders,
    };
    final response = await (downloadClient?.get(target, headers: headers) ??
        http.get(
          target,
          headers: headers,
        ));
    if (response.statusCode >= 400) {
      var message = 'Image download failed';
      try {
        final decoded = jsonDecode(response.body);
        message = decoded?['error']?['message'] ?? message;
      } catch (_) {}
      throw ApiException(response.statusCode, message);
    }
    return response.bodyBytes;
  }
}
