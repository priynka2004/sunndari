// FILE: screens/beauty_screen.dart
// SCREEN: Beauty Consultation — pick one of your recent looks and send it to a client,
// or recommend products to them.
//
// APIs used:
//   GET /artists/profile/get/
//   GET /artists/portfolio/get_all/
//   GET /artists/profile/share_link/   (when sharing)

import 'package:aira_app/utils/share_profile.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../models/artist/portfolio.dart';
import '../models/artist/artist_profile.dart';
import '../utils/app_feedback.dart';
import '../utils/app_session.dart';
import '../utils/service_locator.dart';
import '../utils/media_url.dart';
import 'portfolio_detail_screen.dart';
import 'recommend_product_screen.dart';

/// SCREEN: Beauty Consultation.
class BeautyScreen extends StatefulWidget {
  const BeautyScreen({super.key});

  @override
  State<BeautyScreen> createState() => _BeautyScreenState();
}

/// State of [BeautyScreen] — holds the screen data and logic.
class _BeautyScreenState extends State<BeautyScreen> {
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  ArtistProfile? _profile;
  List<Portfolio> _looks = [];
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads this screen's data (profile + 6 latest portfolio items).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        // API call: artistService.getProfile → GET /artists/profile/get/
        ServiceLocator.artistService.getProfile(),
        // API call: artistService.getAllPortfolios → GET /artists/portfolio/get_all/
        ServiceLocator.artistService.getAllPortfolios(limit: 6, sortBy: 'createdAt', sortOrder: 'desc'),
      ]);
      if (!mounted) return;
      final looks = ((results[1] as dynamic).data as List<Portfolio>).toList();
      setState(() {
        _profile = results[0] as ArtistProfile;
        _looks = looks;
        if (_selectedId == null || !looks.any((l) => l.portfolioId == _selectedId)) {
          _selectedId = looks.isEmpty ? null : looks.first.portfolioId;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Portfolio? get _selected {
    for (final l in _looks) {
      if (l.portfolioId == _selectedId) return l;
    }
    return null;
  }

  /// Shares the selected look (caption + photo link + profile link) via the system share sheet.
  Future<void> _shareLook() async {
    final look = _selected;
    if (look == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      String? link;
      try {
        // API call: artistBusiness.getShareLink → GET /artists/profile/share_link/
        link = await ServiceLocator.artistBusiness.getShareLink();
      } catch (_) {}
      final name = (_profile?.displayName ?? AppSession.instance.name ?? '').trim();
      final photo = resolveMediaUrl(look.fileUrl);
      final b = StringBuffer(name.isEmpty ? 'Take A Look At My Latest Work On Sunndari ✨' : 'Take A Look At My Latest Work — $name On Sunndari ✨');
      if (look.caption?.trim().isNotEmpty == true) b.write('\n${look.caption!.trim()}');
      if (photo != null && photo.isNotEmpty) b.write('\n$photo');
      if (link != null && link.isNotEmpty) b.write('\nBook me here: $link');
      await SharePlus.instance.share(ShareParams(text: b.toString()));
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _label(String t) =>
      Text(t, style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft));

  Widget _lookTile(Portfolio l) {
    final selected = l.portfolioId == _selectedId;
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: l == _looks.last ? 0 : 10),
        child: GestureDetector(
          onTap: () => setState(() => _selectedId = l.portfolioId),
          onLongPress: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => PortfolioDetailScreen(portfolio: l)),
            );
            if (changed == true) _load();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AiraColors.rose : Colors.transparent, width: 2),
            ),
            child: AiraCard(
              padding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        height: 96,
                        width: double.infinity,
                        child: Image.network(
                          resolveMediaUrl(l.fileUrl) ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(decoration: const BoxDecoration(gradient: AiraGradients.beautyLookTile)),
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: AiraColors.rose,
                            child: Icon(Icons.check_rounded, size: 15, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      l.caption?.isNotEmpty == true ? l.caption! : 'My Work Look',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    final url = resolveMediaUrl(_profile?.profilePhotoUrl);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: (url == null || url.isEmpty) ? AiraGradients.avatarOrb : null,
        image: (url == null || url.isEmpty) ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
    );
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AiraErrorState(message: _error!, onRetry: _load);
    }
    final reviews = _profile?.totalReviews ?? 0;
    final displayName = (_profile?.displayName ?? AppSession.instance.name ?? '').trim();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: SunndariPageHeading(title: 'Beauty Consultation', subtitle: 'Show Clients The Look That Suits Them.'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _label('YOUR RECENT WORK  ·  TAP A LOOK TO SELECT'),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _loading
              ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose)),
          )
              : _looks.isEmpty
              ? AiraCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No Looks Yet. Add Photos In Profile → Business → Portfolio And They Will Show Up Here.',
              style: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft, height: 1.4),
            ),
          )
              : SizedBox(
            // up to 3 per row; extra looks wrap to the next row
            child: Column(
              children: [
                for (var i = 0; i < _looks.length; i += 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = i; j < i + 3; j++)
                          j < _looks.length ? _lookTile(_looks[j]) : const Expanded(child: SizedBox()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AiraCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displayName.isEmpty ? 'Your Profile' : displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 14, color: AiraColors.gold),
                              const SizedBox(width: 4),
                              Text(
                                _loading
                                    ? 'Loading…'
                                    : reviews == 0
                                    ? 'No Reviews Yet'
                                    : '${(_profile?.avgRating ?? 0).toStringAsFixed(1)} · $reviews review${reviews == 1 ? '' : 's'}',
                                style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: _sharing ? 'Opening Share…' : 'Share This Look With Client',
                  icon: Icons.ios_share_rounded,
                  small: true,
                  expand: true,
                  onTap: () => shareArtistProfile(context),                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AiraCard(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const RecommendProductScreen())),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const SunndariIconBubble(icon: Icons.spa_outlined, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recommend Products',
                          style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                      const SizedBox(height: 2),
                      Text('Pick Skincare & Makeup Picks And Send The List To Your Client.',
                          style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft, height: 1.3)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AiraColors.rose),
              ],
            ),
          ),
        ),
      ],
    );
  }
}