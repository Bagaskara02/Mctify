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
import { DEFAULT_ARTWORK, getHighResArtworkUrl } from '../services/musicApi';
import { lyricsService } from '../services/lyricsService';

/**
 * Syllable & Character-by-Character Karaoke Fade-Wipe Widget (Apple Music & Lyra style)
 * Sweeps smoothly across letters from left to right as the singer sings ("BA GUS", etc.)
 */
function KaraokeWordWipe({ word, currentTimeSec, onTap }) {
  const start = word.startTime;
  const end = word.endTime;
  const dur = Math.max(0.04, word.duration || (end - start));

  let progress = 0;
  if (currentTimeSec < start) {
    progress = 0;
  } else if (currentTimeSec >= end) {
    progress = 1;
  } else {
    progress = (currentTimeSec - start) / dur;
    progress = Math.max(0, Math.min(1, progress));
  }

  const isActivelySinging = progress > 0 && progress < 1;
  const p = progress * 100;

  return (
    <span
      onClick={(e) => {
        e.stopPropagation();
        onTap?.();
      }}
      className={`inline-block transition-transform duration-100 cursor-pointer select-none ${
        isActivelySinging
          ? 'scale-[1.05] -translate-y-0.5 font-black'
          : progress >= 1
          ? 'text-white font-extrabold'
          : 'text-white/35 font-bold hover:text-white/60'
      }`}
      style={{
        letterSpacing: '-0.02em',
        ...(isActivelySinging
          ? {
              backgroundImage: `linear-gradient(90deg, #FFFFFF 0%, #FFFFFF ${Math.max(0, p - 6).toFixed(1)}%, #00E5FF ${p.toFixed(1)}%, rgba(255, 255, 255, 0.35) ${Math.min(100, p + 8).toFixed(1)}%, rgba(255, 255, 255, 0.35) 100%)`,
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              filter: 'drop-shadow(0 0 16px rgba(0, 229, 255, 0.9)) drop-shadow(0 0 4px #00E5FF)',
            }
          : progress >= 1
          ? {
              filter: 'drop-shadow(0 0 10px rgba(0, 163, 255, 0.35))',
            }
          : {}),
      }}
    >
      {word.word}
    </span>
  );
}

