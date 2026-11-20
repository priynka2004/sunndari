// FILE: widgets/completion_proof_image.dart
// WIDGET: the photo of a finished service. It is private: the image route needs the Bearer header,
// so it cannot be shown with a plain public link.

import 'package:flutter/material.dart';
import '../api/api_endpoints.dart';
import '../models/booking/booking.dart';
import '../theme/tokens.dart';
import '../utils/app_session.dart';

/// Shows [CompletionProof] (booking.completionProof) as an image.
class CompletionProofImage extends StatelessWidget {
  final CompletionProof proof;
  final double? width;
  final double? height;
  final BoxFit fit;

  const CompletionProofImage({
    super.key,
    required this.proof,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final token = AppSession.instance.accessToken;
    var full = proof.url.startsWith('http') ? proof.url : '${ApiEndpoints.baseUrl}${proof.url}';
    // A retaken photo keeps the same route — this makes the phone fetch the new picture instead of the cached one.
    final stamp = proof.uploadedAt;
    if (stamp != null && stamp.isNotEmpty) {
      full = '$full${full.contains('?') ? '&' : '?'}v=${Uri.encodeQueryComponent(stamp)}';
    }
    Widget placeholder(IconData i) => Container(
          width: width,
          height: height,
          color: AiraColors.blush,
          alignment: Alignment.center,
          child: Icon(i, size: 26, color: AiraColors.rose),
        );
    return Image.network(
      full,
      width: width,
      height: height,
      fit: fit,
      headers: token == null || token.isEmpty ? null : {'Authorization': 'Bearer $token'},
      errorBuilder: (_, __, ___) => placeholder(Icons.broken_image_outlined),
      loadingBuilder: (c, child, prog) => prog == null ? child : placeholder(Icons.image_outlined),
    );
  }
}
