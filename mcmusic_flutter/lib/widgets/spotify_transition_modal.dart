import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/transition_engine.dart';
import 'optimized_image.dart';

/// Authentic Spotify "Edit transition BETA" Studio Modal for Android & iOS.
/// Features:
/// - Smart Automix AI bar (% MATCH, harmonic Camelot key badge, Auto-Mix preset)
/// - Outgoing Track (Deck A) & Incoming Track (Deck B) cards with BPM, Camelot key, duration, and "Ganti" song picker
/// - Interactive Dual-Deck Waveform Canvas with CustomPainter SVG-like volume/filter envelope curves,
///   horizontal drag/tap scrubbing, center Play/Pause audition button, Bars selector, Sync toggle, and Cue Outro/Intro fine-tuner
/// - Real Dual-Deck Native Audio Audition Mixer (`TransitionAuditionMixer`) playing both songs simultaneously
/// - Bottom 3-column Settings Dock (`VOLUME`, `EQ`, `EFFECTS`) + `"Simpan & Uji Langsung di Player Utama"` button
class SpotifyTransitionModal extends StatefulWidget {
  final AudioPlayerManager player;
  final Track? initialOutgoing;
  final Track? initialIncoming;

  const SpotifyTransitionModal({
    super.key,
    required this.player,
    this.initialOutgoing,
    this.initialIncoming,
  });

  static Future<void> show(
    BuildContext context,
    AudioPlayerManager player, {
    Track? initialOutgoing,
    Track? initialIncoming,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => SpotifyTransitionModal(
        player: player,
        initialOutgoing: initialOutgoing,
        initialIncoming: initialIncoming,
      ),
    );
  }

  @override
  State<SpotifyTransitionModal> createState() => _SpotifyTransitionModalState();
}

class _SpotifyTransitionModalState extends State<SpotifyTransitionModal> {
  final MusicApiService _apiService = MusicApiService();
  final TransitionAuditionMixer _auditionMixer = TransitionAuditionMixer();

  static final List<Track> _fallbackCatalog = [
    Track(
      id: 'trans-1',
      title: 'Keep You Safe',
      artist: 'New West',
      artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=300',
      duration: 192,
      genre: 'Indie Pop',
    ),
    Track(
      id: 'trans-2',
      title: 'Fall In Love Alone',
      artist: 'Stacey Ryan',
      artwork: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=300',
      duration: 205,
      genre: 'Pop Soul',
    ),
    Track(
      id: 'trans-3',
      title: 'Die With A Smile',
      artist: 'Lady Gaga, Bruno Mars',
      artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=300',
      duration: 251,
      genre: 'Pop Soul',
    ),
    Track(
      id: 'trans-4',
      title: 'Birds of a Feather',
      artist: 'Billie Eilish',
      artwork: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=300',
      duration: 210,
      genre: 'Indie Pop',
    ),
  ];

  late Track _outgoingTrack;
  late Track _incomingTrack;
  TransitionConfig _config = const TransitionConfig();
  SmartAutomixPreset? _smartPreset;
  List<double> _topWaveBars = [];
  List<double> _bottomWaveBars = [];

  double _auditionProgress = 0.0;
  double _mixProgress = 0.0;
  String _auditionPhase = 'idle';
  TransitionEnvelope? _liveEnvelope;

  bool _showCueNudge = false;
  bool _showAutoInsight = false;
  String? _statusBanner;
  Timer? _bannerTimer;

  bool _wasMainPlayerPlaying = false;

  @override
  void initState() {
    super.initState();
    _resolveInitialTracks();
    _auditionMixer.onTick = ({
      required double progress,
      required double mixProgress,
      required String phase,
      required TransitionEnvelope envelope,
    }) {
      if (!mounted) return;
      setState(() {
        _auditionProgress = progress;
        _mixProgress = mixProgress;
        _auditionPhase = phase;
        _liveEnvelope = envelope;
      });
    };
    _auditionMixer.onComplete = () {
      if (!mounted) return;
      setState(() {
        _auditionPhase = 'idle';
        _auditionProgress = 0.0;
        _mixProgress = 0.0;
        _liveEnvelope = null;
      });
    };
    _auditionMixer.onStateChanged = () {
      if (mounted) setState(() {});
    };

    _loadPairConfiguration();
  }

