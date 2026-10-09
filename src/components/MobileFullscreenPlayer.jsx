import React, { useRef, useState } from 'react';
import { 
  ChevronDown, 
  Play, 
  Pause, 
  SkipBack, 
  SkipForward, 
  Shuffle, 
  Repeat, 
  Repeat1, 
  Heart, 
  Mic2, 
  ListMusic 
} from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';

export default function MobileFullscreenPlayer({
  isOpen,
  onClose,
  currentTrack,
  isPlaying,
  currentTime,
  duration,
  isShuffle,
  isRepeat,
  repeatMode = 'off',
  isLiked,
  onPlayPause,
  onPrev,
  onNext,
  onSeek,
  onToggleShuffle,
  onToggleRepeat,
  onToggleLike,
  onOpenLyrics,
  onOpenQueue,
}) {
  if (!isOpen || !currentTrack) return null;

  const scrubberRef = useRef(null);
  const [isScrubbing, setIsScrubbing] = useState(false);
  const [scrubTime, setScrubTime] = useState(0);

  const formatTime = (seconds) => {
    if (!seconds || isNaN(seconds) || seconds < 0) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  const handlePointerDown = (e) => {
    e.preventDefault();
    if (!scrubberRef.current || !duration) return;
    const rect = scrubberRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    const newTime = ratio * duration;
    setIsScrubbing(true);
    setScrubTime(newTime);
    e.currentTarget.setPointerCapture(e.pointerId);
  };

  const handlePointerMove = (e) => {
    if (!isScrubbing || !scrubberRef.current || !duration) return;
    const rect = scrubberRef.current.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    setScrubTime(ratio * duration);
  };

  const handlePointerUp = (e) => {
    if (!isScrubbing) return;
    setIsScrubbing(false);
    if (scrubberRef.current && duration) {
      const rect = scrubberRef.current.getBoundingClientRect();
      const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      onSeek(ratio * duration);
    }
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch (_) {}
  };

  const activeDisplayTime = isScrubbing ? scrubTime : currentTime;
  const progressPercent = duration > 0 ? Math.min(100, Math.max(0, (activeDisplayTime / duration) * 100)) : 0;

  return (
    <div className="fixed inset-0 z-50 bg-gradient-to-b from-[#182a44] via-[#121212] to-[#000000] text-white flex flex-col justify-between p-6 select-none animate-in fade-in slide-in-from-bottom duration-300">
      {/* Top Header */}
      <div className="flex items-center justify-between">
        <button
          onClick={onClose}
          className="p-2 rounded-full hover:bg-white/10 text-white/80 active:scale-95 transition-transform"
        >
          <ChevronDown className="w-7 h-7" />
        </button>

        <div className="text-center">
          <p className="text-[10px] font-bold tracking-widest uppercase text-white/70">
            Sedang Memutar
          </p>
          <p className="text-xs font-semibold text-white truncate max-w-[200px]">
            {currentTrack.album || 'Koleksi Musik'}
          </p>
        </div>

        <button
          onClick={() => {
            onClose();
            onOpenQueue();
          }}
          className="p-2 rounded-full hover:bg-white/10 text-white/80 active:scale-95 transition-transform"
        >
          <ListMusic className="w-6 h-6" />
        </button>
      </div>

      {/* Big Cover Art */}
      <div className="my-auto flex justify-center py-4">
        <div className="relative aspect-square w-full max-w-[320px] rounded-2xl shadow-2xl overflow-hidden bg-[#242424]">
          <img
            src={currentTrack.artwork || DEFAULT_ARTWORK}
            alt={currentTrack.title}
            onError={(e) => {
              e.currentTarget.onerror = null;
              e.currentTarget.src = DEFAULT_ARTWORK;
            }}
            className="w-full h-full object-cover"
          />
        </div>
      </div>

      {/* Track Info & Like */}
      <div className="flex items-center justify-between mb-4">
        <div className="min-w-0 pr-4">
          <h2 className="text-xl sm:text-2xl font-black text-white truncate tracking-tight">
            {currentTrack.title}
          </h2>
          <p className="text-sm sm:text-base text-[#b3b3b3] truncate mt-0.5">
            {currentTrack.artist}
          </p>
        </div>

        <button
          onClick={() => onToggleLike(currentTrack)}
          className={`p-2 rounded-full active:scale-90 transition-transform ${
            isLiked ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
          }`}
        >
          <Heart className={`w-6 h-6 ${isLiked ? 'fill-current' : ''}`} />
        </button>
      </div>

      {/* Progress Bar & Timestamps */}
      <div className="mb-4">
        <div
          ref={scrubberRef}
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          className="relative h-6 flex items-center cursor-pointer select-none touch-none"
        >
          <div className="w-full h-1.5 bg-[#4d4d4d] rounded-full relative overflow-visible">
            <div
              className="absolute left-0 top-0 bottom-0 bg-[#00a3ff] rounded-full"
              style={{ width: `${progressPercent}%` }}
            />
            <div
              className="w-3.5 h-3.5 rounded-full bg-white shadow-md absolute top-1/2 -translate-y-1/2 -translate-x-1/2"
              style={{ left: `${progressPercent}%` }}
            />
          </div>
        </div>

        <div className="flex items-center justify-between text-xs text-[#b3b3b3] font-medium tabular-nums px-0.5">
          <span>{formatTime(activeDisplayTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>
      </div>

      {/* Playback Controls */}
      <div className="flex items-center justify-between px-2 mb-6">
        <button
          onClick={onToggleShuffle}
          className={`p-2 transition-colors ${
            isShuffle ? 'text-[#00a3ff]' : 'text-[#b3b3b3]'
          }`}
        >
          <Shuffle className="w-5 h-5" />
        </button>

        <button
          onClick={onPrev}
          className="p-2 text-white active:scale-95 transition-transform"
        >
          <SkipBack className="w-8 h-8 fill-current" />
        </button>

        <button
          onClick={onPlayPause}
          className="w-16 h-16 rounded-full bg-white text-black flex items-center justify-center shadow-xl active:scale-95 transition-transform"
        >
          {isPlaying ? (
            <Pause className="w-7 h-7 fill-black" />
          ) : (
            <Play className="w-7 h-7 fill-black ml-1" />
          )}
        </button>

        <button
          onClick={onNext}
          className="p-2 text-white active:scale-95 transition-transform"
        >
          <SkipForward className="w-8 h-8 fill-current" />
        </button>

        <button
          onClick={onToggleRepeat}
          className={`p-2 relative transition-colors ${
            (repeatMode !== 'off' || isRepeat) ? 'text-[#00a3ff]' : 'text-[#b3b3b3]'
          }`}
          title={
            repeatMode === 'one'
              ? 'Ulangi 1 Lagu'
              : (repeatMode === 'all' || isRepeat)
              ? 'Ulangi Semua'
              : 'Ulangi'
          }
        >
          {repeatMode === 'one' ? (
            <Repeat1 className="w-5 h-5" />
          ) : (
            <Repeat className="w-5 h-5" />
          )}
          {(repeatMode !== 'off' || isRepeat) && (
            <span className="w-1 h-1 bg-[#00a3ff] rounded-full absolute bottom-1 left-1/2 -translate-x-1/2" />
          )}
        </button>
      </div>

      {/* Bottom Bar: Karaoke Lyrics Button */}
      <div className="flex items-center justify-center pb-2">
        <button
          onClick={() => {
            onClose();
            onOpenLyrics();
          }}
          className="w-full py-3 px-5 rounded-2xl bg-white/10 hover:bg-white/15 border border-white/10 flex items-center justify-between active:scale-[0.98] transition-all"
        >
          <div className="flex items-center gap-2.5">
            <Mic2 className="w-5 h-5 text-[#00a3ff]" />
            <span className="text-xs font-bold text-white tracking-wide">
              Lirik Karaoke (Beautiful Lyrics)
            </span>
          </div>
          <span className="text-xs font-semibold text-[#00a3ff]">Buka</span>
        </button>
      </div>
    </div>
  );
}
