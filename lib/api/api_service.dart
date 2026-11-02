// FILE: api/api_service.dart
// Core HTTP client: GET / POST / PUT / DELETE / multipart, auth header, auto token-refresh on 401, error mapping.
// Every other *_service.dart uses this class.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../utils/api_logger.dart';
import '../utils/app_session.dart';
import 'api_endpoints.dart';

/// A file to upload in a multipart request.
class UploadFile {
  final String field;
  final String path;
  final String? filename;
  const UploadFile(this.field, this.path, {this.filename});
}

/// Core HTTP client used by every service.
class ApiService {
  static const String baseUrl = ApiEndpoints.baseUrl;

  static const _requestTimeout = Duration(seconds: 20);

  /// One shared client for the whole app: the connection (TCP + TLS) is reused
  /// instead of being opened again for every request. Idle connections are
  /// dropped after 10 s so a stale one is never reused.
  static final http.Client _client =
  IOClient(HttpClient()..idleTimeout = const Duration(seconds: 10));

  /// Short-lived GET cache for a few endpoints that the app asks for again and
  /// again within seconds (startup / refresh). Any POST / PUT / DELETE clears it.
  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<http.Response>> _inFlight = {};
  static int _cacheGen = 0;
  static const Map<String, Duration> _cacheTtls = {
    ApiEndpoints.artistsProfileGet: Duration(seconds: 10),
    ApiEndpoints.artistsOnboardingStatus: Duration(seconds: 10),
    ApiEndpoints.artistsServicesGetAll: Duration(seconds: 10),
    ApiEndpoints.artistsPortfolioGetAll: Duration(seconds: 10),
    ApiEndpoints.coreBookingStatusGetAll: Duration(minutes: 10),
  };

  /// False for writes that cannot change anything we cache.
  static bool _writeAffectsCache(Uri uri, dynamic body) {
    final p = uri.path;
    if (p.startsWith('/chat/') ||
        p.startsWith('/help_center/') ||
        p.startsWith('/notifications/')) {
      return false;
    }
    // Saving the phone's push (FCM) token: body is only {"fcm_token": ...}.
    if (p == '/users/profile/update/' &&
        body is Map &&
        body.length == 1 &&
        body.containsKey('fcm_token')) {
      return false;
    }
    return true;
  }

  /// Forgets every cached GET (call it if some data changed outside ApiService).
  static void clearCache() {
    _cacheGen++;
    _cache.clear();
    _inFlight.clear();
  }

  static const _uploadTimeout = Duration(seconds: 120);

  /// Called when the saved login can no longer be used (access token dead
  /// and refresh failed — e.g. the artist logged in on another phone, since
  /// only one session per user is allowed). main.dart sets it to send the
  /// artist back to the login screen instead of leaving them stuck.
  static VoidCallback? onSessionExpired;
  static DateTime? _lastExpiredNotice;

  static void _notifySessionExpired() {
    final now = DateTime.now();
    final last = _lastExpiredNotice;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _lastExpiredNotice = now;
    clearCache();
    onSessionExpired?.call();
  }

  /// Current access token from the saved session.
  String? get _token => AppSession.instance.accessToken;
  /// Returns true if it has token.
  bool get _hasToken => _token != null && _token!.isNotEmpty;

