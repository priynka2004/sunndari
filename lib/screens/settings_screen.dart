// FILE: screens/settings_screen.dart
// SCREEN: Profile / Settings tab — profile card, account, business links, logout.

import 'package:aira_app/utils/service_locator.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:aira_app/utils/media_url.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/artist/artist_profile.dart';
import '../utils/app_feedback.dart';
import '../utils/artist_extra_details.dart';
import '../utils/profile_completeness.dart';
import 'edit_profile_screen.dart';
import 'business_details_screen.dart';
import 'notifications_screen.dart';
import 'auth/registration_status_screen.dart';
import 'help_center_screen.dart';
import 'support_tickets_screen.dart';
import 'calendar_screen.dart';
import 'edit_working_hours_screen.dart';
import 'public_profile_preview_screen.dart';
import 'auth/forgot_password_screen.dart';
import '../utils/share_profile.dart';
import 'onboarding/artist_page_setup_screen.dart';
import 'my_clients_screen.dart';
import 'reviews_ratings_screen.dart';
import 'insights_screen.dart';
import 'marketing_screen.dart';
import 'beauty_screen.dart';

/// SCREEN: Profile / Settings tab — profile card, account, business links, logout.
class SettingsScreen extends StatefulWidget {
  final String name;
  final String? city;
  final ArtistProfile? profile;
  final VoidCallback onLogout;
  final VoidCallback? onProfileUpdated;

  const SettingsScreen({
    super.key,
    this.name = '',
    this.city,
    this.profile,
    required this.onLogout,
    this.onProfileUpdated,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// State of [SettingsScreen] — holds the screen data and logic.
class _SettingsScreenState extends State<SettingsScreen> {
  bool? _accepting; // null until the profile is known

  /// Turns new bookings on / off. Off = hidden from search and cannot be booked (existing bookings are unaffected).
  /// API: artistBusiness.setAcceptingBookings → PUT /artists/profile/accepting_bookings/
  Future<void> _toggleAccepting(bool v) async {
    final before = _accepting ?? widget.profile?.isAcceptingBookings ?? true;
    setState(() => _accepting = v);
    try {
      await ServiceLocator.artistBusiness.setAcceptingBookings(v);
    } catch (e) {
      if (mounted) {
        setState(() => _accepting = before);
        AppFeedback.showError(context, e);
      }
    }
  }

  ArtistExtraDetails _extra = const ArtistExtraDetails();
  double? _completion;
  bool _photoBusy = false;

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data.
  Future<void> _load() async {
    final extra = await ArtistExtraDetails.load();
    if (!mounted) return;
    setState(() => _extra = extra);
    _computeCompletion(extra);
  }

  /// Computes completion.
  Future<void> _computeCompletion(ArtistExtraDetails extra) async {
    try {
      final c = await ProfileCompleteness.load(profile: widget.profile);
      if (!mounted) return;
      setState(() => _completion = c.fraction);
    } catch (_) {
    }
  }

  /// Changes photo.
  Future<void> _changePhoto() async {
    final hasPhoto = (_extra.profilePhotoPath ?? '').isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AiraColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AiraColors.hair, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AiraColors.charcoal),
              title: Text(hasPhoto ? 'Choose A Different Photo' : 'Choose From Gallery',
                  style: AiraText.sans(fontSize: 14.5)),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AiraColors.errorText),
                title: Text('Remove Photo', style: AiraText.sans(fontSize: 14.5, color: AiraColors.errorText)),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'remove') {
      setState(() => _photoBusy = true);
      final updated = await _extra.clearProfilePhoto();
      // API call: artistBusiness.deleteProfilePhoto → DELETE /artists/profile/photo/delete/?kind=profile
      try {
        await ServiceLocator.artistBusiness.deleteProfilePhoto('profile');
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _extra = updated;
        _photoBusy = false;
      });
      _computeCompletion(updated);
      return;
    }

    setState(() => _photoBusy = true);
    final path = await ArtistExtraDetails.pickAndSaveProfilePhoto(source: ImageSource.gallery);
    if (!mounted) return;
    if (path == null) {
      setState(() => _photoBusy = false);
      return;
    }
    final updated = _extra.copyWith(profilePhotoPath: path);
    await updated.save();
    try {
      // API call: artistBusiness.uploadProfilePhotos → PUT /artists/profile/photo/upload/
      await ServiceLocator.artistBusiness.uploadProfilePhotos(profilePhoto: XFile(path));
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
    if (!mounted) return;
    setState(() {
      _extra = updated;
      _photoBusy = false;
    });
    _computeCompletion(updated);
    if (mounted) AppFeedback.showSuccess(context, 'Profile Photo Updated ✓');
  }

