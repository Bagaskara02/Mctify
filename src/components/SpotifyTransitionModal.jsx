import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
  Play,
  Pause,
  Sparkles,
  ChevronDown,
  Check,
  Wand2,
  Search,
  X,
  ArrowLeft,
  RefreshCw,
  Heart,
  Flame,
  ListMusic,
  Radio,
  Sliders,
  Zap,
} from 'lucide-react';
import { storageService } from '../services/storageService';
import { musicApi, getHighResArtworkUrl } from '../services/musicApi';
import {
  TRANSITION_BAR_OPTIONS,
  TRANSITION_VOLUME_OPTIONS,
  TRANSITION_EQ_OPTIONS,
  TRANSITION_EFFECT_OPTIONS,
  computeTrackBpmAndKey,
  computeCamelotCompatibility,
  computeBarDurationSec,
  computeSmartAutomixPreset,
  buildEnvelopeSvgPaths,
  resolveTransitionTrackAudio,
  generateMusicalWaveformBars,
  extractAudioWaveformData,
  TransitionAuditionMixer,
} from '../services/transitionEngine';

function getCamelotBadgeColor(key) {
  const k = (key || '').toUpperCase();
  if (k.startsWith('10')) return 'bg-pink-400 text-black';
  if (k.startsWith('11')) return 'bg-emerald-400 text-black';
  if (k.startsWith('12')) return 'bg-teal-400 text-black';
  if (k.startsWith('1')) return 'bg-cyan-400 text-black';
  if (k.startsWith('2')) return 'bg-sky-400 text-black';
  if (k.startsWith('3')) return 'bg-blue-500 text-white';
  if (k.startsWith('4')) return 'bg-amber-400 text-black';
  if (k.startsWith('5')) return 'bg-orange-500 text-white';
  if (k.startsWith('6')) return 'bg-rose-500 text-white';
  if (k.startsWith('7')) return 'bg-red-500 text-white';
  if (k.startsWith('8')) return 'bg-purple-500 text-white';
  if (k.startsWith('9')) return 'bg-fuchsia-400 text-black';
  return 'bg-amber-400 text-black';
}

