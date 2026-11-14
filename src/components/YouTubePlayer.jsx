import React, { useEffect, useRef, useState } from 'react';
import { Tv, TvMinimal, X } from 'lucide-react';
import { webAudioEqualizer } from '../services/webAudioEqualizer';
import { audioQualityService } from '../services/audioQualityService';

/**
 * YouTube Audio/Video Player Engine
 * Powers full-length song streaming (3 - 5+ minutes) like Lyra Music / Spotube.
 */
export default function YouTubePlayer({
  videoId,
  isPlaying,
  volume,
  isMuted,
  playbackRate = 1.0,
  seekTime,
  onTimeUpdate,
  onEnded,
  onError,
}) {
  const playerRef = useRef(null);
  const endedVideoIdRef = useRef('');
  const loadedVideoIdRef = useRef('');
  const backgroundKickTimerRef = useRef(null);
  const [isReady, setIsReady] = useState(false);
  const [showVideo, setShowVideo] = useState(false);
  const [eqSettings, setEqSettings] = useState(() => webAudioEqualizer.settings);

  // Live refs prevent stale closures inside YT.Player callbacks on background tabs
  const videoIdRef = useRef(videoId);
  const isPlayingRef = useRef(isPlaying);
  const volumeRef = useRef(volume);
  const isMutedRef = useRef(isMuted);
  const eqSettingsRef = useRef(eqSettings);
  const playbackRateRef = useRef(playbackRate);
  const onTimeUpdateRef = useRef(onTimeUpdate);
  const onEndedRef = useRef(onEnded);
  const onErrorRef = useRef(onError);
  const seekTimeRef = useRef(seekTime);

  videoIdRef.current = videoId;
  isPlayingRef.current = isPlaying;
  volumeRef.current = volume;
  isMutedRef.current = isMuted;
  eqSettingsRef.current = eqSettings;
  playbackRateRef.current = playbackRate;
  onTimeUpdateRef.current = onTimeUpdate;
  onEndedRef.current = onEnded;
  onErrorRef.current = onError;
  seekTimeRef.current = seekTime;

  // Subscribe to realtime Equalizer changes
  useEffect(() => {
    return webAudioEqualizer.subscribe((updated) => {
      setEqSettings(updated);
    });
  }, []);

  // Global Autoplay Unblocker: on any user tap/click/key, unpause YouTube if marked isPlaying
  useEffect(() => {
    const unlockAutoplay = () => {
      if (isPlayingRef.current && playerRef.current) {
        try {
          const st = playerRef.current.getPlayerState?.();
          if (st !== window.YT?.PlayerState?.PLAYING && st !== window.YT?.PlayerState?.BUFFERING) {
            playerRef.current.unMute?.();
            playerRef.current.playVideo?.();
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

  const scheduleBackgroundPlaybackKick = (targetVid) => {
    clearBackgroundKick();
    if (!isPlayingRef.current || !targetVid) return;

    const kick = (attempt) => {
      if (!playerRef.current || !isPlayingRef.current || videoIdRef.current !== targetVid) return;
      try {
        const st = playerRef.current.getPlayerState?.();
        // YT States: -1=UNSTARTED, 0=ENDED, 1=PLAYING, 2=PAUSED, 3=BUFFERING, 5=CUED
        if (st === window.YT?.PlayerState?.CUED || st === window.YT?.PlayerState?.PAUSED || st === -1) {
          playerRef.current.playVideo?.();
        }
        if (st !== window.YT?.PlayerState?.PLAYING && attempt < 4) {
          backgroundKickTimerRef.current = setTimeout(() => kick(attempt + 1), attempt === 1 ? 350 : 750);
        }
      } catch {}
    };

    backgroundKickTimerRef.current = setTimeout(() => kick(1), 280);
  };

  // Load YouTube IFrame API script once
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
    const checkReady = () => {
      if (cancelled) return;
      if (window.YT && window.YT.Player) {
        initPlayer();
      } else {
        setTimeout(checkReady, 100);
      }
    };

    checkReady();

    return () => {
      cancelled = true;
      clearBackgroundKick();
      if (playerRef.current) {
        try {
          playerRef.current.destroy();
        } catch {}
      }
    };
  }, []);

  const triggerEnded = () => {
    const curVid = videoIdRef.current;
    if (!curVid || endedVideoIdRef.current === curVid) return;
    endedVideoIdRef.current = curVid;
    clearBackgroundKick();
    console.log('[YouTubePlayer] Track ended, auto-advancing to next song in queue for:', curVid);
    onEndedRef.current?.();
  };

  const initPlayer = () => {
    if (playerRef.current) return;
    try {
      playerRef.current = new window.YT.Player('yt-music-engine', {
        height: '100%',
        width: '100%',
        videoId: videoIdRef.current || '',
        playerVars: {
          autoplay: 1,
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
            setIsReady(true);
            window.__mctify_yt_player = event.target;
            try {
              event.target.getIframe?.()?.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture');
            } catch {}
            if (isMutedRef.current) {
              event.target.mute();
            } else {
              event.target.unMute();
              const multiplier = webAudioEqualizer.getLoudnessMultiplier(eqSettingsRef.current);
              const effectiveVol = Math.max(1, Math.min(100, Math.round((volumeRef.current || 0.8) * 100 * multiplier)));
              event.target.setVolume(effectiveVol);
            }
            if (videoIdRef.current) {
              loadedVideoIdRef.current = videoIdRef.current;
              const startAt = typeof seekTimeRef.current === 'number' && seekTimeRef.current > 0 ? seekTimeRef.current : 0;
              if (isPlayingRef.current) {
                try {
                  event.target.loadVideoById(videoIdRef.current, startAt);
                } catch {
                  event.target.loadVideoById({ videoId: videoIdRef.current, startSeconds: startAt });
                }
                event.target.playVideo?.();
                scheduleBackgroundPlaybackKick(videoIdRef.current);
              } else {
                try {
                  event.target.cueVideoById(videoIdRef.current, startAt);
                } catch {
                  event.target.cueVideoById({ videoId: videoIdRef.current, startSeconds: startAt });
                }
              }
            }
          },
          onStateChange: (event) => {
            const st = event.data;
            if (st === window.YT.PlayerState.PLAYING) {
              clearBackgroundKick();
              try {
                const current = playerRef.current?.getCurrentTime?.() || 0;
                const dur = playerRef.current?.getDuration?.() || 0;
                const targetSec = seekTimeRef.current;
                if (typeof targetSec === 'number' && targetSec > 0 && Math.abs(current - targetSec) > 3) {
                  playerRef.current?.seekTo?.(targetSec, true);
                  seekTimeRef.current = null;
                }
                if (dur > 0 && current < dur - 2) {
                  endedVideoIdRef.current = '';
                }
              } catch {}
            } else if (st === window.YT.PlayerState.ENDED) {
              triggerEnded();
            } else if (st === window.YT.PlayerState.PAUSED) {
              // In background tabs, YouTube may enter PAUSED at track end OR pause CUED/next track
              try {
                const current = playerRef.current?.getCurrentTime?.() || 0;
                const dur = playerRef.current?.getDuration?.() || 0;
                if (dur > 5 && current >= dur - 1.5) {
                  triggerEnded();
                } else if (isPlayingRef.current && videoIdRef.current && document.hidden) {
                  scheduleBackgroundPlaybackKick(videoIdRef.current);
                }
              } catch {}
            } else if (st === window.YT.PlayerState.CUED || st === -1) {
              // Critical for background tabs: kick CUED/UNSTARTED immediately into PLAYING
              if (isPlayingRef.current && videoIdRef.current) {
                try {
                  playerRef.current?.playVideo?.();
                  scheduleBackgroundPlaybackKick(videoIdRef.current);
                } catch {}
              }
            }
          },
          onError: (err) => {
            console.warn('YouTube player error:', err);
            clearBackgroundKick();
            onErrorRef.current?.(err);
          },
        },
      });
    } catch (e) {
      console.warn('Failed to initialize YouTube player:', e);
    }
  };

  // Sync videoId (single atomic load/cue without conflicting immediate playVideo call)
  useEffect(() => {
    if (!isReady || !playerRef.current) return;

    if (!videoId) {
      loadedVideoIdRef.current = '';
      clearBackgroundKick();
      try {
        playerRef.current.pauseVideo();
      } catch {}
      return;
    }

    if (loadedVideoIdRef.current !== videoId) {
      loadedVideoIdRef.current = videoId;
      try {
        const startAt = typeof seekTimeRef.current === 'number' && seekTimeRef.current > 0 ? seekTimeRef.current : 0;
        if (isPlayingRef.current) {
          try {
            playerRef.current.loadVideoById(videoId, startAt);
          } catch {
            playerRef.current.loadVideoById({
              videoId: videoId,
              startSeconds: startAt,
            });
          }
          playerRef.current.unMute?.();
          playerRef.current.playVideo?.();
          scheduleBackgroundPlaybackKick(videoId);
        } else {
          try {
            playerRef.current.cueVideoById(videoId, startAt);
          } catch {
            playerRef.current.cueVideoById({
              videoId: videoId,
              startSeconds: startAt,
            });
          }
        }
      } catch (e) {
        console.warn(e);
      }
    }
  }, [videoId, isReady]);

  // Sync isPlaying cleanly without clobbering an in-flight loadVideoById on track switch
  useEffect(() => {
    if (!isReady || !playerRef.current || !videoId) return;
    try {
      if (isPlaying) {
        if (loadedVideoIdRef.current === videoId) {
          const st = playerRef.current.getPlayerState?.();
          if (st !== window.YT?.PlayerState?.PLAYING && st !== window.YT?.PlayerState?.BUFFERING) {
            playerRef.current.playVideo();
          }
          scheduleBackgroundPlaybackKick(videoId);
        }
      } else {
        clearBackgroundKick();
        playerRef.current.pauseVideo();
      }
    } catch (e) {
      console.warn(e);
    }
  }, [isPlaying, isReady, videoId]);

  // Sync volume, mute & dynamic equalizer acoustic loudness
  useEffect(() => {
    if (!isReady || !playerRef.current) return;
    try {
      if (isMuted) {
        playerRef.current.mute();
      } else {
        playerRef.current.unMute();
        const multiplier = webAudioEqualizer.getLoudnessMultiplier(eqSettings);
        const effectiveVol = Math.max(0, Math.min(100, Math.round(volume * 100 * multiplier)));
        playerRef.current.setVolume(effectiveVol);
      }
    } catch (e) {
      console.warn(e);
    }
  }, [volume, isMuted, isReady, eqSettings]);

  // Sync seekTime
  useEffect(() => {
    if (!isReady || !playerRef.current || seekTime === null || seekTime === undefined) return;
    try {
      playerRef.current.seekTo(seekTime, true);
    } catch (e) {
      console.warn(e);
    }
  }, [seekTime, isReady]);

  // Sync audio/playback quality (Hi-Res Lossless, High, Standard, Data Saver)
  useEffect(() => {
    const applyQuality = (qId) => {
      if (!isReady || !playerRef.current) return;
      try {
        if (qId === 'lossless') {
          playerRef.current.setPlaybackQuality?.('highres');
        } else if (qId === 'high') {
          playerRef.current.setPlaybackQuality?.('hd1080');
        } else if (qId === 'standard') {
          playerRef.current.setPlaybackQuality?.('medium');
        } else if (qId === 'dataSaver') {
          playerRef.current.setPlaybackQuality?.('small');
        }
      } catch (e) {
        console.warn('Failed to set playback quality:', e);
      }
    };

    applyQuality(audioQualityService.getQuality());
    return audioQualityService.subscribe((qId) => {
      applyQuality(qId);
    });
  }, [isReady, videoId]);

  // Sync playback speed (0.75x, 1.0x, 1.25x, 1.5x, 2.0x)
  useEffect(() => {
    if (!isReady || !playerRef.current) return;
    try {
      playerRef.current.setPlaybackRate?.(playbackRate);
    } catch (e) {
      console.warn('Failed to set playback rate:', e);
    }
  }, [playbackRate, isReady]);

  // Poll currentTime & duration smoothly with Web Worker (exempt from background tab timer throttling)
  useEffect(() => {
    if (!isReady) return;

    let worker = null;
    let fallbackTimer = null;

    const pollTime = () => {
      try {
        const activeVid = videoIdRef.current;
        if (playerRef.current && isPlayingRef.current && activeVid) {
          // Guard against reading previous song's timestamp while player transitions to activeVid
          const url = playerRef.current.getVideoUrl?.() || '';
          if (url && !url.includes(activeVid)) return;

          const current = playerRef.current.getCurrentTime?.() || 0;
          const dur = playerRef.current.getDuration?.() || 0;
          if (Number.isFinite(current) && Number.isFinite(dur) && dur > 0) {
            onTimeUpdateRef.current?.(current, dur);

            // True end of track trigger (strictly at the end of track)
            if (dur > 5 && current >= dur - 0.6) {
              triggerEnded();
            }
          }
        }
      } catch {}
    };

    try {
      const blob = new Blob([
        `let t = null;
         self.onmessage = (e) => {
           if (e.data === 'start') {
             if (!t) t = setInterval(() => self.postMessage('tick'), 150);
           } else if (e.data === 'stop') {
             if (t) { clearInterval(t); t = null; }
           }
         };`
      ], { type: 'application/javascript' });
      const blobUrl = URL.createObjectURL(blob);
      worker = new Worker(blobUrl);
      worker.onmessage = () => pollTime();
      worker.postMessage('start');
    } catch {
      fallbackTimer = setInterval(pollTime, 150);
    }

    return () => {
      if (worker) {
        try {
          worker.postMessage('stop');
          worker.terminate();
        } catch {}
      }
      if (fallbackTimer) {
        clearInterval(fallbackTimer);
      }
    };
  }, [isReady, isPlaying, videoId]);

  return (
    <>
      {/* Container for YouTube Iframe (Proper 320x240 dimensions prevent mobile browser background throttling) */}
      <div 
        className={`fixed z-30 transition-all duration-300 ${
          showVideo 
            ? 'bottom-28 right-6 w-80 h-48 rounded-2xl overflow-hidden shadow-2xl border border-white/20 bg-black' 
            : 'fixed -left-[9999px] -top-[9999px] w-[320px] h-[240px] pointer-events-none'
        }`}
      >
        <div id="yt-music-engine" className="w-full h-full" />
        
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
