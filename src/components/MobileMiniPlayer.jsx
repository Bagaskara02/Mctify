import React from 'react';
import { Play, Pause, Heart, Mic2 } from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';

export default function MobileMiniPlayer({
  currentTrack,
  isPlaying,
  currentTime,
  duration,
  isLiked,
  onPlayPause,
  onToggleLike,
  onOpenFullscreen,
}) {
  if (!currentTrack) return null;

  const progressPercent = duration > 0 ? Math.min(100, Math.max(0, (currentTime / duration) * 100)) : 0;

  return (
    <div 
      onClick={onOpenFullscreen}
      className="md:hidden fixed bottom-[60px] left-2 right-2 h-14 bg-[#242424]/95 backdrop-blur-xl border border-white/10 rounded-lg shadow-2xl flex items-center justify-between px-2.5 z-40 select-none cursor-pointer group active:scale-[0.99] transition-all overflow-hidden"
    >
      {/* Bottom hairline progress bar indicator */}
      <div className="absolute bottom-0 left-0 right-0 h-[2.5px] bg-white/15">
        <div 
          className="h-full bg-[#00a3ff] transition-all duration-200" 
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
          <p className="text-[11px] text-[#b3b3b3] truncate mt-0.5">
            {currentTrack.artist}
          </p>
        </div>
      </div>

      {/* Right: Quick Actions */}
      <div className="flex items-center gap-1.5 flex-shrink-0" onClick={(e) => e.stopPropagation()}>
        <button
          onClick={() => onToggleLike(currentTrack)}
          className={`p-2 rounded-full transition-transform active:scale-90 ${
            isLiked ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
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
