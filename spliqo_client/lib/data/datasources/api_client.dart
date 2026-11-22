import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:spliqo/core/config/app_config.dart';
import 'package:spliqo/core/errors/failures.dart';
import 'package:uuid/uuid.dart';

/// HTTP Client for FastAPI Backend path adhering to Section 13 & 15.4 of Standards:
/// 1. Correlation and request IDs on every request.
/// 2. Automatic bearer token header injection.
/// 3. Idempotency-Key support for mutations.
/// 4. Maps standard error envelope directly to Failure objects.
class ApiClient {
  new({
    http.Client? httpClient,
    String? baseUrl,
    this.tokenProvider,
  })  : _httpClient = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.current.backendUrl;

  final http.Client _httpClient;
  final String _baseUrl;
  final Future<String?> Function()? tokenProvider;
  final Uuid _uuid = const Uuid();

  Uri _buildUri(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl/v1$cleanPath');
  }

  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Request-ID': _uuid.v4(),
    };

    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }

    if (tokenProvider != null) {
      final token = await tokenProvider!();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  void _handleErrorResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw Failure.fromJson(decoded);
    } on FormatException {
      throw Failure(
        code: 'http_${response.statusCode}',
        message: 'Server returned HTTP ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> get(String path) async {
    try {
      final uri = _buildUri(path);
      final headers = await _headers();
      final response = await _httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      _handleErrorResponse(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Failure {
      rethrow;
    } on Object catch (e) {
      throw Failure.network(e.toString());
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    try {
      final uri = _buildUri(path);
      final headers = await _headers(idempotencyKey: idempotencyKey);
      final response = await _httpClient
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      _handleErrorResponse(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Failure {
      rethrow;
    } on Object catch (e) {
      throw Failure.network(e.toString());
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    try {
      final uri = _buildUri(path);
      final headers = await _headers(idempotencyKey: idempotencyKey);
      final response = await _httpClient
          .put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      _handleErrorResponse(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Failure {
      rethrow;
    } on Object catch (e) {
      throw Failure.network(e.toString());
    }
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = _buildUri(path);
      final headers = await _headers();
      final response = await _httpClient
          .patch(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      _handleErrorResponse(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Failure {
      rethrow;
    } on Object catch (e) {
      throw Failure.network(e.toString());
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required List<int> fileBytes,
    required String filename,
    required String fieldName,
    Map<String, String>? fields,
  }) async {
    try {
      final uri = _buildUri(path);
      final request = http.MultipartRequest('POST', uri);

      final headers = await _headers();
      headers.remove('Content-Type'); // Let multipart set boundary
      request.headers.addAll(headers);

      if (fields != null) {
        request.fields.addAll(fields);
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          fileBytes,
          filename: filename,
        ),
      );

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      _handleErrorResponse(response);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on Failure {
      rethrow;
    } on Object catch (e) {
      throw Failure.network(e.toString());
    }
  }
}