  /// Default headers: JSON + Bearer token.
  Map<String, String> get _headers {
    final h = {'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (_hasToken) h['Authorization'] = 'Bearer $_token';
    return h;
  }

  Future<bool>? _refreshInFlight;

  /// Joins base URL + endpoint + query params.
  Uri _buildUri(String endpoint, Map<String, dynamic>? queryParameters) {
    final uri = Uri.parse('$baseUrl$endpoint');
    if (queryParameters == null || queryParameters.isEmpty) return uri;
    return uri.replace(queryParameters: {
      for (final e in queryParameters.entries)
        if (e.value != null) e.key: e.value.toString(),
    });
  }

  /// GET request (adds auth header, retries after token refresh on 401).
  Future<http.Response> get(String endpoint,
      {Map<String, dynamic>? queryParameters}) {
    final uri = _buildUri(endpoint, queryParameters);
    Future<http.Response> send() =>
        _sendWithRetry('GET', uri, () => _client.get(uri, headers: _headers));

    final ttl = _cacheTtls[endpoint];
    if (ttl == null) return send();

    // Cached per logged-in token + full URL (so another user / another artist_id never mixes).
    final key = '${_token ?? ''}|$uri';
    final hit = _cache[key];
    if (hit != null && DateTime.now().isBefore(hit.expires)) {
      return Future.value(hit.response);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending; // same call already running -> share it

    final gen = _cacheGen;
    late final Future<http.Response> f;
    f = send().then((r) {
      if (gen == _cacheGen) {
        _cache[key] = _CacheEntry(r, DateTime.now().add(ttl));
      }
      return r;
    }).whenComplete(() {
      if (identical(_inFlight[key], f)) _inFlight.remove(key);
    });
    _inFlight[key] = f;
    return f;
  }

  /// POST request with JSON body.
  Future<http.Response> post(String endpoint, {dynamic data}) {
    final uri = _buildUri(endpoint, null);
    return _sendWithRetry(
      'POST',
      uri,
          () => _client.post(uri,
          headers: _headers, body: data != null ? jsonEncode(data) : null),
      body: data,
    );
  }

  /// PUT request with JSON body.
  Future<http.Response> put(String endpoint, {dynamic data}) {
    final uri = _buildUri(endpoint, null);
    return _sendWithRetry(
      'PUT',
      uri,
          () => _client.put(uri,
          headers: _headers, body: data != null ? jsonEncode(data) : null),
      body: data,
    );
  }

  /// DELETE request.
  Future<http.Response> delete(String endpoint,
      {Map<String, dynamic>? queryParameters}) {
    final uri = _buildUri(endpoint, queryParameters);
    return _sendWithRetry('DELETE', uri, () => _client.delete(uri, headers: _headers));
  }

  /// POST multipart/form-data (file upload with text fields).
  Future<http.Response> postMultipart(
      String endpoint, {
        Map<String, String> fields = const {},
        List<UploadFile> files = const [],
      }) {
    final uri = _buildUri(endpoint, null);
    return _sendWithRetry(
      'POST(multipart)',
      uri,
          () async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Accept'] = 'application/json';
        if (_hasToken) request.headers['Authorization'] = 'Bearer $_token';
        request.fields.addAll(fields);
        for (final f in files) {
          request.files.add(
              await http.MultipartFile.fromPath(f.field, f.path, filename: f.filename));
        }
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      },
      fields: fields,
      files: [
        for (final f in files) '${f.field}=${f.filename ?? f.path.split('/').last}',
      ],
      timeout: _uploadTimeout,
    );
  }

  /// PUT with multipart/form-data (used by PUT /artists/packages/photo/upload/).
  Future<http.Response> putMultipart(
      String endpoint, {
        Map<String, String> fields = const {},
        List<UploadFile> files = const [],
      }) {
    final uri = _buildUri(endpoint, null);
    return _sendWithRetry(
      'PUT(multipart)',
      uri,
          () async {
        final request = http.MultipartRequest('PUT', uri);
        request.headers['Accept'] = 'application/json';
        if (_hasToken) request.headers['Authorization'] = 'Bearer $_token';
        request.fields.addAll(fields);
        for (final f in files) {
          request.files.add(
              await http.MultipartFile.fromPath(f.field, f.path, filename: f.filename));
        }
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      },
      fields: fields,
      files: [
        for (final f in files) '${f.field}=${f.filename ?? f.path.split('/').last}',
      ],
      timeout: _uploadTimeout,
    );
  }

  /// Sends the request; on 401 refreshes the token once and retries.
  Future<http.Response> _sendWithRetry(
      String method,
      Uri uri,
      Future<http.Response> Function() doRequest, {
        dynamic body,
        Map<String, String>? fields,
        List<String>? files,
        Duration timeout = _requestTimeout,
      }) async {

    // A write clears the cache, except writes that can never change cached data
    // (chat / help-center / notifications, and the push-token-only profile update).
    final isWrite = method != 'GET' && _writeAffectsCache(uri, body);
    if (isWrite) clearCache(); // data is about to change -> never serve old cached data

    try {
      final sentAuth = _hasToken;

      var response = await _attempt(method, uri, doRequest, timeout,
          body: body, fields: fields, files: files);

      if (response.statusCode == 401 &&
          (AppSession.instance.refreshToken?.isNotEmpty ?? false)) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          response = await _attempt(method, uri, doRequest, timeout,
              body: body, fields: fields, files: files, retry: true);
        }
      }

      return _handle(response, sentAuth: sentAuth);
    } finally {
      if (isWrite) clearCache(); // and again after it finished
    }
  }

  Future<http.Response> _attempt(
      String method,
      Uri uri,
      Future<http.Response> Function() doRequest,
      Duration timeout, {
        dynamic body,
        Map<String, String>? fields,
        List<String>? files,
        bool retry = false,
      }) async {
    final id = ApiLog.nextId();
    final sw = Stopwatch()..start();
    ApiLog.request(id, method, uri,
        auth: _hasToken, retry: retry, body: body, fields: fields, files: files);
    try {
      final r = _withUtf8(await _safeSend(doRequest, timeout));
      ApiLog.response(id, method, uri, r, sw.elapsed);
      return r;
    } catch (e) {
      ApiLog.error(id, method, uri, e, sw.elapsed);
      rethrow;
    }
  }

  /// Safely runs send.
  Future<http.Response> _safeSend(
      Future<http.Response> Function() doRequest, Duration timeout) async {
    try {
      return await doRequest().timeout(timeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiService] network error (${e.runtimeType}): $e');
      throw _networkException(e);
    }
  }

  /// Network exception.
  Exception _networkException(Object e) {
    if (e is TimeoutException) {
      return Exception(
          'The Server Is Slow To Respond. Please Check Your Internet And Try Again.');
    }
    if (e is SocketException) {
      return Exception(
          'No Internet Connection. Please Turn On Mobile Data Or Wi-Fi And Try Again.');
    }
    if (e is HandshakeException) {
      return Exception('Secure Connection Failed. Please Check Your Date, Time And Internet, Then Try Again.');
    }
    if (e is http.ClientException) {
      return Exception(
          'Cannot Reach Sunndari Right Now. Please Check Your Internet And Try Again.');
    }
    if (e is FormatException) {
      return Exception('The Server Sent An Unexpected Reply. Please Try Again In A Moment.');
    }
    if (e is Exception) return e;
    return Exception('Could Not Complete The Request. Please Check Your Internet And Try Again.');
  }

  /// With utf8.
  http.Response _withUtf8(http.Response r) {
    final ct = r.headers['content-type'] ?? '';
    final lower = ct.toLowerCase();
    if (lower.contains('charset')) return r;
    final textual = lower.isEmpty || lower.contains('json') || lower.contains('text');
    if (!textual) return r;
    final headers = Map<String, String>.from(r.headers)
      ..['content-type'] = ct.isEmpty ? 'application/json; charset=utf-8' : '$ct; charset=utf-8';
    return http.Response.bytes(
      r.bodyBytes,
      r.statusCode,
      request: r.request,
      headers: headers,
      isRedirect: r.isRedirect,
      persistentConnection: r.persistentConnection,
      reasonPhrase: r.reasonPhrase,
    );
  }

  /// Refreshes the access token. API: POST /auth/token/refresh/
  Future<bool> _refreshToken() {
    return _refreshInFlight ??= _doRefreshToken().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  /// Does the actual refresh call. API: POST /auth/token/refresh/
  Future<bool> _doRefreshToken() async {
    final refreshToken = AppSession.instance.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;

    final uri = Uri.parse('$baseUrl${ApiEndpoints.authTokenRefresh}');
    final id = ApiLog.nextId();
    final sw = Stopwatch()..start();
    const tag = 'API/refresh';
    ApiLog.request(id, 'POST', uri, tag: tag, body: {'refresh_token': refreshToken});

    final http.Response response;
    try {
      response = _withUtf8(await _client
          .post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refresh_token': refreshToken}),
      )
          .timeout(_requestTimeout));
    } catch (e) {
      ApiLog.error(id, 'POST', uri, e, sw.elapsed, tag: tag);
      throw _networkException(e);
    }
    ApiLog.response(id, 'POST', uri, response, sw.elapsed, tag: tag);

    if (response.statusCode >= 500) {
      throw Exception('Sunndari Server Is Having Trouble Right Now. Please Try Again In A Few Minutes.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AppSession.instance.clear();
      _notifySessionExpired();
      return false;
    }

    try {
      Map<String, dynamic> j = jsonDecode(response.body) as Map<String, dynamic>;
      for (final key in ['data', 'result']) {
        final v = j[key];
        if (v is Map<String, dynamic>) {
          j = v;
          break;
        }
      }
      Map<String, dynamic> tokenSrc = j;
      final nested = j['tokens'] ?? j['token'];
      if (nested is Map<String, dynamic>) tokenSrc = nested;

      String findToken(List<String> keys) {
        for (final k in keys) {
          final v = tokenSrc[k];
          if (v is String && v.isNotEmpty) return v;
        }
        return '';
      }

      final newAccess = findToken(['access_token', 'access', 'token', 'accessToken']);
      final newRefresh = findToken(['refresh_token', 'refresh', 'refreshToken']);

      if (newAccess.isEmpty) {
        ApiLog.info('ApiService', 'token-refresh: no access token found in response');
        AppSession.instance.clear();
        return false;
      }

      AppSession.instance.accessToken = newAccess;
      if (newRefresh.isNotEmpty) AppSession.instance.refreshToken = newRefresh;
      await AppSession.instance.save(
        accessToken: newAccess,
        refreshToken: newRefresh.isNotEmpty ? newRefresh : refreshToken,
        userId: AppSession.instance.userId ?? 0,
        name: AppSession.instance.name ?? '',
        role: AppSession.instance.role ?? '',
      );
      return true;
    } catch (e) {
      ApiLog.info('ApiService', 'token-refresh: could not parse response: $e');
      return false;
    }
  }

  http.Response _handle(http.Response response, {required bool sentAuth}) {
    if (response.statusCode == 401 && sentAuth) {
      AppSession.instance.clear();
      _notifySessionExpired();
      throw Exception('Session Expired. Please Login Again.');
    }
    // Messages that tell the artist nothing — replaced by a reason based on the status code.
    bool generic(String m) {
      final t = m.toLowerCase();
      return t.contains('something went wrong') || t.contains('internal server error') ||
          t.contains('an error occurred') || t.contains('bad gateway') || t.contains('<html');
    }
    String? bodyMessage() {
      try {
        final body = jsonDecode(response.body);
        if (body is Map) {
          final err = body['error'];
          final c = (err is List && err.isNotEmpty) ? err.first : (body['detail'] ?? body['message']);
          if (c is String && c.trim().isNotEmpty && !generic(c)) return c.trim();
        }
      } catch (_) {}
      return null;
    }
    switch (response.statusCode) {
      case 413:
        throw Exception('This File Is Too Large. Please Choose A Smaller Photo (Under 5 MB) And Try Again.');
      case 415:
        throw Exception('This File Type Is Not Supported. Please Upload A JPG Or PNG Photo.');
      case 408:
      case 504:
        throw Exception('The Server Took Too Long To Respond. Please Check Your Internet And Try Again.');
      case 429:
        throw Exception('Too Many Attempts. Please Wait A Minute And Try Again.');
      case 502:
      case 503:
        final otpMsg = bodyMessage();
        if (otpMsg != null && otpMsg.toLowerCase().contains('otp')) throw Exception(otpMsg); // "Unable to send OTP right now, please try again"
        throw Exception('Sunndari Is Being Updated Or Is Busy Right Now. Please Try Again In A Few Minutes.');
    }
    if (response.statusCode >= 500) {
      final m = bodyMessage();
      if (m != null) throw Exception(m);
      throw Exception('Sunndari Server Had A Problem (Error ${response.statusCode}). Please Try Again In A Few Minutes.');
    }
    if (response.statusCode == 403) {
      throw Exception(bodyMessage() ?? "You Don't Have Permission To Do This. Please Contact Support If You Think This Is A Mistake.");
    }
    if (response.statusCode >= 400) {
      if (kDebugMode && (response.statusCode == 404 || response.statusCode == 405)) {
        // Makes missing / wrong-method endpoints easy to spot (users still see a friendly message).
        debugPrint('[ApiService] ${response.statusCode} ${response.request?.method} ${response.request?.url.path} '
            '— Endpoint Missing Or Method Not Allowed');
      }
      String msg = 'Could Not Complete The Request (Error ${response.statusCode}). Please Try Again.';
      try {
        final body = jsonDecode(response.body);
        dynamic candidate;
        if (body is Map) {
          final err = body['error'] ?? body['errors'];
          if (err is Map && err.isNotEmpty) {
            // Field validation: {"message": "Validation error", "error": {"city": ["This field may not be blank."]}}
            final first = err.values.first;
            final text = (first is List && first.isNotEmpty) ? first.first : first;
            if (text != null) candidate = ApiService.friendlyFieldError(err.keys.first.toString(), text.toString());
          }
          candidate ??= body['detail'];
          // Field validation can also be error: [ {"city": ["This field may not be blank."]} ] (error[0] is a map).
          if (candidate == null && err is List && err.isNotEmpty && err.first is Map && (err.first as Map).isNotEmpty) {
            final m = err.first as Map;
            final first = m.values.first;
            final text = (first is List && first.isNotEmpty) ? first.first : first;
            if (text != null) candidate = ApiService.friendlyFieldError(m.keys.first.toString(), text.toString());
          }
          // Business-rule errors carry the useful text in error[0]; message is generic ("Value Error ...").
          if (candidate == null && err is List && err.isNotEmpty) candidate = err.first;
          if (candidate == null && err is String) candidate = err;
          candidate ??= body['message'];
        }
        if (candidate is String && candidate.trim().isNotEmpty) {
          msg = candidate;
        }
      } catch (e) {
        ApiLog.info('ApiService', 'failed to parse error body: $e');
      }
      throw Exception(msg);
    }
    return response;
  }

  /// Turns a raw field error (`pan_number` + "This field may not be blank.") into a clear sentence.
  static String friendlyFieldError(String field, String message) {
    final f = field.toLowerCase();
    final m = message.toLowerCase();
    if (f.contains('pan')) return 'Please Enter A Valid PAN Number.';
    if (f.contains('ifsc')) return 'Please Enter A Valid IFSC Code.';
    if (f.contains('date_of_birth') || f.contains('dob')) {
      return m.contains('18') ? 'You Must Be At Least 18 Years Old.' : 'Please Enter A Valid Date Of Birth.';
    }
    if (f.contains('pin')) return 'Please Enter A Valid 6-digit Pincode.';
    final label = field.replaceAll('_', ' ').trim().toLowerCase();
    if (m.contains('blank') || m.contains('required') || m.contains('null') || m.contains('empty')) {
      return 'Please Enter/Select The Required Information${label.isEmpty ? '' : ' ($label)'}.';
    }
    if (m.contains('already')) return 'This $label Is Already In Use.';
    return 'Please Enter A Valid $label.';
  }
}

/// One cached GET response and when it stops being valid.
class _CacheEntry {
  final http.Response response;
  final DateTime expires;
  const _CacheEntry(this.response, this.expires);
}