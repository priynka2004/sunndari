// FILE: services/deep_link_service.dart
// Opens PublicArtistProfileScreen ONLY when a shared profile link is tapped.
//
// Link format (what the app receives):  sunndari://app/profile?slug=<publicSlug>&t=<tap time>
// The shared https link (docs/index.html on GitHub Pages) opens this; it adds `t` so every tap is unique.
//
// Flow: link arrives (cold start or app already open) -> kept as "pending" ->
// once Splash has opened the first screen (markReady) -> PublicArtistProfileScreen(slug) is pushed on top.
// That screen calls GET /public/artists/get/?slug=... (no login needed).
//
// Why "last handled link" is saved: Android gives the app the SAME old link again when it is
// reopened from Recent Apps / relaunched. Without this check, a normal app open would show the profile.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/public_artist_profile_screen.dart';
import '../utils/nav_key.dart';
import '../utils/service_locator.dart';

/// Custom scheme + host registered in AndroidManifest.xml.
const String kDeepLinkScheme = 'sunndari';
const String kDeepLinkHost = 'app';

/// Hosted redirect page (docs/index.html on GitHub Pages, repo aira, folder /docs).
//const String kProfileOpenPageUrl = 'https://priynka2004.github.io/aira/';

const String kProfileOpenPageUrl = 'https://priynka2004.github.io/sunndari/';


const String _kLastHandledLink = 'deep_link_last_handled';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  Uri? _pending;
  bool _ready = false;
  String? _lastHandled; // loaded from SharedPreferences in init()

  /// Builds the https link that is shared (WhatsApp, Telegram, SMS, Instagram, anywhere).
  /// Example: https://priynka2004.github.io/aira/?slug=priya-sheoran-e4c2de
  static String profileShareUrl(String slug) {
    final base = kProfileOpenPageUrl.endsWith('/') ? kProfileOpenPageUrl : '$kProfileOpenPageUrl/';
    return '$base?slug=${Uri.encodeQueryComponent(slug)}';
  }

  /// The logged-in artist's public slug.
  /// API: GET /artists/profile/get/ (publicSlug); if empty, GET /artists/profile/share_link/ (slug read from the URL).
  static Future<String?> mySlug() async {
    try {
      final s = (await ServiceLocator.artistService.getProfile()).publicSlug?.trim();
      if (s != null && s.isNotEmpty) return s;
    } catch (_) {}
    try {
      final link = (await ServiceLocator.artistBusiness.getShareLink())?.trim();
      if (link != null && link.isNotEmpty) {
        final u = Uri.tryParse(link);
        final q = u?.queryParameters['slug'];
        if (q != null && q.isNotEmpty) return q;
        final segs = u?.pathSegments.where((e) => e.isNotEmpty).toList() ?? const [];
        if (segs.isNotEmpty) return segs.last;
      }
    } catch (_) {}
    return null;
  }

  /// Ready-to-share link for the logged-in artist (null if the slug could not be loaded).
  static Future<String?> myProfileShareUrl() async {
    final slug = await mySlug();
    return slug == null ? null : profileShareUrl(slug);
  }

  /// Call once in main() before runApp.
  /// (app_links' uriLinkStream also gives the launch link, so getInitialLink is not called separately.)
  Future<void> init() async {
    try {
      _lastHandled = (await SharedPreferences.getInstance()).getString(_kLastHandledLink);
    } catch (_) {}
    _sub ??= _appLinks.uriLinkStream.listen(_handle, onError: (e) => debugPrint('DeepLink stream error = $e'));
  }

  /// Call after Splash has opened the first screen (Login or the app). The public profile needs no login.
  void markReady() {
    _ready = true;
    _flush();
  }

  bool _isProfileLink(Uri uri) =>
      uri.scheme == kDeepLinkScheme && uri.host == kDeepLinkHost && uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'profile';

  void _handle(Uri uri) {
    debugPrint('DeepLink received = $uri');
    if (!_isProfileLink(uri)) return;
    if ((uri.queryParameters['slug'] ?? '').trim().isEmpty) return; // no slug -> nothing to open
    final key = uri.toString();
    if (key == _lastHandled) {
      debugPrint('DeepLink ignored (same old link given again by Android)');
      return;
    }
    _pending = uri;
    _flush();
  }

  void _flush() {
    if (!_ready || _pending == null) return;
    final uri = _pending!;
    final slug = uri.queryParameters['slug']!.trim();

    // Remember it so the same link is never opened twice (e.g. app reopened from Recent Apps).
    _lastHandled = uri.toString();
    SharedPreferences.getInstance().then((p) => p.setString(_kLastHandledLink, uri.toString())).catchError((_) => false);

    // Let the screen opened by Splash finish its first frame first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null || _pending == null) return;
      _pending = null;
      debugPrint('DeepLink opening public profile, slug = $slug');
      nav.push(MaterialPageRoute(builder: (_) => PublicArtistProfileScreen(slug: slug)));
    });
    // App may be idle (link tapped while it was already open) — make sure a frame runs.
    WidgetsBinding.instance.scheduleFrame();
  }
}