  void _resolveInitialTracks() {
    final p = widget.player;
    final current = widget.initialOutgoing ?? p.currentTrack;
    final nextInQ = widget.initialIncoming ?? p.nextTrackInQueue;

    if (current != null) {
      _outgoingTrack = current;
    } else if (p.queue.isNotEmpty) {
      _outgoingTrack = p.queue.first;
    } else {
      _outgoingTrack = _fallbackCatalog[0];
    }

    if (nextInQ != null && nextInQ.id != _outgoingTrack.id) {
      _incomingTrack = nextInQ;
    } else {
      final alt = p.queue.firstWhere(
        (t) => t.id != _outgoingTrack.id,
        orElse: () => _fallbackCatalog.firstWhere(
          (t) => t.title != _outgoingTrack.title,
          orElse: () => _fallbackCatalog[1],
        ),
      );
      _incomingTrack = alt;
    }

    _rebuildWaveformsAndSmartPreset();
  }

  void _rebuildWaveformsAndSmartPreset() {
    _smartPreset = TransitionEngine.computeSmartAutomixPreset(_outgoingTrack, _incomingTrack);
    _topWaveBars = TransitionEngine.generateMusicalWaveformBars(
      _outgoingTrack,
      count: 60,
      role: 'outgoing',
    );
    _bottomWaveBars = TransitionEngine.generateMusicalWaveformBars(
      _incomingTrack,
      count: 60,
      role: 'incoming',
    );
  }

  Future<void> _loadPairConfiguration() async {
    final loaded = await widget.player.storageService.getTransitionForPair(
      _outgoingTrack,
      _incomingTrack,
    );
    final metaA = TransitionEngine.computeTrackBpmAndKey(_outgoingTrack);
    final metaB = TransitionEngine.computeTrackBpmAndKey(_incomingTrack);
    final barStats = TransitionEngine.computeBarDurationSec(metaA.bpm, metaB.bpm, loaded.bars);
    if (!mounted) return;
    final nextCfg = loaded.copyWith(
      bpmA: metaA.bpm,
      bpmB: metaB.bpm,
      durationSec: barStats.durationSec,
    );
    setState(() {
      _config = nextCfg;
    });
    unawaited(_auditionMixer.preloadDecks(
      outgoing: _outgoingTrack,
      incoming: _incomingTrack,
      config: nextCfg,
    ));
  }