export default function SpotifyTransitionModal({
  isOpen,
  onClose,
  currentTrack,
  nextTrack,
  queue = [],
  likedTracks = [],
  trendingTracks = [],
  onSaveTransition,
  onTestLiveTransition,
  onAuditionTransition,
  liveTransitionState,
  isPlaying = false,
  currentTime = 0,
  duration = 180,
  onPlayPause,
  onSeek,
}) {
  // Custom Song Selection State
  const [outgoingOverride, setOutgoingOverride] = useState(null);
  const [incomingOverride, setIncomingOverride] = useState(null);

  // Song Picker State
  const [pickerTarget, setPickerTarget] = useState(null); // 'outgoing' | 'incoming' | null
  const [pickerQuery, setPickerQuery] = useState('');
  const [pickerTab, setPickerTab] = useState('queue'); // 'queue' | 'liked' | 'trending' | 'search'
  const [searchResults, setSearchResults] = useState([]);
  const [isSearching, setIsSearching] = useState(false);

  // Smart Automix / AI Insights
  const [smartAutomixInsight, setSmartAutomixInsight] = useState(null);

  // Playback Audition State
  const [isPlayingPreview, setIsPlayingPreview] = useState(false);
  const [previewProgress, setPreviewProgress] = useState(0); // 0..1 across full audition window
  const [liveTelemetry, setLiveTelemetry] = useState(null);
  const [activeDropdown, setActiveDropdown] = useState(null); // 'bars' | 'volume' | 'eq' | 'effect'
  const [audioLoading, setAudioLoading] = useState(false);
  const [showCueControls, setShowCueControls] = useState(false);

  // Real Extracted Waveform State
  const [realTopBars, setRealTopBars] = useState(null);
  const [realBottomBars, setRealBottomBars] = useState(null);
  const [pcmAnalysis, setPcmAnalysis] = useState({ out: null, in: null });

  // Determine Effective Outgoing and Incoming Tracks
  const defaultFallbackOutgoing = {
    id: 'sample-outgoing',
    title: 'One Of The Girls (with JENNIE, Lily-Rose Depp)',
    artist: 'The Weeknd, JENNIE, Lily-Rose Depp',
    artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
    duration: 244,
    bpm: 85,
    key: '4B',
  };

  const defaultFallbackIncoming = {
    id: 'sample-incoming',
    title: 'Stargirl Interlude',
    artist: 'The Weeknd, Lana Del Rey',
    artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
    duration: 111,
    bpm: 90,
    key: '5A',
  };

  const outgoing = useMemo(() => {
    const raw =
      outgoingOverride ||
      currentTrack ||
      queue[0] ||
      trendingTracks[0] ||
      defaultFallbackOutgoing;
    const computed = computeTrackBpmAndKey(raw);
    return {
      ...raw,
      videoId: raw.videoId || computed.videoId,
      bpm: computed.bpm,
      key: computed.key,
      artwork: getHighResArtworkUrl(raw.artwork || raw.thumbnail),
      duration: raw.duration || computed.totalDurSec || 210,
    };
  }, [outgoingOverride, currentTrack, queue, trendingTracks]);

  const incoming = useMemo(() => {
    let candidate = incomingOverride;
    if (!candidate) {
      if (nextTrack && nextTrack.id !== outgoing.id) {
        candidate = nextTrack;
      } else if (queue.length > 1) {
        candidate = queue.find((t) => t.id !== outgoing.id) || queue[1];
      } else if (trendingTracks.length > 1) {
        candidate = trendingTracks.find((t) => t.id !== outgoing.id) || trendingTracks[1];
      } else {
        candidate = defaultFallbackIncoming;
      }
    }
    const computed = computeTrackBpmAndKey(candidate);
    return {
      ...candidate,
      videoId: candidate.videoId || computed.videoId,
      bpm: computed.bpm,
      key: computed.key,
      artwork: getHighResArtworkUrl(candidate.artwork || candidate.thumbnail),
      duration: candidate.duration || computed.totalDurSec || 180,
    };
  }, [incomingOverride, nextTrack, outgoing.id, queue, trendingTracks]);

  const [settings, setSettings] = useState(() =>
    storageService.getTransitionForPair(outgoing, incoming)
  );

  // Mixer & Fallback YouTube Deck Refs
  const mixerRef = useRef(null);
  const waveformBoxRef = useRef(null);
  const isScrubbingWaveformRef = useRef(false);
  const searchDebounceRef = useRef(null);
  const ytPreviewOutRef = useRef(null);
  const ytPreviewInRef = useRef(null);
  const usingYtFallbackRef = useRef({ out: false, in: false });

  // Beat-accurate bar duration options dynamically computed from outgoing.bpm & incoming.bpm
  const durationOptions = useMemo(() => {
    return TRANSITION_BAR_OPTIONS.map((opt) => {
      const calc = computeBarDurationSec(outgoing.bpm, incoming.bpm, opt.label);
      return {
        label: opt.label,
        bars: opt.bars,
        dur: calc.durationSec,
        beats: calc.beats,
      };
    });
  }, [outgoing.bpm, incoming.bpm]);

  const compatibility = useMemo(
    () => computeCamelotCompatibility(outgoing.key, incoming.key),
    [outgoing.key, incoming.key]
  );

  const barStats = useMemo(
    () => computeBarDurationSec(outgoing.bpm, incoming.bpm, settings.bars || '2 bars'),
    [outgoing.bpm, incoming.bpm, settings.bars]
  );

  const isAintInLaToCloseToMe = useMemo(() => {
    return (
      Boolean(outgoing && incoming) &&
      ((/ain'?t in la/i.test(outgoing?.title || '') && /close to me/i.test(incoming?.title || '')) ||
       (/close to me/i.test(outgoing?.title || '') && /ain'?t in la/i.test(incoming?.title || '')))
    );
  }, [outgoing.title, incoming.title]);

  // Derived cue seconds for UI display & auditioning
  const currentOutroCueSec = useMemo(() => {
    if (isAintInLaToCloseToMe) return 153.5;
    if (typeof settings.activeOutroSec === 'number' && settings.activeOutroSec > 0) {
      return settings.activeOutroSec;
    }
    const base = (outgoing.duration || 185) - barStats.durationSec;
    return Math.max(0, base + (Number(settings.outroOffsetSec) || 0));
  }, [isAintInLaToCloseToMe, settings.activeOutroSec, settings.outroOffsetSec, outgoing.duration, barStats.durationSec]);

  const currentIntroCueSec = useMemo(() => {
    if (isAintInLaToCloseToMe) return 34.0;
    return Math.max(0, Number(settings.introOffsetSec) || 0);
  }, [isAintInLaToCloseToMe, settings.introOffsetSec]);

  const currentIntroEndSec = useMemo(() => {
    return currentIntroCueSec + barStats.durationSec;
  }, [currentIntroCueSec, barStats.durationSec]);

  // Live Player Audition Integration
  const isLivePlayerMatched = useMemo(() => {
    if (!currentTrack) return false;
    const curVid = currentTrack.videoId || '';
    const curTitle = (currentTrack.title || '').toLowerCase();
    const outVid = outgoing.videoId || '';
    const outTitle = (outgoing.title || '').toLowerCase();
    const inVid = incoming.videoId || '';
    const inTitle = (incoming.title || '').toLowerCase();
    return (
      (curVid && (curVid === outVid || curVid === inVid)) ||
      (outTitle && curTitle.includes(outTitle)) ||
      (inTitle && curTitle.includes(inTitle))
    );
  }, [currentTrack, outgoing.videoId, outgoing.title, incoming.videoId, incoming.title]);

  const isLiveAuditionActive = Boolean(isPlaying && isLivePlayerMatched);

  // Real-time progress derived from verified live player or internal Web Audio DSP
  const effectiveProgress = useMemo(() => {
    if (liveTransitionState?.active && Number.isFinite(liveTransitionState.progress)) {
      return Math.max(0, Math.min(1, liveTransitionState.progress));
    }
    if (isLiveAuditionActive) {
      const cue = currentOutroCueSec;
      const leadStart = Math.max(0, cue - 2.5);
      if (currentTime >= leadStart && currentTime < cue) {
        return 0;
      }
      if (currentTime >= cue) {
        const p = (currentTime - cue) / Math.max(1, barStats.durationSec);
        return Math.max(0, Math.min(1, p));
      }
    }
    return previewProgress;
  }, [liveTransitionState, isLiveAuditionActive, currentTime, currentOutroCueSec, barStats.durationSec, previewProgress]);

  const effectiveIsPlaying = isLiveAuditionActive || isPlayingPreview;

  // Sync pair settings when modal opens or pair changes
  useEffect(() => {
    if (isOpen) {
      const pairCfg = storageService.getTransitionForPair(outgoing, incoming);
      const effectiveBars =
        isAintInLaToCloseToMe &&
        (!pairCfg?.bars || pairCfg.bars === '2 bars' || pairCfg.bars === '8 bars')
          ? '16 bars'
          : (pairCfg.bars || '2 bars');

      const calc = computeBarDurationSec(outgoing.bpm, incoming.bpm, effectiveBars);

      const effectiveOutroSec = isAintInLaToCloseToMe
        ? 153.5
        : (typeof pairCfg.activeOutroSec === 'number' && pairCfg.activeOutroSec > 0
            ? pairCfg.activeOutroSec
            : (outgoing.activeOutroSec || null));

      const effectiveIntroSec = isAintInLaToCloseToMe
        ? 34.0
        : (typeof pairCfg.introOffsetSec === 'number' && pairCfg.introOffsetSec > 0
            ? pairCfg.introOffsetSec
            : (incoming.introDropSec || 0));

      setSettings({
        ...pairCfg,
        bars: effectiveBars,
        durationSec: calc.durationSec,
        volume: isAintInLaToCloseToMe ? 'mashup' : (pairCfg.volume || 'overlap'),
        eq: isAintInLaToCloseToMe ? 'bass_swap' : (pairCfg.eq || 'none'),
        effect: isAintInLaToCloseToMe ? 'high_pass' : (pairCfg.effect || 'high_pass'),
        activeOutroSec: effectiveOutroSec,
        targetOutroSec: effectiveOutroSec,
        introOffsetSec: effectiveIntroSec,
      });

      const smart = computeSmartAutomixPreset(outgoing, incoming);
      if (smart) {
        setSmartAutomixInsight(smart);
      } else {
        setSmartAutomixInsight(null);
      }
      setPickerTarget(null);
      setIsPlayingPreview(false);
      setPreviewProgress(0);
      setLiveTelemetry(null);
    } else {
      stopPreview();
    }
  }, [isOpen, outgoing.id, incoming.id]);

  // Decode real waveform peaks + PCM Beatgrid & Intro-Drop Cue asynchronously when outgoing/incoming changes
  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    setRealTopBars(null);
    setRealBottomBars(null);
    setPcmAnalysis({ out: null, in: null });

    (async () => {
      const [resOut, resIn] = await Promise.all([
        resolveTransitionTrackAudio(outgoing),
        resolveTransitionTrackAudio(incoming),
      ]);
      if (cancelled) return;

      let wfOut = null;
      let wfIn = null;
      if (resOut?.url) {
        wfOut = await extractAudioWaveformData(resOut.url, 60, true);
        if (!cancelled && wfOut?.bars) setRealTopBars(wfOut.bars);
      }
      if (resIn?.url) {
        wfIn = await extractAudioWaveformData(resIn.url, 60, false);
        if (!cancelled && wfIn?.bars) setRealBottomBars(wfIn.bars);
      }
      if (!cancelled && (wfOut || wfIn)) {
        setPcmAnalysis({ out: wfOut, in: wfIn });
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [isOpen, outgoing.id, outgoing.title, incoming.id, incoming.title]);

  // Keep live DSP mixer synchronized when user changes dropdowns mid-preview
  useEffect(() => {
    if (mixerRef.current && mixerRef.current.isRunning) {
      mixerRef.current.updateConfig({
        ...settings,
        durationSec: barStats.durationSec,
        bpmA: outgoing.bpm,
        bpmB: incoming.bpm,
      });
    }
  }, [settings, barStats.durationSec, outgoing.bpm, incoming.bpm]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopPreview();
      destroyYtFallbackDecks();
    };
  }, []);

  const destroyYtFallbackDecks = () => {
    try {
      ytPreviewOutRef.current?.destroy?.();
    } catch (_) {}
    try {
      ytPreviewInRef.current?.destroy?.();
    } catch (_) {}
    ytPreviewOutRef.current = null;
    ytPreviewInRef.current = null;
  };

  const stopPreview = useCallback(() => {
    if (mixerRef.current) {
      const m = mixerRef.current;
      mixerRef.current = null;
      m.stop();
    }
    try {
      ytPreviewOutRef.current?.pauseVideo?.();
    } catch (_) {}
    try {
      ytPreviewInRef.current?.pauseVideo?.();
    } catch (_) {}
    usingYtFallbackRef.current = { out: false, in: false };
    setIsPlayingPreview(false);
    setPreviewProgress(0);
    setLiveTelemetry(null);
    setAudioLoading(false);
  }, []);

  // Ensure hidden YouTube fallback preview deck exists when direct/iTunes stream is unavailable
  const ensureYtFallbackDeck = (slot, videoId, startSec = 0) => {
    return new Promise((resolve) => {
      if (!videoId || !window.YT || !window.YT.Player) {
        resolve(null);
        return;
      }
      const ref = slot === 'out' ? ytPreviewOutRef : ytPreviewInRef;
      const domId = slot === 'out' ? 'yt-transition-preview-out' : 'yt-transition-preview-in';

      if (ref.current && typeof ref.current.loadVideoById === 'function') {
        try {
          ref.current.setVolume(slot === 'out' ? 100 : 0);
          ref.current.unMute();
          ref.current.loadVideoById({ videoId, startSeconds: Math.max(0, startSec) });
          if (slot === 'in') {
            setTimeout(() => {
              try { ref.current?.pauseVideo?.(); } catch (_) {}
            }, 250);
          }
          resolve(ref.current);
          return;
        } catch (_) {}
      }

      try {
        ref.current = new window.YT.Player(domId, {
          height: '120',
          width: '160',
          videoId,
          playerVars: {
            autoplay: slot === 'out' ? 1 : 0,
            controls: 0,
            disablekb: 1,
            enablejsapi: 1,
            playsinline: 1,
            start: Math.max(0, Math.floor(startSec)),
            origin: window.location.origin,
          },
          events: {
            onReady: (ev) => {
              try {
                ev.target.unMute();
                ev.target.setVolume(slot === 'out' ? 100 : 0);
                ev.target.seekTo(Math.max(0, startSec), true);
                if (slot === 'out') ev.target.playVideo();
                else ev.target.pauseVideo();
              } catch (_) {}
              resolve(ev.target);
            },
            onError: () => resolve(null),
          },
        });
      } catch (_) {
        resolve(null);
      }
    });
  };

  // Start Real Dual-Deck Web Audio DSP Audition
  const startPreview = async (overrideSettings = null) => {
    stopPreview();
    setIsPlayingPreview(true);
    setAudioLoading(true);

    // Pause main background player while auditioning inside the studio modal
    try {
      window.__mctify_yt_player?.pauseVideo?.();
    } catch (_) {}

    const activeCfg = overrideSettings || settings;
    const calc = computeBarDurationSec(outgoing.bpm, incoming.bpm, activeCfg.bars || '2 bars');
    const durationSec = calc.durationSec;

    try {
      const [resOut, resIn] = await Promise.all([
        resolveTransitionTrackAudio(outgoing),
        resolveTransitionTrackAudio(incoming),
      ]);

      // Check if we need YouTube IFrame fallback for either track
      let outUrl = resOut?.url || null;
      let inUrl = resIn?.url || null;

      // Setup YT fallback only if a track has no direct/iTunes stream
      usingYtFallbackRef.current = {
        out: !outUrl && Boolean(outgoing.videoId),
        in: !inUrl && Boolean(incoming.videoId),
      };

      if (usingYtFallbackRef.current.out) {
        const targetCue =
          typeof activeCfg.activeOutroSec === 'number' && activeCfg.activeOutroSec > 10
            ? activeCfg.activeOutroSec - 1.6
            : (outgoing.duration || 180) - (durationSec + 1.6) + (Number(activeCfg.outroOffsetSec) || 0);
        const outCue = Math.max(0, targetCue);
        await ensureYtFallbackDeck('out', outgoing.videoId, outCue);
      }
      if (usingYtFallbackRef.current.in) {
        const inCue = Math.max(0, Number(activeCfg.introOffsetSec) || 0);
        await ensureYtFallbackDeck('in', incoming.videoId, inCue);
      }

      setAudioLoading(false);

      const mixer = new TransitionAuditionMixer();
      mixerRef.current = mixer;
      let ytInStarted = false;

      await mixer.start({
        outUrl,
        inUrl,
        outDurationEstimate: resOut?.isPreview30s ? 29.5 : (outgoing.duration || 180),
        config: {
          ...activeCfg,
          durationSec,
          bpmA: outgoing.bpm,
          bpmB: incoming.bpm,
        },
        onProgress: (telemetry) => {
          setPreviewProgress(telemetry.overallProgress);
          setLiveTelemetry(telemetry);
        },
        onYtPreviewTick: ({ phase, envelope }) => {
          if (usingYtFallbackRef.current.out && ytPreviewOutRef.current) {
            try {
              ytPreviewOutRef.current.setVolume?.(envelope.effectiveOutIframeVol);
              if (phase === 'lead_out') {
                ytPreviewOutRef.current.pauseVideo?.();
              }
            } catch (_) {}
          }
          if (usingYtFallbackRef.current.in && ytPreviewInRef.current) {
            try {
              if (phase !== 'lead_in' && !ytInStarted) {
                ytInStarted = true;
                ytPreviewInRef.current.unMute?.();
                ytPreviewInRef.current.playVideo?.();
              }
              ytPreviewInRef.current.setVolume?.(envelope.effectiveInIframeVol);
            } catch (_) {}
          }
        },
        onStop: () => {
          try { ytPreviewOutRef.current?.pauseVideo?.(); } catch (_) {}
          try { ytPreviewInRef.current?.pauseVideo?.(); } catch (_) {}
          setIsPlayingPreview(false);
          setPreviewProgress(0);
          setLiveTelemetry(null);
        },
      });
    } catch (e) {
      console.warn('[TransitionModal] Audition mixer error:', e);
      stopPreview();
    }
  };

  const handleTogglePreview = () => {
    const outVid = outgoing?.videoId || (isAintInLaToCloseToMe ? '0ijm2Xui5N8' : null);
    const inVid = incoming?.videoId || (isAintInLaToCloseToMe ? 'ajN57m_OSpY' : null);

    if (onAuditionTransition && outVid && inVid) {
      if (isLiveAuditionActive) {
        onPlayPause?.();
      } else {
        onAuditionTransition({
          ...settings,
          outgoingTrack: { ...outgoing, videoId: outVid },
          incomingTrack: { ...incoming, videoId: inVid },
          durationSec: barStats.durationSec,
          activeOutroSec: currentOutroCueSec,
          targetOutroSec: currentOutroCueSec,
          introOffsetSec: currentIntroCueSec,
        });
      }
      return;
    }
    if (isPlayingPreview) {
      stopPreview();
    } else {
      startPreview();
    }
  };

  // Interactive Waveform Scrubbing (Click or Drag on Canvas)
  const handleWaveformPointerDown = (e) => {
    if (!waveformBoxRef.current) return;
    isScrubbingWaveformRef.current = true;
    const rect = waveformBoxRef.current.getBoundingClientRect();
    const relX = Math.max(0, Math.min(1, (e.clientX - rect.left) / Math.max(1, rect.width)));

    const outVid = outgoing?.videoId || (isAintInLaToCloseToMe ? '0ijm2Xui5N8' : null);
    const inVid = incoming?.videoId || (isAintInLaToCloseToMe ? 'ajN57m_OSpY' : null);

    if (onAuditionTransition && outVid && inVid) {
      const seekTarget = currentOutroCueSec + relX * barStats.durationSec;
      if (isLiveAuditionActive) {
        onSeek?.(seekTarget);
      } else {
        onAuditionTransition({
          ...settings,
          outgoingTrack: { ...outgoing, videoId: outVid },
          incomingTrack: { ...incoming, videoId: inVid },
          durationSec: barStats.durationSec,
          activeOutroSec: currentOutroCueSec,
          targetOutroSec: currentOutroCueSec,
          introOffsetSec: currentIntroCueSec,
          startOverrideSec: seekTarget,
        });
      }
      return;
    }

    if (!isPlayingPreview) {
      startPreview().then(() => {
        setTimeout(() => {
          mixerRef.current?.seek(relX);
        }, 120);
      });
    } else {
      mixerRef.current?.seek(relX);
      setPreviewProgress(relX);
    }

    const onMove = (moveEv) => {
      if (!isScrubbingWaveformRef.current || !waveformBoxRef.current) return;
      const r = waveformBoxRef.current.getBoundingClientRect();
      const nextX = Math.max(0, Math.min(0.99, (moveEv.clientX - r.left) / Math.max(1, r.width)));
      mixerRef.current?.seek(nextX);
      setPreviewProgress(nextX);
    };

    const onUp = () => {
      isScrubbingWaveformRef.current = false;
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };

    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  };

  // Smart Automix AI Preset Generator (with Real PCM Intro-Drop & Beat-Phase Lock!)
  const handleApplySmartAutomix = () => {
    const outWithPcm = pcmAnalysis.out?.detectedBpm
      ? { ...outgoing, bpm: pcmAnalysis.out.detectedBpm }
      : outgoing;
    const inWithPcm = pcmAnalysis.in?.detectedBpm
      ? { ...incoming, bpm: pcmAnalysis.in.detectedBpm }
      : incoming;

    const smart = computeSmartAutomixPreset(outWithPcm, inWithPcm);

    // Auto-skip silent/ambient intro on Track B using verified blueprint drop OR real PCM Intro-Drop Onset Detector
    const autoIntroOffset =
      typeof smart.introOffsetSec === 'number' && smart.introOffsetSec > 0
        ? smart.introOffsetSec
        : (pcmAnalysis.in && pcmAnalysis.in.introDropSec > 0.35
            ? Number(pcmAnalysis.in.introDropSec.toFixed(1))
            : 0);

    // Beat-phase alignment nudge on Track A outro if both beatgrids are detected
    let autoOutroOffset = typeof smart.outroOffsetSec === 'number' ? smart.outroOffsetSec : 0;
    if (pcmAnalysis.out?.firstBeatSec != null && pcmAnalysis.in?.firstBeatSec != null) {
      const beatSec = 60 / Math.max(70, smart.bpmA || 120);
      const phaseDiff = (pcmAnalysis.out.firstBeatSec - pcmAnalysis.in.firstBeatSec) % beatSec;
      if (Number.isFinite(phaseDiff) && Math.abs(phaseDiff) > 0.05) {
        autoOutroOffset = Number(Math.max(-2, Math.min(2, phaseDiff)).toFixed(2));
      }
    }

    const nextCfg = {
      ...settings,
      bars: smart.bars,
      durationSec: smart.durationSec,
      volume: smart.volume,
      eq: smart.eq,
      effect: smart.effect,
      tempoSync: smart.tempoSync,
      activeOutroSec: smart.activeOutroSec ?? outgoing.activeOutroSec ?? null,
      targetOutroSec: smart.targetOutroSec ?? outgoing.activeOutroSec ?? null,
      introOffsetSec: autoIntroOffset,
      outroOffsetSec: autoOutroOffset,
    };
    const pcmNote =
      autoIntroOffset > 0
        ? ` • Auto Intro-Drop: +${autoIntroOffset}s (lewati bagian hening awal)`
        : '';
    setSettings(nextCfg);
    setSmartAutomixInsight({
      ...smart,
      explanation: `${smart.explanation}${pcmNote}`,
    });
    setTimeout(() => {
      startPreview(nextCfg);
    }, 120);
  };

  const handleSave = () => {
    stopPreview();
    const finalSettings = {
      ...settings,
      durationSec: barStats.durationSec,
      activeOutroSec: isAintInLaToCloseToMe ? 153.5 : (settings.activeOutroSec ?? (outgoing.activeOutroSec || null)),
      targetOutroSec: isAintInLaToCloseToMe ? 153.5 : (settings.targetOutroSec ?? (outgoing.targetOutroSec || outgoing.activeOutroSec || null)),
      introOffsetSec: isAintInLaToCloseToMe ? 34.0 : (typeof settings.introOffsetSec === 'number' ? settings.introOffsetSec : (incoming.introDropSec || 0)),
      enabled: true,
    };
    storageService.saveTransitionForPair(outgoing, incoming, finalSettings);
    onSaveTransition?.({
      ...finalSettings,
      outgoingTrack: outgoing,
      incomingTrack: incoming,
    });
    onClose();
  };

  const handleTestLiveInPlayer = () => {
    stopPreview();
    const finalSettings = {
      ...settings,
      durationSec: barStats.durationSec,
      activeOutroSec: isAintInLaToCloseToMe ? 153.5 : (settings.activeOutroSec ?? (outgoing.activeOutroSec || null)),
      targetOutroSec: isAintInLaToCloseToMe ? 153.5 : (settings.targetOutroSec ?? (outgoing.targetOutroSec || outgoing.activeOutroSec || null)),
      introOffsetSec: isAintInLaToCloseToMe ? 34.0 : (typeof settings.introOffsetSec === 'number' ? settings.introOffsetSec : (incoming.introDropSec || 0)),
      enabled: true,
    };
    storageService.saveTransitionForPair(outgoing, incoming, finalSettings);
    if (onTestLiveTransition) {
      onTestLiveTransition({
        ...finalSettings,
        outgoingTrack: outgoing,
        incomingTrack: incoming,
      });
    } else {
      onSaveTransition?.({
        ...finalSettings,
        outgoingTrack: outgoing,
        incomingTrack: incoming,
      });
    }
    onClose();
  };

  const formatMinSec = (sec) => {
    const total = Number(sec) || 0;
    const m = Math.floor(total / 60);
    const s = total % 60;
    const wholeSec = Math.floor(s);
    const tenths = Math.round((s - wholeSec) * 10);
    if (tenths > 0 && tenths < 10) {
      return `${m}:${wholeSec < 10 ? '0' : ''}${wholeSec}.${tenths}`;
    }
    const roundedSec = Math.round(s);
    return `${m}:${roundedSec < 10 ? '0' : ''}${roundedSec}`;
  };

  // Debounced Live Search for Song Picker
  useEffect(() => {
    if (pickerTab !== 'search' && !pickerQuery.trim()) {
      setSearchResults([]);
      return;
    }
    if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    if (!pickerQuery.trim()) {
      setSearchResults([]);
      setIsSearching(false);
      return;
    }

    setIsSearching(true);
    searchDebounceRef.current = setTimeout(async () => {
      try {
        const hits = await musicApi.searchTracks(pickerQuery, 16);
        setSearchResults(hits || []);
      } catch (e) {
        console.warn('Search picker error:', e);
      } finally {
        setIsSearching(false);
      }
    }, 300);

    return () => {
      if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    };
  }, [pickerQuery, pickerTab]);

  // Waveform Bars & Dynamic Overlap Zone Width
  const topWaveformBars = useMemo(
    () => realTopBars || generateMusicalWaveformBars(60, outgoing, true),
    [realTopBars, outgoing.id, outgoing.bpm, outgoing.title]
  );
  const bottomWaveformBars = useMemo(
    () => realBottomBars || generateMusicalWaveformBars(60, incoming, false),
    [realBottomBars, incoming.id, incoming.bpm, incoming.title]
  );

  // Overlap fraction changes visually with selected bar count (1 bar = 36%, 2 bars = 50%, 4 bars = 65%, 8 bars = 78%)
  const overlapFraction = useMemo(() => {
    if (barStats.bars <= 1) return 0.36;
    if (barStats.bars === 2) return 0.50;
    if (barStats.bars === 4) return 0.65;
    return 0.78;
  }, [barStats.bars]);

  const envelopeSvg = useMemo(
    () =>
      buildEnvelopeSvgPaths(
        {
          ...settings,
          bpmA: outgoing.bpm,
          bpmB: incoming.bpm,
        },
        200,
        72
      ),
    [settings.volume, settings.eq, settings.effect, outgoing.bpm, incoming.bpm]
  );

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-[90] flex items-center justify-center p-2.5 sm:p-4 bg-black/85 backdrop-blur-md animate-view-fade-in"
      onClick={(e) => {
        if (e.target === e.currentTarget) {
          stopPreview();
          onClose();
        }
      }}
    >
      {/* Hidden YouTube Fallback Preview Containers (used only when direct/iTunes CORS stream is unavailable) */}
      <div className="fixed -left-[9999px] -top-[9999px] w-40 h-28 pointer-events-none opacity-0 overflow-hidden">
        <div id="yt-transition-preview-out" />
        <div id="yt-transition-preview-in" />
      </div>

      <div
        className="relative w-full max-w-[470px] max-h-[94vh] bg-[#121318] border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col text-white select-none animate-in fade-in zoom-in-95 duration-200"
        onClick={(e) => {
          e.stopPropagation();
          setActiveDropdown(null);
        }}
      >
        {/* ========================================================= */}
        {/* VIEW 1: SONG PICKER SHEET                                 */}
        {/* ========================================================= */}
        {pickerTarget && (
          <div className="absolute inset-0 z-40 bg-[#121318] flex flex-col animate-in slide-in-from-right duration-200">
            <div className="flex items-center justify-between px-4 py-3.5 border-b border-white/10 bg-[#161820]">
              <button
                onClick={() => setPickerTarget(null)}
                className="flex items-center gap-1.5 text-xs font-bold text-[#a1a1aa] hover:text-white transition-colors"
              >
                <ArrowLeft className="w-4 h-4" />
                <span>Kembali</span>
              </button>
              <h4 className="font-bold text-sm text-white">
                {pickerTarget === 'outgoing'
                  ? 'Pilih Lagu Keluar (Deck A)'
                  : 'Pilih Lagu Masuk (Deck B)'}
              </h4>
              <button
                onClick={() => setPickerTarget(null)}
                className="w-7 h-7 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 hover:text-white transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="p-3 border-b border-white/10 bg-[#161820]/60">
              <div className="relative">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-white/40" />
                <input
                  type="text"
                  value={pickerQuery}
                  onChange={(e) => {
                    setPickerQuery(e.target.value);
                    if (pickerTab !== 'search') setPickerTab('search');
                  }}
                  placeholder="Cari judul lagu atau artis..."
                  autoFocus
                  className="w-full bg-[#20222a] border border-white/10 rounded-xl pl-9 pr-9 py-2 text-xs text-white placeholder-white/40 focus:outline-none focus:border-emerald-400"
                />
                {pickerQuery && (
                  <button
                    onClick={() => setPickerQuery('')}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-white/40 hover:text-white"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            </div>

            <div className="flex items-center gap-1 px-3 py-2 border-b border-white/5 bg-[#14151c] overflow-x-auto no-scrollbar text-xs">
              <button
                onClick={() => setPickerTab('queue')}
                className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                  pickerTab === 'queue'
                    ? 'bg-emerald-500 text-black'
                    : 'bg-white/5 text-white/70 hover:bg-white/10'
                }`}
              >
                <ListMusic className="w-3.5 h-3.5" />
                <span>Antrean ({queue.length})</span>
              </button>
              <button
                onClick={() => setPickerTab('liked')}
                className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                  pickerTab === 'liked'
                    ? 'bg-emerald-500 text-black'
                    : 'bg-white/5 text-white/70 hover:bg-white/10'
                }`}
              >
                <Heart className="w-3.5 h-3.5" />
                <span>Disukai ({likedTracks.length})</span>
              </button>
              <button
                onClick={() => setPickerTab('trending')}
                className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                  pickerTab === 'trending'
                    ? 'bg-emerald-500 text-black'
                    : 'bg-white/5 text-white/70 hover:bg-white/10'
                }`}
              >
                <Flame className="w-3.5 h-3.5" />
                <span>Hits &amp; Populer</span>
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-2 space-y-1">
              {isSearching && (
                <div className="py-8 text-center text-xs text-white/50 flex items-center justify-center gap-2">
                  <RefreshCw className="w-4 h-4 animate-spin text-emerald-400" />
                  <span>Mencari lagu di katalog...</span>
                </div>
              )}

              {(() => {
                let pool = [];
                if (pickerTab === 'search' || pickerQuery.trim()) {
                  pool = searchResults;
                } else if (pickerTab === 'queue') {
                  pool = queue;
                } else if (pickerTab === 'liked') {
                  pool = likedTracks;
                } else {
                  pool = trendingTracks;
                }

                if (!isSearching && pool.length === 0) {
                  return (
                    <div className="py-12 text-center text-xs text-white/40">
                      {pickerQuery
                        ? 'Tidak ada lagu yang cocok dengan pencarian.'
                        : 'Belum ada lagu dalam daftar ini.'}
                    </div>
                  );
                }

                return pool.map((t, idx) => {
                  const bpmKey = computeTrackBpmAndKey(t);
                  return (
                    <div
                      key={`pick-${t.id || t.videoId || idx}`}
                      onClick={() => {
                        stopPreview();
                        if (pickerTarget === 'outgoing') {
                          setOutgoingOverride(t);
                        } else {
                          setIncomingOverride(t);
                        }
                        setPickerTarget(null);
                        setPickerQuery('');
                        setSmartAutomixInsight(null);
                      }}
                      className="flex items-center justify-between p-2 rounded-xl hover:bg-white/10 cursor-pointer transition-colors group"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <img
                          src={getHighResArtworkUrl(t.artwork || t.thumbnail)}
                          alt={t.title}
                          className="w-10 h-10 rounded-lg object-cover bg-neutral-800 flex-shrink-0"
                        />
                        <div className="min-w-0">
                          <h5 className="text-xs font-bold text-white truncate max-w-[205px] group-hover:text-emerald-400 transition-colors">
                            {t.title}
                          </h5>
                          <p className="text-[11px] text-[#a1a1aa] truncate max-w-[205px]">
                            {t.artist}
                          </p>
                        </div>
                      </div>

                      <div className="flex items-center gap-2 flex-shrink-0">
                        <span className="text-[10px] font-mono text-white/60">
                          {bpmKey.bpm} bpm
                        </span>
                        <span
                          className={`px-1.5 py-0.5 rounded text-[9px] font-black ${getCamelotBadgeColor(
                            bpmKey.key
                          )}`}
                        >
                          {bpmKey.key}
                        </span>
                        <button className="px-2.5 py-1 rounded-lg bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500 hover:text-black font-bold text-[11px] transition-all">
                          Pilih
                        </button>
                      </div>
                    </div>
                  );
                });
              })()}
            </div>
          </div>
        )}

        {/* ========================================================= */}
        {/* VIEW 2: SPOTIFY EDIT TRANSITION STUDIO (BETA)             */}
        {/* ========================================================= */}

        {/* 1. Header Bar: Cancel | Edit transition [BETA] | Save */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-white/[0.06] bg-[#161820] shrink-0">
          <button
            onClick={() => {
              stopPreview();
              onClose();
            }}
            className="text-xs sm:text-sm font-semibold text-[#a1a1aa] hover:text-white transition-colors"
          >
            Cancel
          </button>

          <div className="flex items-center gap-2">
            <h3 className="font-bold text-sm sm:text-base text-white tracking-tight">
              Edit transition
            </h3>
            <span className="px-2 py-0.5 rounded-full text-[10px] font-black uppercase tracking-wider bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
              BETA
            </span>
          </div>

          <button
            onClick={handleSave}
            className="text-xs sm:text-sm font-bold text-emerald-400 hover:text-emerald-300 transition-colors"
          >
            Save
          </button>
        </div>

        {/* 2. Scrollable Body Container */}
        <div className="p-4 sm:p-5 space-y-3 overflow-y-auto no-scrollbar">
          {/* Smart Automix AI Bar */}
          <div className="flex items-center justify-between gap-2 p-2.5 rounded-xl bg-gradient-to-r from-emerald-500/15 via-[#182638] to-[#121c2b] border border-emerald-500/25">
            <div className="flex items-center gap-2 min-w-0">
              <div className="w-7 h-7 rounded-lg bg-emerald-500/20 flex items-center justify-center flex-shrink-0">
                <Sparkles className="w-4 h-4 text-emerald-400" />
              </div>
              <div className="min-w-0">
                <p className="text-xs font-bold text-white flex items-center gap-1.5 truncate">
                  <span>Smart Automix DSP</span>
                  <span className="text-[9px] px-1.5 py-0.2 rounded bg-emerald-400/20 text-emerald-300 border border-emerald-400/30 font-black">
                    {compatibility.score}% MATCH
                  </span>
                </p>
                <p className="text-[10px] text-white/60 truncate">
                  {compatibility.label} • {barStats.durationSec}s ({barStats.beats} ketukan)
                </p>
              </div>
            </div>

            <button
              onClick={handleApplySmartAutomix}
              className="px-3 py-1.5 rounded-lg bg-emerald-500 hover:bg-emerald-400 text-black font-black text-xs flex items-center gap-1.5 shadow-lg shadow-emerald-500/20 active:scale-95 transition-all flex-shrink-0"
            >
              <Wand2 className="w-3.5 h-3.5" />
              <span>Auto-Mix</span>
            </button>
          </div>

          {smartAutomixInsight && (
            <div className="p-2.5 rounded-xl bg-emerald-950/40 border border-emerald-500/35 text-[11px] text-emerald-200 leading-relaxed animate-in fade-in duration-200">
              <p className="font-semibold">{smartAutomixInsight.explanation}</p>
            </div>
          )}

          {/* Outgoing Track Row (Deck A) */}
          <div
            onClick={() => setPickerTarget('outgoing')}
            className="flex items-center justify-between gap-2.5 bg-white/[0.03] hover:bg-white/[0.06] p-2.5 rounded-xl border border-white/5 cursor-pointer transition-colors group"
          >
            <div className="flex items-center gap-3 min-w-0">
              <img
                src={outgoing.artwork}
                alt={outgoing.title}
                className="w-11 h-11 rounded-lg object-cover bg-neutral-800 shadow-md flex-shrink-0"
              />
              <div className="min-w-0">
                <h4 className="text-xs sm:text-sm font-bold text-white truncate max-w-[165px] sm:max-w-[195px] group-hover:text-cyan-300 transition-colors">
                  {outgoing.title}
                </h4>
                <p className="text-[11px] text-[#a1a1aa] truncate max-w-[165px] sm:max-w-[195px]">
                  {outgoing.artist}
                </p>
              </div>
            </div>

            <div className="text-right flex-shrink-0 flex items-center gap-1.5 sm:gap-2">
              <span className="text-xs text-white/85 font-mono font-semibold">
                {outgoing.bpm} bpm
              </span>
              <span
                className={`px-1.5 py-0.5 rounded text-[10px] font-black ${getCamelotBadgeColor(
                  outgoing.key
                )}`}
              >
                {outgoing.key}
              </span>
              <span
                className="px-2 py-0.5 rounded bg-cyan-500/20 border border-cyan-400/40 text-[11px] font-mono font-bold text-cyan-300 shadow-[0_0_8px_rgba(6,182,212,0.25)]"
                title="Titik awal transisi lagu keluar"
              >
                Mulai: {formatMinSec(currentOutroCueSec)}
              </span>
              <span className="text-xs text-[#a1a1aa] tabular-nums font-mono">
                / {formatMinSec(outgoing.duration)}
              </span>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setPickerTarget('outgoing');
                }}
                className="px-2 py-1 rounded-md bg-white/10 hover:bg-white/20 text-[10px] font-bold text-white/90 hover:text-white transition-all"
                title="Ganti Lagu Keluar"
              >
                Ganti
              </button>
            </div>
          </div>

          {/* ========================================================= */}
          {/* INTERACTIVE DUAL-DECK WAVEFORM STUDIO CANVAS              */}
          {/* ========================================================= */}
          <div
            ref={waveformBoxRef}
            onPointerDown={handleWaveformPointerDown}
            className="relative rounded-2xl bg-[#181a22] border border-white/[0.08] px-4 py-3.5 overflow-hidden cursor-ew-resize"
            title="Klik atau geser pada waveform untuk mengaudisi titik transisi"
          >
            {/* Subtle Beat Grid Lines */}
            <div className="absolute inset-0 pointer-events-none flex justify-between px-4 opacity-15">
              {Array.from({ length: 9 }).map((_, idx) => (
                <div
                  key={`grid-${idx}`}
                  className={`h-full w-px ${
                    idx === 4 ? 'bg-white/70' : 'bg-white/25'
                  }`}
                />
              ))}
            </div>

            {/* 1. TOP WAVEFORM: Outgoing Track (Grey Lead-In -> Cyan Overlap Zone) */}
            <div className="relative h-20 flex items-center justify-between gap-[2px]">
              <div className="absolute top-1 left-1.5 z-10 pointer-events-none">
                <span className="px-1.5 py-0.5 rounded bg-black/80 backdrop-blur-sm border border-cyan-400/40 text-[9px] font-mono text-cyan-300 font-bold tracking-tight shadow-sm">
                  Cue Outro: {formatMinSec(currentOutroCueSec)}
                </span>
              </div>
              {topWaveformBars.map((h, i) => {
                const ratio = i / topWaveformBars.length;
                const overlapStartRatio = 1 - overlapFraction;
                const isOverlapped = ratio >= overlapStartRatio;
                const localOverlapPos = isOverlapped
                  ? (ratio - overlapStartRatio) / overlapFraction
                  : 0;
                // Modulate bar brightness with active playhead
                const isPlayed = effectiveIsPlaying && effectiveProgress >= ratio;

                return (
                  <div
                    key={`top-${i}`}
                    className={`flex-1 rounded-full transition-all duration-100 ${
                      isOverlapped
                        ? isPlayed
                          ? 'bg-cyan-300 shadow-[0_0_10px_rgba(34,211,238,0.65)]'
                          : 'bg-cyan-400/85 shadow-[0_0_6px_rgba(6,182,212,0.35)]'
                        : isPlayed
                        ? 'bg-white/65'
                        : 'bg-white/35'
                    }`}
                    style={{
                      height: `${Math.max(12, h * (isOverlapped && settings.volume === 'cut' && localOverlapPos > 0.84 ? 0.25 : 1))}%`,
                    }}
                  />
                );
              })}

              {/* Dynamic Outgoing SVG Volume/Filter Envelope Overlay on Overlap Region */}
              <div
                className="absolute top-0 bottom-0 right-0 pointer-events-none"
                style={{ width: `${overlapFraction * 100}%` }}
              >
                <svg
                  viewBox="0 0 200 72"
                  preserveAspectRatio="none"
                  className="w-full h-full overflow-visible"
                >
                  <defs>
                    <linearGradient id="outEnvGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.24" />
                      <stop offset="100%" stopColor="#22d3ee" stopOpacity="0.02" />
                    </linearGradient>
                  </defs>
                  <path d={envelopeSvg.outAreaPath} fill="url(#outEnvGrad)" />
                  {/* 1. Cyan Volume Envelope */}
                  <polyline
                    fill="none"
                    stroke="#22d3ee"
                    strokeWidth="2.4"
                    points={envelopeSvg.outLinePoints}
                  />
                  {/* 2. Yellow/Gold Bass Swap Step Automation Line */}
                  {(settings.volume === 'mashup' || settings.eq === 'bass_swap' || settings.eq === 'high_pass') && envelopeSvg.outBassPoints && (
                    <polyline
                      fill="none"
                      stroke="#facc15"
                      strokeWidth="2.0"
                      strokeLinejoin="round"
                      points={envelopeSvg.outBassPoints}
                    />
                  )}
                  {/* 3. Pink/Magenta Filter S-Curve Sweep Line */}
                  {settings.effect !== 'none' && envelopeSvg.outFilterPoints && (
                    <polyline
                      fill="none"
                      stroke="#f472b6"
                      strokeWidth="2.0"
                      strokeLinecap="round"
                      points={envelopeSvg.outFilterPoints}
                    />
                  )}
                </svg>
                <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-cyan-400/75 rounded-full" />
              </div>
            </div>

            {/* 2. CENTER CONTROLS: Play Button + Bars Dropdown + Tempo Sync / Telemetry */}
            <div
              className="relative my-2.5 flex items-center justify-center gap-2.5 z-20"
              onPointerDown={(e) => e.stopPropagation()}
            >
              {/* Play / Pause Preview Button */}
              <button
                onClick={handleTogglePreview}
                disabled={audioLoading}
                className="w-11 h-11 rounded-full bg-white text-black flex items-center justify-center shadow-[0_0_24px_rgba(255,255,255,0.3)] hover:scale-105 active:scale-95 transition-all cursor-pointer relative"
                title={
                  effectiveIsPlaying
                    ? 'Hentikan Audisi Transisi'
                    : 'Putar Audisi Transisi Real-Time'
                }
              >
                {audioLoading ? (
                  <RefreshCw className="w-5 h-5 text-black animate-spin" />
                ) : effectiveIsPlaying ? (
                  <Pause className="w-5 h-5 fill-black" />
                ) : (
                  <Play className="w-5 h-5 fill-black ml-0.5" />
                )}
              </button>

              {/* Bars Selector Pill (1 bar, 2 bars, 4 bars, 8 bars) */}
              <div className="relative">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveDropdown(activeDropdown === 'bars' ? null : 'bars');
                  }}
                  className="px-3.5 py-1.5 rounded-full bg-[#262832] hover:bg-[#323542] border border-white/15 text-xs font-bold text-white flex items-center gap-1.5 shadow-md active:scale-95 transition-all"
                >
                  <span>{settings.bars || '2 bars'}</span>
                  <span className="text-[10px] text-emerald-400 font-mono">
                    ({barStats.durationSec}s)
                  </span>
                  <ChevronDown className="w-3.5 h-3.5 text-white/70" />
                </button>

                {activeDropdown === 'bars' && (
                  <div
                    className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 w-48 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                    onClick={(e) => e.stopPropagation()}
                  >
                    {durationOptions.map((opt) => (
                      <button
                        key={opt.label}
                        onClick={() => {
                          setSettings((prev) => ({
                            ...prev,
                            bars: opt.label,
                            durationSec: opt.dur,
                          }));
                          setActiveDropdown(null);
                        }}
                        className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                          settings.bars === opt.label
                            ? 'text-emerald-400'
                            : 'text-white'
                        }`}
                      >
                        <div>
                          <span>{opt.label}</span>
                          <span className="text-[10px] text-white/45 ml-1.5 font-mono">
                            {opt.dur}s • {opt.beats} beats
                          </span>
                        </div>
                        {settings.bars === opt.label && (
                          <Check className="w-3.5 h-3.5" />
                        )}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Tempo Sync Pill */}
              <button
                onClick={() =>
                  setSettings((prev) => ({
                    ...prev,
                    tempoSync: prev.tempoSync === false,
                  }))
                }
                className={`px-2.5 py-1.5 rounded-full border text-[10px] font-bold flex items-center gap-1 transition-all ${
                  settings.tempoSync !== false
                    ? 'bg-emerald-500/20 border-emerald-400/40 text-emerald-300'
                    : 'bg-white/5 border-white/10 text-white/50 hover:text-white'
                }`}
                title="Sinkronisasi Tempo Otomatis (Beatmatch)"
              >
                <Zap className="w-3 h-3" />
                <span>Sync</span>
              </button>

              {/* Cue Offset Fine-Tuner Toggle */}
              <button
                onClick={() => setShowCueControls((v) => !v)}
                className={`p-1.5 rounded-full border text-[10px] transition-all ${
                  showCueControls
                    ? 'bg-cyan-500/20 border-cyan-400/40 text-cyan-300'
                    : 'bg-white/5 border-white/10 text-white/50 hover:text-white'
                }`}
                title="Atur Titik Cue Outro & Intro"
              >
                <Sliders className="w-3.5 h-3.5" />
              </button>
            </div>

            {/* Optional Cue Point Nudge Bar */}
            {showCueControls && (
              <div
                onPointerDown={(e) => e.stopPropagation()}
                className="mb-2.5 px-2.5 py-1.5 rounded-xl bg-black/50 border border-white/10 flex items-center justify-between text-[10px] text-white/80"
              >
                <div className="flex items-center gap-1.5">
                  <span className="text-cyan-300 font-bold">Cue Outro:</span>
                  <button
                    onClick={() =>
                      setSettings((p) => {
                        const cur =
                          typeof p.activeOutroSec === 'number' && p.activeOutroSec > 0
                            ? p.activeOutroSec
                            : Math.max(0, (outgoing.duration || 185) - barStats.durationSec + (Number(p.outroOffsetSec) || 0));
                        const nxt = Math.max(5, cur - 2);
                        return {
                          ...p,
                          activeOutroSec: nxt,
                          targetOutroSec: nxt,
                          outroOffsetSec: Number((nxt - ((outgoing.duration || 185) - barStats.durationSec)).toFixed(1)),
                        };
                      })
                    }
                    className="px-1.5 py-0.5 rounded bg-white/10 hover:bg-white/20 font-mono active:scale-95 transition-transform"
                  >
                    -2s
                  </button>
                  <span className="font-mono text-cyan-300 font-bold px-1.5 py-0.5 bg-black/60 rounded border border-cyan-500/30">
                    {formatMinSec(currentOutroCueSec)}
                  </span>
                  <button
                    onClick={() =>
                      setSettings((p) => {
                        const cur =
                          typeof p.activeOutroSec === 'number' && p.activeOutroSec > 0
                            ? p.activeOutroSec
                            : Math.max(0, (outgoing.duration || 185) - barStats.durationSec + (Number(p.outroOffsetSec) || 0));
                        const nxt = Math.min((outgoing.duration || 185) - 2, cur + 2);
                        return {
                          ...p,
                          activeOutroSec: nxt,
                          targetOutroSec: nxt,
                          outroOffsetSec: Number((nxt - ((outgoing.duration || 185) - barStats.durationSec)).toFixed(1)),
                        };
                      })
                    }
                    className="px-1.5 py-0.5 rounded bg-white/10 hover:bg-white/20 font-mono active:scale-95 transition-transform"
                  >
                    +2s
                  </button>
                </div>

                <div className="flex items-center gap-1.5">
                  <span className="text-fuchsia-300 font-bold">Cue Intro:</span>
                  <button
                    onClick={() =>
                      setSettings((p) => {
                        const cur = Math.max(0, Number(p.introOffsetSec) || 0);
                        const nxt = Math.max(0, cur - 2);
                        return { ...p, introOffsetSec: nxt };
                      })
                    }
                    className="px-1.5 py-0.5 rounded bg-white/10 hover:bg-white/20 font-mono active:scale-95 transition-transform"
                  >
                    -2s
                  </button>
                  <span className="font-mono text-fuchsia-300 font-bold px-1.5 py-0.5 bg-black/60 rounded border border-fuchsia-500/30">
                    {formatMinSec(currentIntroCueSec)}
                  </span>
                  <button
                    onClick={() =>
                      setSettings((p) => {
                        const cur = Math.max(0, Number(p.introOffsetSec) || 0);
                        const nxt = Math.min((incoming.duration || 180) - 5, cur + 2);
                        return { ...p, introOffsetSec: nxt };
                      })
                    }
                    className="px-1.5 py-0.5 rounded bg-white/10 hover:bg-white/20 font-mono active:scale-95 transition-transform"
                  >
                    +2s
                  </button>
                </div>
              </div>
            )}

            {/* 3. BOTTOM WAVEFORM: Incoming Track (Purple Overlap Zone -> Grey Body) */}
            <div className="relative h-20 flex items-center justify-between gap-[2px]">
              <div className="absolute bottom-1 left-1.5 z-10 pointer-events-none">
                <span className="px-1.5 py-0.5 rounded bg-black/80 backdrop-blur-sm border border-fuchsia-400/40 text-[9px] font-mono text-fuchsia-300 font-bold tracking-tight shadow-sm">
                  Cue Intro: {formatMinSec(currentIntroCueSec)} → {formatMinSec(currentIntroEndSec)}
                </span>
              </div>
              {bottomWaveformBars.map((h, i) => {
                const ratio = i / bottomWaveformBars.length;
                const isOverlapped = ratio <= overlapFraction;
                const isPlayed = effectiveIsPlaying && effectiveProgress >= ratio;

                return (
                  <div
                    key={`bottom-${i}`}
                    className={`flex-1 rounded-full transition-all duration-100 ${
                      isOverlapped
                        ? isPlayed
                          ? 'bg-fuchsia-300 shadow-[0_0_10px_rgba(232,121,249,0.65)]'
                          : 'bg-fuchsia-500/85 shadow-[0_0_6px_rgba(217,70,239,0.35)]'
                        : isPlayed
                        ? 'bg-white/65'
                        : 'bg-white/35'
                    }`}
                    style={{ height: `${h}%` }}
                  />
                );
              })}

              {/* Dynamic Incoming SVG Volume/Filter Envelope Overlay on Overlap Region */}
              <div
                className="absolute top-0 bottom-0 left-0 pointer-events-none"
                style={{ width: `${overlapFraction * 100}%` }}
              >
                <div className="absolute top-0 left-0 right-0 h-[2px] bg-fuchsia-400/75 rounded-full" />
                <svg
                  viewBox="0 0 200 72"
                  preserveAspectRatio="none"
                  className="w-full h-full overflow-visible"
                >
                  <defs>
                    <linearGradient id="inEnvGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#e879f9" stopOpacity="0.24" />
                      <stop offset="100%" stopColor="#e879f9" stopOpacity="0.02" />
                    </linearGradient>
                  </defs>
                  <path d={envelopeSvg.inAreaPath} fill="url(#inEnvGrad)" />
                  {/* 1. Cyan/Magenta Volume Envelope */}
                  <polyline
                    fill="none"
                    stroke={settings.volume === 'mashup' ? '#22d3ee' : '#e879f9'}
                    strokeWidth="2.4"
                    points={envelopeSvg.inLinePoints}
                  />
                  {/* 2. Yellow/Gold Bass Swap Step Automation Line (jumps up at Bar 4 midpoint) */}
                  {(settings.volume === 'mashup' || settings.eq === 'bass_swap') && envelopeSvg.inBassPoints && (
                    <polyline
                      fill="none"
                      stroke="#facc15"
                      strokeWidth="2.0"
                      strokeLinejoin="round"
                      points={envelopeSvg.inBassPoints}
                    />
                  )}
                </svg>
              </div>
            </div>

            {/* Live DSP Telemetry Overlay while Auditioning */}
            {effectiveIsPlaying && (
              <div className="mt-2 pt-2 border-t border-white/10 flex items-center justify-between text-[10px] font-mono text-white/75">
                <span className="text-cyan-300">
                  Deck A: {liveTransitionState?.outVolPercent ?? (liveTelemetry?.envelope ? Math.round(liveTelemetry.envelope.outGain * 100) : 100)}%
                  {settings.effect === 'high_pass' && ' • HPF S-Curve'}
                </span>
                <span className="text-emerald-400 font-bold uppercase">
                  {liveTransitionState?.active ? `MASHUP BLEND (${Math.round(effectiveProgress * 100)}%)` : 'AUDISI LIVE'}
                </span>
                <span className="text-fuchsia-300">
                  Deck B: {liveTransitionState?.inVolPercent ?? (liveTelemetry?.envelope ? Math.round(liveTelemetry.envelope.inGain * 100) : 100)}%
                </span>
              </div>
            )}

            {/* Live Playhead Sweep Line */}
            {effectiveIsPlaying && (
              <div
                className="absolute top-0 bottom-0 w-0.5 bg-emerald-400 shadow-[0_0_12px_#34d399] pointer-events-none z-20"
                style={{ left: `${effectiveProgress * 100}%` }}
              />
            )}
          </div>

          {/* Incoming Track Row (Deck B) */}
          <div
            onClick={() => setPickerTarget('incoming')}
            className="flex items-center justify-between gap-2.5 bg-white/[0.03] hover:bg-white/[0.06] p-2.5 rounded-xl border border-white/5 cursor-pointer transition-colors group"
          >
            <div className="flex items-center gap-3 min-w-0">
              <img
                src={incoming.artwork}
                alt={incoming.title}
                className="w-11 h-11 rounded-lg object-cover bg-neutral-800 shadow-md flex-shrink-0"
              />
              <div className="min-w-0">
                <h4 className="text-xs sm:text-sm font-bold text-white truncate max-w-[165px] sm:max-w-[195px] group-hover:text-fuchsia-300 transition-colors">
                  {incoming.title}
                </h4>
                <p className="text-[11px] text-[#a1a1aa] truncate max-w-[165px] sm:max-w-[195px]">
                  {incoming.artist}
                </p>
              </div>
            </div>

            <div className="text-right flex-shrink-0 flex items-center gap-1.5 sm:gap-2">
              <span className="text-xs text-white/85 font-mono font-semibold">
                {incoming.bpm} bpm
              </span>
              <span
                className={`px-1.5 py-0.5 rounded text-[10px] font-black ${getCamelotBadgeColor(
                  incoming.key
                )}`}
              >
                {incoming.key}
              </span>
              <span
                className="px-2 py-0.5 rounded bg-fuchsia-500/20 border border-fuchsia-400/40 text-[11px] font-mono font-bold text-fuchsia-300 shadow-[0_0_8px_rgba(217,70,239,0.25)]"
                title="Rentang masuk lagu baru hingga transisi selesai"
              >
                Mulai: {formatMinSec(currentIntroCueSec)} → {formatMinSec(currentIntroEndSec)}
              </span>
              <span className="text-xs text-[#a1a1aa] tabular-nums font-mono">
                / {formatMinSec(incoming.duration)}
              </span>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setPickerTarget('incoming');
                }}
                className="px-2 py-1 rounded-md bg-white/10 hover:bg-white/20 text-[10px] font-bold text-white/90 hover:text-white transition-all"
                title="Ganti Lagu Masuk"
              >
                Ganti
              </button>
            </div>
          </div>

          {/* 3. Bottom Settings Dock (3 Dropdowns: VOLUME | EQ | EFFECTS) */}
          <div className="rounded-2xl bg-[#181a22] border border-white/[0.08] p-3 grid grid-cols-3 gap-2">
            {/* Column 1: VOLUME */}
            <div className="relative">
              <label className="text-[10px] font-bold uppercase tracking-wider text-white/40 block mb-1">
                Volume
              </label>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveDropdown(activeDropdown === 'volume' ? null : 'volume');
                }}
                className="w-full py-2 px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.1] text-xs font-bold text-white flex items-center justify-between transition-colors"
              >
                <span className="truncate">
                  {TRANSITION_VOLUME_OPTIONS.find((o) => o.id === settings.volume)?.label ||
                    'Overlap'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-white/60 flex-shrink-0" />
              </button>

              {activeDropdown === 'volume' && (
                <div
                  className="absolute bottom-full left-0 mb-2 w-52 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                  onClick={(e) => e.stopPropagation()}
                >
                  {TRANSITION_VOLUME_OPTIONS.map((opt) => (
                    <button
                      key={opt.id}
                      onClick={() => {
                        setSettings((prev) => ({ ...prev, volume: opt.id }));
                        setActiveDropdown(null);
                      }}
                      className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                        settings.volume === opt.id ? 'text-emerald-400' : 'text-white'
                      }`}
                    >
                      <div className="pr-2">
                        <div>{opt.label}</div>
                        <div className="text-[10px] text-white/50">{opt.desc}</div>
                      </div>
                      {settings.volume === opt.id && (
                        <Check className="w-3.5 h-3.5 flex-shrink-0" />
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Column 2: EQ */}
            <div className="relative">
              <label className="text-[10px] font-bold uppercase tracking-wider text-white/40 block mb-1">
                EQ
              </label>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveDropdown(activeDropdown === 'eq' ? null : 'eq');
                }}
                className="w-full py-2 px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.1] text-xs font-bold text-white flex items-center justify-between transition-colors"
              >
                <span className="truncate">
                  {TRANSITION_EQ_OPTIONS.find((o) => o.id === settings.eq)?.label ||
                    'None'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-white/60 flex-shrink-0" />
              </button>

              {activeDropdown === 'eq' && (
                <div
                  className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 w-56 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                  onClick={(e) => e.stopPropagation()}
                >
                  {TRANSITION_EQ_OPTIONS.map((opt) => (
                    <button
                      key={opt.id}
                      onClick={() => {
                        setSettings((prev) => ({ ...prev, eq: opt.id }));
                        setActiveDropdown(null);
                      }}
                      className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                        settings.eq === opt.id ? 'text-emerald-400' : 'text-white'
                      }`}
                    >
                      <div className="pr-2">
                        <div>{opt.label}</div>
                        <div className="text-[10px] text-white/50">{opt.desc}</div>
                      </div>
                      {settings.eq === opt.id && (
                        <Check className="w-3.5 h-3.5 flex-shrink-0" />
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Column 3: EFFECTS */}
            <div className="relative">
              <label className="text-[10px] font-bold uppercase tracking-wider text-white/40 block mb-1">
                Effects
              </label>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveDropdown(activeDropdown === 'effect' ? null : 'effect');
                }}
                className="w-full py-2 px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.1] text-xs font-bold text-white flex items-center justify-between transition-colors"
              >
                <span className="truncate">
                  {TRANSITION_EFFECT_OPTIONS.find((o) => o.id === settings.effect)
                    ?.label || 'High pass filter'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-white/60 flex-shrink-0" />
              </button>

              {activeDropdown === 'effect' && (
                <div
                  className="absolute bottom-full right-0 mb-2 w-56 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                  onClick={(e) => e.stopPropagation()}
                >
                  {TRANSITION_EFFECT_OPTIONS.map((opt) => (
                    <button
                      key={opt.id}
                      onClick={() => {
                        setSettings((prev) => ({ ...prev, effect: opt.id }));
                        setActiveDropdown(null);
                      }}
                      className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                        settings.effect === opt.id ? 'text-emerald-400' : 'text-white'
                      }`}
                    >
                      <div className="pr-2">
                        <div>{opt.label}</div>
                        <div className="text-[10px] text-white/50">{opt.desc}</div>
                      </div>
                      {settings.effect === opt.id && (
                        <Check className="w-3.5 h-3.5 flex-shrink-0" />
                      )}
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* 4. Live Player Test Button (Play Outgoing -> Incoming Transition directly in Main Player) */}
          <button
            onClick={handleTestLiveInPlayer}
            className="w-full py-2.5 px-4 rounded-xl bg-white/[0.06] hover:bg-emerald-500/20 border border-white/10 hover:border-emerald-500/40 text-xs font-bold text-white hover:text-emerald-300 flex items-center justify-center gap-2 transition-all active:scale-[0.99]"
          >
            <Radio className="w-3.5 h-3.5 text-emerald-400" />
            <span>
              Simpan &amp; Uji Langsung di Player Utama ({outgoing.title} ⇄ {incoming.title})
            </span>
          </button>
        </div>
      </div>
    </div>
  );
}
