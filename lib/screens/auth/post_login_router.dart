// FILE: screens/auth/post_login_router.dart
// FILE: post_login_router.dart
// Decides where to go after login/splash: Onboarding, Registration Status, Artist Page Setup, Under Review, or the main app shell.
//
// APIs used:
//   GET /artists/profile/get/
//   GET /artists/onboarding/status/

import 'package:flutter/material.dart';
import '../../app_shell.dart';
import '../../utils/app_feedback.dart';
import '../../utils/approval_status.dart';
import '../../utils/onboarding_progress.dart';
import '../../utils/service_locator.dart';
import '../onboarding/artist_page_setup_screen.dart';
import '../onboarding/onboarding_flow_screen.dart';
import '../onboarding/registration_fee_screen.dart';
import 'registration_status_screen.dart';

/// Two admin approvals:
///  (1) the normal artist approval — the artist waits on "Onboarding Under Review" until the admin approves
///      (profile approval status), and only then can build the artist page;
///  (2) the portfolio / page approval — a boolean the backend sets to "pending" when the artist reaches the page
///      builder and the admin approves after the page is submitted (see PortfolioApproval in artist_page_setup_screen.dart).
/// Set to false to let artists open the page builder without approval (1).
const bool kRequireFirstApproval = true;

/// Decides the next screen from the artist's review status + onboarding progress.
///
/// New flow (Sunndari API): onboarding steps (profile, KYC, payout, agreement) → Build My Artist Page
/// (services, portfolio, location) → POST /artists/onboarding/submit/ → admin review → approved.
/// The server only accepts the submit when EVERY checklist step is done, so the artist goes straight into
/// the page builder after onboarding instead of waiting for approval first.
/// API: GET /artists/profile/get/ · GET /artists/onboarding/status/
Future<Widget> resolvePostAuthScreen() async {
  final profile = await ServiceLocator.artistService.getProfile();
  final statusId = profile.approvalStatusId;
  final kind = await resolveArtistStatusKind(profile);

  if (kind == ApprovalStatusKind.suspended) {
    return RegistrationStatusScreen(approvalStatusId: statusId);
  }

  if (kind == ApprovalStatusKind.approved) {
    // Registration fee not paid yet (and not exempt) → the fee screen stays the only screen until it is paid.
    final fee = kRegistrationFeeBeforeSubmit ? await pendingRegistrationFee() : null;
    if (fee != null) return RegistrationFeeScreen(fee: fee, standalone: true);
    // Approval 1 done → build the page; then wait for approval 2 (portfolio) before the app opens.
    if (await ArtistPageSetup.needed(profile: profile)) return const ArtistPageSetupScreen();
    if (await ArtistPageReview.pending()) return const ArtistPageUnderReviewScreen();
    return const AiraAppShell();
  }

  final progress = await OnboardingProgress.load(profile: profile);
  if (!progress.allDone) return const OnboardingFlowScreen();

  // Rejected → show the admin's reason with a way to fix and resubmit.
  if (kind == ApprovalStatusKind.rejected) return RegistrationStatusScreen(approvalStatusId: statusId);

  // Submitted under the old single-approval rule (server status `submitted`) → page under review.
  if (await ArtistPageReview.pending(useFlag: false)) return const ArtistPageUnderReviewScreen();

  // Onboarding done but approval 1 not given yet → stay on "Onboarding Under Review" (it re-checks by itself).
  if (kRequireFirstApproval) return const OnboardingFlowScreen();
  return const ArtistPageSetupScreen();
}

/// Called after login/OTP success: opens the right screen and clears the back stack.
Future<void> routeAfterLogin(BuildContext context) async {
  try {
    final screen = await resolvePostAuthScreen();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
          (_) => false,
    );
  } catch (e) {
    debugPrint(e.toString());
    if (context.mounted) AppFeedback.showError(context, e);
  }
}
