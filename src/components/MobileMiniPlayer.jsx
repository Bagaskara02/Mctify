import React, { useRef, useState, useEffect } from 'react';
import { Play, Pause, Heart } from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';
import { extractPaletteFromImage } from '../utils/colorExtractor';

export default function MobileMiniPlayer({
  currentTrack,
  isPlaying,
  currentTime,
  duration,
  isLiked,
  onPlayPause,
  onToggleLike,
  onOpenFullscreen,
  onNext,
  onPrev,
}) {
  const touchStartX = useRef(null);
  const [tint, setTint] = useState('#1d2b3a');

  useEffect(() => {
    if (!currentTrack?.artwork) return;
    let cancelled = false;
    extractPaletteFromImage(currentTrack.artwork).then((pal) => {
      if (!cancelled && pal?.primary) {
        setTint(pal.primary);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [currentTrack?.artwork]);

  if (!currentTrack) return null;

  const progressPercent = duration > 0 ? Math.min(100, Math.max(0, (currentTime / duration) * 100)) : 0;

  const handleTouchStart = (e) => {
    touchStartX.current = e.touches[0].clientX;
  };

  const handleTouchEnd = (e) => {
    if (touchStartX.current === null) return;
    const diffX = e.changedTouches[0].clientX - touchStartX.current;
    touchStartX.current = null;

    if (diffX < -50) {
      onNext?.();
    } else if (diffX > 50) {
      onPrev?.();
    }
  };

  return (
    <div
      onClick={onOpenFullscreen}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
      style={{
        background: `linear-gradient(135deg, ${tint}f2 0%, #14161be8 100%)`,
      }}
      className="md:hidden fixed bottom-[60px] left-2 right-2 h-14 backdrop-blur-xl border border-white/10 rounded-xl shadow-2xl flex items-center justify-between px-2.5 z-40 select-none cursor-pointer group active:scale-[0.99] transition-all duration-500 overflow-hidden"
    >
      {/* Bottom hairline progress bar indicator */}
      <div className="absolute bottom-0 left-2 right-2 h-[2.5px] bg-white/15 rounded-full overflow-hidden">
        <div
          className="h-full bg-white transition-all duration-200"
          style={{ width: `${progressPercent}%` }}
        />
      </div>

      {/* Left: Artwork + Title & Artist */}
      <div className="flex items-center gap-2.5 min-w-0 flex-1 mr-2">
        <img
          src={currentTrack.artwork || DEFAULT_ARTWORK}
          alt={currentTrack.title}
          onError={(e) => {
            e.currentTarget.onerror = null;
            e.currentTarget.src = DEFAULT_ARTWORK;
          }}
          className="w-10 h-10 rounded-md object-cover shadow bg-black flex-shrink-0"
        />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-bold text-white truncate tracking-tight">
            {currentTrack.title}
          </p>
          <p className="text-[11px] text-white/75 truncate mt-0.5">
            {currentTrack.artist}
          </p>
        </div>
      </div>

      {/* Right: Quick Actions */}
      <div className="flex items-center gap-1.5 flex-shrink-0" onClick={(e) => e.stopPropagation()}>
        <button
          onClick={() => onToggleLike(currentTrack)}
          className={`p-2 rounded-full transition-transform active:scale-90 ${
            isLiked ? 'text-[#3B82F6]' : 'text-white/75 hover:text-white'
          }`}
          title={isLiked ? 'Disukai' : 'Sukai'}
        >
          <Heart className={`w-4 h-4 ${isLiked ? 'fill-current' : ''}`} />
        </button>

        <button
          onClick={onPlayPause}
          className="w-9 h-9 rounded-full bg-white hover:scale-105 active:scale-95 text-black flex items-center justify-center shadow-lg transition-transform"
          title={isPlaying ? 'Jeda' : 'Putar'}
        >
          {isPlaying ? (
            <Pause className="w-4 h-4 fill-black" />
          ) : (
            <Play className="w-4 h-4 fill-black ml-0.5" />
          )}
        </button>
      </div>
    </div>
  );
}
