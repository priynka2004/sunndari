// FILE: screens/kyc_bank_details_screen.dart
// SCREEN: KYC & Bank Details — view / submit KYC documents and payout details.
//
// APIs used:
//   GET /artists/documents/get_all/      (ID proof: masked number, status, rejection reason)
//   GET /artists/documents/file/         (image bytes — needs the Bearer header)
//   POST /artists/documents/create/      (Update ID Proof — replaces the old one)
//   GET /artists/payout_account/get/     (account number is masked)

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/artist/artist_extras.dart';
import '../utils/app_feedback.dart';
import '../utils/approval_status.dart';
import '../models/artist/bank_details.dart';
import '../models/artist/kyc_document.dart';
import '../theme/tokens.dart';
import '../utils/artist_extra_details.dart';
import '../utils/ifsc_lookup.dart';
import '../utils/media_url.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';
import 'onboarding/onboarding_flow_screen.dart' show OnboardingFlowScreen;

/// SCREEN: KYC & Bank Details — view / submit KYC documents and payout details.
class KycBankDetailsScreen extends StatefulWidget {
  final bool embedded;
  const KycBankDetailsScreen({super.key, this.embedded = false});

  @override
  State<KycBankDetailsScreen> createState() => _KycBankDetailsScreenState();
}

/// State of [KycBankDetailsScreen] — holds the screen data and logic.
class _KycBankDetailsScreenState extends State<KycBankDetailsScreen> {
  bool _loading = true;
  bool _loadedOnce = false;

  KycDocument? _kyc;
  BankDetails? _bank;
  ArtistExtraDetails _extra = const ArtistExtraDetails();

  bool _showAadhar = false;
  bool _showAccount = false;

  /// Runs once when the screen opens; starts: _load().
  @override
  void initState() {
    super.initState();
    _load();
  }

  /// ID proof returned by the server (null until one is uploaded).
  ArtistDocument? _idDoc;
  ApprovalStatusKind _idKind = ApprovalStatusKind.pending; // resolved from verificationStatusId
  String? _serverUpi;
  final Map<String, Future<Uint8List>> _docBytes = {};

  /// Loads this screen's data.
  /// Uses 2 APIs (see inline notes).
  Future<void> _load() async {
    if (!_loadedOnce) setState(() => _loading = true);
    try {
      // API call: artistBusiness.getDocuments → GET /artists/documents/get_all/
      final docs = await ServiceLocator.artistBusiness.getDocuments();
      final id = docs.where((d) => d.documentType == 'id_proof');
      _idDoc = id.isEmpty ? null : id.first;
      // API call: GET /core/approval-status/get_all/ — verificationStatusId → pending / approved / rejected
      _idKind = await resolveApprovalStatusKind(_idDoc?.verificationStatusId);
      _docBytes.clear();
      final d = _idDoc;
      // The same KycDocument shape is kept so the rest of this screen stays unchanged. Image "urls" use a
      // private `doc:<id>:<side>` scheme that _kycImage resolves with an authenticated request.
      _kyc = d == null
          ? null
          : KycDocument(
              artistId: 0,
              aadharNumber: d.documentNumberMasked,
              aadharImageUrl: 'doc:${d.documentId}:front',
              aadharBackImageUrl: d.hasBackFile ? 'doc:${d.documentId}:back' : null,
            );
    } catch (e, st) {
      debugPrint('[KycBankDetails] getDocuments failed: $e\n$st');
    }
    try {
      // API call: artistBusiness.getPayoutAccount → GET /artists/payout_account/get/
      final acc = await ServiceLocator.artistBusiness.getPayoutAccount();
      _serverUpi = acc.upiId;
      _bank = acc.isSaved
          ? BankDetails(
              artistId: 0,
              accountHolderName: acc.accountHolderName,
              accountNumber: acc.accountNumberMasked,
              ifscCode: acc.ifscCode,
              bankName: _bankNameCache,
            )
          : null;
      // The payout API does not store a bank name, so it is looked up again from the IFSC (same lookup as onboarding).
      final code = acc.ifscCode.trim().toUpperCase();
      if (_bank != null && IfscLookup.isValidFormat(code)) {
        if (_bankNameCacheFor != code) {
          final info = await IfscLookup.fetch(code);
          if (info != null && info.bank.trim().isNotEmpty) {
            _bankNameCache = info.bank;
            _bankNameCacheFor = code;
          }
        }
        if ((_bankNameCache ?? '').isNotEmpty && _bankNameCacheFor == code) {
          _bank = BankDetails(
            artistId: 0,
            accountHolderName: _bank!.accountHolderName,
            accountNumber: _bank!.accountNumber,
            ifscCode: _bank!.ifscCode,
            bankName: _bankNameCache,
          );
        }
      }
    } catch (e, st) {
      debugPrint('[KycBankDetails] getPayoutAccount failed: $e\n$st');
    }
    try {
      _extra = await ArtistExtraDetails.load();
    } catch (e, st) {
      debugPrint('[KycBankDetails] ArtistExtraDetails.load failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadedOnce = true;
    });
  }

