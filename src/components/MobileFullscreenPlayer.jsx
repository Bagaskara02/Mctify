import React, { useRef, useState, useEffect } from 'react';
import { audioQualityService } from '../services/audioQualityService';
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
  ListMusic,
  Sliders,
  Gauge,
  Moon
} from 'lucide-react';
import { DEFAULT_ARTWORK, cleanTrackTitle } from '../services/musicApi';
import { extractPaletteFromImage } from '../utils/colorExtractor';

// cleanTrackTitle imported from musicApi.js

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
  lyricsData = null,
  playbackRate = 1.0,
  onPlaybackRateChange,
  isSleepTimerActive = false,
  onOpenSleepTimer,
  onPlayPause,
  onPrev,
  onNext,
  onSeek,
  onToggleShuffle,
  onToggleRepeat,
  onToggleLike,
  onOpenLyrics,
  onOpenQueue,
  onOpenEqualizer,
  onOpenAudioQuality,
}) {
  const scrubberRef = useRef(null);
  const [isScrubbing, setIsScrubbing] = useState(false);
  const [scrubTime, setScrubTime] = useState(0);
  const [currentQuality, setCurrentQuality] = useState(() => audioQualityService.getQuality());
  const [palette, setPalette] = useState({ primary: '#182a44', secondary: '#121212' });

  useEffect(() => {
    if (!currentTrack?.artwork) return;
    let cancelled = false;
    extractPaletteFromImage(currentTrack.artwork).then((pal) => {
      if (!cancelled && pal?.primary) {
        setPalette(pal);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [currentTrack?.artwork]);

  useEffect(() => {
    return audioQualityService.subscribe((qId) => {
      setCurrentQuality(qId);
    });
  }, []);

  if (!isOpen || !currentTrack) return null;

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

  // Live calibrated lyric lines preview
  const lyricLines = lyricsData?.lines || [];
  const hasNonLatin = lyricLines.some((l) => l.hasRomanization || /[\uAC00-\uD7A3\u3040-\u309F\u30A0-\u30FF]/.test(l.text));
  const baseLatency = hasNonLatin ? 0.48 : 0.20;
  const effectiveLyricTime = Math.max(0, currentTime - baseLatency);
  let activeLyricIdx = -1;
  for (let i = 0; i < lyricLines.length; i++) {
    if (lyricLines[i].time <= effectiveLyricTime) {
      if (i === lyricLines.length - 1 || lyricLines[i + 1].time > effectiveLyricTime) {
        activeLyricIdx = i;
        break;
      }
    }
  }
  const activeLyric = activeLyricIdx !== -1 ? lyricLines[activeLyricIdx] : lyricLines[0];
  const nextLyric = activeLyricIdx !== -1 && activeLyricIdx + 1 < lyricLines.length ? lyricLines[activeLyricIdx + 1] : lyricLines[1];

  return (
    <div
      style={{
        background: `linear-gradient(180deg, ${palette.primary} 0%, ${palette.secondary} 54%, #09090b 100%)`,
      }}
      className="fixed inset-0 z-50 text-white flex flex-col overflow-y-auto no-scrollbar p-6 select-none animate-in fade-in slide-in-from-bottom duration-300 transition-colors duration-700"
    >
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

      {/* Big Cover Art with Play/Pause Scale Bounce */}
      <div className="my-auto flex justify-center py-4">
        <div
          onClick={onOpenLyrics}
          className={`relative aspect-square w-full max-w-[320px] rounded-2xl shadow-2xl overflow-hidden bg-[#242424] cursor-pointer transition-transform duration-300 ${
            isPlaying ? 'scale-100' : 'scale-[0.93]'
          }`}
        >
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
          <div className="flex items-center gap-2">
            <h2 className="text-xl sm:text-2xl font-black text-white truncate tracking-tight">
              {cleanTrackTitle(currentTrack.title)}
            </h2>
            {currentQuality === 'lossless' && (
              <span className="shrink-0 px-2 py-0.5 rounded text-[10px] font-black tracking-wider bg-gradient-to-r from-amber-400 to-yellow-400 text-black shadow-md">
                LOSSLESS
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 mt-0.5">
            <p className="text-sm sm:text-base text-[#b3b3b3] truncate">
              {currentTrack.artist}
            </p>
            {currentQuality === 'lossless' && (
              <span className="text-[10px] text-amber-300 font-mono font-semibold">
                • 24-bit/96kHz FLAC
              </span>
            )}
          </div>
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

      {/* Bottom Bar: Karaoke Lyrics, Equalizer, Audio Quality, Sleep Timer & Playback Speed */}
      <div className="grid grid-cols-5 gap-1.5 pb-2">
        <button
          onClick={() => {
            onClose();
            onOpenLyrics();
          }}
          className="py-2 px-1 rounded-xl bg-white/10 hover:bg-white/15 border border-white/10 flex flex-col items-center justify-center gap-1 active:scale-[0.98] transition-all"
        >
          <Mic2 className="w-4 h-4 text-[#00a3ff]" />
          <span className="text-[10px] font-bold text-white tracking-tight">
            Lirik
          </span>
        </button>

        <button
          onClick={() => {
            onClose();
            onOpenEqualizer?.();
          }}
          className="py-2 px-1 rounded-xl bg-white/10 hover:bg-white/15 border border-white/10 flex flex-col items-center justify-center gap-1 active:scale-[0.98] transition-all"
        >
          <Sliders className="w-4 h-4 text-[#00a3ff]" />
          <span className="text-[10px] font-bold text-white tracking-tight">
            Equalizer
          </span>
        </button>

        <button
          onClick={() => {
            onClose();
            onOpenAudioQuality?.();
          }}
          className={`py-2 px-1 rounded-xl border flex flex-col items-center justify-center gap-1 active:scale-[0.98] transition-all ${
            currentQuality === 'lossless'
              ? 'bg-amber-500/15 border-amber-400/40 text-amber-300 hover:bg-amber-500/20 shadow-sm shadow-amber-500/10'
              : 'bg-white/10 hover:bg-white/15 border-white/10 text-white'
          }`}
        >
          <Gauge className={`w-4 h-4 ${currentQuality === 'lossless' ? 'text-amber-400' : 'text-[#00a3ff]'}`} />
          <span className="text-[10px] font-bold tracking-tight">
            {currentQuality === 'lossless' ? 'Hi-Res FLAC' : 'Kualitas'}
          </span>
        </button>

        <button
          onClick={() => {
            onClose();
            onOpenSleepTimer?.();
          }}
          className={`py-2 px-1 rounded-xl border flex flex-col items-center justify-center gap-1 active:scale-[0.98] transition-all relative ${
            isSleepTimerActive
              ? 'bg-[#00a3ff]/20 text-[#00a3ff] border-[#00a3ff]/40'
              : 'bg-white/10 hover:bg-white/15 border-white/10 text-white'
          }`}
          title="Pengatur Waktu Tidur"
        >
          <Moon className={`w-4 h-4 ${isSleepTimerActive ? 'text-[#00a3ff]' : 'text-neutral-300'}`} />
          <span className="text-[10px] font-bold tracking-tight">
            Tidur
          </span>
          {isSleepTimerActive && (
            <span className="absolute top-1 right-1 w-1.5 h-1.5 rounded-full bg-[#00a3ff] animate-ping" />
          )}
        </button>

        <button
          onClick={() => {
            const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
            const curIdx = speeds.indexOf(playbackRate);
            const nextIdx = (curIdx === -1 ? 1 : curIdx + 1) % speeds.length;
            onPlaybackRateChange?.(speeds[nextIdx]);
          }}
          className={`py-2 px-1 rounded-xl border flex flex-col items-center justify-center gap-1 active:scale-[0.98] transition-all ${
            playbackRate !== 1.0
              ? 'bg-[#00a3ff]/20 text-[#00a3ff] border-[#00a3ff]/40'
              : 'bg-white/10 hover:bg-white/15 border-white/10 text-white'
          }`}
          title="Ganti Kecepatan Putar"
        >
          <span className="text-xs font-black text-[#00a3ff]">
            {playbackRate}x
          </span>
          <span className="text-[10px] font-bold text-neutral-300 tracking-tight">
            Speed
          </span>
        </button>
      </div>

      {/* Artwork-Tinted Inline Live Lyrics Preview Card (Matches Flutter FullscreenPlayer) */}
      <div
        onClick={() => {
          onClose();
          onOpenLyrics();
        }}
        style={{
          background: `linear-gradient(145deg, ${palette.primary}cc 0%, #14161be6 100%)`,
        }}
        className="mt-4 mb-2 p-4 rounded-2xl border border-white/15 shadow-xl cursor-pointer active:scale-[0.99] transition-all"
      >
        <div className="flex items-center justify-between mb-2.5">
          <div className="flex items-center gap-1.5">
            <Mic2 className="w-4 h-4 text-white" />
            <span className="text-xs font-black tracking-wide text-white">Lirik</span>
          </div>
          <span className="px-2.5 py-0.5 rounded-full bg-black/30 text-[10px] font-bold text-white">
            Layar Penuh ↗
          </span>
        </div>

        {lyricLines.length === 0 ? (
          <p className="text-sm font-bold text-white/75">
            Ketuk untuk membuka lirik sinkron &amp; mode karaoke penuh...
          </p>
        ) : (
          <div className="space-y-1">
            <p className="text-base font-black text-white leading-snug line-clamp-2">
              {activeLyric?.romanizedText || activeLyric?.text}
            </p>
            {nextLyric?.text && (
              <p className="text-sm font-bold text-white/55 leading-snug line-clamp-2">
                {nextLyric?.romanizedText || nextLyric.text}
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
