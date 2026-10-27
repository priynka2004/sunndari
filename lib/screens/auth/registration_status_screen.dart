// FILE: screens/auth/registration_status_screen.dart
// SCREEN: Registration Status — shows pending / approved / rejected / suspended review state after onboarding.
//
// APIs used:
//   GET /artists/profile/get/

import 'post_login_router.dart';
import 'package:flutter/material.dart';
import '../../app_shell.dart';
import '../../theme/tokens.dart';
import '../../utils/app_feedback.dart';
import '../../utils/app_session.dart';
import '../../models/artist/artist_profile.dart';
import '../../models/artist/artist_extras.dart';
import '../../utils/approval_status.dart';
import '../../utils/onboarding_progress.dart';
import '../../utils/service_locator.dart';
import '../../widgets/common.dart';
import '../onboarding/onboarding_flow_screen.dart';
import '../onboarding/artist_page_setup_screen.dart';
import '../help_center_screen.dart';
import '../edit_profile_screen.dart';
import 'login_screen.dart';

/// SCREEN: Registration Status — shows pending / approved / rejected / suspended review state after onboarding.
class RegistrationStatusScreen extends StatefulWidget {
  final int? approvalStatusId;

  const RegistrationStatusScreen({super.key, required this.approvalStatusId});

  @override
  State<RegistrationStatusScreen> createState() => _RegistrationStatusScreenState();
}

/// State of [RegistrationStatusScreen] — holds the screen data and logic.
class _RegistrationStatusScreenState extends State<RegistrationStatusScreen> {
  ApprovalStatusKind _kind = ApprovalStatusKind.pending;
  String? _rejectionReason;
  OnboardingProgress? _progress;
  bool _loading = true;
  bool _checking = false;

  /// Admin verification of the ID proof (shown under "Admin Review").
  /// null = no ID proof found yet.
  ApprovalStatusKind? _idProofStatus;
  String? _idProofRejection;

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data.
  /// API: artistService.getProfile → GET /artists/profile/get/
  Future<void> _load() async {
    ArtistProfile? profile;
    try {
      profile = await ServiceLocator.artistService.getProfile();
    } catch (_) {}

    // API call: GET /artists/onboarding/status/ (falls back to the approval-status id)
    final kind = profile == null
        ? await resolveApprovalStatusKind(widget.approvalStatusId)
        : await resolveArtistStatusKind(profile);
    String? reason;
    if (kind == ApprovalStatusKind.rejected) {
      try {
        reason = (await ServiceLocator.artistBusiness.getOnboardingStatus()).rejectionReason ?? profile?.rejectionReason;
        if ((reason ?? '').isEmpty) {
          // API call: GET /artists/review/feedback/get_all/ (newest first)
          final fb = await ServiceLocator.artistBusiness.getReviewFeedback(sortOrder: 'desc');
          final rej = fb.where((f) => f.decision == 'rejected');
          if (rej.isNotEmpty) reason = rej.first.message;
        }
      } catch (_) {}
    }
    // API call: GET /artists/documents/get_all/ — ID proof verification (pending | approved | rejected)
    ApprovalStatusKind? idStatus;
    String? idReason;
    try {
      final docs = await ServiceLocator.artistBusiness.getDocuments();
      final ids = docs.where((d) => d.documentType == 'id_proof').toList();
      if (ids.isNotEmpty) {
        final ArtistDocument d = ids.first;
        final name = d.verificationStatus.trim().toLowerCase();
        if (name.isNotEmpty) {
          idStatus = name.contains('approv') || name.contains('verif')
              ? ApprovalStatusKind.approved
              : name.contains('reject')
                  ? ApprovalStatusKind.rejected
                  : ApprovalStatusKind.pending;
        } else {
          final k = await resolveApprovalStatusKind(d.verificationStatusId);
          idStatus = k == ApprovalStatusKind.unknown ? ApprovalStatusKind.pending : k;
        }
        idReason = d.rejectionReason;
      }
    } catch (_) {}
    final progress = await OnboardingProgress.load();
    if (!mounted) return;
    setState(() {
      _idProofStatus = idStatus;
      _idProofRejection = idReason;
      _kind = kind;
      _progress = progress;
      _rejectionReason = reason;
      _loading = false;
    });
  }

