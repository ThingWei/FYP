import 'dart:convert';
import 'package:http/http.dart' as http;
class ApiException implements Exception { final int status; final String message; ApiException(this.status, this.message); }
class ApiClient {
  ApiClient(this.baseUrl, {this.tokenProvider}); final String baseUrl; final Future<String?> Function()? tokenProvider;
  Future<dynamic> request(String method, String path, {Object? body}) async {
    final token = await tokenProvider?.call();
    final request = http.Request(method, Uri.parse('$baseUrl$path'))..headers.addAll({'content-type':'application/json', if(token != null) 'authorization':'Bearer $token'});
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await request.send()); final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) throw ApiException(response.statusCode, decoded?['error']?['message'] ?? 'Request failed');
    return decoded?['data'];
  }
}

