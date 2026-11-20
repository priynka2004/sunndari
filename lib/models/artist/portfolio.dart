// FILE: models/artist/portfolio.dart  |  MODEL
// One portfolio item (photo/video + caption + approval status).

/// Model: Portfolio.
class Portfolio {
  final int portfolioId;
  final int artistId;
  final String fileUrl;
  final String mediaType;
  final int subCategoryId;
  final String? caption;
  final int? approvalStatusId;
  final bool isActive;
  final bool isWorkSample;
  final int sortOrder;
  /// Videos are shrunk by the server in the background: pending → processing → ready, or failed.
  /// Images and older items are always `ready`.
  final String processingStatus;
  /// Plain-language reason when [processingStatus] is `failed` (show it to the artist).
  final String? processingError;
  /// Still frame of a video (grid thumbnail).
  final String? posterUrl;
  /// Length of a video in seconds.
  final int? durationSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Portfolio({
    required this.portfolioId,
    required this.artistId,
    required this.fileUrl,
    required this.mediaType,
    required this.subCategoryId,
    this.caption,
    this.approvalStatusId,
    required this.isActive,
    this.isWorkSample = false,
    this.sortOrder = 0,
    this.processingStatus = 'ready',
    this.processingError,
    this.posterUrl,
    this.durationSeconds,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True while the server is still working on a video (show a "processing" state).
  bool get isProcessing => processingStatus == 'pending' || processingStatus == 'processing';

  /// True when the server could not process a video (show [processingError]).
  bool get processingFailed => processingStatus == 'failed';

  /// Builds this object from API JSON.
  factory Portfolio.fromJson(Map<String, dynamic> json) => Portfolio(
    portfolioId: json['portfolioId'],
    artistId: json['artistId'],
    fileUrl: json['fileUrl'],
    mediaType: json['mediaType'],
    subCategoryId: json['subCategoryId'],
    caption: json['caption'],
    approvalStatusId: json['approvalStatusId'],
    isActive: json['isActive'] != false,
    isWorkSample: json['isWorkSample'] == true,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    processingStatus: (json['processingStatus'] ?? 'ready').toString(),
    processingError: (json['processingError'] ?? '').toString().isEmpty ? null : json['processingError'].toString(),
    posterUrl: (json['posterUrl'] ?? '').toString().isEmpty ? null : json['posterUrl'].toString(),
    durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );
}
