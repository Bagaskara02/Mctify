import React, { useRef, useState } from 'react';
import { 
  Play, 
  Pause, 
  SkipBack, 
  SkipForward, 
  Shuffle, 
  Repeat, 
  Mic2, 
  Volume2, 
  Volume1,
  VolumeX, 
  Heart,
  ListMusic,
  PanelRight,
  MoreHorizontal
} from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';

export default function PlayerBar({
  currentTrack,
  isPlaying,
  currentTime,
  duration,
  volume,
  isMuted,
  isShuffle,
  isRepeat,
  isLiked,
  isLyricsOpen,
  isQueueOpen,
  isRightSidebarOpen,
  onPlayPause,
  onPrev,
  onNext,
  onSeek,
  onVolumeChange,
  onToggleMute,
  onToggleShuffle,
  onToggleRepeat,
  onToggleLike,
  onToggleLyrics,
  onToggleQueue,
  onToggleRightSidebar,
  onTrackContextMenu,
}) {
  const progressBarRef = useRef(null);
  const volumeBarRef = useRef(null);

  // Scrubber drag state
  const [isScrubbing, setIsScrubbing] = useState(false);
  const [scrubTime, setScrubTime] = useState(0);
  const [isScrubberHovered, setIsScrubberHovered] = useState(false);

  // Volume drag state
  const [isVolumeScrubbing, setIsVolumeScrubbing] = useState(false);
  const [isVolumeHovered, setIsVolumeHovered] = useState(false);

  const formatTime = (seconds) => {
    if (!seconds || isNaN(seconds) || seconds < 0) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  // --- Scrubber Pointer Event Handlers (Prevents text selection, smooth dragging) ---
  const handleScrubberPointerDown = (e) => {
    e.preventDefault();
    if (!progressBarRef.current || !duration) return;
    const rect = progressBarRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    const newTime = ratio * duration;
    setIsScrubbing(true);
    setScrubTime(newTime);
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handleScrubberPointerMove = (e) => {
    if (!isScrubbing || !progressBarRef.current || !duration) return;
    const rect = progressBarRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    setScrubTime(ratio * duration);
  };

  const handleScrubberPointerUp = (e) => {
    if (!isScrubbing) return;
    setIsScrubbing(false);
    if (progressBarRef.current && duration) {
      const rect = progressBarRef.current.getBoundingClientRect();
      const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      onSeek(ratio * duration);
    }
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch (_) {}
  };

  // --- Volume Pointer Event Handlers ---
  const handleVolumePointerDown = (e) => {
    e.preventDefault();
    if (!volumeBarRef.current) return;
    const rect = volumeBarRef.current.getBoundingClientRect();
    const newVol = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    setIsVolumeScrubbing(true);
    onVolumeChange(newVol);
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handleVolumePointerMove = (e) => {
    if (!isVolumeScrubbing || !volumeBarRef.current) return;
    const rect = volumeBarRef.current.getBoundingClientRect();
    const newVol = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    onVolumeChange(newVol);
  };

  const handleVolumePointerUp = (e) => {
    if (!isVolumeScrubbing) return;
    setIsVolumeScrubbing(false);
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch (_) {}
  };

  const activeDisplayTime = isScrubbing ? scrubTime : currentTime;
  const progressPercent = duration > 0 ? Math.min(100, Math.max(0, (activeDisplayTime / duration) * 100)) : 0;
  const currentVolumePercent = isMuted ? 0 : Math.round(volume * 100);

  return (
    <footer className="h-20 bg-black border-t border-[#242424] px-4 md:px-6 flex items-center justify-between select-none z-40 relative text-white select-none">
      {/* Left Column: Track Info */}
      <div className="flex items-center gap-3.5 w-1/4 min-w-[180px] max-w-[320px]">
        {currentTrack ? (
          <>
            <div 
              className="relative group cursor-pointer flex-shrink-0" 
              onClick={onToggleLyrics}
              title="Buka Lirik Karaoke"
            >
              <img
                src={currentTrack.artwork || DEFAULT_ARTWORK}
                alt={currentTrack.title}
                onError={(e) => {
                  e.currentTarget.onerror = null;
                  e.currentTarget.src = DEFAULT_ARTWORK;
                }}
                className="w-14 h-14 rounded-md object-cover shadow-md bg-[#282828]"
              />
              <div className="absolute inset-0 bg-black/50 rounded-md opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity">
                <Mic2 className="w-5 h-5 text-[#00a3ff]" />
              </div>
            </div>

            <div className="min-w-0 pr-2">
              <h4 
                onClick={onToggleLyrics}
                className="font-bold text-sm truncate hover:underline cursor-pointer text-white tracking-tight"
                title={currentTrack.title}
              >
                {currentTrack.title}
              </h4>
              <p 
                className="text-xs text-[#b3b3b3] truncate hover:underline hover:text-white cursor-pointer mt-0.5"
                title={currentTrack.artist}
              >
                {currentTrack.artist}
              </p>
            </div>

            <div className="flex items-center gap-1 flex-shrink-0">
              <button
                onClick={() => onToggleLike(currentTrack)}
                className={`p-1.5 rounded-full transition-all active:scale-90 ${
                  isLiked 
                    ? 'text-[#00a3ff]' 
                    : 'text-[#b3b3b3] hover:text-white'
                }`}
                title={isLiked ? 'Hapus dari Favorit' : 'Simpan ke Favorit'}
              >
                <Heart className={`w-4 h-4 ${isLiked ? 'fill-current' : ''}`} />
              </button>

              <button
                onClick={(e) => onTrackContextMenu?.(e, currentTrack)}
                className="p-1.5 rounded-full text-[#b3b3b3] hover:text-white transition-colors"
                title="Lainnya"
              >
                <MoreHorizontal className="w-4 h-4" />
              </button>
            </div>
          </>
        ) : (
          <div className="flex items-center gap-3 text-neutral-500 text-xs">
            <div className="w-14 h-14 rounded-md bg-[#181818]" />
            <span>Pilih lagu untuk memutar</span>
          </div>
        )}
      </div>

      {/* Center Column: Controls & Timeline */}
      <div className="flex flex-col items-center gap-1.5 w-2/4 max-w-xl select-none">
        {/* Playback Buttons */}
        <div className="flex items-center gap-4 sm:gap-6">
          <button
            onClick={onToggleShuffle}
            className={`p-1.5 transition-colors ${
              isShuffle ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
            }`}
            title="Putar Acak"
          >
            <Shuffle className="w-4 h-4" />
          </button>

          <button
            onClick={onPrev}
            className="p-1.5 text-[#b3b3b3] hover:text-white active:scale-95 transition-all"
            title="Sebelumnya"
          >
            <SkipBack className="w-5 h-5 fill-current" />
          </button>

          <button
            onClick={onPlayPause}
            className="w-8 h-8 sm:w-9 sm:h-9 rounded-full bg-white hover:scale-105 active:scale-95 text-black flex items-center justify-center transition-all shadow-md"
            title={isPlaying ? 'Jeda' : 'Putar'}
          >
            {isPlaying ? (
              <Pause className="w-4 h-4 fill-black" />
            ) : (
              <Play className="w-4 h-4 fill-black ml-0.5" />
            )}
          </button>

          <button
            onClick={onNext}
            className="p-1.5 text-[#b3b3b3] hover:text-white active:scale-95 transition-all"
            title="Berikutnya"
          >
            <SkipForward className="w-5 h-5 fill-current" />
          </button>

          <button
            onClick={onToggleRepeat}
            className={`p-1.5 transition-colors ${
              isRepeat ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
            }`}
            title="Ulangi Lagu"
          >
            <Repeat className="w-4 h-4" />
          </button>
        </div>

        {/* Scrubber Progress Bar (Spotify Native Spec) */}
        <div className="w-full flex items-center gap-2 text-[11px] text-[#a7a7a7] select-none">
          <span className="w-10 text-right tabular-nums select-none pointer-events-none">
            {formatTime(activeDisplayTime)}
          </span>

          {/* Interactive Scrub Track Hitbox */}
          <div
            ref={progressBarRef}
            onPointerDown={handleScrubberPointerDown}
            onPointerMove={handleScrubberPointerMove}
            onPointerUp={handleScrubberPointerUp}
            onMouseEnter={() => setIsScrubberHovered(true)}
            onMouseLeave={() => setIsScrubberHovered(false)}
            className="relative flex-1 h-4 flex items-center cursor-pointer group select-none touch-none"
          >
            {/* Background Rail */}
            <div className="w-full h-1 group-hover:h-1.5 bg-[#4d4d4d] rounded-full transition-all duration-150 relative overflow-visible">
              {/* Filled Progress Bar */}
              <div
                className={`absolute left-0 top-0 bottom-0 rounded-full transition-colors ${
                  isScrubberHovered || isScrubbing ? 'bg-[#00a3ff]' : 'bg-white'
                }`}
                style={{ width: `${progressPercent}%` }}
              />

              {/* White Playhead Knob */}
              <div 
                className={`w-3 h-3 rounded-full bg-white shadow-[0_2px_4px_rgba(0,0,0,0.5)] absolute top-1/2 -translate-y-1/2 -translate-x-1/2 transition-opacity pointer-events-none ${
                  isScrubberHovered || isScrubbing ? 'opacity-100 scale-100' : 'opacity-0 scale-75'
                }`}
                style={{ left: `${progressPercent}%` }}
              />
            </div>
          </div>

          <span className="w-10 text-left tabular-nums select-none pointer-events-none">
            {formatTime(duration)}
          </span>
        </div>
      </div>

      {/* Right Column: Tools & Volume */}
      <div className="flex items-center justify-end gap-3 w-1/4 min-w-[180px] max-w-[320px]">
        {/* Beautiful Lyrics Trigger */}
        <button
          onClick={onToggleLyrics}
          className={`p-2 rounded-full transition-all active:scale-95 ${
            isLyricsOpen
              ? 'text-[#00a3ff]'
              : 'text-[#b3b3b3] hover:text-white'
          }`}
          title="Lirik Karaoke Bersinkron"
        >
          <Mic2 className="w-4 h-4" />
        </button>

        {/* Queue Drawer Trigger */}
        <button
          onClick={onToggleQueue}
          className={`p-2 rounded-full transition-all active:scale-95 ${
            isQueueOpen
              ? 'text-[#00a3ff]'
              : 'text-[#b3b3b3] hover:text-white'
          }`}
          title="Daftar Antrean Putar"
        >
          <ListMusic className="w-4 h-4" />
        </button>

        {/* Now Playing Right Sidebar Toggle */}
        <button
          onClick={onToggleRightSidebar}
          className={`hidden xl:block p-2 rounded-full transition-all active:scale-95 ${
            isRightSidebarOpen
              ? 'text-[#00a3ff]'
              : 'text-[#b3b3b3] hover:text-white'
          }`}
          title="Tampilan Sedang Diputar"
        >
          <PanelRight className="w-4 h-4" />
        </button>

        {/* Spotify Native Custom Volume Control */}
        <div className="flex items-center gap-2">
          <button
            onClick={onToggleMute}
            className="text-[#b3b3b3] hover:text-white transition-colors p-1"
            title={isMuted ? 'Batal Bisukan' : 'Bisukan'}
          >
            {isMuted || volume === 0 ? (
              <VolumeX className="w-4 h-4 text-rose-400" />
            ) : volume < 0.5 ? (
              <Volume1 className="w-4 h-4" />
            ) : (
              <Volume2 className="w-4 h-4" />
            )}
          </button>

          {/* Custom Volume Track */}
          <div
            ref={volumeBarRef}
            onPointerDown={handleVolumePointerDown}
            onPointerMove={handleVolumePointerMove}
            onPointerUp={handleVolumePointerUp}
            onMouseEnter={() => setIsVolumeHovered(true)}
            onMouseLeave={() => setIsVolumeHovered(false)}
            className="w-24 h-4 flex items-center cursor-pointer group select-none touch-none"
            title={`Volume ${currentVolumePercent}%`}
          >
            <div className="w-full h-1 group-hover:h-1.5 bg-[#4d4d4d] rounded-full transition-all relative">
              <div
                className={`absolute left-0 top-0 bottom-0 rounded-full transition-colors ${
                  isVolumeHovered || isVolumeScrubbing ? 'bg-[#00a3ff]' : 'bg-white'
                }`}
                style={{ width: `${currentVolumePercent}%` }}
              />
              <div 
                className={`w-3 h-3 rounded-full bg-white shadow-md absolute top-1/2 -translate-y-1/2 -translate-x-1/2 transition-opacity pointer-events-none ${
                  isVolumeHovered || isVolumeScrubbing ? 'opacity-100' : 'opacity-0'
                }`}
                style={{ left: `${currentVolumePercent}%` }}
              />
            </div>
          </div>
        </div>
      </div>
    </footer>
  );
}
