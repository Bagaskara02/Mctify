import 'dart:async';
import 'package:audio_service/audio_service.dart';
import '../models/track.dart';

class MediaAudioHandler extends BaseAudioHandler with SeekHandler {
  Function()? onPlay;
  Function()? onPause;
  Function()? onSkipToNext;
  Function()? onSkipToPrevious;
  Function(Duration)? onSeekTo;

  // TWS & Bluetooth Headset Multi-Tap Detector
  Timer? _mediaClickTimer;
  int _mediaClickCount = 0;

  MediaAudioHandler() {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  void updateTrack(Track track, Duration duration) {
    mediaItem.add(MediaItem(
      id: track.id,
      album: track.album,
      title: track.title,
      artist: track.artist,
      duration: duration,
      artUri: Uri.tryParse(track.artwork),
    ));
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: position,
      bufferedPosition: position,
      speed: 1.0,
    ));
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
      case MediaButton.media:
        // TWS Multi-Tap Detection:
        // 1 tap: Play/Pause (debounced by 320ms)
        // 2 taps: Skip to next track (debounced by 320ms)
        // 3 taps: Rewind to 00:00 / Previous track (fires immediately on 3rd tap)
        _mediaClickCount++;
        _mediaClickTimer?.cancel();

        if (_mediaClickCount >= 3) {
          // 3 taps reached: Fire previous immediately
          _mediaClickCount = 0;
          await skipToPrevious();
        } else {
          // Wait 320ms to see if another tap occurs
          _mediaClickTimer = Timer(const Duration(milliseconds: 320), () async {
            final count = _mediaClickCount;
            _mediaClickCount = 0;
            if (count == 1) {
              final isPlaying = playbackState.value.playing;
              if (isPlaying) {
                await pause();
              } else {
                await play();
              }
            } else if (count == 2) {
              await skipToNext();
            }
          });
        }
    }
  }

  @override
  Future<void> play() async {
    onPlay?.call();
  }

  @override
  Future<void> pause() async {
    onPause?.call();
  }

  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    onSeekTo?.call(position);
  }
}
