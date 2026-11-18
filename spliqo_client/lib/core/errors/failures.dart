/// Domain failures representing errors returned by FastAPI error envelope
/// or Direct-path PostgREST / Realtime rejections.
class Failure implements Exception {
  const new({
    required this.code,
    required this.message,
    this.fields = const <Map<String, String>>[],
  });

  factory fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>? ?? json;
    final code = error['code'] as String? ?? 'unknown_error';
    final message = error['message'] as String? ?? 'An unexpected error occurred.';
    final fieldsRaw = error['fields'] as List<dynamic>? ?? const <dynamic>[];
    final fields = fieldsRaw.map((f) {
      if (f is Map) {
        return f.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return <String, String>{};
    }).toList();

    return Failure(code: code, message: message, fields: fields);
  }

  factory network(String details) => Failure(
        code: 'network_error',
        message: 'Could not connect to the server: $details',
      );

  factory unauthorized() => const Failure(
        code: 'unauthorized',
        message: 'Authentication session expired. Please sign in again.',
      );

  final String code;
  final String message;
  final List<Map<String, String>> fields;

  @override
  String toString() => '$code: $message';
}
