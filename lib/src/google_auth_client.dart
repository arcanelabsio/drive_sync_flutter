import 'package:http/http.dart' as http;

/// An [http.BaseClient] that injects Google auth headers into every request.
///
/// Use this to wrap the auth headers from `google_sign_in` into an HTTP client
/// that can be passed to [GoogleDriveAdapter].
///
/// ```dart
/// final account = await GoogleSignIn(scopes: ['drive']).signIn();
/// final headers = await account!.authHeaders;
/// final authClient = GoogleAuthClient(headers);
/// final adapter = GoogleDriveAdapter(httpClient: authClient, folderName: 'Backups');
/// ```
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner;

  /// Create an auth client from a map of headers (typically from `account.authHeaders`).
  GoogleAuthClient(this._headers, {http.Client? inner})
    : _inner = inner ?? http.Client();

  /// Create an auth client from an async headers future.
  static Future<GoogleAuthClient> fromAccount(
    Future<Map<String, String>> authHeaders, {
    http.Client? inner,
  }) async {
    final headers = await authHeaders;
    return GoogleAuthClient(headers, inner: inner);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
