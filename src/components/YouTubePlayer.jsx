import React, { useEffect, useRef, useState } from 'react';
import { Tv, TvMinimal, X } from 'lucide-react';

/**
 * YouTube Audio/Video Player Engine
 * Powers full-length song streaming (3 - 5+ minutes) like Lyra Music / Spotube.
 */
export default function YouTubePlayer({
  videoId,
  isPlaying,
  volume,
  isMuted,
  seekTime,
  onTimeUpdate,
  onEnded,
  onError,
}) {
  const playerRef = useRef(null);
  const [isReady, setIsReady] = useState(false);
  const [showVideo, setShowVideo] = useState(false);

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
              event.target.setVolume(volume * 100);
            }
          },
          onStateChange: (event) => {
            if (event.data === window.YT.PlayerState.ENDED) {
              onEnded?.();
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
    if (isReady && playerRef.current && videoId) {
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
  }, [videoId, isReady]);

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

  // Sync volume & mute
  useEffect(() => {
    if (!isReady || !playerRef.current) return;
    try {
      if (isMuted) {
        playerRef.current.mute();
      } else {
        playerRef.current.unMute();
        playerRef.current.setVolume(volume * 100);
      }
    } catch (e) {
      console.warn(e);
    }
  }, [volume, isMuted, isReady]);

  // Sync seekTime
  useEffect(() => {
    if (!isReady || !playerRef.current || seekTime === null || seekTime === undefined) return;
    try {
      playerRef.current.seekTo(seekTime, true);
    } catch (e) {
      console.warn(e);
    }
  }, [seekTime]);

  // Poll currentTime & duration continuously
  useEffect(() => {
    if (!isReady) return;
    const interval = setInterval(() => {
      try {
        if (playerRef.current && isPlaying) {
          const current = playerRef.current.getCurrentTime?.() || 0;
          const dur = playerRef.current.getDuration?.() || 0;
          if (Number.isFinite(current) && Number.isFinite(dur) && dur > 0) {
            onTimeUpdate?.(current, dur);
          }
        }
      } catch {}
    }, 250);

    return () => clearInterval(interval);
  }, [isReady, isPlaying, onTimeUpdate]);

  return (
    <>
      {/* Container for YouTube Iframe - Hidden or floating mini player */}
      <div 
        className={`fixed z-30 transition-all duration-300 ${
          showVideo 
            ? 'bottom-28 right-6 w-80 h-48 rounded-2xl overflow-hidden shadow-2xl border border-white/20 bg-black' 
            : 'w-1 h-1 opacity-0 pointer-events-none -left-96 bottom-0'
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
