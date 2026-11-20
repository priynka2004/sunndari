// FILE: widgets/video_viewer.dart
// WIDGET: full-screen video player for portfolio videos.
//
// Needs the `video_player` package:  flutter pub add video_player
// (https videos work on Android and iOS without extra setup.)
//
// Usage:  await showVideoViewer(context, url: resolveMediaUrl(p.fileUrl)!, title: p.caption);

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Opens the player on top of the current screen. Returns when it is closed.
Future<void> showVideoViewer(BuildContext context, {required String url, String? title}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _VideoViewerPage(url: url, title: title)),
  );
}

class _VideoViewerPage extends StatefulWidget {
  final String url;
  final String? title;
  const _VideoViewerPage({required this.url, this.title});

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _togglePlay(VideoPlayerValue v) {
    if (v.isPlaying) {
      _c.pause();
    } else {
      // Played to the end → start again.
      if (v.duration > Duration.zero && v.position >= v.duration) _c.seekTo(Duration.zero);
      _c.play();
    }
  }

  Widget _video() {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            const Text('Could Not Play This Video.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Please Check Your Internet And Try Again. If It Still Does Not Play, Upload The Video Again.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
    if (!_ready) return const CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white);
    return GestureDetector(
      onTap: () => _togglePlay(_c.value),
      child: AspectRatio(aspectRatio: _c.value.aspectRatio == 0 ? 9 / 16 : _c.value.aspectRatio, child: VideoPlayer(_c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _video()),
            Positioned(
              top: 4,
              left: 4,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(widget.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            if (_ready && !_failed)
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _c,
                  builder: (_, v, __) => Row(
                    children: [
                      IconButton(
                        icon: Icon(v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 40),
                        onPressed: () => _togglePlay(v),
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          _c,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.white,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
