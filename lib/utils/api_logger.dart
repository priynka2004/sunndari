// FILE: utils/api_logger.dart
// Debug-only API request/response logger (hides passwords/tokens).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Api Log.
class ApiLog {
  ApiLog._();

  static const bool enabled = kDebugMode;

  static const int maxBodyChars = 12000;

  static int _seq = 0;
  /// Next id.
  static int nextId() => ++_seq;

  static const _secretBodyKeys = ['password', 'passwd', 'pwd', 'otp', 'access_token', 'refresh_token', 'accesstoken', 'refreshtoken', 'id_token'];
  static const _secretQueryKeys = {'key', 'token', 'api_key', 'apikey'};

  /// Sends the request.
  static void request(
      int id,
      String method,
      Uri uri, {
        String tag = 'API',
        bool auth = false,
        bool retry = false,
        dynamic body,
        Map<String, String>? fields,
        List<String>? files,
      }) {
    if (!enabled) return;
    final lines = <String>[
      '→ $method ${_safeUri(uri)}'
          '${auth ? '  [auth]' : ''}'
          '${retry ? '  [retry after token refresh]' : ''}',
    ];
    if (body != null) lines.add('body: ${_prettyObject(_mask(body))}');
    if (fields != null && fields.isNotEmpty) {
      lines.add('fields: ${_prettyObject(_mask(fields))}');
    }
    if (files != null && files.isNotEmpty) lines.add('files: ${files.join(', ')}');
    _emit('$tag #$id', lines);
  }

  static void response(
      int id,
      String method,
      Uri uri,
      http.Response r,
      Duration elapsed, {
        String tag = 'API',
      }) {
    if (!enabled) return;
    final ok = r.statusCode >= 200 && r.statusCode < 300;
    final ct = (r.headers['content-type'] ?? '').toLowerCase();
    final isText = ct.isEmpty ||
        ct.contains('json') ||
        ct.contains('text') ||
        ct.contains('xml') ||
        ct.contains('javascript');

    final String body = isText
        ? _prettyBody(utf8.decode(r.bodyBytes, allowMalformed: true))
        : '<binary ${r.bodyBytes.length} bytes, ${ct.isEmpty ? 'unknown type' : ct}>';

    _emit('$tag #$id', [
      '← ${r.statusCode} ${ok ? 'OK' : 'ERROR'} $method ${_safeUri(uri)} '
          '(${elapsed.inMilliseconds} ms)',
      body,
    ]);
  }

  static void error(
      int id,
      String method,
      Uri uri,
      Object e,
      Duration elapsed, {
        String tag = 'API',
      }) {
    if (!enabled) return;
    _emit('$tag #$id', [
      '✖ $method ${_safeUri(uri)} FAILED after ${elapsed.inMilliseconds} ms',
      '${e.runtimeType}: $e',
    ]);
  }

  static void info(String tag, String message) {
    if (!enabled) return;
    debugPrint('[$tag] $message');
  }

  static void ws(String tag, String direction, [Object? data]) {
    if (!enabled) return;
    final text = data == null ? '' : ' ${_truncate(data.toString())}';
    debugPrint('[WS/$tag] $direction$text');
  }

  static Future<http.Response> get(
      Uri uri, {
        Map<String, String>? headers,
        String tag = 'HTTP',
        Duration timeout = const Duration(seconds: 20),
      }) async {
    final id = nextId();
    final sw = Stopwatch()..start();
    request(id, 'GET', uri, tag: tag);
    try {
      final r = await http.get(uri, headers: headers).timeout(timeout);
      response(id, 'GET', uri, r, sw.elapsed, tag: tag);
      return r;
    } catch (e) {
      error(id, 'GET', uri, e, sw.elapsed, tag: tag);
      rethrow;
    }
  }

  static Future<http.Response> post(
      Uri uri, {
        Map<String, String>? headers,
        Object? body,
        String tag = 'HTTP',
        Duration timeout = const Duration(seconds: 20),
      }) async {
    final id = nextId();
    final sw = Stopwatch()..start();
    request(id, 'POST', uri, tag: tag);
    try {
      final r = await http.post(uri, headers: headers, body: body).timeout(timeout);
      response(id, 'POST', uri, r, sw.elapsed, tag: tag);
      return r;
    } catch (e) {
      error(id, 'POST', uri, e, sw.elapsed, tag: tag);
      rethrow;
    }
  }

  static void _emit(String header, List<String> lines) {
    final b = StringBuffer('┌─ [$header]\n');
    for (final line in lines) {
      for (final l in line.split('\n')) {
        b.writeln('│ $l');
      }
    }
    b.write('└─');
    debugPrint(b.toString());
  }

  /// Pretty body.
  static String _prettyBody(String raw) {
    if (raw.trim().isEmpty) return '(empty body)';
    String out;
    try {
      out = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      out = raw;
    }
    return _truncate(out);
  }

  /// Pretty object.
  static String _prettyObject(dynamic o) {
    try {
      return _truncate(const JsonEncoder.withIndent('  ').convert(o));
    } catch (_) {
      return _truncate(o.toString());
    }
  }

  static String _truncate(String s) {
    if (s.length <= maxBodyChars) return s;
    return '${s.substring(0, maxBodyChars)}\n… (${s.length - maxBodyChars} more chars cut)';
  }

  static dynamic _mask(dynamic v) {
    if (v is Map) {
      return v.map((k, val) {
        final isSecret =
        _secretBodyKeys.any((s) => k.toString().toLowerCase().contains(s));
        return MapEntry(k, isSecret ? '***' : _mask(val));
      });
    }
    if (v is List) return v.map(_mask).toList();
    return v;
  }

  /// Safely runs URI.
  static String _safeUri(Uri uri) {
    if (!uri.hasQuery) return uri.toString();
    final q = Map<String, String>.from(uri.queryParameters);
    var changed = false;
    for (final k in q.keys.toList()) {
      if (_secretQueryKeys.contains(k.toLowerCase())) {
        q[k] = '***';
        changed = true;
      }
    }
    return changed ? uri.replace(queryParameters: q).toString() : uri.toString();
  }
}