function KaraokeLineWipe({ line, currentTimeSec }) {
  const dur = Math.max(0.5, line.duration || (line.endTime - line.time) || 3.5);
  let progress = 0;
  if (currentTimeSec < line.time) {
    progress = 0;
  } else if (currentTimeSec >= (line.endTime || line.time + dur)) {
    progress = 1;
  } else {
    progress = Math.max(0, Math.min(1, (currentTimeSec - line.time) / dur));
  }
  const p = progress * 100;
  const isActivelySinging = progress > 0 && progress < 1;

  return (
    <span
      className={`inline-block transition-all duration-100 ${
        isActivelySinging ? 'font-black scale-[1.01]' : 'font-extrabold'
      }`}
      style={
        isActivelySinging
          ? {
              backgroundImage: `linear-gradient(90deg, #FFFFFF 0%, #FFFFFF ${Math.max(0, p - 4).toFixed(1)}%, #00E5FF ${p.toFixed(1)}%, rgba(255, 255, 255, 0.35) ${Math.min(100, p + 6).toFixed(1)}%, rgba(255, 255, 255, 0.35) 100%)`,
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              filter: 'drop-shadow(0 0 16px rgba(0, 229, 255, 0.85))',
            }
          : {
              color: progress >= 1 ? '#FFFFFF' : 'rgba(255, 255, 255, 0.35)',
            }
      }
    >
      {line.text}
    </span>
  );
}

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
  const [manualOffset, setManualOffset] = useState(null); // null = Auto-Sync mode active!
  const [palette, setPalette] = useState({ primary: '#00a3ff', secondary: '#2eb4ff', tertiary: '#0055b3' });
  const [autoScroll, setAutoScroll] = useState(true);
  const [userScrolled, setUserScrolled] = useState(false);

  // 60 FPS sub-millisecond smooth interpolation ticker
  const [smoothTime, setSmoothTime] = useState(currentTime);
  const lastReportedTimeRef = useRef(currentTime);
  const lastTimestampRef = useRef(performance.now());

  const containerRef = useRef(null);
  const scrollTimeoutRef = useRef(null);
  const activeLineRef = useRef(null);

  const trackKey = track ? `${(track.artist || '').trim().toLowerCase()}:::${(track.title || '').trim().toLowerCase()}` : '';

  // Synchronize reference with player's 80ms time polling
  useEffect(() => {
    lastReportedTimeRef.current = currentTime;
    lastTimestampRef.current = performance.now();
    setSmoothTime(currentTime);
  }, [currentTime]);

  // High-precision animation frame ticker for buttery smooth letter-wipe
  useEffect(() => {
    if (!isPlaying) return;
    let animId;
    const loop = () => {
      const elapsed = (performance.now() - lastTimestampRef.current) / 1000;
      if (elapsed >= 0 && elapsed <= 0.25) {
        setSmoothTime(lastReportedTimeRef.current + elapsed);
      }
      animId = requestAnimationFrame(loop);
    };
    animId = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(animId);
  }, [isPlaying]);

  // Load persistent sync offset for current track if user manually adjusted it earlier
  useEffect(() => {
    if (trackKey) {
      const saved = lyricsService.getTrackSyncOffset(trackKey);
      if (typeof saved === 'number') {
        setManualOffset(saved);
      } else {
        setManualOffset(null);
      }
    } else {
      setManualOffset(null);
    }
  }, [trackKey]);

  const autoOffset = lyricsData?.autoOffset || 0;
  const isAutoSync = manualOffset === null;
  const effectiveOffset = isAutoSync ? autoOffset : manualOffset;

  const updateSyncOffset = (delta) => {
    setManualOffset(prev => {
      const base = prev !== null ? prev : autoOffset;
      const next = Math.round((base + delta) * 10) / 10;
      if (trackKey) {
        lyricsService.saveTrackSyncOffset(trackKey, next);
      }
      return next;
    });
  };

  const resetToAutoSync = () => {
    setManualOffset(null);
    if (trackKey) {
      lyricsService.removeTrackSyncOffset(trackKey);
    }
  };

  // Extract vibrant colors from album artwork
  useEffect(() => {
    if (track?.artwork) {
      extractPaletteFromImage(getHighResArtworkUrl(track.artwork)).then(pal => {
        setPalette({
          primary: pal.primary || '#00a3ff',
          secondary: pal.secondary || '#2eb4ff',
          tertiary: '#0055b3',
        });
      });
    }
  }, [track?.artwork]);

  // Effective playback time with calibrated auto/manual offset
  const effectiveTime = Math.max(0, smoothTime + effectiveOffset);
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
              src={getHighResArtworkUrl(track?.artwork)} 
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
              
              {/* Auto / Manual Indicator Pill */}
              {isAutoSync ? (
                <div className="flex items-center gap-1 px-1.5 py-0.5 rounded-full bg-[#00a3ff]/15 border border-[#00a3ff]/30 text-[10px] text-[#00e5ff] font-bold">
                  <Sparkles className="w-2.5 h-2.5 text-[#00e5ff] animate-pulse" />
                  <span>Auto-Sync</span>
                  <span className="font-mono tabular-nums text-white/90">
                    {effectiveOffset === 0 ? '0.0s' : effectiveOffset > 0 ? `+${effectiveOffset.toFixed(1)}s` : `${effectiveOffset.toFixed(1)}s`}
                  </span>
                </div>
              ) : (
                <div className="flex items-center gap-1 px-1.5 py-0.5 rounded-full bg-amber-500/15 border border-amber-500/30 text-[10px] text-amber-300 font-bold">
                  <span>Manual</span>
                  <span className="font-mono tabular-nums">
                    {effectiveOffset > 0 ? `+${effectiveOffset.toFixed(1)}s` : `${effectiveOffset.toFixed(1)}s`}
                  </span>
                </div>
              )}

              {/* Fast Rewind / Advance Sync Buttons */}
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

              {!isAutoSync && (
                <button 
                  onClick={resetToAutoSync}
                  className="px-1.5 py-0.5 rounded-md hover:bg-white/10 text-[#00e5ff] hover:text-white flex items-center gap-1 text-[11px] font-bold border border-[#00e5ff]/30 bg-[#00a3ff]/10"
                  title="Kembalikan ke Auto-Sync"
                >
                  <RotateCcw className="w-2.5 h-2.5" />
                  <span className="hidden sm:inline">Auto</span>
                </button>
              )}

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
                  src={getHighResArtworkUrl(track?.artwork)} 
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
                        
                        {/* If Active Line: Animate Word-by-Word with Syllable & Character Fade-Wipe! */}
                        {isActive ? (
                          line.words && line.words.length > 0 ? (
                            <div className="flex flex-wrap items-baseline gap-x-2.5 gap-y-1.5">
                              {line.words.map((w) => (
                                <KaraokeWordWipe
                                  key={w.id}
                                  word={w}
                                  currentTimeSec={effectiveTime}
                                  onTap={() => onSeek(w.startTime)}
                                />
                              ))}
                            </div>
                          ) : (
                            <KaraokeLineWipe
                              line={line}
                              currentTimeSec={effectiveTime}
                            />
                          )
                        ) : (
                          /* Inactive line */
                          <span
                            className={`inline-block transition-all duration-300 ${
                              isPast
                                ? 'text-white/40 font-semibold'
                                : 'text-white/25 group-hover:text-white/60 font-semibold'
                            } ${
                              line.isBackgroundVocal ? 'italic text-white/35 text-[0.85em]' : ''
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
