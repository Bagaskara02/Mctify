import React, { useEffect, useRef, useState } from 'react';
import { 
  X, 
  Maximize2, 
  Minimize2, 
  Music, 
  Type, 
  Clock, 
  Sparkles,
  RotateCcw,
  Minus,
  Plus
} from 'lucide-react';
import { extractPaletteFromImage } from '../utils/colorExtractor';
import { DEFAULT_ARTWORK } from '../services/musicApi';
import { lyricsService } from '../services/lyricsService';

/**
 * BeautifulLyrics Component
 * High-precision Karaoke Engine:
 * - Word-by-word syllable karaoke animation & vocal bounce
 * - Anticipatory vocal-onset lead compensation (~120ms)
 * - Fine-grain sync calibration (-0.5s to +0.5s) with per-track persistence
 * - Visual instrumental countdown & break indicators
 * - Dynamic mesh-gradient background
 * - Interactive click-to-seek by word or line
 */
export default function BeautifulLyrics({
  track,
  currentTime,
  duration,
  lyricsData,
  isLoadingLyrics,
  isPlaying,
  onSeek,
  onClose,
}) {
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [fontSize, setFontSize] = useState('large'); // 'normal' | 'large' | 'huge'
  const [syncOffset, setSyncOffset] = useState(0);
  const [palette, setPalette] = useState({ primary: '#00a3ff', secondary: '#2eb4ff', tertiary: '#0055b3' });
  const [autoScroll, setAutoScroll] = useState(true);
  const [userScrolled, setUserScrolled] = useState(false);

  const containerRef = useRef(null);
  const scrollTimeoutRef = useRef(null);
  const activeLineRef = useRef(null);

  const trackKey = track ? `${(track.artist || '').trim().toLowerCase()}:::${(track.title || '').trim().toLowerCase()}` : '';

  // Load persistent sync offset for current track
  useEffect(() => {
    if (trackKey) {
      const saved = lyricsService.getTrackSyncOffset(trackKey);
      setSyncOffset(saved);
    }
  }, [trackKey]);

  const updateSyncOffset = (delta) => {
    setSyncOffset(prev => {
      const next = Math.round((prev + delta) * 10) / 10;
      if (trackKey) {
        lyricsService.saveTrackSyncOffset(trackKey, next);
      }
      return next;
    });
  };

  const resetSyncOffset = () => {
    setSyncOffset(0);
    if (trackKey) {
      lyricsService.saveTrackSyncOffset(trackKey, 0);
    }
  };

  // Extract vibrant colors from album artwork
  useEffect(() => {
    if (track?.artwork) {
      extractPaletteFromImage(track.artwork).then(pal => {
        setPalette({
          primary: pal.primary || '#00a3ff',
          secondary: pal.secondary || '#2eb4ff',
          tertiary: '#0055b3',
        });
      });
    }
  }, [track?.artwork]);

  // Apply vocal anticipation lead (+0.12s) so the visual prompt aligns with natural vocal onset
  const effectiveTime = Math.max(0, currentTime + syncOffset + 0.12);
  const lines = lyricsData?.lines || [];

  // Determine active line index
  let activeIndex = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].time <= effectiveTime) {
      if (i === lines.length - 1 || lines[i + 1].time > effectiveTime) {
        activeIndex = i;
        break;
      }
    }
  }

  // Smooth autoscroll to keep active line centered
  useEffect(() => {
    if (!autoScroll || userScrolled || activeIndex === -1) return;

    if (activeLineRef.current && containerRef.current) {
      const container = containerRef.current;
      const element = activeLineRef.current;

      const elementTop = element.offsetTop;
      const elementHeight = element.offsetHeight;
      const containerHeight = container.offsetHeight;

      const targetScroll = elementTop - containerHeight * 0.35 + elementHeight / 2;

      container.scrollTo({
        top: Math.max(0, targetScroll),
        behavior: 'smooth',
      });
    }
  }, [activeIndex, autoScroll, userScrolled]);

  const handleUserScroll = () => {
    setUserScrolled(true);
    if (scrollTimeoutRef.current) clearTimeout(scrollTimeoutRef.current);
    scrollTimeoutRef.current = setTimeout(() => {
      setUserScrolled(false);
    }, 2500);
  };

  const getFontSizeClass = () => {
    switch (fontSize) {
      case 'normal':
        return 'text-xl sm:text-2xl md:text-3xl leading-relaxed';
      case 'huge':
        return 'text-3xl sm:text-4xl md:text-5xl leading-tight font-black';
      case 'large':
      default:
        return 'text-2xl sm:text-3xl md:text-4xl leading-snug font-extrabold';
    }
  };

  return (
    <div 
      className={`fixed inset-0 z-50 flex flex-col overflow-hidden transition-all duration-500 bg-[#06080e] ${
        isFullscreen ? 'p-0' : 'p-3 sm:p-6'
      }`}
    >
      {/* Dynamic Ambient Background - Electric Azure & Album Mesh Glow Canvas */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none select-none">
        {/* Floating Electric Azure Orb 1 */}
        <div 
          className="absolute -top-[15%] -left-[10%] w-[65vw] h-[65vw] rounded-full blur-[130px] opacity-40 animate-drift-1 transition-colors duration-1000"
          style={{ background: `radial-gradient(circle, ${palette.primary} 0%, transparent 70%)` }}
        />
        {/* Floating Cyan/Blue Orb 2 */}
        <div 
          className="absolute top-[35%] -right-[15%] w-[60vw] h-[60vw] rounded-full blur-[140px] opacity-35 animate-drift-2 transition-colors duration-1000"
          style={{ background: `radial-gradient(circle, #00a3ff 0%, transparent 70%)` }}
        />
        {/* Floating Royal Navy Orb 3 */}
        <div 
          className="absolute -bottom-[20%] left-[25%] w-[70vw] h-[70vw] rounded-full blur-[150px] opacity-30 animate-drift-3 transition-colors duration-1000"
          style={{ background: `radial-gradient(circle, ${palette.tertiary} 0%, transparent 70%)` }}
        />
        {/* Darkening veil for high-contrast typography */}
        <div className="absolute inset-0 bg-black/60 backdrop-blur-[70px]" />
      </div>

      {/* Main Container */}
      <div className="relative z-10 flex flex-col h-full w-full max-w-7xl mx-auto">
        {/* Top Header Bar */}
        <header className="flex items-center justify-between px-4 py-3 sm:py-4 border border-white/10 backdrop-blur-xl rounded-2xl bg-white/[0.04] mb-3 shadow-xl">
          {/* Song Info */}
          <div className="flex items-center gap-3 min-w-0">
            <img 
              src={track?.artwork || DEFAULT_ARTWORK} 
              alt={track?.title} 
              onError={(e) => {
                e.currentTarget.onerror = null;
                e.currentTarget.src = DEFAULT_ARTWORK;
              }}
              className="w-12 h-12 sm:w-14 sm:h-14 rounded-2xl object-cover shadow-xl border border-white/10 bg-neutral-900"
            />
            <div className="min-w-0">
              <h2 className="text-white font-bold text-base sm:text-lg truncate tracking-tight">
                {track?.title || 'No Track Selected'}
              </h2>
              <p className="text-neutral-400 text-xs sm:text-sm truncate">
                {track?.artist || 'Unknown Artist'} • {track?.album || ''}
              </p>
            </div>
          </div>

          {/* Controls: Offset, Font size, Fullscreen, Close */}
          <div className="flex items-center gap-2 sm:gap-3">
            {/* Sync Tuner & Calibration Widget */}
            <div className="flex items-center gap-1 sm:gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-xl bg-white/5 border border-white/10 text-xs text-white/80">
              <Clock className="w-3.5 h-3.5 text-[#00a3ff]" />
              <span className="hidden sm:inline text-white/60 text-[11px]">Sync:</span>
              <span className={`font-mono font-bold tabular-nums text-xs ${syncOffset === 0 ? 'text-[#00a3ff]' : syncOffset > 0 ? 'text-amber-400' : 'text-emerald-400'}`}>
                {syncOffset === 0 ? 'Tepat' : syncOffset > 0 ? `+${syncOffset.toFixed(1)}s` : `${syncOffset.toFixed(1)}s`}
              </span>

              {/* -0.5s / -0.1s */}
              <button 
                onClick={() => updateSyncOffset(-0.5)}
                className="hidden lg:inline-block px-1.5 py-0.5 rounded hover:bg-white/10 text-white/70 active:scale-95 text-[11px]"
                title="Percepat lirik (-0.5s)"
              >
                -0.5
              </button>
              <button 
                onClick={() => updateSyncOffset(-0.1)}
                className="px-1.5 py-0.5 rounded hover:bg-white/10 text-white/90 active:scale-95 font-bold"
                title="Percepat lirik (-0.1s)"
              >
                <Minus className="w-3 h-3" />
              </button>

              {syncOffset !== 0 && (
                <button 
                  onClick={resetSyncOffset}
                  className="p-1 rounded hover:bg-white/10 text-white/50 hover:text-white"
                  title="Reset kalibrasi sync ke 0.0s"
                >
                  <RotateCcw className="w-2.5 h-2.5" />
                </button>
              )}

              {/* +0.1s / +0.5s */}
              <button 
                onClick={() => updateSyncOffset(0.1)}
                className="px-1.5 py-0.5 rounded hover:bg-white/10 text-white/90 active:scale-95 font-bold"
                title="Tunda lirik (+0.1s)"
              >
                <Plus className="w-3 h-3" />
              </button>
              <button 
                onClick={() => updateSyncOffset(0.5)}
                className="hidden lg:inline-block px-1.5 py-0.5 rounded hover:bg-white/10 text-white/70 active:scale-95 text-[11px]"
                title="Tunda lirik (+0.5s)"
              >
                +0.5
              </button>
            </div>

            {/* Font Size Toggle */}
            <div className="hidden sm:flex items-center gap-1 px-2 py-1 rounded-xl bg-white/5 border border-white/10 text-xs">
              <Type className="w-3.5 h-3.5 text-white/50 ml-1" />
              {['normal', 'large', 'huge'].map((size) => (
                <button
                  key={size}
                  onClick={() => setFontSize(size)}
                  className={`px-2 py-1 rounded-lg capitalize transition-all ${
                    fontSize === size 
                      ? 'bg-[#00a3ff] text-black font-bold shadow-md shadow-[#00a3ff]/30' 
                      : 'text-white/50 hover:text-white/80'
                  }`}
                >
                  {size}
                </button>
              ))}
            </div>

            {/* Fullscreen Button */}
            <button
              onClick={() => setIsFullscreen(!isFullscreen)}
              className="p-2 sm:p-2.5 rounded-xl bg-white/5 hover:bg-white/10 text-white/80 hover:text-white border border-white/10 transition-all active:scale-95"
              title={isFullscreen ? 'Exit Fullscreen' : 'Cinema Fullscreen'}
            >
              {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
            </button>

            {/* Close Button */}
            <button
              onClick={onClose}
              className="p-2 sm:p-2.5 rounded-xl bg-white/10 hover:bg-white/20 text-white border border-white/20 transition-all active:scale-95"
              title="Close Lyrics"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </header>

        {/* Content Body */}
        <div className="relative flex-1 grid grid-cols-1 lg:grid-cols-12 gap-6 min-h-0 overflow-hidden">
          {/* Left Column: Artwork Hero (Apple Music Cinema Style) */}
          <div className="hidden lg:flex lg:col-span-4 flex-col justify-between p-8 rounded-3xl bg-white/[0.03] border border-white/10 overflow-hidden">
            <div className="flex flex-col items-center text-center my-auto">
              <div className="relative group">
                <img
                  src={track?.artwork || DEFAULT_ARTWORK} 
                  alt={track?.title} 
                  onError={(e) => {
                    e.currentTarget.onerror = null;
                    e.currentTarget.src = DEFAULT_ARTWORK;
                  }}
                  className="w-72 h-72 xl:w-80 xl:h-80 rounded-3xl object-cover shadow-2xl border border-white/15 transition-transform duration-700 group-hover:scale-105 bg-neutral-900"
                  style={{
                    boxShadow: `0 25px 60px -15px ${palette.primary}77`,
                  }}
                />
                {isPlaying && (
                  <div className="absolute bottom-4 right-4 px-3.5 py-1.5 rounded-full bg-black/75 backdrop-blur-md border border-[#00a3ff]/40 flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full bg-[#00a3ff] animate-ping" />
                    <span className="text-xs font-semibold text-[#00a3ff]">Karaoke Akurat</span>
                  </div>
                )}
              </div>

              <div className="mt-8 max-w-xs">
                <h1 className="text-white text-2xl font-black tracking-tight line-clamp-2">
                  {track?.title}
                </h1>
                <p className="text-neutral-400 text-sm font-semibold mt-1">
                  {track?.artist}
                </p>
                <p className="text-neutral-500 text-xs mt-0.5">
                  {track?.album}
                </p>
              </div>
            </div>

            <div className="pt-4 border-t border-white/10 flex items-center justify-between text-xs text-neutral-400">
              <span className="flex items-center gap-1.5 text-[#00a3ff] font-medium">
                <Sparkles className="w-3.5 h-3.5 text-[#00a3ff]" />
                Lirik Sinkron & Karaoke
              </span>
              <span>Klik lirik untuk melompat</span>
            </div>
          </div>

          {/* Right Column: Dynamic Syllable Karaoke Lines */}
          <div 
            ref={containerRef}
            onScroll={handleUserScroll}
            className="col-span-1 lg:col-span-8 overflow-y-auto px-4 sm:px-8 pt-8 pb-36 scroll-smooth relative no-scrollbar"
          >
            {isLoadingLyrics ? (
              <div className="h-full flex flex-col items-center justify-center gap-4 text-white/50">
                <div className="w-10 h-10 border-4 border-white/20 border-t-[#00a3ff] rounded-full animate-spin" />
                <p className="text-sm font-medium animate-pulse">Menghubungkan lirik sinkron durasi akurat...</p>
              </div>
            ) : lines.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center text-center p-8 space-y-4 text-white/40">
                <Music className="w-16 h-16 opacity-30 stroke-[1.5]" />
                <div className="space-y-1">
                  <h3 className="text-xl font-bold text-white">Lirik Belum Tersedia</h3>
                  <p className="text-sm max-w-md">
                    Lirik bersinkronisasi untuk lagu ini sedang dalam proses antrean indeks LRCLIB.
                  </p>
                </div>
              </div>
            ) : (
              <div className="space-y-8 sm:space-y-10 py-24 select-none">
                {lines.map((line, idx) => {
                  const isActive = idx === activeIndex;
                  const isPast = idx < activeIndex;

                  // Instrumental break indicator
                  if (line.isInstrumental) {
                    return (
                      <div 
                        key={line.id || idx}
                        ref={isActive ? activeLineRef : null}
                        className={`transition-all duration-300 py-3 flex items-center gap-3 ${
                          isActive ? 'text-[#00a3ff] opacity-100 scale-100' : 'text-white/30 opacity-40 scale-95'
                        }`}
                      >
                        <Music className="w-5 h-5 text-[#00a3ff]" />
                        <span className="text-base sm:text-lg font-bold tracking-widest uppercase font-mono">
                          {line.text || '♪  Musik  ♪'}
                        </span>
                        {isActive && (
                          <div className="flex gap-1.5 ml-2">
                            <span className="w-2 h-2 rounded-full bg-[#00a3ff] animate-ping" />
                            <span className="w-2 h-2 rounded-full bg-[#00a3ff]/70" />
                            <span className="w-2 h-2 rounded-full bg-[#00a3ff]/40" />
                          </div>
                        )}
                      </div>
                    );
                  }

                  return (
                    <div
                      key={line.id || idx}
                      ref={isActive ? activeLineRef : null}
                      onClick={() => onSeek(line.time)}
                      className={`cursor-pointer transition-all duration-300 transform origin-left group ${
                        getFontSizeClass()
                      } ${
                        isActive
                          ? 'opacity-100 scale-100 font-black'
                          : isPast
                          ? 'opacity-40 hover:opacity-75 scale-95 font-bold'
                          : 'opacity-25 hover:opacity-60 scale-90 font-bold'
                      }`}
                    >
                      {/* Active Line indicator bullet */}
                      <div className="flex items-center gap-3">
                        <span 
                          className={`w-2 h-2 rounded-full transition-all duration-300 flex-shrink-0 ${
                            isActive 
                              ? 'opacity-100 scale-100 bg-[#00a3ff]' 
                              : 'opacity-0 scale-0'
                          }`} 
                        />
                        
                        {/* If Active Line: Animate Word-by-Word (Syllables)! */}
                        {isActive && line.words && line.words.length > 0 ? (
                          <div className="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                            {line.words.map((w) => {
                              const isWordCurrent = effectiveTime >= w.startTime && effectiveTime < w.endTime;
                              const isWordFinished = effectiveTime >= w.endTime;

                              return (
                                <span
                                  key={w.id}
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    onSeek(w.startTime);
                                  }}
                                  className={`inline-block transition-all duration-150 transform hover:scale-110 ${
                                    isWordCurrent
                                      ? 'text-[#00e5ff] font-black scale-105 -translate-y-0.5 drop-shadow-[0_0_16px_rgba(0,163,255,1)]'
                                      : isWordFinished
                                      ? 'text-white font-extrabold opacity-100 scale-100'
                                      : 'text-white/40 opacity-40 font-bold scale-95'
                                  }`}
                                >
                                  {w.word}
                                </span>
                              );
                            })}
                          </div>
                        ) : (
                          /* Inactive or plain-line fallback */
                          <span
                            className={`inline-block transition-all duration-300 ${
                              isActive ? 'text-white' : 'text-white/70 group-hover:text-white'
                            } ${
                              line.isBackgroundVocal ? 'italic text-white/50 text-[0.85em]' : ''
                            }`}
                          >
                            {line.text}
                          </span>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