  String? _bankNameCache;
  String? _bankNameCacheFor;

  bool _filled(String? v) => (v ?? '').trim().isNotEmpty;

  String? get _aadhar {
    final v = (_kyc?.aadharNumber ?? '').trim();
    if (v.isNotEmpty) return v;
    return null;
  }

  String? get _pan {
    final v = (_kyc?.panNumber ?? '').trim();
    return v.isEmpty ? null : v.toUpperCase();
  }

  String? get _upi {
    final v = ((_serverUpi ?? '').trim().isNotEmpty ? _serverUpi! : (_extra.upiId ?? '')).trim();
    return v.isEmpty ? null : v;
  }

  /// Returns true if it has bank.
  bool get _hasBank {
    final b = _bank;
    if (b == null) return false;
    return _filled(b.accountNumber) ||
        _filled(b.accountHolderName) ||
        _filled(b.ifscCode) ||
        _filled(b.bankName);
  }

  /// Mask aadhaar.
  String _maskAadhar(String v) {
    final d = v.replaceAll(RegExp(r'\s'), '');
    if (d.length < 4) return v;
    return 'XXXX XXXX ${d.substring(d.length - 4)}';
  }

  /// Groups Aadhaar.
  String _groupAadhar(String v) {
    final d = v.replaceAll(RegExp(r'\s'), '');
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(d[i]);
    }
    return b.toString();
  }

  /// Mask account.
  String _maskAccount(String v) {
    if (v.length <= 4) return v;
    return '${'•' * (v.length - 4)}${v.substring(v.length - 4)}';
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
  }

  /// UI piece: section title.
  Widget _sectionTitle(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 6),
    child: Row(children: [
      Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: AiraColors.blush, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: AiraColors.roseDeep),
      ),
      const SizedBox(width: 10),
      Text(text.toUpperCase(),
          style: AiraText.sans(
              fontSize: 12, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft, letterSpacing: 0.6)),
    ]),
  );

  /// UI piece: status chip.
  Widget _statusChip(String text, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text(text, style: AiraText.sans(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    ]),
  );

  /// UI piece: row.
  Widget _row(String label, String? value, {List<Widget> trailing = const [], bool last = false}) {
    final has = value != null && value.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AiraColors.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                const SizedBox(height: 3),
                Text(
                  has ? value : 'Not Provided',
                  style: AiraText.sans(
                    fontSize: 15,
                    fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                    color: has ? AiraColors.charcoal : AiraColors.charcoalSoft.withOpacity(0.6),
                    letterSpacing: has ? 0.3 : 0,
                  ),
                ),
              ],
            ),
          ),
          if (has) ...trailing,
        ],
      ),
    );
  }

  /// UI piece: icon btn.
  Widget _iconBtn(IconData icon, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, size: 18, color: AiraColors.charcoalSoft),
    ),
  );

  /// UI piece: KYC image.
  Widget _kycImage(String label, String url, {BoxFit fit = BoxFit.cover}) {
    Widget broken() => const Center(
      child: Icon(Icons.image_not_supported_outlined, color: AiraColors.charcoalSoft),
    );

    if (url.startsWith('data:image')) {
      try {
        final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
        return Image.memory(bytes, fit: fit, errorBuilder: (_, __, ___) => broken());
      } catch (e) {
        debugPrint('[KycBankDetails] $label base64 decode failed: $e');
        return broken();
      }
    }

    if (url.startsWith('doc:')) {
      // KYC files are private: fetch the bytes with the Bearer header (Image.network would get 401).
      final parts = url.split(':'); // doc:<id>:<side>
      final id = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
      final side = parts.length > 2 ? parts[2] : 'front';
      final fut = _docBytes.putIfAbsent(
        url,
        // API call: artistBusiness.getDocumentFile → GET /artists/documents/file/
        () => ServiceLocator.artistBusiness.getDocumentFile(id, side: side),
      );
      return FutureBuilder<Uint8List>(
        future: fut,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AiraColors.rose),
              ),
            );
          }
          if (snap.hasError || snap.data == null || snap.data!.isEmpty) return broken();
          // PDFs cannot be drawn by Image.memory — errorBuilder shows the placeholder.
          return Image.memory(snap.data!, fit: fit, errorBuilder: (_, __, ___) => broken());
        },
      );
    }

    final resolved = resolveMediaUrl(url);
    if (resolved == null) return broken();

    return Image.network(
      resolved,
      fit: fit,
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AiraColors.rose),
        ),
      ),
      errorBuilder: (_, error, __) {
        debugPrint('[KycBankDetails] $label image failed: $error (url: $resolved)');
        return broken();
      },
    );
  }

  /// UI piece: doc thumb.
  Widget _docThumb(String label, String? url) {
    final has = url != null && url.isNotEmpty;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: has ? () => _openPreview(label, url) : null,
            child: Container(
              height: 96,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AiraColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AiraColors.hair),
              ),
              child: has
                  ? Stack(fit: StackFit.expand, children: [
                _kycImage(label, url),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                    child: const Icon(Icons.zoom_out_map, size: 13, color: Colors.white),
                  ),
                ),
              ])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.image_outlined, size: 22, color: AiraColors.charcoalSoft.withOpacity(0.5)),
                const SizedBox(height: 4),
                Text('Not Uploaded',
                    style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft.withOpacity(0.7))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens preview.
  void _openPreview(String title, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            // Flexible: a tall ID photo shrinks to the space left instead of overflowing the dialog.
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(child: _kycImage(title, url, fit: BoxFit.contain)),
              ),
            ),
            const SizedBox(height: 8),
            Text(title, style: AiraText.sans(fontSize: 13, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  /// Label for the API id_type.
  String _idLabel(String? t) => switch (t) {
        'aadhaar' => 'Aadhaar Number',
        'voter_id' => 'Voter ID Number',
        'passport' => 'Passport Number',
        'driving_licence' => 'Driving Licence Number',
        _ => 'ID Number',
      };

  /// Replaces the ID proof: opens the upload screen; the new ID goes back to "pending" and is verified again.
  /// API: POST /artists/documents/create/ (a new ID proof replaces the previous one)
  Future<void> _updateIdProof() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const OnboardingFlowScreen(updateIdProof: true)),
    );
    if (changed == true && mounted) {
      AppFeedback.showSuccess(context, 'ID Proof Updated. Our Team Will Verify It Again.');
      _load();
    }
  }

  /// UI piece: identity card (ID proof from /artists/documents/get_all/).
  Widget _identityCard() {
    final doc = _idDoc;
    final number = _aadhar; // masked by the server
    final (chipText, chipColor, chipIcon) = switch (_idKind) {
      ApprovalStatusKind.approved => ('Verified', const Color(0xFF1F9254), Icons.verified_rounded),
      ApprovalStatusKind.rejected => ('Rejected', const Color(0xFFD64545), Icons.error_outline_rounded),
      _ => ('Under Review', const Color(0xFFB4780A), Icons.hourglass_top_rounded),
    };
    return AiraCard(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (doc != null)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: _statusChip(chipText, chipColor, chipIcon),
          ),
        if (doc != null && _idKind == ApprovalStatusKind.rejected && (doc.rejectionReason ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text('Reason: ${doc.rejectionReason}',
                style: AiraText.sans(fontSize: 12.5, color: const Color(0xFFD64545))),
          ),
        _row(
          _idLabel(doc?.idType),
          number,
          last: true,
        ),
        const SizedBox(height: 6),
        Row(children: [
          _docThumb('Front', _kyc?.aadharImageUrl),
          const SizedBox(width: 12),
          _docThumb('Back', _kyc?.aadharBackImageUrl),
        ]),
        if (doc != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _updateIdProof,
              icon: const Icon(Icons.edit_outlined, size: 18, color: AiraColors.rose),
              label: Text('Update ID Proof',
                  style: AiraText.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AiraColors.rose)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Tap Update ID Proof To Upload A New One — It Replaces This One And Is Verified Again.',
            style: AiraText.sans(fontSize: 11.5, color: AiraColors.charcoalSoft),
          ),
        ),
      ]),
    );
  }

  /// UI piece: payout card.
  Widget _payoutCard() {
    final upi = _upi;
    final bank = _bank;
    final primaryIsUpi = _extra.payoutMethod == PayoutMethod.upi;

    if (upi == null && !_hasBank) {
      return AiraCard(
        padding: const EdgeInsets.all(18),
        child: Text('No Payout Details Added Yet.',
            style: AiraText.sans(fontSize: 14, color: AiraColors.charcoalSoft)),
      );
    }

    final tiles = <Widget>[];

    Widget upiTile() => _payoutBlock(
      title: 'UPI',
      icon: Icons.qr_code_2_rounded,
      isPrimary: primaryIsUpi,
      children: [
        _row('UPI ID', upi,
            last: true, trailing: [_iconBtn(Icons.copy_rounded, () => _copy('UPI ID', upi!))]),
      ],
    );

    Widget bankTile() => _payoutBlock(
      title: 'Bank Account',
      icon: Icons.account_balance_outlined,
      isPrimary: !primaryIsUpi,
      children: [
        _row('Account Holder', _filled(bank?.accountHolderName) ? bank!.accountHolderName : null),
        _row(
          'Account Number',
          _filled(bank?.accountNumber)
              ? (_showAccount ? bank!.accountNumber : _maskAccount(bank!.accountNumber))
              : null,
          trailing: [
            _iconBtn(_showAccount ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    () => setState(() => _showAccount = !_showAccount)),
          ],
        ),
        _row('IFSC Code', _filled(bank?.ifscCode) ? bank!.ifscCode.toUpperCase() : null,
            trailing: [
              _iconBtn(Icons.copy_rounded, () => _copy('IFSC', bank!.ifscCode.toUpperCase())),
            ]),
        _row('Bank Name', _filled(bank?.bankName) ? bank!.bankName : null, last: true),
      ],
    );

    if (primaryIsUpi) {
      if (upi != null) tiles.add(upiTile());
      if (_hasBank) tiles.add(bankTile());
    } else {
      if (_hasBank) tiles.add(bankTile());
      if (upi != null) tiles.add(upiTile());
    }

    return Column(children: [
      for (var i = 0; i < tiles.length; i++) ...[
        tiles[i],
        if (i < tiles.length - 1) const SizedBox(height: 12),
      ],
    ]);
  }

  /// UI piece: payout block.
  Widget _payoutBlock({
    required String title,
    required IconData icon,
    required bool isPrimary,
    required List<Widget> children,
  }) {
    return AiraCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      borderColor: isPrimary ? AiraColors.rose : AiraColors.hair,
      borderWidth: isPrimary ? 1.4 : 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: AiraColors.roseDeep),
          const SizedBox(width: 8),
          Text(title, style: AiraText.sans(fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (isPrimary) _statusChip('Payout Method', AiraColors.roseDeep, Icons.check_circle_rounded),
        ]),
        const SizedBox(height: 4),
        ...children,
      ]),
    );
  }

  /// UI piece: header.
  Widget _header() {
    final hasAnything = _aadhar != null || _idDoc != null || _hasBank || _upi != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SunndariBackChip(onTap: () => Navigator.of(context).pop()),
          ),
        Expanded(child: Text('KYC & Bank Details', style: AiraText.serif(fontSize: 20, fontWeight: FontWeight.w600))),
        _statusChip(
          hasAnything ? 'Submitted' : 'Pending',
          hasAnything ? AiraColors.success : AiraColors.warn,
          hasAnything ? Icons.verified_outlined : Icons.schedule,
        ),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AiraColors.blush.withOpacity(0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_outline_rounded, size: 18, color: AiraColors.roseDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These Details Are View-Only. To Correct Or Change Them, Please Contact Sunndari Support.',
              style: AiraText.sans(fontSize: 12.5, height: 1.45),
            ),
          ),
        ]),
      ),
    ]);
  }

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    final Widget content = _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
            : RefreshIndicator(
          color: AiraColors.rose,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              _header(),
              const SizedBox(height: 22),
              _sectionTitle(Icons.badge_outlined, 'Identity Verification'),
              _identityCard(),
              const SizedBox(height: 22),
              _sectionTitle(Icons.account_balance_wallet_outlined, 'Payout Details'),
              _payoutCard(),
            ],
          ),
        );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(child: content),
    );
  }
}