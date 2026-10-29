import React, { useEffect, useRef, useState } from 'react';
import { Tv, TvMinimal, X } from 'lucide-react';
import { webAudioEqualizer } from '../services/webAudioEqualizer';

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
  const endedTriggeredRef = useRef(false);
  const [isReady, setIsReady] = useState(false);
  const [showVideo, setShowVideo] = useState(false);
  const [eqSettings, setEqSettings] = useState(() => webAudioEqualizer.settings);

  // Subscribe to realtime Equalizer changes
  useEffect(() => {
    return webAudioEqualizer.subscribe((updated) => {
      setEqSettings(updated);
    });
  }, []);

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

    const checkReady = () => {
      if (window.YT && window.YT.Player) {
        initPlayer();
      } else {
        setTimeout(checkReady, 100);
      }
    };

    checkReady();

    return () => {
      if (playerRef.current) {
        try {
          playerRef.current.destroy();
        } catch {}
      }
    };
  }, []);

  const triggerEnded = () => {
    if (endedTriggeredRef.current) return;
    endedTriggeredRef.current = true;
    console.log('[YouTubePlayer] Track ended, auto-advancing to next song in queue');
    onEnded?.();
  };

  const initPlayer = () => {
    if (playerRef.current) return;
    try {
      playerRef.current = new window.YT.Player('yt-music-engine', {
        height: '100%',
        width: '100%',
        videoId: videoId || '',
        playerVars: {
          autoplay: 0,
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
            if (isMuted) {
              event.target.mute();
            } else {
              const multiplier = webAudioEqualizer.getLoudnessMultiplier(eqSettings);
              const effectiveVol = Math.max(0, Math.min(100, Math.round(volume * 100 * multiplier)));
              event.target.setVolume(effectiveVol);
            }
          },
          onStateChange: (event) => {
            if (event.data === window.YT.PlayerState.ENDED) {
              triggerEnded();
            } else if (event.data === window.YT.PlayerState.PAUSED) {
              // In background tabs, YouTube sometimes enters PAUSED at the very end of video instead of ENDED
              try {
                const current = playerRef.current?.getCurrentTime?.() || 0;
                const dur = playerRef.current?.getDuration?.() || 0;
                if (dur > 5 && current >= dur - 1.2) {
                  triggerEnded();
                }
              } catch {}
            }
          },
          onError: (err) => {
            console.warn('YouTube player error:', err);
            onError?.(err);
          },
        },
      });
    } catch (e) {
      console.warn('Failed to initialize YouTube player:', e);
    }
  };

  // Sync videoId
  useEffect(() => {
    endedTriggeredRef.current = false;
    if (isReady && playerRef.current) {
      if (!videoId) {
        // Track has no videoId yet (e.g. resolving). Stop old video immediately to prevent audio leak!
        try {
          playerRef.current.pauseVideo();
        } catch {}
        return;
      }
      try {
        const currentUrl = playerRef.current.getVideoUrl?.() || '';
        if (!currentUrl.includes(videoId)) {
          if (isPlaying) {
            playerRef.current.loadVideoById(videoId);
          } else {
            playerRef.current.cueVideoById(videoId);
          }
        }
      } catch (e) {
        console.warn(e);
      }
    }
  }, [videoId, isReady, isPlaying]);

  // Sync isPlaying
  useEffect(() => {
    if (!isReady || !playerRef.current || !videoId) return;
    try {
      if (isPlaying) {
        playerRef.current.playVideo();
      } else {
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
      endedTriggeredRef.current = false;
      playerRef.current.seekTo(seekTime, true);
    } catch (e) {
      console.warn(e);
    }
  }, [seekTime]);

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
        if (playerRef.current && isPlaying && videoId) {
          const current = playerRef.current.getCurrentTime?.() || 0;
          const dur = playerRef.current.getDuration?.() || 0;
          if (Number.isFinite(current) && Number.isFinite(dur) && dur > 0) {
            onTimeUpdate?.(current, dur);

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
             if (!t) t = setInterval(() => self.postMessage('tick'), 100);
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
      fallbackTimer = setInterval(pollTime, 100);
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
  }, [isReady, isPlaying, onTimeUpdate, videoId]);

  return (
    <>
      {/* Container for YouTube Iframe */}
      <div 
        className={`fixed z-30 transition-all duration-300 ${
          showVideo 
            ? 'bottom-28 right-6 w-80 h-48 rounded-2xl overflow-hidden shadow-2xl border border-white/20 bg-black' 
            : 'w-1 h-1 opacity-[0.001] pointer-events-none bottom-0 right-0'
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