  /// Checks status.
  /// API: artistService.getProfile → GET /artists/profile/get/
  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final profile = await ServiceLocator.artistService.getProfile();
      final approved = await resolveArtistStatusKind(profile) == ApprovalStatusKind.approved;
      if (!mounted) return;
      if (approved) {
        if (await ArtistPageSetup.isProfileComplete(profile: profile)) {
          if (!mounted) return;
          // Approval 1 done → the router decides: page builder, "page under review" (approval 2) or the app.
          await routeAfterLogin(context);
        } else {
          await _load();
        }
      } else {
        AppFeedback.showInfo(context, "Still Under Review — We'll Notify You As Soon As You're Approved.");
        await _load();
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e, onRetry: _checkStatus);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Opens onboarding.
  Future<void> _openOnboarding() async {
    // Navigates to OnboardingFlowScreen
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingFlowScreen()));
    if (!mounted) return;
    setState(() => _loading = true);
    await _load();
  }

  bool _resubmitting = false;

  /// Rejected artist: opens the profile edit screen so the rejected details can be corrected.
  /// API: artistService.getProfile → GET /artists/profile/get/ (then EditProfileScreen saves the changes)
  Future<void> _updateProfile() async {
    try {
      final profile = await ServiceLocator.artistService.getProfile();
      if (!mounted) return;
      // Navigates to EditProfileScreen
      final updated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
      );
      if (updated == true && mounted) {
        AppFeedback.showSuccess(context, 'Profile Updated ✓ Now Resubmit For Review');
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e, onRetry: _updateProfile);
    }
  }

  /// Sends the corrected profile back to admin for approval.
  /// API: artistBusiness.submitOnboarding → POST /artists/onboarding/submit/
  Future<void> _resubmit() async {
    setState(() => _resubmitting = true);
    try {
      await ServiceLocator.artistBusiness.submitOnboarding();
      if (!mounted) return;
      AppFeedback.showSuccess(context, 'Sent For Review ✓ We’ll Notify You Once It Is Checked.');
      setState(() => _loading = true);
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e, onRetry: _resubmit);
    } finally {
      if (mounted) setState(() => _resubmitting = false);
    }
  }

  /// Logs the user out.
  Future<void> _logout() async {
    await AppSession.instance.clear();
    if (!mounted) return;
    // Navigates to LoginScreen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  /// UI: logs out link.
  Widget _logoutLink() => Center(
        child: TextButton(
          onPressed: _logout,
          child: Text(
            'Log Out',
            style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.errorText),
          ),
        ),
      );

  /// Contact support.
  void _contactSupport() {
    // Navigates to HelpCenterScreen
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
  }

  /// UI piece: support link.
  Widget _supportLink() => Center(
        child: TextButton.icon(
          onPressed: _contactSupport,
          icon: const Icon(Icons.headset_mic_outlined, size: 18, color: AiraColors.roseDeep),
          label: Text('Contact Support',
              style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
        ),
      );

  /// UI piece: badge.
  Widget _badge(IconData icon, {bool sparkle = false}) => Center(
        child: Container(
          width: 118,
          height: 118,
          decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
          child: sparkle
              ? Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: const BoxDecoration(gradient: AiraGradients.button, shape: BoxShape.circle),
                    child: Icon(icon, size: 42, color: Colors.white),
                  ),
                )
              : Icon(icon, size: 56, color: AiraColors.roseDeep),
        ),
      );

  /// UI piece: note.
  Widget _note(IconData icon, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AiraColors.pinkFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AiraColors.hair),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AiraColors.roseDeep),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft, height: 1.4)),
            ),
          ],
        ),
      );

  /// UI piece: ID proof verification line shown inside the Admin Review step.
  Widget _idProofRow() {
    final st = _idProofStatus;
    final IconData icon;
    final Color color;
    final String label;
    switch (st) {
      case ApprovalStatusKind.approved:
        icon = Icons.verified_rounded;
        color = AiraColors.success;
        label = 'ID Proof: Verified';
        break;
      case ApprovalStatusKind.rejected:
        icon = Icons.error_outline_rounded;
        color = AiraColors.errorText;
        label = 'ID Proof: Rejected';
        break;
      case ApprovalStatusKind.pending:
        icon = Icons.hourglass_bottom_rounded;
        color = AiraColors.roseDeep;
        label = 'ID Proof: Verification Pending';
        break;
      default:
        icon = Icons.help_outline_rounded;
        color = AiraColors.charcoalSoft;
        label = 'ID Proof: Not Uploaded';
    }
    final reason = st == ApprovalStatusKind.rejected && (_idProofRejection ?? '').isNotEmpty ? _idProofRejection! : null;
    return Padding(
      padding: const EdgeInsets.only(left: 48, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: color))),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: 3),
            Text(reason, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35)),
          ],
        ],
      ),
    );
  }

  /// UI piece: timeline.
  Widget _timeline() {
    Widget row(String title, String sub, {required int state}) {
      final done = state == 0;
      final active = state == 1;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: (done || active) ? AiraGradients.button : null,
                color: (done || active) ? null : AiraColors.pinkFill,
                border: (done || active) ? null : Border.all(color: AiraColors.pinkBorder),
              ),
              child: Icon(
                done ? Icons.check_rounded : (active ? Icons.access_time_rounded : Icons.description_outlined),
                size: 19,
                color: (done || active) ? Colors.white : AiraColors.charcoalSoft,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AiraText.sans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: state == 2 ? AiraColors.charcoalSoft : AiraColors.roseDeep,
                      )),
                  const SizedBox(height: 2),
                  Text(sub, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AiraCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          row('Application Submitted', 'Your Details Have Been Received.', state: 0),
          row('Admin Review', 'In Progress', state: 1),
          _idProofRow(),
          row('Set Up Your Artist Page', 'Available After Approval', state: 2),
        ],
      ),
    );
  }

  /// UI piece: approved card.
  Widget _approvedCard() {
    Widget item(IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              SunndariIconBubble(icon: icon, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                    const SizedBox(height: 2),
                    Text(sub, style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                  ],
                ),
              ),
            ],
          ),
        );
    return AiraCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create Your Artist Page', style: AiraText.serif(fontSize: 20)),
          const SizedBox(height: 6),
          item(Icons.image_outlined, 'Showcase Your Portfolio', 'Share Your Work And Style.'),
          item(Icons.description_outlined, 'Add Services, Packages & Pricing', 'Tell Clients What You Offer.'),
          item(Icons.group_add_outlined, 'Offer Additional Services', 'Expand Your Opportunities.'),
        ],
      ),
    );
  }

  /// UI piece: received.
  Widget _received() {
    final p = _progress;
    if (p == null) return const SizedBox.shrink();
    const labels = ['Your Details', 'Services & Portfolio', 'Documents', 'Partner Agreement'];
    return AiraCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(
                    p.isDone(i) ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: p.isDone(i) ? AiraColors.success : AiraColors.charcoalSoft.withOpacity(0.5),
                  ),
                  const SizedBox(width: 12),
                  Text(labels[i], style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// UI piece: body.
  Widget _body() {
    if (_kind == ApprovalStatusKind.approved) {
      return _layout(
        barTitle: 'Welcome To Sunndari',
        children: [
          _badge(Icons.check_rounded, sparkle: true),
          const SizedBox(height: 14),
          const SunndariTitle(title: 'You’re Approved!', size: 36),
          const SizedBox(height: 6),
          Text('O N B O A R D I N G   A P P R O V E D',
              textAlign: TextAlign.center,
              style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
          const SizedBox(height: 8),
          Text('Welcome To Sunndari.\nIt’s Time To Build Your Beauty Business.',
              textAlign: TextAlign.center,
              style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft, height: 1.45)),
          const SizedBox(height: 18),
          _approvedCard(),
          const SizedBox(height: 14),
          _note(Icons.info_outline_rounded, 'Your Profile Will Go Live After Your Artist Page Is Reviewed And Approved.'),
        ],
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: 'Build My Artist Page',
              arrow: true,
              expand: true,
              onTap: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                  return;
                }
                // Navigates to ArtistPageSetupScreen
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ArtistPageSetupScreen()),
                );
              },
            ),
          ],
        ),
      );
    }

    if (_kind == ApprovalStatusKind.rejected) {
      return _layout(
        barTitle: 'Application Status',
        children: [
          _badge(Icons.edit_note_rounded),
          const SizedBox(height: 14),
          SunndariTitle(
            title: 'Your Profile\nNeeds Changes',
            subtitle: (_rejectionReason ?? '').isNotEmpty
                ? "We Couldn't Approve Your Profile Yet: $_rejectionReason"
                : "We Couldn't Approve Your Profile Yet. Please Review Your Details And Submit Again.",
            size: 34,
          ),
        ],
        bottom: Column(
          children: [
            PrimaryButton(label: 'Update My Profile', icon: Icons.edit_outlined, expand: true, onTap: _updateProfile),
            const SizedBox(height: 10),
            GhostButton(
              label: _resubmitting ? 'Sending…' : 'Resubmit For Review',
              icon: Icons.send_rounded,
              expand: true,
              onTap: _resubmitting ? null : _resubmit,
            ),
            TextButton(
              onPressed: _openOnboarding,
              child: Text('Edit Other Onboarding Details',
                  style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
            ),
            _logoutLink(),
          ],
        ),
      );
    }

    if (_kind == ApprovalStatusKind.suspended) {
      return _layout(
        barTitle: 'Application Status',
        children: [
          _badge(Icons.pause_circle_outline_rounded),
          const SizedBox(height: 14),
          const SunndariTitle(
            title: 'Account\nSuspended',
            subtitle: 'Your Artist Account Is Currently Suspended. Please Contact Support For More Information.',
            size: 34,
          ),
        ],
        bottom: Column(children: [_supportLink(), _logoutLink()]),
      );
    }

    final complete = _progress?.allDone ?? false;
    return _layout(
      barTitle: 'Application Status',
      children: [
        _badge(Icons.description_outlined),
        const SizedBox(height: 14),
        SunndariTitle(
          title: complete ? 'Onboarding\nUnder Review' : 'Finish Your\nOnboarding',
          subtitle: complete
              ? 'Your Application Has Been Received. Our Team Is Reviewing Your Details And Documents.'
              : 'Complete All 4 Steps So Our Team Can Review And Approve You.',
          size: 34,
        ),
        const SizedBox(height: 20),
        if (complete) _timeline() else _received(),
        const SizedBox(height: 14),
        if (complete)
          Center(
            child: Text('We’ll Notify You When Your Application Status Changes.',
                textAlign: TextAlign.center,
                style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
          ),
        if (complete) const SizedBox(height: 12),
        if (complete && _idProofStatus == ApprovalStatusKind.rejected) ...[
          _note(Icons.error_outline_rounded, 'Your ID Proof Was Not Accepted. Tap “View Submitted Application” To Upload It Again.'),
          const SizedBox(height: 10),
        ],
        if (complete) _note(Icons.info_outline_rounded, 'Your Artist Profile Is Not Live Yet.'),
      ],
      bottom: Column(
        children: [
          if (complete) ...[
            PrimaryButton(label: 'View Submitted Application', expand: true, onTap: _openOnboarding),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _checking ? null : _checkStatus,
              child: Text(_checking ? 'Checking…' : 'Check Status',
                  style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
            ),
            _supportLink(),
          ] else
            PrimaryButton(label: 'Continue Onboarding', arrow: true, expand: true, onTap: _openOnboarding),
          _logoutLink(),
        ],
      ),
    );
  }

  /// UI piece: layout.
  Widget _layout({required String barTitle, required List<Widget> children, required Widget bottom}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: SunndariFlowBar(
            title: barTitle,
            onBack: Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            children: [
              ...children,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: bottom,
        ),
      ],
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SunndariBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
              : _body(),
        ),
      ),
    );
  }
}

/// Goes to to app shell.
void goToAppShell(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AiraAppShell()),
    (r) => false,
  );
}