  void _showStatus(String msg) {
    _bannerTimer?.cancel();
    setState(() => _statusBanner = msg);
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusBanner = null);
    });
  }

  void _updateConfig(TransitionConfig updated) {
    final metaA = TransitionEngine.computeTrackBpmAndKey(_outgoingTrack);
    final metaB = TransitionEngine.computeTrackBpmAndKey(_incomingTrack);
    final barStats = TransitionEngine.computeBarDurationSec(metaA.bpm, metaB.bpm, updated.bars);
    final normalized = updated.copyWith(
      bpmA: metaA.bpm,
      bpmB: metaB.bpm,
      durationSec: barStats.durationSec,
    );
    setState(() => _config = normalized);
    _auditionMixer.updateConfig(normalized);
  }

  Future<void> _toggleAudition() async {
    HapticFeedback.lightImpact();
    if (_auditionMixer.isPlaying) {
      await _auditionMixer.stop();
      setState(() {
        _auditionPhase = 'idle';
        _liveEnvelope = null;
      });
      if (_wasMainPlayerPlaying && !widget.player.isPlaying) {
        _wasMainPlayerPlaying = false;
        unawaited(widget.player.resumePlayback(reason: 'audition_stopped'));
      }
      return;
    }

    if (widget.player.isPlaying) {
      _wasMainPlayerPlaying = true;
      await widget.player.pausePlayback();
    }

    await _auditionMixer.start(
      outgoing: _outgoingTrack,
      incoming: _incomingTrack,
      config: _config,
      startProgress: _auditionProgress > 0.02 && _auditionProgress < 0.92
          ? _auditionProgress
          : 0.0,
    );
  }

  void _applySmartAutomix() {
    HapticFeedback.mediumImpact();
    final preset = TransitionEngine.computeSmartAutomixPreset(_outgoingTrack, _incomingTrack);
    _smartPreset = preset;
    _updateConfig(preset.config);
    setState(() => _showAutoInsight = true);
    _showStatus('Smart Automix diterapkan: ${preset.summary}');
  }

  Future<void> _handleSave({bool testLiveInPlayer = false}) async {
    HapticFeedback.mediumImpact();
    await _auditionMixer.stop(silent: true);
    _wasMainPlayerPlaying = false;
    await widget.player.saveAndApplyTransition(
      outgoing: _outgoingTrack,
      incoming: _incomingTrack,
      config: _config,
      testLiveInPlayer: testLiveInPlayer,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF16161D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF22D3EE), size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                testLiveInPlayer
                    ? 'Menguji transisi langsung: ${_outgoingTrack.title} ➔ ${_incomingTrack.title}'
                    : 'Transisi disimpan (${_config.bars} • ${_config.volumeMode})',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final s = seconds > 0 ? seconds : 180;
    final mins = s ~/ 60;
    final secs = s % 60;
    return '$mins:${secs < 10 ? '0' : ''}$secs';
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    final shouldResumeMain = _wasMainPlayerPlaying && !widget.player.isPlaying;
    unawaited(_auditionMixer.dispose());
    if (shouldResumeMain) {
      unawaited(widget.player.resumePlayback(reason: 'transition_modal_closed'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metaA = TransitionEngine.computeTrackBpmAndKey(_outgoingTrack);
    final metaB = TransitionEngine.computeTrackBpmAndKey(_incomingTrack);
    final harmonic = TransitionEngine.computeCamelotCompatibility(metaA.camelot, metaB.camelot);
    final barStats = TransitionEngine.computeBarDurationSec(metaA.bpm, metaB.bpm, _config.bars);
    final smart = _smartPreset ?? TransitionEngine.computeSmartAutomixPreset(_outgoingTrack, _incomingTrack);

    final volLabel = TransitionEngine.volumePresets
        .firstWhere((e) => e.id == _config.volumeMode, orElse: () => TransitionEngine.volumePresets.first)
        .label;
    final eqLabel = TransitionEngine.eqPresets
        .firstWhere((e) => e.id == _config.eqMode, orElse: () => TransitionEngine.eqPresets.first)
        .label;
    final fxLabel = TransitionEngine.effectPresets
        .firstWhere((e) => e.id == _config.effectsMode, orElse: () => TransitionEngine.effectPresets.first)
        .label;

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.75),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 1. Top Header Bar (Cancel | Edit transition BETA | Save)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Edit transition',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22D3EE).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.45)),
                      ),
                      child: const Text(
                        'BETA',
                        style: TextStyle(
                          color: Color(0xFF67E8F9),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _handleSave(testLiveInPlayer: false),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1ED760),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),

          // 2. Smart Automix AI Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showAutoInsight = !_showAutoInsight),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(harmonic.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${smart.compatibilityScore}% MATCH',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '• ${harmonic.label} • ${barStats.beats} ketukan',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _applySmartAutomix,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF22D3EE).withValues(alpha: 0.22),
                          const Color(0xFFA855F7).withValues(alpha: 0.22),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.auto_fix_high_rounded, size: 14, color: Color(0xFF67E8F9)),
                        SizedBox(width: 5),
                        Text(
                          'Auto-Mix',
                          style: TextStyle(
                            color: Color(0xFF67E8F9),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showAutoInsight)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFF22D3EE), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${metaA.keyName} (${metaA.camelot}) ➔ ${metaB.keyName} (${metaB.camelot}) • '
                      'Rekomendasi: ${smart.config.bars}, ${smart.config.volumeMode}, EQ ${smart.config.eqMode}.',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),

          if (_statusBanner != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1ED760).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1ED760).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF1ED760), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusBanner!,
                      style: const TextStyle(
                        color: Color(0xFF86EFAC),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Scrollable Studio Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  // Track 1 (Outgoing) & Track 2 (Incoming) Header Cards
                  _buildTrackRowCard(
                    track: _outgoingTrack,
                    meta: metaA,
                    isOutgoing: true,
                    onTapPick: () => _openSongPickerSheet(isOutgoing: true),
                  ),
                  const SizedBox(height: 8),
                  _buildTrackRowCard(
                    track: _incomingTrack,
                    meta: metaB,
                    isOutgoing: false,
                    onTapPick: () => _openSongPickerSheet(isOutgoing: false),
                  ),

                  const SizedBox(height: 14),

                  // 4. Interactive Dual-Waveform Canvas
                  _buildDualWaveformCanvas(barStats),

                  const SizedBox(height: 12),

                  // 5. Live Test in Main Player CTA Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _handleSave(testLiveInPlayer: true),
                      icon: const Icon(Icons.equalizer_rounded, size: 17, color: Color(0xFF67E8F9)),
                      label: const Text(
                        'Simpan & Uji Langsung di Player Utama',
                        style: TextStyle(
                          color: Color(0xFFA5F3FC),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        backgroundColor: const Color(0xFF22D3EE).withValues(alpha: 0.08),
                        side: BorderSide(color: const Color(0xFF22D3EE).withValues(alpha: 0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 6. Bottom 3-Column Settings Dock (Volume | EQ | Effects)
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset > 0 ? bottomInset + 8 : 16),
            decoration: BoxDecoration(
              color: const Color(0xFF101016),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.09))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildDockButton(
                    category: 'VOLUME',
                    valueLabel: volLabel,
                    icon: _buildVolumeCurveMiniIcon(_config.volumeMode),
                    onTap: () => _openPresetSheet(
                      title: 'Pilih Kurva Volume',
                      options: TransitionEngine.volumePresets,
                      selectedId: _config.volumeMode,
                      accentColor: const Color(0xFF22D3EE),
                      onSelect: (id) => _updateConfig(_config.copyWith(volumeMode: id)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDockButton(
                    category: 'EQ',
                    valueLabel: eqLabel,
                    icon: const Icon(Icons.tune_rounded, color: Color(0xFFA855F7), size: 22),
                    onTap: () => _openPresetSheet(
                      title: 'Pilih Mode Equalizer (EQ)',
                      options: TransitionEngine.eqPresets,
                      selectedId: _config.eqMode,
                      accentColor: const Color(0xFFA855F7),
                      onSelect: (id) => _updateConfig(_config.copyWith(eqMode: id)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDockButton(
                    category: 'EFFECTS',
                    valueLabel: fxLabel,
                    icon: const Icon(Icons.auto_fix_normal_rounded, color: Color(0xFF1ED760), size: 22),
                    onTap: () => _openPresetSheet(
                      title: 'Pilih Efek Filter & Delay',
                      options: TransitionEngine.effectPresets,
                      selectedId: _config.effectsMode,
                      accentColor: const Color(0xFF1ED760),
                      onSelect: (id) => _updateConfig(_config.copyWith(effectsMode: id)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRowCard({
    required Track track,
    required TrackBpmAndKey meta,
    required bool isOutgoing,
    required VoidCallback onTapPick,
  }) {
    final accentColor = isOutgoing ? const Color(0xFF22D3EE) : const Color(0xFFA855F7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              OptimizedImage(
                imageUrl: track.artwork,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(9),
                memCacheWidth: 100,
                memCacheHeight: 100,
              ),
              Positioned(
                bottom: -3,
                right: -3,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0A0A0D), width: 1.8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${meta.bpm} bpm',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      meta.camelot,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatDuration(track.duration),
                    style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTapPick,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Text(
                        'Ganti',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDualWaveformCanvas(BarDurationStats barStats) {
    final env = _liveEnvelope;
    final isPlaying = _auditionMixer.isPlaying;
    final isLoading = _auditionMixer.isLoading;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111117),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Top Time Ruler
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'OUTRO (${_config.outroOffsetSec >= 0 ? '+' : ''}${_config.outroOffsetSec.toStringAsFixed(0)}s)',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'ZONA TRANSISI • ${_config.bars.toUpperCase()} (${barStats.durationSec.toStringAsFixed(1)}S)',
                  style: const TextStyle(
                    color: Color(0xFF22D3EE),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'INTRO (+${_config.introOffsetSec.toStringAsFixed(0)}s)',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Interactive Dual-Waveform Area
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final p = (details.localPosition.dx / width).clamp(0.0, 0.99);
                  setState(() => _auditionProgress = p);
                  if (_auditionMixer.isPlaying) {
                    _auditionMixer.seek(p);
                  }
                },
                onHorizontalDragUpdate: (details) {
                  final p = (details.localPosition.dx / width).clamp(0.0, 0.99);
                  setState(() => _auditionProgress = p);
                  if (_auditionMixer.isPlaying) {
                    _auditionMixer.seek(p);
                  }
                },
                child: Stack(
                  children: [
                    // Vertical Overlap Highlight & Playhead
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TransitionBackdropPainter(
                          auditionProgress: _auditionProgress,
                          isPlaying: isPlaying,
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Column(
                        children: [
                          // TOP WAVEFORM (Outgoing Track / Deck A - Cyan)
                          SizedBox(
                            height: 76,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _DeckWaveformPainter(
                                bars: _topWaveBars,
                                isOutgoing: true,
                                config: _config,
                              ),
                            ),
                          ),

                          // CENTER FLOATING CONTROLS ROW (Play/Pause, Bars, Sync, Cue)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Play / Pause Audition Button
                                GestureDetector(
                                  onTap: _toggleAudition,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.45),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.3,
                                                color: Colors.black,
                                              ),
                                            )
                                          : Icon(
                                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                              color: Colors.black,
                                              size: 27,
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Bars Selector Pill
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () => _openBarsSelectorSheet(barStats),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${_config.bars} ',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '(${barStats.durationSec.toStringAsFixed(1)}s)',
                                          style: const TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Tempo Sync Pill
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    _updateConfig(_config.copyWith(syncTempo: !_config.syncTempo));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: _config.syncTempo
                                          ? const Color(0xFF22D3EE).withValues(alpha: 0.18)
                                          : Colors.white.withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _config.syncTempo
                                            ? const Color(0xFF22D3EE).withValues(alpha: 0.5)
                                            : Colors.white.withValues(alpha: 0.12),
                                      ),
                                    ),
                                    child: Text(
                                      'Sync',
                                      style: TextStyle(
                                        color: _config.syncTempo ? const Color(0xFF67E8F9) : Colors.white60,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Cue Fine-Tuner Toggle
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _showCueNudge = !_showCueNudge);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: _showCueNudge
                                          ? const Color(0xFFA855F7).withValues(alpha: 0.22)
                                          : Colors.white.withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _showCueNudge
                                            ? const Color(0xFFA855F7).withValues(alpha: 0.5)
                                            : Colors.white.withValues(alpha: 0.12),
                                      ),
                                    ),
                                    child: Text(
                                      'Cue',
                                      style: TextStyle(
                                        color: _showCueNudge ? const Color(0xFFD8B4FE) : Colors.white60,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Optional Cue Outro / Intro Fine-Tuner Bar
                          if (_showCueNudge)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildCueControlGroup(
                                    label: 'Outro',
                                    color: const Color(0xFF22D3EE),
                                    onMinus: () => _updateConfig(_config.copyWith(
                                      outroOffsetSec: (_config.outroOffsetSec - 1.0).clamp(-12.0, 10.0),
                                    )),
                                    onPlus: () => _updateConfig(_config.copyWith(
                                      outroOffsetSec: (_config.outroOffsetSec + 1.0).clamp(-12.0, 10.0),
                                    )),
                                  ),
                                  TextButton(
                                    onPressed: () => _updateConfig(_config.copyWith(
                                      outroOffsetSec: 0.0,
                                      introOffsetSec: 0.0,
                                    )),
                                    style: TextButton.styleFrom(
                                      minimumSize: Size.zero,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    ),
                                    child: const Text(
                                      'Reset Cue',
                                      style: TextStyle(color: Colors.white54, fontSize: 10.5),
                                    ),
                                  ),
                                  _buildCueControlGroup(
                                    label: 'Intro',
                                    color: const Color(0xFFA855F7),
                                    onMinus: () => _updateConfig(_config.copyWith(
                                      introOffsetSec: (_config.introOffsetSec - 1.0).clamp(0.0, 25.0),
                                    )),
                                    onPlus: () => _updateConfig(_config.copyWith(
                                      introOffsetSec: (_config.introOffsetSec + 1.0).clamp(0.0, 25.0),
                                    )),
                                  ),
                                ],
                              ),
                            ),

                          // BOTTOM WAVEFORM (Incoming Track / Deck B - Purple)
                          SizedBox(
                            height: 76,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _DeckWaveformPainter(
                                bars: _bottomWaveBars,
                                isOutgoing: false,
                                config: _config,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Bottom Telemetry Readout Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  env != null
                      ? 'Deck A: ${(env.outGain * 100).round()}%${env.outHighpassHz > 40 ? ' • HPF ${env.outHighpassHz.round()}Hz' : ''}'
                      : 'Deck A • ${_config.volumeMode.toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFF67E8F9),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isPlaying
                      ? (_auditionPhase == 'lead_in'
                          ? 'OUTRO LEAD-IN'
                          : _auditionPhase == 'transition'
                              ? 'MIXING (${(_mixProgress * 100).round()}%)'
                              : 'INTRO LEAD-OUT')
                      : 'GESER WAVEFORM UNTUK SCRUB PREVIEW',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  env != null
                      ? 'Deck B: ${(env.inGain * 100).round()}%${_config.syncTempo ? ' • ${env.inPlaybackRate.toStringAsFixed(2)}x' : ''}'
                      : 'Deck B • EQ ${_config.eqMode.toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFFD8B4FE),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCueControlGroup({
    required String label,
    required Color color,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 5),
        InkWell(
          onTap: onMinus,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('-1s', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: onPlus,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('+1s', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildDockButton({
    required String category,
    required String valueLabel,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(height: 24, child: Center(child: icon)),
            const SizedBox(height: 5),
            Text(
              valueLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeCurveMiniIcon(String mode) {
    return SizedBox(
      width: 42,
      height: 20,
      child: CustomPaint(
        painter: _MiniVolumeCurvePainter(mode: mode),
      ),
    );
  }

  void _openBarsSelectorSheet(BarDurationStats currentStats) {
    final metaA = TransitionEngine.computeTrackBpmAndKey(_outgoingTrack);
    final metaB = TransitionEngine.computeTrackBpmAndKey(_incomingTrack);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DURASI BAR TRANSISI (4/4 BEATGRID)',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                ...TransitionEngine.barOptions.map((b) {
                  final stats = TransitionEngine.computeBarDurationSec(metaA.bpm, metaB.bpm, b);
                  final isSelected = _config.bars == b;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: isSelected ? const Color(0xFF1ED760).withValues(alpha: 0.14) : null,
                    title: Text(
                      b,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF1ED760) : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Text(
                      '${stats.beats} beat • ${stats.durationSec.toStringAsFixed(1)}s',
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF86EFAC) : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _updateConfig(_config.copyWith(bars: b));
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPresetSheet({
    required String title,
    required List<TransitionPresetOption> options,
    required String selectedId,
    required Color accentColor,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 12),
                ...options.map((item) {
                  final isSelected = item.id == selectedId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? accentColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: ListTile(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(ctx);
                        onSelect(item.id);
                      },
                      title: Row(
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              color: isSelected ? accentColor : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.badge,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          item.desc,
                          style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded, color: accentColor, size: 20)
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSongPickerSheet({required bool isOutgoing}) async {
    final chosen = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12121A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _TransitionSongPickerSheet(
        player: widget.player,
        apiService: _apiService,
        isOutgoing: isOutgoing,
        currentTrack: isOutgoing ? _outgoingTrack : _incomingTrack,
        fallbackCatalog: _fallbackCatalog,
      ),
    );

    if (chosen != null && mounted) {
      await _auditionMixer.stop(silent: true);
      setState(() {
        if (isOutgoing) {
          _outgoingTrack = chosen;
        } else {
          _incomingTrack = chosen;
        }
        _auditionProgress = 0.0;
        _mixProgress = 0.0;
        _auditionPhase = 'idle';
        _liveEnvelope = null;
        _rebuildWaveformsAndSmartPreset();
      });
      await _loadPairConfiguration();
      _showStatus(
        isOutgoing
            ? 'Lagu 1 (Keluar) diganti ke "${chosen.title}"'
            : 'Lagu 2 (Masuk) diganti ke "${chosen.title}"',
      );
    }
  }
}

/// Song Picker Sheet inside SpotifyTransitionModal supporting Queue, Liked Songs, and Live Search.
class _TransitionSongPickerSheet extends StatefulWidget {
  final AudioPlayerManager player;
  final MusicApiService apiService;
  final bool isOutgoing;
  final Track currentTrack;
  final List<Track> fallbackCatalog;

  const _TransitionSongPickerSheet({
    required this.player,
    required this.apiService,
    required this.isOutgoing,
    required this.currentTrack,
    required this.fallbackCatalog,
  });

  @override
  State<_TransitionSongPickerSheet> createState() => _TransitionSongPickerSheetState();
}

class _TransitionSongPickerSheetState extends State<_TransitionSongPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _activeTab = 'queue'; // 'queue', 'liked', 'popular'
  List<Track> _likedTracks = [];
  List<Track> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadLiked();
  }

  Future<void> _loadLiked() async {
    final liked = await widget.player.storageService.getLikedTracks();
    if (mounted) setState(() => _likedTracks = liked);
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final res = await widget.apiService.searchTracks(q.trim());
        if (mounted) {
          setState(() {
            _searchResults = res;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().length >= 2;
    List<Track> list;
    if (hasQuery) {
      list = _searchResults;
    } else if (_activeTab == 'queue') {
      list = widget.player.queue.isNotEmpty ? widget.player.queue : widget.fallbackCatalog;
    } else if (_activeTab == 'liked') {
      list = _likedTracks.isNotEmpty ? _likedTracks : widget.fallbackCatalog;
    } else {
      list = widget.fallbackCatalog;
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isOutgoing
                      ? 'Pilih Lagu 1 (Deck A - Keluar)'
                      : 'Pilih Lagu 2 (Deck B - Masuk)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Cari judul lagu atau penyanyi...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (!hasQuery)
              Row(
                children: [
                  _buildTabChip('queue', 'Antrean (${widget.player.queue.length})'),
                  const SizedBox(width: 8),
                  _buildTabChip('liked', 'Disukai (${_likedTracks.length})'),
                  const SizedBox(width: 8),
                  _buildTabChip('popular', 'Rekomendasi'),
                ],
              ),
            const SizedBox(height: 10),
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF22D3EE)),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final item = list[i];
                        final meta = TransitionEngine.computeTrackBpmAndKey(item);
                        final isCurrent = item.id == widget.currentTrack.id;
                        return ListTile(
                          onTap: () => Navigator.pop(context, item),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          leading: OptimizedImage(
                            imageUrl: item.artwork,
                            width: 42,
                            height: 42,
                            borderRadius: BorderRadius.circular(8),
                            memCacheWidth: 100,
                            memCacheHeight: 100,
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? const Color(0xFF1ED760) : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          subtitle: Text(
                            item.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${meta.bpm} bpm',
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  meta.camelot,
                                  style: const TextStyle(
                                    color: Color(0xFF67E8F9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String id, String label) {
    final active = _activeTab == id;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _activeTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Draws the central Transition Zone highlight and the live audition vertical playhead line.
class _TransitionBackdropPainter extends CustomPainter {
  final double auditionProgress;
  final bool isPlaying;

  const _TransitionBackdropPainter({
    required this.auditionProgress,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final leftZone = size.width * 0.25;
    final rightZone = size.width * 0.75;

    final zoneRect = Rect.fromLTRB(leftZone, 0, rightZone, size.height);
    final zonePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF22D3EE).withValues(alpha: 0.07),
          Colors.transparent,
          const Color(0xFFA855F7).withValues(alpha: 0.07),
        ],
      ).createShader(zoneRect);
    canvas.drawRect(zoneRect, zonePaint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(leftZone, 0), Offset(leftZone, size.height), borderPaint);
    canvas.drawLine(Offset(rightZone, 0), Offset(rightZone, size.height), borderPaint);

    if (isPlaying || auditionProgress > 0.005) {
      final x = (auditionProgress.clamp(0.0, 1.0)) * size.width;
      final headPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), headPaint);
      canvas.drawCircle(Offset(x, 6), 4.0, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TransitionBackdropPainter oldDelegate) {
    return oldDelegate.auditionProgress != auditionProgress ||
        oldDelegate.isPlaying != isPlaying;
  }
}

/// Draws the 60 musical waveform bars and the dynamic volume/filter envelope curve for Deck A or Deck B.
class _DeckWaveformPainter extends CustomPainter {
  final List<double> bars;
  final bool isOutgoing;
  final TransitionConfig config;

  const _DeckWaveformPainter({
    required this.bars,
    required this.isOutgoing,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final accentColor = isOutgoing ? const Color(0xFF22D3EE) : const Color(0xFFA855F7);
    final greyColor = const Color(0xFF6B7280).withValues(alpha: 0.42);
    final mutedColor = const Color(0xFF2A2A35).withValues(alpha: 0.30);

    // 1. Draw 60 vertical bars
    final count = bars.length;
    final step = size.width / count;
    final barWidth = (step * 0.56).clamp(2.0, 5.0);

    for (int i = 0; i < count; i++) {
      final normX = i / count;
      final inZone = normX >= 0.25 && normX <= 0.75;
      final isMutedTail = isOutgoing ? (normX > 0.75) : (normX < 0.25);

      Color barColor;
      if (inZone) {
        barColor = accentColor;
      } else if (isMutedTail) {
        barColor = mutedColor;
      } else {
        barColor = greyColor;
      }

      final barH = (bars[i] * size.height * 0.86).clamp(6.0, size.height * 0.92);
      final cx = i * step + step * 0.5;
      final top = (size.height - barH) * 0.5;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barWidth * 0.5, top, barWidth, barH),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(rrect, Paint()..color = barColor);
    }

    // 2. Draw Dynamic Volume/Filter Envelope Curve across the overlap zone (25%..75%)
    const int samples = 36;
    final startX = size.width * 0.25;
    final endX = size.width * 0.75;
    final zoneW = endX - startX;

    final linePath = Path();
    final fillPath = Path();

    for (int i = 0; i <= samples; i++) {
      final p = i / samples;
      final env = TransitionEngine.evaluateTransitionEnvelope(p, config);
      final gain = isOutgoing ? env.outGain : env.inGain;
      final x = startX + p * zoneW;
      final y = (size.height - 6.0) - (gain * (size.height - 14.0));

      if (i == 0) {
        if (isOutgoing) {
          linePath.moveTo(0, 8.0);
          linePath.lineTo(startX, 8.0);
          linePath.lineTo(x, y);

          fillPath.moveTo(startX, size.height);
          fillPath.lineTo(startX, 8.0);
          fillPath.lineTo(x, y);
        } else {
          linePath.moveTo(x, y);
          fillPath.moveTo(startX, size.height);
          fillPath.lineTo(x, y);
        }
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    if (isOutgoing) {
      fillPath.lineTo(endX, size.height);
      fillPath.close();
    } else {
      linePath.lineTo(size.width, 8.0);
      fillPath.lineTo(endX, size.height);
      fillPath.close();
    }

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: 0.30),
          accentColor.withValues(alpha: 0.03),
        ],
      ).createShader(Rect.fromLTWH(startX, 0, zoneW, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = config.volumeMode == 'mashup' ? const Color(0xFF22D3EE) : accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, strokePaint);

    // 3. Yellow/Gold Bass Swap Step Automation Line (Spotify Mix reference)
    if (config.volumeMode == 'mashup' || config.eqMode == 'bass_swap') {
      final bassPath = Path();
      for (int i = 0; i <= samples; i++) {
        final p = i / samples;
        final env = TransitionEngine.evaluateTransitionEnvelope(p, config);
        final db = isOutgoing ? env.outLowDb : env.inLowDb;
        final norm = ((db + 20.0) / 20.0).clamp(0.0, 1.0);
        final x = startX + p * zoneW;
        final y = size.height * 0.90 - norm * (size.height * 0.44);
        if (i == 0) {
          bassPath.moveTo(x, y);
        } else {
          bassPath.lineTo(x, y);
        }
      }
      canvas.drawPath(
        bassPath,
        Paint()
          ..color = const Color(0xFFFACC15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 4. Pink/Magenta Filter S-Curve Sweep Line on Outgoing Deck (Spotify Mix reference)
    if (isOutgoing && config.effectsMode != 'none') {
      final filterPath = Path();
      for (int i = 0; i <= samples; i++) {
        final p = i / samples;
        final env = TransitionEngine.evaluateTransitionEnvelope(p, config);
        double filterNorm = 0.0;
        if (env.outHighpassHz > 30.0) {
          filterNorm = ((env.outHighpassHz - 20.0) / 2000.0).clamp(0.0, 1.0);
        } else if (env.outLowpassHz < 16000.0) {
          filterNorm = ((18000.0 - env.outLowpassHz) / 17600.0).clamp(0.0, 1.0);
        }
        final x = startX + p * zoneW;
        final y = size.height * 0.52 - filterNorm * (size.height * 0.36);
        if (i == 0) {
          filterPath.moveTo(x, y);
        } else {
          filterPath.lineTo(x, y);
        }
      }
      canvas.drawPath(
        filterPath,
        Paint()
          ..color = const Color(0xFFF472B6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeckWaveformPainter oldDelegate) {
    return oldDelegate.config.volumeMode != config.volumeMode ||
        oldDelegate.config.eqMode != config.eqMode ||
        oldDelegate.config.effectsMode != config.effectsMode ||
        oldDelegate.bars != bars;
  }
}

class _MiniVolumeCurvePainter extends CustomPainter {
  final String mode;

  const _MiniVolumeCurvePainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final cyanPaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final purplePaint = Paint()
      ..color = const Color(0xFFA855F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final outPath = Path();
    final inPath = Path();
    final cfg = TransitionConfig(volumeMode: mode);

    const steps = 16;
    for (int i = 0; i <= steps; i++) {
      final p = i / steps;
      final env = TransitionEngine.evaluateTransitionEnvelope(p, cfg);
      final x = p * size.width;
      final yOut = size.height - env.outGain * (size.height - 3) - 1.5;
      final yIn = size.height - env.inGain * (size.height - 3) - 1.5;
      if (i == 0) {
        outPath.moveTo(x, yOut);
        inPath.moveTo(x, yIn);
      } else {
        outPath.lineTo(x, yOut);
        inPath.lineTo(x, yIn);
      }
    }

    canvas.drawPath(outPath, cyanPaint);
    canvas.drawPath(inPath, purplePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniVolumeCurvePainter oldDelegate) =>
      oldDelegate.mode != mode;
}