  /// UI piece: avatar.
  Widget _avatar() {
    final path = _extra.profilePhotoPath;
    final file = (path != null && path.isNotEmpty) ? File(path) : null;
    final hasFile = file != null && file.existsSync();
    final serverUrl = resolveMediaUrl(widget.profile?.profilePhotoUrl);
    final ImageProvider? photo = hasFile ? FileImage(file) : (serverUrl != null ? NetworkImage(serverUrl) : null);

    return GestureDetector(
      onTap: _photoBusy ? null : _changePhoto,
      child: Stack(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: photo != null ? null : AiraGradients.avatarOrb,
              shape: BoxShape.circle,
              image: photo != null ? DecorationImage(image: photo, fit: BoxFit.cover) : null,
            ),
            alignment: Alignment.center,
            child: _photoBusy
                ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : (photo != null
                ? null
                : Text(
              widget.name.isNotEmpty ? widget.name.trim()[0].toUpperCase() : 'S',
              style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            )),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AiraColors.roseDeep,
                shape: BoxShape.circle,
                border: Border.all(color: AiraColors.bg, width: 2),
              ),
              child: const Icon(Icons.edit, size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// UI piece: completion bar.
  Widget _completionBar() {
    final pct = _completion;
    if (pct == null) return const SizedBox.shrink();
    final percent = (pct * 100).round();
    final done = pct >= 0.999;
    // Once the profile is 100% complete the card has done its job → remove it.
    if (done) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AiraColors.pinkFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AiraColors.hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  done ? 'Profile Complete ✓' : 'Profile $percent% Complete',
                  style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (!done)
                  Text('$percent%', style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AiraColors.hair,
                valueColor: AlwaysStoppedAnimation(done ? AiraColors.success : AiraColors.roseDeep),
              ),
            ),
            if (!done) ...[
              const SizedBox(height: 8),
              Text(
                'Add A Photo, Your Services & Documents So Clients Can Find And Book You.',
                style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final city = widget.city;
    final profile = widget.profile;
    final onLogout = widget.onLogout;
    final onProfileUpdated = widget.onProfileUpdated;
    final needsVerification = profile?.approvalStatusId == null;

    Future<void> handleTap(String row) async {
      if (row == 'Edit profile' || row == 'Edit Profile') {
        // Navigates to EditProfileScreen
        final updated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
        );
        if (updated == true) {
          onProfileUpdated?.call();
          _load();
          if (context.mounted) AppFeedback.showSuccess(context, 'Profile Updated ✓');
        }
      } else if (row == 'Edit & Add Service') {
        // Navigates to EditAddServiceScreen (Services & Pricing only)
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditAddServiceScreen()));
        _load();
      } else if (row == 'Edit Working Hours') {
        // Navigates to EditWorkingHoursScreen (per-day timings, same as onboarding)
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditWorkingHoursScreen()));
      } else if (row == 'Business') {
        // Navigates to BusinessDetailsScreen (Locations | Portfolio | KYC tabs)
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BusinessDetailsScreen(initialTab: 'setup')));
        _load();
      } else if (row == 'My Clients') {
        // Navigates to MyClientsScreen
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyClientsScreen()));
      } else if (row == 'Reviews & Ratings') {
        // Navigates to ReviewsRatingsScreen
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewsRatingsScreen(profile: profile)));
      } else if (row == 'Beauty Consultation') {
        // Navigates to BeautyScreen
        Navigator.of(context).push(MaterialPageRoute(
          builder: (ctx) => Scaffold(
            backgroundColor: AiraColors.bg,
            body: SunndariBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SunndariAppBar(onBack: () => Navigator.of(ctx).pop()),
                    ),
                    const Expanded(
                      child: BeautyScreen(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
      } else if (row == 'Business Insights') {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (ctx) => Scaffold(
            backgroundColor: AiraColors.bg,
            body: SunndariBackground(
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SunndariAppBar(onBack: () => Navigator.of(ctx).pop()),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: SunndariPageHeading(
                        title: 'Business Insights',
                        subtitle: 'Understand Your Business At A Glance.',
                      ),
                    ),
                    Expanded(child: InsightsScreen(onNavigate: (target, [tab]) => Navigator.of(ctx).pop())),
                  ],
                ),
              ),
            ),
          ),
        ));
      } else if (row == 'Notifications') {
        // Navigates to NotificationsScreen
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      } else if (row == 'Verification') {
        // Navigates to RegistrationStatusScreen
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RegistrationStatusScreen(approvalStatusId: profile?.approvalStatusId)));
      } else if (row == 'Availability & Calendar') {
        // Navigates to CalendarScreen
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const Scaffold(body: SafeArea(child: CalendarScreen(showBack: true)))));
      } else if (row == 'Password & Security') {
        // Navigates to ForgotPasswordScreen
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
      } else if (row == 'Support Tickets') {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportTicketsScreen()));
      } else if (row == 'Help Centre' || row == 'Help & Support') {
        // Navigates to HelpCenterScreen
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
      } else if (row == 'Log Out' || row == 'Log Out') {
        onLogout();
      } else {
        AppFeedback.showInfo(context, "This Isn't Available Yet — Check Back Soon");
      }
    }

    Widget group(String title, List<(IconData, String)> rows) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AiraText.serif(fontSize: 18)),
          const SizedBox(height: 8),
          AiraCard(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  InkWell(
                    onTap: () => handleTap(rows[i].$2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      decoration: BoxDecoration(
                        border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AiraColors.hair)),
                      ),
                      child: Row(
                        children: [
                          Icon(rows[i].$1, size: 22, color: AiraColors.roseDeep),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(rows[i].$2,
                                style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w600, color: AiraColors.roseDeep)),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 20, color: AiraColors.rose),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final live = profile?.approvalStatusId != null;
    final accepting = _accepting ?? profile?.isAcceptingBookings ?? true;

    return SunndariBackground(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Small app logo at the top of the profile page
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(child: SunndariLogo(width: 84)),
          ),
          const SunndariTabHeader(title: 'My Profile', subtitle: 'Your Brand. Your Business.'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: AiraCard(
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: AiraColors.rose,
                title: Text('Accepting New Bookings',
                    style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700, color: AiraColors.roseDeep)),
                subtitle: Text(
                  accepting
                      ? 'Clients Can Find And Book You.'
                      : 'Hidden From Search. Existing Bookings Are Not Affected.',
                  style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft),
                ),
                value: accepting,
                onChanged: _toggleAccepting,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: AiraCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _avatar(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isNotEmpty ? name : 'Your Artist Profile',
                                style: AiraText.sans(fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                            Text('Manage How Clients See Your Business.',
                                style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                          ],
                        ),
                      ),
                      if (live)
                        GestureDetector(
                          // Navigates to ArtistPageLiveScreen
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ArtistPageLiveScreen(name: name))),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(color: AiraColors.success, borderRadius: BorderRadius.circular(999)),
                            child: Text('Live', style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          label: 'View Public Profile',
                          icon: Icons.visibility_outlined,
                          small: true,
                          expand: true,
                          // Navigates to PublicProfilePreviewScreen
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PublicProfilePreviewScreen(name: name, profile: profile))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PrimaryButton(
                          label: 'Share Profile',
                          icon: Icons.ios_share_rounded,
                          small: true,
                          expand: true,
                          onTap: () => shareArtistProfile(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _completionBar(),
          const SizedBox(height: 16),
          group('My Business', const [
            (Icons.design_services_outlined, 'Edit & Add Service'),
            (Icons.access_time_rounded, 'Edit Working Hours'),
            (Icons.storefront_outlined, 'Business'),
          ]),
          group('Grow', const [
            (Icons.groups_2_outlined, 'My Clients'),
            (Icons.bar_chart_rounded, 'Business Insights'),
            (Icons.star_border_rounded, 'Reviews & Ratings'),
            (Icons.campaign_outlined, 'Marketing Studio (Coming Soon)'),
            (Icons.face_retouching_natural_outlined, 'Beauty Consultation'),
          ]),
          group('Account & Support', [
            (Icons.person_outline_rounded, 'Edit Profile'),
            (Icons.shield_outlined, 'Password & Security'),
            (Icons.help_outline_rounded, 'Help & Support'),
          ]),
          Center(
            child: TextButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18, color: AiraColors.rose),
              label: Text('Log Out', style: AiraText.sans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AiraColors.rose)),
            ),
          ),
        ],
      ),
    );
  }
}