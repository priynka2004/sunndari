// FILE: main.dart  |  APP ENTRY POINT
// Flow: main() -> Firebase init -> push handler -> ServiceLocator.init() -> runApp(AiraApp) -> SplashScreen.
//       Firebase MUST be ready before ServiceLocator.init() (the Firestore services are created there).
//       The slower work — local notifications and deep links — runs right after the first frame
//       (_startServices); the splash waits for it (AppStartup.ready) before opening the next screen.

import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'api/api_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'services/deep_link_service.dart';
import 'services/push_notification_service.dart';
import 'theme/tokens.dart';
import 'utils/app_startup.dart';
import 'utils/nav_key.dart';
import 'utils/responsive_scale.dart';
import 'utils/service_locator.dart';

/// APP ENTRY POINT: Firebase first (the services need it), then the app; local notifications / deep links follow.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Crashlytics: send Flutter errors and uncaught async/platform errors (not in debug runs).
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  ServiceLocator.init();

  // Session died (logged in elsewhere / refresh token expired): go back to
  // the login screen and drop every other screen.
  ApiService.onSessionExpired = () {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  };

  runApp(const AiraApp());
  unawaited(_startServices());
}

/// Start-up work that does not need to block the first frame. Errors never stop the app from opening.
Future<void> _startServices() async {
  try {
    await PushNotificationService.instance.initLocalNotifications();
    // Shared profile link (sunndari://app/profile) -> opens Public Profile Preview.
    await DeepLinkService.instance.init();
  } catch (e) {
    debugPrint('Start-up services error = $e');
  } finally {
    AppStartup.complete();
  }
}

/// Root MaterialApp: theme + navigator key; first screen = SplashScreen.
class AiraApp extends StatelessWidget {
  const AiraApp({super.key});

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Sunndari',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AiraColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AiraColors.rose,
          primary: AiraColors.rose,
          onPrimary: Colors.white,
          surface: AiraColors.bg,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AiraColors.roseDeep,
          selectionHandleColor: AiraColors.rose,
        ),
        splashFactory: InkRipple.splashFactory,
      ),
      // Same proportions on every phone size (bigger phones no longer look small).
      builder: (context, child) => ResponsiveScale(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}