// FILE: utils/video_limits.dart
// Limits for a portfolio video: up to 300 MB and 90 seconds. The server shrinks the video afterwards,
// so any phone video (MP4, MOV, M4V, 3GP, WebM) is fine — nothing has to be compressed on the phone.

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

/// Portfolio video limits.
class VideoLimits {
  VideoLimits._();

  static const int maxBytes = 300 * 1024 * 1024;
  static const Duration maxDuration = Duration(seconds: 90);

  /// Returns a plain-language problem with the picked video, or null when it is fine to upload.
  /// If the length cannot be read on the phone, the server makes the final check.
  static Future<String?> problem(XFile video) async {
    try {
      if (await video.length() > maxBytes) {
        return 'This Video Is Too Large (300 MB Maximum). Please Choose A Smaller One.';
      }
    } catch (_) {}
    VideoPlayerController? c;
    try {
      c = VideoPlayerController.file(File(video.path));
      await c.initialize().timeout(const Duration(seconds: 8));
      if (c.value.duration > maxDuration) {
        return 'The Video Is Too Long (90 Seconds Maximum). Please Trim It.';
      }
    } catch (_) {
      // Could not read the length here — the server will refuse it if it is too long.
    } finally {
      try {
        await c?.dispose();
      } catch (_) {}
    }
    return null;
  }
}
