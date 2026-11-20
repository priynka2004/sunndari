// FILE: api/auth_service.dart
// Auth APIs: register, login, email/phone OTP, Google login, token refresh, forgot / reset / set password.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_endpoints.dart';
import 'api_service.dart';
import '../models/auth/auth_response.dart';
import '../models/auth/register_request.dart';
import '../models/auth/login_request.dart';
import '../models/auth/email_otp_request.dart';
import '../models/auth/email_otp_verify.dart';
import '../models/auth/phone_otp_request.dart';
import '../models/auth/phone_otp_verify.dart';
import '../models/auth/google_auth.dart';
import '../models/auth/token_refresh.dart';
import '../models/auth/forgot_password_request.dart';
import '../models/auth/reset_password_request.dart';
import '../utils/app_session.dart';
import '../utils/fcm_token_helper.dart';

/// Auth Service — API/data layer.
class AuthService {
  final ApiService _apiService;
  AuthService(this._apiService);

  /// Registers.
  /// API: POST /auth/register/
  Future<AuthResponse> register(RegisterRequest data) async {
    final response = await _apiService.post(ApiEndpoints.authRegister, data: data.toJson());
    final auth = _parseAndLog('register', response.body);
    await _persist(auth);
    return auth;
  }

  /// Logs in.
  /// API: POST /auth/login/
  Future<AuthResponse> login(LoginRequest data) async {
    final response = await _apiService.post(ApiEndpoints.authLogin, data: await FcmTokenHelper.withToken(data.toJson()));
    final auth = _parseAndLog('login', response.body);
    await _persist(auth);
    return auth;
  }

  /// Requests email OTP.
  /// API: POST /auth/email-otp/request/
  Future<void> requestEmailOtp(EmailOtpRequest data) async {
    await _apiService.post(ApiEndpoints.authEmailOtpRequest, data: data.toJson());
  }

  /// Verifies email OTP.
  /// API: POST /auth/email-otp/verify/
  Future<AuthResponse> verifyEmailOtp(EmailOtpVerify data) async {
    final response = await _apiService.post(ApiEndpoints.authEmailOtpVerify, data: await FcmTokenHelper.withToken(data.toJson()));
    final auth = _parseAndLog('verifyEmailOtp', response.body);
    await _persist(auth);
    return auth;
  }

  /// Requests phone OTP.
  /// API: POST /auth/phone-otp/request/
  Future<void> requestPhoneOtp(PhoneOtpRequest data) async {
    await _apiService.post(ApiEndpoints.authPhoneOtpRequest, data: data.toJson());
  }

  /// Verifies phone OTP.
  /// API: POST /auth/phone-otp/verify/
  Future<AuthResponse> verifyPhoneOtp(PhoneOtpVerify data) async {
    final response = await _apiService.post(ApiEndpoints.authPhoneOtpVerify, data: await FcmTokenHelper.withToken(data.toJson()));
    final auth = _parseAndLog('verifyPhoneOtp', response.body);
    await _persist(auth);
    return auth;
  }

  /// Google auth.
  /// API: POST /auth/google/
  Future<AuthResponse> googleAuth(GoogleAuth data) async {
    final response = await _apiService.post(ApiEndpoints.authGoogle, data: await FcmTokenHelper.withToken(data.toJson()));
    final auth = _parseAndLog('googleAuth', response.body);
    await _persist(auth);
    return auth;
  }

  /// Refreshes token.
  /// API: POST /auth/token/refresh/
  Future<AuthResponse> refreshToken(TokenRefresh data) async {
    final response = await _apiService.post(ApiEndpoints.authTokenRefresh, data: await FcmTokenHelper.withToken(data.toJson()));
    final auth = _parseAndLog('refreshToken', response.body);
    await _persist(auth);
    return auth;
  }

  /// Requests password reset.
  /// API: POST /auth/forgot-password/ (always 200 — account existence is not revealed)
  Future<void> requestPasswordReset(ForgotPasswordRequest data) async {
    await _apiService.post(ApiEndpoints.authPasswordForgot, data: data.toJson());
  }

  /// Sets password.
  /// API: POST /auth/password/set/
  /// Body: {"new_password": "...", "confirm_password": "..."} (Bearer token of the signed-in user).
  Future<void> setPassword({required String password, required String confirmPassword}) async {
    await _apiService.post(ApiEndpoints.authPasswordSet, data: {
      'new_password': password,
      'confirm_password': confirmPassword,
    });
  }

  /// Resets password.
  /// API: POST /auth/reset-password/ (200 → all sessions revoked, send user to login)
  Future<void> resetPassword(ResetPasswordRequest data) async {
    await _apiService.post(ApiEndpoints.authPasswordReset, data: data.toJson());
  }

  /// Logs the user out.
  Future<void> logout() async {
    await AppSession.instance.clear();
  }

  /// Parses and log.
  AuthResponse _parseAndLog(String tag, String body) {
    if (kDebugMode) {
      debugPrint('[AuthService:$tag] raw response => $body');
    }
    final auth = AuthResponse.fromJson(jsonDecode(body));
    if (kDebugMode) {
      debugPrint('[AuthService:$tag] parsed => userId=${auth.userId}, '
          'access="${auth.accessToken}", refresh="${auth.refreshToken}"');
    }
    return auth;
  }

  /// Saves locally.
  Future<void> _persist(AuthResponse auth) async {
    await AppSession.instance.save(
      accessToken:  auth.accessToken,
      refreshToken: auth.refreshToken,
      userId:       auth.userId,
      name:         auth.name,
      role:         auth.role ?? '',
    );
    if (kDebugMode) {
      debugPrint('[AuthService] session saved -> '
          'isLoggedIn=${AppSession.instance.isLoggedIn}, '
          'token="${AppSession.instance.accessToken}"');
    }
  }
}
