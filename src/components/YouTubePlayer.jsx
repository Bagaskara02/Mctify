import React, { useEffect, useRef, useState } from 'react';
import { Tv, X, Wand2 } from 'lucide-react';
import { webAudioEqualizer } from '../services/webAudioEqualizer';
import { audioQualityService } from '../services/audioQualityService';
import { evaluateTransitionEnvelope } from '../services/transitionEngine';

/**
 * Dual-Deck YouTube Audio/Video Player Engine (Deck A ⇄ Deck B)
 * - Supports full-length song streaming (3 - 5+ minutes)
 * - Pre-cues upcoming track on the standby deck
 * - Executes real-time overlap/crossfade/filter/bass-swap transitions between Deck A and Deck B
 *   with seamless active-deck handoff (0ms gap, no reload on track change)
 */
export default function YouTubePlayer({
  videoId,
  nextVideoId = null,
  transitionConfig = null,
  canAutoTransition = false,
  isPlaying,
  volume,
  isMuted,
  playbackRate = 1.0,
  seekTime,
  onTimeUpdate,
  onEnded,
  onTransitionStateChange,
  onTransitionComplete,
  onError,
}) {
  // Dual-deck player instances: index 0 = Deck A, index 1 = Deck B
  const decksRef = useRef([null, null]);
  const deckReadyRef = useRef([false, false]);
  const activeDeckIdxRef = useRef(0);
  const loadedVidByDeckRef = useRef(['', '']);
  const endedVideoIdRef = useRef('');
  const backgroundKickTimerRef = useRef(null);

  // Live Transition State Refs
  const transitionStateRef = useRef({
    active: false,
    fromDeck: 0,
    toDeck: 1,
    outgoingVid: '',
    incomingVid: '',
    startedAtMs: 0,
    durationSec: 5.5,
    progress: 0,
  });

  // Hybrid Web Audio DSP Bridge Refs (Real BiquadFilter Bass Swap + HPF S-Curve + Smooth Tempo Sync)
  const dspBridgeRef = useRef({
    active: false,
    ctx: null,
    outAudio: null,
    inAudio: null,
    outGain: null,
    inGain: null,
    outLow: null,
    inLow: null,
    outMid: null,
    inMid: null,
    outFilter: null,
    inFilter: null,
    masterGain: null,
    preloadedKey: '',
    preloadedOutAudio: null,
    preloadedInAudio: null,
  });

  const teardownDspBridge = (keepPreloaded = false) => {
    const b = dspBridgeRef.current;
    b.active = false;
    try { b.outAudio?.pause?.(); } catch {}
    try { b.inAudio?.pause?.(); } catch {}
    try {
      if (b.ctx && b.ctx.state !== 'closed') {
        b.ctx.close().catch(() => {});
      }
    } catch {}
    b.ctx = null;
    b.outAudio = null;
    b.inAudio = null;
    b.outGain = null;
    b.inGain = null;
    b.outLow = null;
    b.inLow = null;
    b.outMid = null;
    b.inMid = null;
    b.outFilter = null;
    b.inFilter = null;
    b.masterGain = null;
    if (!keepPreloaded) {
      try { b.preloadedOutAudio?.pause?.(); } catch {}
      try { b.preloadedInAudio?.pause?.(); } catch {}
      b.preloadedOutAudio = null;
      b.preloadedInAudio = null;
      b.preloadedKey = '';
    }
  };

  const prewarmDspBridgeDecks = (outVid, inVid, startOutSec, introCueSec) => {
    if (!outVid || !inVid || outVid === inVid) return;
    const key = `${outVid}:::${inVid}`;
    const b = dspBridgeRef.current;
    if (b.preloadedKey === key && b.preloadedOutAudio && b.preloadedInAudio) return;

    try { b.preloadedOutAudio?.pause?.(); } catch {}
    try { b.preloadedInAudio?.pause?.(); } catch {}

    try {
      const outEl = new Audio(`/api/yt/stream?videoId=${encodeURIComponent(outVid)}`);
      outEl.crossOrigin = 'anonymous';
      outEl.preload = 'auto';
      outEl.muted = false;
      outEl.currentTime = Math.max(0, startOutSec);

      const inEl = new Audio(`/api/yt/stream?videoId=${encodeURIComponent(inVid)}`);
      inEl.crossOrigin = 'anonymous';
      inEl.preload = 'auto';
      inEl.muted = false;
      inEl.currentTime = Math.max(0, introCueSec);

      b.preloadedKey = key;
      b.preloadedOutAudio = outEl;
      b.preloadedInAudio = inEl;
    } catch {}
  };

  const tryActivateDspBridge = async (outVid, inVid, currentOutSec, introCueSec) => {
    const b = dspBridgeRef.current;
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return false;

    const key = `${outVid}:::${inVid}`;
    if (b.preloadedKey !== key || !b.preloadedOutAudio || !b.preloadedInAudio) {
      prewarmDspBridgeDecks(outVid, inVid, currentOutSec, introCueSec);
    }

    const outEl = b.preloadedOutAudio;
    const inEl = b.preloadedInAudio;
    if (!outEl || !inEl) return false;
    // Require at least readyState >= 2 (HAVE_CURRENT_DATA) on both elements so DSP bridge starts with 0ms gap!
    if (outEl.readyState < 2 || inEl.readyState < 2) {
      return false;
    }

    try {
      teardownDspBridge(true);
      const ctx = new AudioCtx();
      if (ctx.state === 'suspended') {
        await ctx.resume();
      }

      const outSrc = ctx.createMediaElementSource(outEl);
      const inSrc = ctx.createMediaElementSource(inEl);

      const outLow = ctx.createBiquadFilter();
      outLow.type = 'lowshelf';
      outLow.frequency.value = 160;
      const inLow = ctx.createBiquadFilter();
      inLow.type = 'lowshelf';
      inLow.frequency.value = 160;

      const outMid = ctx.createBiquadFilter();
      outMid.type = 'peaking';
      outMid.frequency.value = 1250;
      outMid.Q.value = 1.0;
      const inMid = ctx.createBiquadFilter();
      inMid.type = 'peaking';
      inMid.frequency.value = 1250;
      inMid.Q.value = 1.0;

      const outFilter = ctx.createBiquadFilter();
      outFilter.type = 'allpass';
      const inFilter = ctx.createBiquadFilter();
      inFilter.type = 'allpass';

      const outGain = ctx.createGain();
      outGain.gain.value = 1.0;
      const inGain = ctx.createGain();
      inGain.gain.value = transitionConfigRef.current?.volume === 'mashup' ? 1.0 : 0.0;

      const masterGain = ctx.createGain();
      masterGain.gain.value = isMutedRef.current ? 0 : Math.max(0, Math.min(1, volumeRef.current ?? 0.8));

      const comp = ctx.createDynamicsCompressor();
      comp.threshold.value = -4;
      comp.ratio.value = 4;

      outSrc.connect(outLow);
      outLow.connect(outMid);
      outMid.connect(outFilter);
      outFilter.connect(outGain);
      outGain.connect(masterGain);

      inSrc.connect(inLow);
      inLow.connect(inMid);
      inMid.connect(inFilter);
      inFilter.connect(inGain);
      inGain.connect(masterGain);

      masterGain.connect(comp);
      comp.connect(ctx.destination);

      outEl.currentTime = Math.max(0, currentOutSec);
      inEl.currentTime = Math.max(0, introCueSec);

      await Promise.all([outEl.play(), inEl.play()]);

      b.active = true;
      b.ctx = ctx;
      b.outAudio = outEl;
      b.inAudio = inEl;
      b.outGain = outGain;
      b.inGain = inGain;
      b.outLow = outLow;
      b.inLow = inLow;
      b.outMid = outMid;
      b.inMid = inMid;
      b.outFilter = outFilter;
      b.inFilter = inFilter;
      b.masterGain = masterGain;
      b.preloadedOutAudio = null;
      b.preloadedInAudio = null;
      b.preloadedKey = '';
      return true;
    } catch (e) {
      console.warn('[YouTubePlayer] Hybrid Web Audio DSP bridge fallback to IFrame:', e);
      teardownDspBridge(false);
      return false;
    }
  };

  const [isReady, setIsReady] = useState(false);
  const [activeDeckState, setActiveDeckState] = useState(0);
  const [showVideo, setShowVideo] = useState(false);
  const [eqSettings, setEqSettings] = useState(() => webAudioEqualizer.settings);

  // Live refs prevent stale closures inside YT.Player & Web Worker callbacks
  const videoIdRef = useRef(videoId);
  const nextVideoIdRef = useRef(nextVideoId);
  const transitionConfigRef = useRef(transitionConfig);
  const canAutoTransitionRef = useRef(canAutoTransition);
  const isPlayingRef = useRef(isPlaying);
  const volumeRef = useRef(volume);
  const isMutedRef = useRef(isMuted);
  const eqSettingsRef = useRef(eqSettings);
  const playbackRateRef = useRef(playbackRate);
  const onTimeUpdateRef = useRef(onTimeUpdate);
  const onEndedRef = useRef(onEnded);
  const onTransitionStateChangeRef = useRef(onTransitionStateChange);
  const onTransitionCompleteRef = useRef(onTransitionComplete);
  const onErrorRef = useRef(onError);
  const seekTimeRef = useRef(seekTime);

  videoIdRef.current = videoId;
  nextVideoIdRef.current = nextVideoId;
  transitionConfigRef.current = transitionConfig;
  canAutoTransitionRef.current = canAutoTransition;
  isPlayingRef.current = isPlaying;
  volumeRef.current = volume;
  isMutedRef.current = isMuted;
  eqSettingsRef.current = eqSettings;
  playbackRateRef.current = playbackRate;
  onTimeUpdateRef.current = onTimeUpdate;
  onEndedRef.current = onEnded;
  onTransitionStateChangeRef.current = onTransitionStateChange;
  onTransitionCompleteRef.current = onTransitionComplete;
  onErrorRef.current = onError;
  seekTimeRef.current = seekTime;

  const getActivePlayer = () => decksRef.current[activeDeckIdxRef.current];
  const getStandbyDeckIdx = () => 1 - activeDeckIdxRef.current;
  const getStandbyPlayer = () => decksRef.current[1 - activeDeckIdxRef.current];

  const computeMasterCeilingVol = () => {
    const multiplier = webAudioEqualizer.getLoudnessMultiplier(eqSettingsRef.current);
    return Math.max(0, Math.min(100, Math.round((volumeRef.current ?? 0.8) * 100 * multiplier)));
  };

  // Subscribe to realtime Equalizer changes
  useEffect(() => {
    return webAudioEqualizer.subscribe((updated) => {
      setEqSettings(updated);
    });
  }, []);

  // Global Autoplay Unblocker
  useEffect(() => {
    const unlockAutoplay = () => {
      const activePlayer = getActivePlayer();
      if (isPlayingRef.current && activePlayer) {
        try {
          const st = activePlayer.getPlayerState?.();
          if (st !== window.YT?.PlayerState?.PLAYING && st !== window.YT?.PlayerState?.BUFFERING) {
            if (!isMutedRef.current) activePlayer.unMute?.();
            activePlayer.playVideo?.();
          }
        } catch {}
      }
    };

    window.addEventListener('pointerdown', unlockAutoplay, { capture: true, passive: true });
    window.addEventListener('keydown', unlockAutoplay, { capture: true, passive: true });
    window.addEventListener('touchstart', unlockAutoplay, { capture: true, passive: true });

    return () => {
      window.removeEventListener('pointerdown', unlockAutoplay, { capture: true });
      window.removeEventListener('keydown', unlockAutoplay, { capture: true });
      window.removeEventListener('touchstart', unlockAutoplay, { capture: true });
    };
  }, []);

  const clearBackgroundKick = () => {
    if (backgroundKickTimerRef.current) {
      clearTimeout(backgroundKickTimerRef.current);
      backgroundKickTimerRef.current = null;
    }
  };

  const cancelActiveTransition = (pauseStandby = true) => {
    if (!transitionStateRef.current.active) return;
    const toDeck = transitionStateRef.current.toDeck;
    teardownDspBridge(false);
    transitionStateRef.current = {
      active: false,
      fromDeck: activeDeckIdxRef.current,
      toDeck: 1 - activeDeckIdxRef.current,
      outgoingVid: '',
      incomingVid: '',
      startedAtMs: 0,
      durationSec: 5.5,
      progress: 0,
    };
    if (pauseStandby && decksRef.current[toDeck]) {
      try {
        decksRef.current[toDeck].pauseVideo?.();
        decksRef.current[toDeck].setVolume?.(0);
      } catch {}
    }
    const activePlayer = getActivePlayer();
    if (activePlayer) {
      try {
        if (!isMutedRef.current) {
          activePlayer.unMute?.();
          activePlayer.setVolume?.(computeMasterCeilingVol());
        }
        activePlayer.setPlaybackRate?.(playbackRateRef.current || 1.0);
      } catch {}
    }
    onTransitionStateChangeRef.current?.(null);
  };

  const completeActiveTransition = () => {
    const tr = transitionStateRef.current;
    if (!tr.active) return;

    const oldDeckIdx = tr.fromDeck;
    const newDeckIdx = tr.toDeck;
    const incomingVid = tr.incomingVid;
    const wasDspBridge = dspBridgeRef.current.active;
    const dspIncomingTime = wasDspBridge ? (dspBridgeRef.current.inAudio?.currentTime || 0) : 0;

    teardownDspBridge(false);
    transitionStateRef.current = {
      active: false,
      fromDeck: newDeckIdx,
      toDeck: oldDeckIdx,
      outgoingVid: '',
      incomingVid: '',
      startedAtMs: 0,
      durationSec: 5.5,
      progress: 0,
    };

    // Silence & pause old outgoing deck
    const oldPlayer = decksRef.current[oldDeckIdx];
    if (oldPlayer) {
      try {
        oldPlayer.setVolume?.(0);
        oldPlayer.pauseVideo?.();
        oldPlayer.setPlaybackRate?.(1.0);
      } catch {}
    }

    // Promote incoming standby deck to primary active deck
    activeDeckIdxRef.current = newDeckIdx;
    setActiveDeckState(newDeckIdx);
    const newActivePlayer = decksRef.current[newDeckIdx];
    if (newActivePlayer) {
      window.__mctify_yt_player = newActivePlayer;
      try {
        if (wasDspBridge && dspIncomingTime > 0.2) {
          const curYt = newActivePlayer.getCurrentTime?.() || 0;
          if (Math.abs(curYt - dspIncomingTime) > 0.6) {
            newActivePlayer.seekTo?.(dspIncomingTime, true);
          }
        }
        if (isMutedRef.current) {
          newActivePlayer.mute?.();
        } else {
          newActivePlayer.unMute?.();
          newActivePlayer.setVolume?.(computeMasterCeilingVol());
        }
        newActivePlayer.setPlaybackRate?.(playbackRateRef.current || 1.0);
        const cur = newActivePlayer.getCurrentTime?.() || 0;
        const dur = newActivePlayer.getDuration?.() || 0;
        if (Number.isFinite(cur) && Number.isFinite(dur) && dur > 0) {
          onTimeUpdateRef.current?.(cur, dur);
        }
      } catch {}
    }

    endedVideoIdRef.current = '';
    onTransitionStateChangeRef.current?.(null);

    if (incomingVid) {
      onTransitionCompleteRef.current?.(incomingVid);
    }
  };

  const scheduleBackgroundPlaybackKick = (targetVid, deckIdx = activeDeckIdxRef.current) => {
    clearBackgroundKick();
    if (!isPlayingRef.current || !targetVid) return;

    const kick = (attempt) => {
      const player = decksRef.current[deckIdx];
      if (!player || !isPlayingRef.current || loadedVidByDeckRef.current[deckIdx] !== targetVid) return;
      try {
        const st = player.getPlayerState?.();
        if (st === window.YT?.PlayerState?.CUED || st === window.YT?.PlayerState?.PAUSED || st === -1) {
          player.playVideo?.();
        }
        if (st !== window.YT?.PlayerState?.PLAYING && attempt < 4) {
          backgroundKickTimerRef.current = setTimeout(() => kick(attempt + 1), attempt === 1 ? 350 : 750);
        }
      } catch {}
    };

    backgroundKickTimerRef.current = setTimeout(() => kick(1), 260);
  };

  const triggerEnded = (deckIdx) => {
    if (deckIdx !== activeDeckIdxRef.current) return;
    if (transitionStateRef.current.active) {
      completeActiveTransition();
      return;
    }
    const curVid = videoIdRef.current;
    if (!curVid || endedVideoIdRef.current === curVid) return;
    endedVideoIdRef.current = curVid;
    clearBackgroundKick();
    onEndedRef.current?.();
  };

  // Load YouTube IFrame API script and initialize BOTH Deck A and Deck B
  useEffect(() => {
    if (!window.YT) {
      const tag = document.createElement('script');
      tag.src = 'https://www.youtube.com/iframe_api';
      const firstScriptTag = document.getElementsByTagName('script')[0];
      if (firstScriptTag && firstScriptTag.parentNode) {
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
      } else {
        document.head.appendChild(tag);
      }
    }

    let cancelled = false;
    let readyCount = 0;

    const createDeck = (deckIdx, domId) => {
      if (decksRef.current[deckIdx]) return;
      try {
        decksRef.current[deckIdx] = new window.YT.Player(domId, {
          height: '100%',
          width: '100%',
          videoId: deckIdx === 0 ? videoIdRef.current || '' : '',
          playerVars: {
            autoplay: deckIdx === 0 ? 1 : 0,
            controls: 0,
            disablekb: 1,
            enablejsapi: 1,
            fs: 0,
            modestbranding: 1,
            playsinline: 1,
            rel: 0,
            origin: window.location.origin,
          },
          events: {
            onReady: (event) => {
              if (cancelled) return;
              try {
                event.target
                  .getIframe?.()
                  ?.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture');
              } catch {}

              deckReadyRef.current[deckIdx] = true;
              readyCount += 1;
              if (deckIdx === activeDeckIdxRef.current) {
                setIsReady(true);
                window.__mctify_yt_player = event.target;
                if (isMutedRef.current) {
                  event.target.mute();
                } else {
                  event.target.unMute();
                  event.target.setVolume(computeMasterCeilingVol());
                }
                if (videoIdRef.current) {
                  loadedVidByDeckRef.current[deckIdx] = videoIdRef.current;
                  const startAt =
                    typeof seekTimeRef.current === 'number' && seekTimeRef.current > 0
                      ? seekTimeRef.current
                      : 0;
                  if (isPlayingRef.current) {
                    try {
                      event.target.loadVideoById(videoIdRef.current, startAt);
                    } catch {
                      event.target.loadVideoById({
                        videoId: videoIdRef.current,
                        startSeconds: startAt,
                      });
                    }
                    event.target.playVideo?.();
                    scheduleBackgroundPlaybackKick(videoIdRef.current, deckIdx);
                  } else {
                    try {
                      event.target.cueVideoById(videoIdRef.current, startAt);
                    } catch {
                      event.target.cueVideoById({
                        videoId: videoIdRef.current,
                        startSeconds: startAt,
                      });
                    }
                  }
                }
              } else {
                try {
                  event.target.unMute();
                  event.target.setVolume(0);
                } catch {}
              }
            },
            onStateChange: (event) => {
              const st = event.data;
              const isPrimary = deckIdx === activeDeckIdxRef.current;
              const player = decksRef.current[deckIdx];

              if (st === window.YT.PlayerState.PLAYING) {
                if (isPrimary) {
                  clearBackgroundKick();
                  try {
                    const current = player?.getCurrentTime?.() || 0;
                    const dur = player?.getDuration?.() || 0;
                    const targetSec = seekTimeRef.current;
                    if (
                      typeof targetSec === 'number' &&
                      targetSec > 0 &&
                      Math.abs(current - targetSec) > 3
                    ) {
                      player?.seekTo?.(targetSec, true);
                      seekTimeRef.current = null;
                    }
                    if (dur > 0 && current < dur - 2) {
                      endedVideoIdRef.current = '';
                    }
                  } catch {}
                } else if (transitionStateRef.current.active) {
                  // Standby deck has started playing during active transition!
                  // Enforce introCue pin (e.g. 0:33) so it NEVER plays from 0:00!
                  const cfg = transitionConfigRef.current;
                  const introCue =
                    typeof transitionStateRef.current.forcedIntroCue === 'number'
                      ? transitionStateRef.current.forcedIntroCue
                      : Math.max(0, Number(cfg?.introOffsetSec) || 0);
                  if (introCue > 1) {
                    try {
                      const cur = player?.getCurrentTime?.() || 0;
                      if (cur < introCue - 1.5 || cur > introCue + 4.0) {
                        player?.seekTo?.(introCue, true);
                      }
                    } catch {}
                  }
                }
              } else if (st === window.YT.PlayerState.ENDED) {
                if (isPrimary) triggerEnded(deckIdx);
              } else if (st === window.YT.PlayerState.PAUSED) {
                if (isPrimary && !transitionStateRef.current.active) {
                  try {
                    const current = player?.getCurrentTime?.() || 0;
                    const dur = player?.getDuration?.() || 0;
                    if (dur > 5 && current >= dur - 1.5) {
                      triggerEnded(deckIdx);
                    } else if (isPlayingRef.current && videoIdRef.current && document.hidden) {
                      scheduleBackgroundPlaybackKick(videoIdRef.current, deckIdx);
                    }
                  } catch {}
                }
              } else if (st === window.YT.PlayerState.CUED || st === -1) {
                if (isPrimary && isPlayingRef.current && videoIdRef.current) {
                  try {
                    player?.playVideo?.();
                    scheduleBackgroundPlaybackKick(videoIdRef.current, deckIdx);
                  } catch {}
                }
              }
            },
            onError: (err) => {
              if (deckIdx === activeDeckIdxRef.current) {
                console.warn('YouTube primary deck error:', err);
                clearBackgroundKick();
                cancelActiveTransition(true);
                onErrorRef.current?.(err);
              } else if (transitionStateRef.current.active) {
                // Standby deck failed during transition -> complete cleanly via normal track advance
                completeActiveTransition();
              }
            },
          },
        });
      } catch (e) {
        console.warn(`Failed to initialize YouTube deck ${deckIdx}:`, e);
      }
    };

    const checkReady = () => {
      if (cancelled) return;
      if (window.YT && window.YT.Player) {
        createDeck(0, 'yt-music-engine-0');
        createDeck(1, 'yt-music-engine-1');
      } else {
        setTimeout(checkReady, 100);
      }
    };

    checkReady();

    return () => {
      cancelled = true;
      clearBackgroundKick();
      for (const p of decksRef.current) {
        if (p) {
          try {
            p.destroy();
          } catch {}
        }
      }
    };
  }, []);

  // Pre-cue nextVideoId on the standby deck so dual-deck overlap starts with 0ms buffering delay
  useEffect(() => {
    if (!isReady || !nextVideoId || nextVideoId === videoId) return;
    if (transitionStateRef.current.active) return;

    const standbyIdx = getStandbyDeckIdx();
    const standbyPlayer = decksRef.current[standbyIdx];
    if (!deckReadyRef.current[standbyIdx] || !standbyPlayer || typeof standbyPlayer.cueVideoById !== 'function') return;

    if (loadedVidByDeckRef.current[standbyIdx] !== nextVideoId) {
      loadedVidByDeckRef.current[standbyIdx] = nextVideoId;
      const introCue = Math.max(0, Number(transitionConfigRef.current?.introOffsetSec) || 0);
      try {
        standbyPlayer.setVolume?.(0);
        standbyPlayer.cueVideoById({
          videoId: nextVideoId,
          startSeconds: introCue,
        });
      } catch {
        try {
          standbyPlayer.cueVideoById(nextVideoId, introCue);
        } catch {}
      }
    }
  }, [nextVideoId, videoId, isReady]);

  // Sync primary videoId (detects seamless deck handoff when standby deck is already playing videoId!)
  useEffect(() => {
    if (!isReady) return;
    const activeIdx = activeDeckIdxRef.current;
    const activePlayer = decksRef.current[activeIdx];
    if (!activePlayer) return;

    if (!videoId) {
      cancelActiveTransition(true);
      loadedVidByDeckRef.current[activeIdx] = '';
      clearBackgroundKick();
      try {
        activePlayer.pauseVideo();
      } catch {}
      return;
    }

    // Case 1: Active deck ALREADY has this videoId loaded (e.g. just promoted from standby after dual-deck transition!)
    if (loadedVidByDeckRef.current[activeIdx] === videoId) {
      window.__mctify_yt_player = activePlayer;
      return;
    }

    // Case 2: Standby deck already has this videoId actively playing from an in-flight transition and user clicked Next early!
    const standbyIdx = getStandbyDeckIdx();
    if (
      transitionStateRef.current.active &&
      transitionStateRef.current.incomingVid === videoId &&
      loadedVidByDeckRef.current[standbyIdx] === videoId
    ) {
      completeActiveTransition();
      return;
    }

    // Case 3: Fresh track load on the primary active deck
    cancelActiveTransition(true);
    loadedVidByDeckRef.current[activeIdx] = videoId;
    window.__mctify_yt_player = activePlayer;

    try {
      const startAt =
        typeof seekTimeRef.current === 'number' && seekTimeRef.current > 0
          ? seekTimeRef.current
          : 0;
      if (!isMutedRef.current) {
        activePlayer.unMute?.();
        activePlayer.setVolume?.(computeMasterCeilingVol());
      }
      if (isPlayingRef.current) {
        try {
          activePlayer.loadVideoById(videoId, startAt);
        } catch {
          activePlayer.loadVideoById({ videoId, startSeconds: startAt });
        }
        activePlayer.playVideo?.();
        scheduleBackgroundPlaybackKick(videoId, activeIdx);
      } else {
        try {
          activePlayer.cueVideoById(videoId, startAt);
        } catch {
          activePlayer.cueVideoById({ videoId, startSeconds: startAt });
        }
      }
    } catch (e) {
      console.warn(e);
    }
  }, [videoId, isReady]);

  // Sync isPlaying across active deck (and standby deck if mid-transition)
  useEffect(() => {
    if (!isReady || !videoId) return;
    const activeIdx = activeDeckIdxRef.current;
    const activePlayer = decksRef.current[activeIdx];
    const standbyPlayer = getStandbyPlayer();
    if (!activePlayer) return;

    try {
      if (isPlaying) {
        if (loadedVidByDeckRef.current[activeIdx] === videoId) {
          const st = activePlayer.getPlayerState?.();
          if (st !== window.YT?.PlayerState?.PLAYING && st !== window.YT?.PlayerState?.BUFFERING) {
            activePlayer.playVideo();
          }
          scheduleBackgroundPlaybackKick(videoId, activeIdx);
        }
        if (transitionStateRef.current.active && standbyPlayer) {
          standbyPlayer.playVideo?.();
        }
      } else {
        clearBackgroundKick();
        activePlayer.pauseVideo();
        if (transitionStateRef.current.active && standbyPlayer) {
          standbyPlayer.pauseVideo?.();
        }
      }
    } catch (e) {
      console.warn(e);
    }
  }, [isPlaying, isReady, videoId]);

  // Sync volume, mute & dynamic equalizer acoustic loudness
  useEffect(() => {
    if (!isReady) return;
    const activePlayer = getActivePlayer();
    const standbyPlayer = getStandbyPlayer();
    if (!activePlayer) return;

    try {
      if (isMuted) {
        activePlayer.mute();
        standbyPlayer?.mute?.();
      } else {
        activePlayer.unMute();
        if (!transitionStateRef.current.active) {
          activePlayer.setVolume(computeMasterCeilingVol());
        }
      }
    } catch (e) {
      console.warn(e);
    }
  }, [volume, isMuted, isReady, eqSettings]);

  // Sync seekTime
  useEffect(() => {
    if (!isReady || seekTime === null || seekTime === undefined) return;
    const activePlayer = getActivePlayer();
    if (!activePlayer) return;
    try {
      if (transitionStateRef.current.active) {
        cancelActiveTransition(true);
      }
      activePlayer.seekTo(seekTime, true);
    } catch (e) {
      console.warn(e);
    }
  }, [seekTime, isReady]);

  // Sync audio/playback quality
  useEffect(() => {
    const applyQuality = (qId) => {
      if (!isReady) return;
      for (const p of decksRef.current) {
        if (!p) continue;
        try {
          if (qId === 'lossless') p.setPlaybackQuality?.('highres');
          else if (qId === 'high') p.setPlaybackQuality?.('hd1080');
          else if (qId === 'standard') p.setPlaybackQuality?.('medium');
          else if (qId === 'dataSaver') p.setPlaybackQuality?.('small');
        } catch {}
      }
    };

    applyQuality(audioQualityService.getQuality());
    return audioQualityService.subscribe((qId) => {
      applyQuality(qId);
    });
  }, [isReady, videoId]);

  // Sync user playback speed
  useEffect(() => {
    if (!isReady) return;
    const activePlayer = getActivePlayer();
    if (!activePlayer || transitionStateRef.current.active) return;
    try {
      activePlayer.setPlaybackRate?.(playbackRate);
    } catch {}
  }, [playbackRate, isReady]);

  // Begin Dual-Deck Crossfade Transition from activeDeck -> standbyDeck
  const startLiveDualDeckTransition = (currentSec, totalDurSec, forcedIntroCue = null) => {
    const nextVid = nextVideoIdRef.current;
    const curVid = videoIdRef.current;
    const cfg = transitionConfigRef.current || {};
    if (!nextVid || !curVid || nextVid === curVid || transitionStateRef.current.active) return;

    const fromIdx = activeDeckIdxRef.current;
    const toIdx = 1 - fromIdx;
    const fromPlayer = decksRef.current[fromIdx];
    const toPlayer = decksRef.current[toIdx];
    if (!fromPlayer || !toPlayer) return;

    const overlapSec = Math.max(2.0, Math.min(32.0, Number(cfg.durationSec) || 5.5));
    const introCue =
      typeof forcedIntroCue === 'number'
        ? Math.max(0, forcedIntroCue)
        : Math.max(0, Number(cfg.introOffsetSec) || 0);

    transitionStateRef.current = {
      active: true,
      fromDeck: fromIdx,
      toDeck: toIdx,
      outgoingVid: curVid,
      incomingVid: nextVid,
      forcedIntroCue: introCue,
      startedAtMs: performance.now(),
      startTrackTimeSec: currentSec,
      trackDurSec: totalDurSec,
      durationSec: overlapSec,
      progress: 0,
    };

    // Start standby deck at volume 0 and ramp up via evaluateTransitionEnvelope
    loadedVidByDeckRef.current[toIdx] = nextVid;
    try {
      if (isMutedRef.current) {
        toPlayer.mute?.();
      } else {
        toPlayer.unMute?.();
      }
      const isMashup = cfg?.volume === 'mashup';
      toPlayer.setVolume?.(isMashup ? computeMasterCeilingVol() : 0);
      const st = toPlayer.getPlayerState?.();
      if (st === window.YT?.PlayerState?.CUED) {
        toPlayer.playVideo?.();
        if (introCue > 0) {
          try { toPlayer.seekTo?.(introCue, true); } catch {}
        }
      } else {
        try {
          toPlayer.loadVideoById({ videoId: nextVid, startSeconds: introCue });
        } catch {
          toPlayer.loadVideoById?.(nextVid, introCue);
        }
      }
      // Multi-stage seek guards: guarantee standby deck stays strictly at introCue (e.g. 0:33) and never slips to 0:00
      if (introCue > 1) {
        [100, 300, 600, 1100].forEach((delayMs) => {
          setTimeout(() => {
            if (!transitionStateRef.current.active) return;
            try {
              const cur = toPlayer.getCurrentTime?.() || 0;
              if (cur < introCue - 1.5 || cur > introCue + 4.0) {
                toPlayer.seekTo?.(introCue, true);
              }
            } catch {}
          }, delayMs);
        });
      }
    } catch (e) {
      console.warn('[YouTubePlayer] Standby deck start warning:', e);
    }
  };

  // Poll currentTime, duration, and drive Dual-Deck Transition DSP Envelope at 100ms cadence
  useEffect(() => {
    if (!isReady) return;

    let worker = null;
    let fallbackTimer = null;

    const pollTime = () => {
      try {
        const activeIdx = activeDeckIdxRef.current;
        const activePlayer = decksRef.current[activeIdx];
        const activeVid = videoIdRef.current;
        if (!activePlayer || !activeVid) return;

        const playerState = activePlayer.getPlayerState?.();
        const isActuallyPlaying =
          isPlayingRef.current || playerState === window.YT?.PlayerState?.PLAYING;
        if (!isActuallyPlaying) return;

        const url = activePlayer.getVideoUrl?.() || '';
        if (url && url.includes('v=') && !url.includes(activeVid)) return;

        const current = activePlayer.getCurrentTime?.() || 0;
        const dur = activePlayer.getDuration?.() || 0;
        if (!Number.isFinite(current)) return;

        onTimeUpdateRef.current?.(current, Number.isFinite(dur) && dur > 0 ? dur : 0);

        if (!Number.isFinite(dur) || dur <= 0) return;

        const cfg = transitionConfigRef.current;
        const transitionEnabled = cfg?.enabled !== false && canAutoTransitionRef.current;
        const overlapSec = Math.max(2.0, Math.min(32.0, Number(cfg?.durationSec) || 5.5));
        const outroOffset = typeof cfg?.outroOffsetSec === 'number' ? cfg.outroOffsetSec : (Number(cfg?.outroOffsetSec) || 0);
        // Smart Active-Outro Skip: if user hasn't configured outroOffsetSec, start 4s before the dead tail
        const smartOutroLeadSec = cfg?.outroOffsetSec === undefined && dur > 60 ? 4.0 : 0.0;
        const triggerRemainingSec = Math.max(2.0, overlapSec + smartOutroLeadSec - outroOffset);
        const remainingSec = dur - current;

        // Honor explicit activeOutroSec / targetOutroSec (e.g. 150.0s = 2:30 for Ain't In LA)
        // so transition triggers at the designated musical phrase cue, NOT just at the tail end of the video!
        const explicitOutroCue =
          typeof cfg?.activeOutroSec === 'number' && cfg.activeOutroSec > 10
            ? cfg.activeOutroSec
            : (typeof cfg?.targetOutroSec === 'number' && cfg.targetOutroSec > 10
                ? cfg.targetOutroSec
                : null);

        const targetTriggerSec = explicitOutroCue != null
          ? explicitOutroCue
          : Math.max(2.0, dur - triggerRemainingSec);

        const isAtTriggerPoint = explicitOutroCue != null
          ? (current >= targetTriggerSec)
          : (current >= targetTriggerSec || (remainingSec <= triggerRemainingSec && remainingSec > 0.7));

        // Honor explicit introOffsetSec (e.g. +33s for Close To Me chorus drop)
        const effectiveIntroCueSec = typeof cfg?.introOffsetSec === 'number'
          ? Math.max(0, cfg.introOffsetSec)
          : (Number(cfg?.introOffsetSec) || 0);

        // 0. Pre-warm Standby Deck & Hybrid Web Audio DSP Bridge 16s before transition window
        const prewarmTriggerSec = Math.max(0, targetTriggerSec - 16.0);
        const shouldPrewarm =
          (current >= prewarmTriggerSec && current < targetTriggerSec) ||
          (remainingSec <= triggerRemainingSec + 16 && remainingSec > triggerRemainingSec);

        if (
          transitionEnabled &&
          !transitionStateRef.current.active &&
          dur > 15 &&
          shouldPrewarm &&
          nextVideoIdRef.current &&
          nextVideoIdRef.current !== activeVid
        ) {
          // Pre-cue standby deck in YouTube IFrame so it is already buffered at introCue!
          const standbyIdx = 1 - activeDeckIdxRef.current;
          const standbyPlayer = decksRef.current[standbyIdx];
          const nextVid = nextVideoIdRef.current;
          if (standbyPlayer && loadedVidByDeckRef.current[standbyIdx] !== nextVid) {
            loadedVidByDeckRef.current[standbyIdx] = nextVid;
            try {
              standbyPlayer.mute?.();
              standbyPlayer.setVolume?.(0);
              try {
                standbyPlayer.cueVideoById({ videoId: nextVid, startSeconds: effectiveIntroCueSec });
              } catch {
                standbyPlayer.cueVideoById?.(nextVid, effectiveIntroCueSec);
              }
            } catch {}
          }
          prewarmDspBridgeDecks(
            activeVid,
            nextVideoIdRef.current,
            targetTriggerSec,
            effectiveIntroCueSec
          );
        }

        // 1. Trigger Dual-Deck Overlap when entering the transition window
        if (
          transitionEnabled &&
          !transitionStateRef.current.active &&
          dur > overlapSec + 6 &&
          isAtTriggerPoint &&
          remainingSec > 0.7 &&
          nextVideoIdRef.current &&
          nextVideoIdRef.current !== activeVid
        ) {
          startLiveDualDeckTransition(current, dur, effectiveIntroCueSec);
          // Attempt seamless upgrade to Hybrid Web Audio DSP Bridge (real Bass Swap + Filter S-Curve!)
          tryActivateDspBridge(
            activeVid,
            nextVideoIdRef.current,
            current,
            effectiveIntroCueSec
          ).then((ok) => {
            if (ok && transitionStateRef.current.active) {
              // Mute both YouTube IFrames while Hybrid Web Audio DSP Engine drives real EQ/Filter audio!
              try { decksRef.current[transitionStateRef.current.fromDeck]?.setVolume?.(0); } catch {}
              try { decksRef.current[transitionStateRef.current.toDeck]?.setVolume?.(0); } catch {}
              transitionStateRef.current.standbyRolling = true;
            }
          });
        }

        // 2. Drive Dual-Deck Envelope during active transition
        if (transitionStateRef.current.active) {
          const tr = transitionStateRef.current;
          const fromPlayer = decksRef.current[tr.fromDeck];
          const toPlayer = decksRef.current[tr.toDeck];

          // Wait until standby deck is actually PLAYING before advancing the transition clock
          // so YouTube IFrame buffering never eats up the first 1-2s of the Mashup/Drop transition!
          const toState = toPlayer?.getPlayerState?.();
          const introCue =
            typeof tr.forcedIntroCue === 'number'
              ? tr.forcedIntroCue
              : Math.max(0, Number(cfg?.introOffsetSec) || 0);

          if (!tr.standbyRolling) {
            if (toState === window.YT?.PlayerState?.PLAYING) {
              const curStandby = toPlayer?.getCurrentTime?.() || 0;
              if (introCue > 1 && curStandby < introCue - 1.5) {
                try { toPlayer?.seekTo?.(introCue, true); } catch {}
                return;
              }
              tr.standbyRolling = true;
              tr.startedAtMs = performance.now();
            } else {
              // Ensure standby deck is nudged to play; timeout fallback after 2.2s
              if (
                toState === window.YT?.PlayerState?.CUED ||
                toState === window.YT?.PlayerState?.PAUSED ||
                toState === -1
              ) {
                try { toPlayer?.playVideo?.(); } catch {}
              }
              if (performance.now() - tr.startedAtMs > 2200) {
                if (introCue > 1) {
                  try { toPlayer?.seekTo?.(introCue, true); } catch {}
                }
                tr.standbyRolling = true;
                tr.startedAtMs = performance.now();
              } else {
                return;
              }
            }
          } else if (introCue > 1) {
            // In the first 2 seconds of transition, keep enforcing introCue if standby player lagged or reset
            const elapsed = (performance.now() - tr.startedAtMs) / 1000;
            if (elapsed < 2.0) {
              const curStandby = toPlayer?.getCurrentTime?.() || 0;
              if (curStandby < introCue - 1.5) {
                try { toPlayer?.seekTo?.(introCue, true); } catch {}
              }
            }
          }

          const elapsedSec = (performance.now() - tr.startedAtMs) / 1000;
          const p = Math.max(0, Math.min(1, elapsedSec / Math.max(1.5, tr.durationSec)));
          tr.progress = p;

          const env = evaluateTransitionEnvelope(p, cfg || {});
          const masterVol = computeMasterCeilingVol();

          // If Hybrid Web Audio DSP Bridge is active, drive REAL BiquadFilter Bass Swap, HPF S-Curve & Smooth Tempo Sync!
          const b = dspBridgeRef.current;
          if (b.active && b.ctx && b.outGain && b.inGain) {
            const now = b.ctx.currentTime;
            try {
              b.masterGain?.gain?.setTargetAtTime(
                isMutedRef.current ? 0 : Math.max(0, Math.min(1, volumeRef.current ?? 0.8)),
                now,
                0.04
              );
              b.outGain.gain.setTargetAtTime(env.outGain, now, 0.04);
              b.inGain.gain.setTargetAtTime(env.inGain, now, 0.04);
              b.outLow.gain.setTargetAtTime(env.outLowDb, now, 0.03);
              b.inLow.gain.setTargetAtTime(env.inLowDb, now, 0.03);
              b.outMid.gain.setTargetAtTime(env.outMidDb, now, 0.04);
              b.inMid.gain.setTargetAtTime(env.inMidDb, now, 0.04);
              if (env.outFilterType && b.outFilter.type !== env.outFilterType) {
                b.outFilter.type = env.outFilterType;
              }
              if (env.outFilterFreqHz) {
                b.outFilter.frequency.setTargetAtTime(env.outFilterFreqHz, now, 0.04);
                b.outFilter.Q.setTargetAtTime(env.outFilterQ || 1.0, now, 0.04);
              }
              if (env.inFilterType && b.inFilter.type !== env.inFilterType) {
                b.inFilter.type = env.inFilterType;
              }
              if (env.inFilterFreqHz) {
                b.inFilter.frequency.setTargetAtTime(env.inFilterFreqHz, now, 0.04);
              }
              if (b.outAudio && Number.isFinite(env.outPlaybackRate)) {
                b.outAudio.playbackRate = env.outPlaybackRate;
              }
              if (b.inAudio && Number.isFinite(env.inPlaybackRate)) {
                b.inAudio.playbackRate = env.inPlaybackRate;
              }
              // Keep YouTube IFrames silent while Web Audio DSP Bridge is outputting
              try { fromPlayer?.setVolume?.(0); } catch {}
              try { toPlayer?.setVolume?.(0); } catch {}
            } catch {}
          } else {
            let outVol = Math.round((env.effectiveOutIframeVol / 100) * masterVol);
            let inVol = Math.round((env.effectiveInIframeVol / 100) * masterVol);

            // Anti-clipping headroom balance when Overlap runs both decks at full energy (bypass in mashup so Ain't In LA & Close To Me keep 100% full volume without fade)
            if (cfg?.volume !== 'mashup' && outVol + inVol > masterVol * 1.35) {
              const scale = (masterVol * 1.35) / Math.max(1, outVol + inVol);
              outVol = Math.round(outVol * scale);
              inVol = Math.round(inVol * scale);
            }

            if (!isMutedRef.current) {
              try { fromPlayer?.setVolume?.(outVol); } catch {}
              try {
                toPlayer?.unMute?.();
                toPlayer?.setVolume?.(inVol);
              } catch {}
            }
          }

          // Apply gentle Tempo-Sync playback rate on YouTube IFrame when available
          if (cfg?.tempoSync !== false && !tr.tempoApplied) {
            tr.tempoApplied = true;
            try {
              const rates = toPlayer?.getAvailablePlaybackRates?.() || [];
              if (rates.length > 0 && env.inPlaybackRate && Math.abs(env.inPlaybackRate - 1) >= 0.04) {
                const nearest = rates.reduce((prev, curr) =>
                  Math.abs(curr - env.inPlaybackRate) < Math.abs(prev - env.inPlaybackRate) ? curr : prev
                );
                if (Math.abs(nearest - env.inPlaybackRate) <= 0.12) {
                  toPlayer?.setPlaybackRate?.(nearest);
                }
              }
            } catch {}
          }

          // Ensure standby deck stays rolling
          try {
            if (
              toState === window.YT?.PlayerState?.CUED ||
              toState === window.YT?.PlayerState?.PAUSED
            ) {
              toPlayer?.playVideo?.();
            }
          } catch {}

          onTransitionStateChangeRef.current?.({
            active: true,
            progress: p,
            bars: cfg?.bars || '2 bars',
            volume: cfg?.volume || 'overlap',
            eq: cfg?.eq || 'none',
            effect: cfg?.effect || 'high_pass',
            outVolPercent: Math.round(env.outGain * 100),
            inVolPercent: Math.round(env.inGain * 100),
          });

          if (p >= 1.0 || remainingSec <= 0.35) {
            try { toPlayer?.setPlaybackRate?.(playbackRateRef.current || 1.0); } catch {}
            completeActiveTransition();
            return;
          }
        } else if (dur > 5 && current >= dur - 0.6) {
          triggerEnded(activeIdx);
        }
      } catch {}
    };

    // Always run primary main-thread 100ms interval so CSP or worker policies can NEVER freeze the clock at 0:00!
    fallbackTimer = setInterval(pollTime, 100);
    pollTime();

    // Supplemental Web Worker tick for background-tab resilience when tab is hidden
    let blobUrl = null;
    try {
      const blob = new Blob(
        [
          `let t = null;
           self.onmessage = (e) => {
             if (e.data === 'start') {
               if (!t) t = setInterval(() => self.postMessage('tick'), 250);
             } else if (e.data === 'stop') {
               if (t) { clearInterval(t); t = null; }
             }
           };`,
        ],
        { type: 'application/javascript' }
      );
      blobUrl = URL.createObjectURL(blob);
      worker = new Worker(blobUrl);
      worker.onmessage = () => {
        if (document.hidden) pollTime();
      };
      worker.onerror = () => {
        try {
          worker?.terminate();
        } catch {}
        worker = null;
      };
      worker.postMessage('start');
    } catch {
      worker = null;
    }

    return () => {
      if (fallbackTimer) {
        clearInterval(fallbackTimer);
      }
      if (worker) {
        try {
          worker.postMessage('stop');
          worker.terminate();
        } catch {}
      }
      if (blobUrl) {
        try {
          URL.revokeObjectURL(blobUrl);
        } catch {}
      }
    };
  }, [isReady, isPlaying, videoId]);

  return (
    <>
      {/* Dual-Deck Containers for YouTube IFrames (320x240 prevents mobile browser background throttling) */}
      <div
        className={`fixed z-30 transition-all duration-300 ${
          showVideo
            ? 'bottom-28 right-6 w-80 h-48 rounded-2xl overflow-hidden shadow-2xl border border-white/20 bg-black'
            : 'fixed -left-[9999px] -top-[9999px] w-[320px] h-[240px] pointer-events-none'
        }`}
      >
        <div
          className={`w-full h-full ${
            activeDeckState === 0 ? 'block' : 'fixed -left-[9999px] -top-[9999px] w-[320px] h-[240px]'
          }`}
        >
          <div id="yt-music-engine-0" className="w-full h-full" />
        </div>
        <div
          className={`w-full h-full ${
            activeDeckState === 1 ? 'block' : 'fixed -left-[9999px] -top-[9999px] w-[320px] h-[240px]'
          }`}
        >
          <div id="yt-music-engine-1" className="w-full h-full" />
        </div>

        {showVideo && (
          <button
            onClick={() => setShowVideo(false)}
            className="absolute top-2 right-2 p-1.5 rounded-full bg-black/70 hover:bg-black text-white backdrop-blur-md transition-colors"
            title="Hide video"
          >
            <X className="w-4 h-4" />
          </button>
        )}
      </div>

      {/* Floating Toggle Button (Mini Player Video Switcher) */}
      {videoId && (
        <button
          onClick={() => setShowVideo(!showVideo)}
          className={`fixed bottom-28 right-6 z-20 p-2.5 rounded-2xl border backdrop-blur-md text-xs font-semibold flex items-center gap-1.5 shadow-xl transition-all ${
            showVideo
              ? 'opacity-0 pointer-events-none'
              : 'bg-white/10 hover:bg-white/20 text-white/70 hover:text-white border-white/15'
          }`}
          title="Toggle Music Video / Canvas"
        >
          <Tv className="w-4 h-4 text-emerald-400" />
          <span className="hidden sm:inline">Music Video</span>
        </button>
      )}
    </>
  );
}
