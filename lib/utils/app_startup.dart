// FILE: utils/app_startup.dart
// Tracks the start-up work that runs AFTER the first Flutter frame (Firebase, push, deep links).
//
// main() calls runApp() straight away so the Sunndari splash screen shows immediately — before, main() waited for
// all of this first, and the phone kept showing its own black launch screen with the app icon the whole time.
// The splash screen waits for [AppStartup.ready] before it opens the next screen.

import 'dart:async';

class AppStartup {
  static final Completer<void> _done = Completer<void>();

  /// Completes when Firebase / push / deep-link start-up has finished (or failed — the app still opens).
  static Future<void> get ready => _done.future;

  static void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}
