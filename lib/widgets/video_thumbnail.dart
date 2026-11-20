// FILE: widgets/video_thumbnail.dart
// Thumbnail for a video: the server's poster picture, else the video's own first frame (paused, never played).

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Thumbnail of a video: the server's poster image when there is one, otherwise the video's own first frame
/// (the video is loaded but never played here). While it loads — or if it cannot load — a plain gradient shows.
class VideoThumbnail extends StatefulWidget {
  final String url;
  final String? posterUrl;
  const VideoThumbnail({super.key, required this.url, this.posterUrl});

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _c;
  bool _ready = false;

  bool get _hasPoster => (widget.posterUrl ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!_hasPoster) _load();
  }

  Future<void> _load() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      await c.setVolume(0);
      // A tiny seek makes sure a real picture (not a black frame) is drawn while the video is paused.
      await c.seekTo(const Duration(milliseconds: 300));
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Keep the gradient: the video still opens (and plays) when tapped.
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    Widget picture = const SizedBox.shrink();
    if (_hasPoster) {
      picture = Image.network(widget.posterUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else if (_ready && c != null && c.value.isInitialized && c.value.size.width > 0) {
      picture = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
      );
    }
    return Stack(fit: StackFit.expand, children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF5A0A24), Color(0xFF22120D)],
          ),
        ),
      ),
      picture,
      // A light scrim so the white play button and labels stay readable on any picture.
      Container(color: Colors.black.withOpacity(0.18)),
    ]);
  }
}