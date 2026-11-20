// FILE: screens/auth/splash_screen.dart
// SCREEN: Splash (first screen).
// Loads saved session -> if logged in goes to resolvePostAuthScreen(), else LoginScreen.

import 'package:flutter/material.dart';
import '../../services/deep_link_service.dart';
import '../../utils/app_feedback.dart';
import '../../theme/tokens.dart';
import '../../utils/app_session.dart';
import '../../utils/app_startup.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';
import 'post_login_router.dart';

/// SCREEN: Splash (first screen).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// State of [SplashScreen] — holds the screen data and logic.
class _SplashScreenState extends State<SplashScreen> {
  /// Runs once when the screen opens; starts: _bootstrap().
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Splash logic: load session -> not logged in = LoginScreen, else resolvePostAuthScreen().
  Future<void> _bootstrap() async {
    await AppSession.instance.load();
    await Future.delayed(const Duration(milliseconds: 1400));
    // Firebase / push / deep links start after the first frame; wait for them (at most 6 s) before moving on.
    await AppStartup.ready.timeout(const Duration(seconds: 6), onTimeout: () {});
    if (!mounted) return;

    if (!AppSession.instance.isLoggedIn) {
      _goTo(const LoginScreen());
      DeepLinkService.instance.markReady(); // public profile link opens even before login
      return;
    }

    await _resolve();
  }

  String? _error;
  bool _retrying = false;

  /// Opens the right screen. Only a real "login expired" sends the artist to Login;
  /// internet / server problems show the reason with a Retry button instead.
  Future<void> _resolve() async {
    setState(() {
      _error = null;
      _retrying = true;
    });
    try {
      final screen = await resolvePostAuthScreen();
      if (!mounted) return;
      _goTo(screen);
      DeepLinkService.instance.markReady();
    } catch (e) {
      debugPrint('Splash Error = $e');
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      final expired = raw.contains('session expired') || raw.contains('401') || raw.contains('unauthorized');
      if (expired) {
        await AppSession.instance.clear();
        if (!mounted) return;
        _goTo(const LoginScreen());
        DeepLinkService.instance.markReady();
        return;
      }
      setState(() {
        _error = AppFeedback.friendlyMessage(e);
        _retrying = false;
      });
    }
  }

  /// Goes to to.
  void _goTo(Widget screen) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 5),
              const SunndariLogo(width: 300),
              const SizedBox(height: 26),
              if (_error != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: AiraText.sans(fontSize: 13.5, color: AiraColors.errorText, height: 1.4)),
                ),
                const SizedBox(height: 14),
                PrimaryButton(label: _retrying ? 'Trying…' : 'Try Again', small: true, onTap: _retrying ? null : _resolve),
                TextButton(
                  onPressed: () async {
                    await AppSession.instance.clear();
                    if (mounted) _goTo(const LoginScreen());
                  },
                  child: Text('Log In Again', style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w700, color: AiraColors.rose)),
                ),
              ],
              if (_error == null)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AiraColors.rose),
                ),
              const Spacer(flex: 4),
              Text(
                'Build Your Beauty Business.',
                style: AiraText.sans(fontSize: 17, color: AiraColors.charcoalSoft),
              ),
              const SizedBox(height: 14),
              Container(
                width: 56,
                height: 3.5,
                decoration: BoxDecoration(
                  gradient: AiraGradients.button,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Spacer(flex: 3),
              Text(
                'ARA Cosmetech Pvt. Ltd.',
                style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
