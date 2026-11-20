// FILE: screens/review_customer_screen.dart
// SCREEN: Review Customer — artist rates the customer after completing a booking.
//
// APIs used:
//   GET /artists/customer_reviews/get_all/   (was this booking already reviewed?)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../models/artist/create_portfolio.dart';
import '../models/enums/media_type_enum.dart';

/// SCREEN: Review Customer — artist rates the customer after completing a booking.
class ReviewCustomerScreen extends StatefulWidget {
  final int bookingId;
  final String customerName;
  /// Service sub-category of the booking (used for the makeup photos). When null, the first active one is used.
  final int? subCategoryId;
  const ReviewCustomerScreen({super.key, required this.bookingId, required this.customerName, this.subCategoryId});

  static const _reviewedKey = 'reviewed_customer_booking_ids';

  /// True once the artist has already reviewed the customer for this booking.
  /// Checked on the phone first, then with the server (so it also works after a reinstall or on a new phone).
  /// API: artistBusiness.getCustomerReviewsGiven → GET /artists/customer_reviews/get_all/?filter_key=bookingId
  static Future<bool> isReviewed(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getStringList(_reviewedKey) ?? const <String>[]).contains('$bookingId')) return true;
    } catch (_) {}
    try {
      final list = await ServiceLocator.artistBusiness.getCustomerReviewsGiven(bookingId: bookingId);
      final done = list.any((e) => ((e['bookingId'] ?? e['booking_id']) as num?)?.toInt() == bookingId);
      if (done) await markReviewed(bookingId);
      return done;
    } catch (_) {
      return false;
    }
  }

  /// Remembers that this booking's customer review is done (so the Journey
  /// screen does not offer "Review Customer" again).
  static Future<void> markReviewed(int bookingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_reviewedKey) ?? <String>[]).toList();
      if (!list.contains('$bookingId')) {
        list.add('$bookingId');
        await prefs.setStringList(_reviewedKey, list);
      }
    } catch (_) {}
  }

  @override
  State<ReviewCustomerScreen> createState() => _ReviewCustomerScreenState();
}

/// State of [ReviewCustomerScreen] — holds the screen data and logic.
class _ReviewCustomerScreenState extends State<ReviewCustomerScreen> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  /// Photos of the customer's finished makeup (1 to 5, required).
  static const _maxPhotos = 5;
  final List<XFile> _photos = [];
  String? _photoError;

  /// Takes a makeup photo with the camera (one per tap, up to [_maxPhotos]) — not picked from the gallery.
  /// The original is sent as it is; the server shrinks it.
  Future<void> _pickPhotos() async {
    try {
      final room = _maxPhotos - _photos.length;
      if (room <= 0) {
        AppFeedback.showInfo(context, 'You Can Add Up To $_maxPhotos Photos');
        return;
      }
      final shot = await ImagePicker().pickImage(source: ImageSource.camera);
      if (shot == null || !mounted) return;
      setState(() {
        if (!_photos.any((e) => e.path == shot.path)) _photos.add(shot);
        _photoError = null;
      });
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    }
  }

  /// Uploads the makeup photos as portfolio items.
  /// API: GET /core/service-sub-category/get_all/ · POST /artists/portfolio/create/
  /// Returns how many photos failed to upload.
  Future<int> _uploadPhotos() async {
    var subId = widget.subCategoryId;
    if (subId == null) {
      final subs = (await ServiceLocator.coreService.getAllServiceSubCategories(limit: 100)).data.where((x) => x.isActive).toList();
      if (subs.isEmpty) return _photos.length;
      subId = subs.first.subCategoryId;
    }
    var failed = 0;
    for (final f in _photos) {
      try {
        await ServiceLocator.artistService.createPortfolio(CreatePortfolio(
          mediaType: MediaTypeEnum.image,
          subCategoryId: subId,
          file: f,
          caption: 'Makeup for ${widget.customerName}',
        ));
      } catch (_) {
        failed++;
      }
    }
    return failed;
  }

  /// Frees controllers / listeners when the screen closes.
  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Submits the form.
  /// API: POST /artists/customer_reviews/create/
  Future<void> _submit() async {
    if (_photos.isEmpty) {
      setState(() => _photoError = 'Please Add At Least 1 Photo Of The Makeup You Did (Up To $_maxPhotos).');
      return;
    }
    setState(() => _submitting = true);
    try {
      // API call: artistBusiness.reviewCustomer → POST /artists/customer_reviews/create/
      // (once per completed booking; private to the artist)
      await ServiceLocator.artistBusiness.reviewCustomer(
        bookingId: widget.bookingId,
        rating: _rating,
        comment: _commentController.text.trim(),
      );
      await ReviewCustomerScreen.markReviewed(widget.bookingId);
      int failedPhotos = 0;
      try {
        failedPhotos = await _uploadPhotos();
      } catch (_) {
        failedPhotos = _photos.length;
      }
      if (mounted && failedPhotos > 0) {
        AppFeedback.showWarning(context,
            '$failedPhotos Photo${failedPhotos == 1 ? '' : 's'} Could Not Be Uploaded. You Can Add ${failedPhotos == 1 ? 'It' : 'Them'} Later From Portfolio.');
      }
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  SunndariBackChip(onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Review Customer', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  if (_submitted)
                    AiraCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 40, color: AiraColors.success),
                          const SizedBox(height: 12),
                          Text('Review Submitted', style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Thanks For The Feedback On ${widget.customerName}.',
                              style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          PrimaryButton(label: 'Done', expand: true, onTap: () => Navigator.of(context).pop()),
                        ],
                      ),
                    )
                  else ...[
                    AiraCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text('How Was ${widget.customerName}?',
                              style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (i) {
                              final filled = i < _rating;
                              return GestureDetector(
                                onTap: () => setState(() => _rating = i + 1),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(
                                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                                    size: 34,
                                    color: AiraColors.gold,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AiraCard(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _commentController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Anything Worth Noting For Next Time? (Optional)',
                          hintStyle: AiraText.sans(fontSize: 13, color: AiraColors.charcoalSoft),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AiraCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Photos Of ${widget.customerName}’s Makeup',
                              style: AiraText.sans(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Required · Add 1 To $_maxPhotos Photos Of The Finished Look.',
                              style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 72,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              children: [
                                for (var i = 0; i < _photos.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(File(_photos[i].path), width: 72, height: 72, fit: BoxFit.cover),
                                        ),
                                        Positioned(
                                          right: -6,
                                          top: -6,
                                          child: GestureDetector(
                                            onTap: () => setState(() => _photos.removeAt(i)),
                                            child: Container(
                                              width: 22,
                                              height: 22,
                                              decoration: const BoxDecoration(color: AiraColors.roseDeep, shape: BoxShape.circle),
                                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_photos.length < _maxPhotos)
                                  GestureDetector(
                                    onTap: _submitting ? null : _pickPhotos,
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: AiraColors.pinkFill,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AiraColors.pinkBorder, width: 1.1),
                                      ),
                                      child: const Icon(Icons.photo_camera_outlined, size: 28, color: AiraColors.roseDeep),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_photoError != null) ...[
                            const SizedBox(height: 10),
                            Text(_photoError!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: _submitting ? 'Submitting…' : 'Submit Review',
                      expand: true,
                      onTap: _submitting ? null : _submit,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}