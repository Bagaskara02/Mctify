import React, { useEffect, useRef, useState } from 'react';
import { 
  X, 
  Maximize2, 
  Minimize2, 
  Music
} from 'lucide-react';
import { extractPaletteFromImage } from '../utils/colorExtractor';
import { DEFAULT_ARTWORK, getHighResArtworkUrl } from '../services/musicApi';

/**
 * Spicy Lyrics True Syllable & Word-Synced Karaoke Wipe
 * Driven directly by studio-grade start/end timestamps (Apple Music / NetEase YRC / Musixmatch style)
 */
function KaraokeWord({ word, currentTimeSec, onTap }) {
  const start = word.startTime;
  const end = word.endTime;
  const dur = Math.max(0.04, word.duration || (end - start));

  let progress = 0;
  if (currentTimeSec < start) {
    progress = 0;
  } else if (currentTimeSec >= end) {
    progress = 1;
  } else {
    progress = Math.max(0, Math.min(1, (currentTimeSec - start) / dur));
  }

  const isActivelySinging = progress > 0 && progress < 1;
  const isFinished = progress >= 1;

  // Syllable/character-level sub-sweep if chars array exists
  if (word.chars && word.chars.length > 0) {
    return (
      <span
        onClick={(e) => {
          e.stopPropagation();
          onTap?.();
        }}
        className={`inline-flex items-baseline cursor-pointer select-none transition-all duration-100 ${
          isActivelySinging
            ? 'scale-[1.04] -translate-y-0.5 font-black drop-shadow-[0_0_16px_rgba(59,130,246,0.85)]'
            : isFinished
            ? 'text-white font-extrabold drop-shadow-[0_0_8px_rgba(255,255,255,0.25)]'
            : 'text-white/28 font-bold hover:text-white/60'
        }`}
        style={{ letterSpacing: '-0.02em' }}
      >
        {word.chars.map((ch, idx) => {
          let cp = 0;
          if (currentTimeSec < ch.startTime) {
            cp = 0;
          } else if (currentTimeSec >= ch.endTime) {
            cp = 1;
          } else {
            const cd = Math.max(0.02, ch.duration || (ch.endTime - ch.startTime));
            cp = Math.max(0, Math.min(1, (currentTimeSec - ch.startTime) / cd));
          }

          const isCharActive = cp > 0 && cp < 1;
          const charPercent = (cp * 100).toFixed(1);

          return (
            <span
              key={idx}
              className="inline-block"
              style={
                isCharActive
                  ? {
                      backgroundImage: `linear-gradient(90deg, #FFFFFF 0%, #FFFFFF ${Math.max(0, charPercent - 4)}%, #60A5FA ${charPercent}%, rgba(255, 255, 255, 0.28) ${Math.min(100, Number(charPercent) + 8)}%, rgba(255, 255, 255, 0.28) 100%)`,
                      WebkitBackgroundClip: 'text',
                      WebkitTextFillColor: 'transparent',
                      filter: 'drop-shadow(0 0 12px rgba(59, 130, 246, 0.95))',
                    }
                  : cp >= 1
                  ? { color: '#FFFFFF' }
                  : { color: 'rgba(255, 255, 255, 0.28)' }
              }
            >
              {ch.char}
            </span>
          );
        })}
      </span>
    );
  }

  // Word-level smooth gradient wipe
  const p = (progress * 100).toFixed(1);

  return (
    <span
      onClick={(e) => {
        e.stopPropagation();
        onTap?.();
      }}
      className={`inline-block cursor-pointer select-none transition-all duration-100 ${
        isActivelySinging
          ? 'scale-[1.04] -translate-y-0.5 font-black'
          : isFinished
          ? 'text-white font-extrabold drop-shadow-[0_0_8px_rgba(255,255,255,0.25)]'
          : 'text-white/28 font-bold hover:text-white/60'
      }`}
      style={{
        letterSpacing: '-0.02em',
        ...(isActivelySinging
          ? {
              backgroundImage: `linear-gradient(90deg, #FFFFFF 0%, #FFFFFF ${Math.max(0, p - 5)}%, #60A5FA ${p}%, rgba(255, 255, 255, 0.28) ${Math.min(100, Number(p) + 8)}%, rgba(255, 255, 255, 0.28) 100%)`,
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              filter: 'drop-shadow(0 0 14px rgba(59, 130, 246, 0.9))',
            }
          : {}),
      }}
    >
      {word.word}
    </span>
  );
}

function KaraokeLineFallback({ line, currentTimeSec }) {
  const dur = Math.max(0.5, line.duration || (line.endTime - line.time) || 3.5);
  let progress = 0;
  if (currentTimeSec < line.time) {
    progress = 0;
  } else if (currentTimeSec >= (line.endTime || line.time + dur)) {
    progress = 1;
  } else {
    progress = Math.max(0, Math.min(1, (currentTimeSec - line.time) / dur));
  }
  const p = (progress * 100).toFixed(1);
  const isActivelySinging = progress > 0 && progress < 1;

  return (
    <span
      className={`inline-block transition-all duration-100 ${
        isActivelySinging ? 'font-black scale-[1.01]' : 'font-extrabold'
      }`}
      style={
        isActivelySinging
          ? {
              backgroundImage: `linear-gradient(90deg, #FFFFFF 0%, #FFFFFF ${Math.max(0, p - 4)}%, #60A5FA ${p}%, rgba(255, 255, 255, 0.28) ${Math.min(100, Number(p) + 6)}%, rgba(255, 255, 255, 0.28) 100%)`,
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              filter: 'drop-shadow(0 0 16px rgba(59, 130, 246, 0.85))',
            }
          : {
              color: progress >= 1 ? '#FFFFFF' : 'rgba(255, 255, 255, 0.28)',
            }
      }
    >
      {line.text}
    </span>
  );
}

function InterludeLine({ line, currentTimeSec, isActive }) {
  const dur = Math.max(0.5, line.endTime - line.time);
  const progress = Math.max(0, Math.min(1, (currentTimeSec - line.time) / dur));
  const dot1 = progress >= 0.1;
  const dot2 = progress >= 0.45;
  const dot3 = progress >= 0.8;

  return (
    <div
      className={`transition-all duration-300 py-4 flex items-center gap-3 select-none ${
        isActive ? 'opacity-100 scale-100' : 'opacity-25 scale-95'
      }`}
    >
      <div className="flex items-center gap-2.5">
        <span
          className={`w-3 h-3 rounded-full transition-all duration-200 ${
            isActive && dot1
              ? 'bg-[#3B82F6] scale-125 shadow-[0_0_12px_#3B82F6]'
              : 'bg-white/20 scale-100'
          }`}
        />
        <span
          className={`w-3 h-3 rounded-full transition-all duration-200 ${
            isActive && dot2
              ? 'bg-[#3B82F6] scale-125 shadow-[0_0_12px_#3B82F6]'
              : 'bg-white/20 scale-100'
          }`}
        />
        <span
          className={`w-3 h-3 rounded-full transition-all duration-200 ${
            isActive && dot3
              ? 'bg-[#3B82F6] scale-125 shadow-[0_0_12px_#3B82F6]'
              : 'bg-white/20 scale-100'
          }`}
        />
      </div>
    </div>
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
  const [palette, setPalette] = useState({ primary: '#2563EB', secondary: '#3B82F6', tertiary: '#1D4ED8' });
  const [userScrolled, setUserScrolled] = useState(false);

  // User lyric timing sync calibration (persisted in localStorage)
  const [syncOffsetSec, setSyncOffsetSec] = useState(() => {
    try {
      const saved = localStorage.getItem('mcmusic_lyrics_sync_offset');
      return saved !== null ? parseFloat(saved) : 0;
    } catch {
      return 0;
    }
  });

  const updateSyncOffset = (delta) => {
    setSyncOffsetSec((prev) => {
      const next = Math.round((prev + delta) * 10) / 10;
      try {
        localStorage.setItem('mcmusic_lyrics_sync_offset', next.toString());
      } catch (_) {}
      return next;
    });
  };

  const resetSyncOffset = () => {
    setSyncOffsetSec(0);
    try {
      localStorage.setItem('mcmusic_lyrics_sync_offset', '0');
    } catch (_) {}
  };

  // 60 FPS sub-millisecond smooth interpolation ticker
  const [smoothTime, setSmoothTime] = useState(currentTime);
  const lastReportedTimeRef = useRef(currentTime);
  const lastTimestampRef = useRef(performance.now());

  const containerRef = useRef(null);
  const scrollTimeoutRef = useRef(null);
  const activeLineRef = useRef(null);

  // Synchronize reference with player's actual time
  useEffect(() => {
    lastReportedTimeRef.current = currentTime;
    lastTimestampRef.current = performance.now();
    setSmoothTime(currentTime);
  }, [currentTime]);

  // High-precision animation frame ticker for buttery smooth wipe
  useEffect(() => {
    if (!isPlaying) {
      setSmoothTime(currentTime);
      return;
    }
    let animId;
    const loop = () => {
      const elapsed = (performance.now() - lastTimestampRef.current) / 1000;
      if (elapsed >= 0 && elapsed <= 0.3) {
        setSmoothTime(lastReportedTimeRef.current + elapsed);
      }
      animId = requestAnimationFrame(loop);
    };
    animId = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(animId);
  }, [isPlaying, currentTime]);

  // Extract vibrant colors from album artwork for ambient backdrop
  useEffect(() => {
    if (track?.artwork) {
      extractPaletteFromImage(getHighResArtworkUrl(track.artwork)).then(pal => {
        setPalette({
          primary: pal.primary || '#2563EB',
          secondary: pal.secondary || '#3B82F6',
          tertiary: '#1D4ED8',
        });
      });
    }
  }, [track?.artwork]);

  // Acoustic output latency calibration: Calibrated so lyrics don't rush ahead of vocals
  // Base offset: 0.65s (delayed by an extra 300ms so lyric doesn't highlight too early) + user offset
  const effectiveTime = Math.max(0, smoothTime - (0.65 + syncOffsetSec));
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
    if (userScrolled || activeIndex === -1) return;

    if (activeLineRef.current && containerRef.current) {
      const container = containerRef.current;
      const element = activeLineRef.current;

      const elementTop = element.offsetTop;
      const elementHeight = element.offsetHeight;
      const containerHeight = container.offsetHeight;

      const targetScroll = elementTop - containerHeight * 0.38 + elementHeight / 2;

      container.scrollTo({
        top: Math.max(0, targetScroll),
        behavior: 'smooth',
      });
    }
  }, [activeIndex, userScrolled]);

  const handleUserScroll = () => {
    setUserScrolled(true);
    if (scrollTimeoutRef.current) clearTimeout(scrollTimeoutRef.current);
    scrollTimeoutRef.current = setTimeout(() => {
      setUserScrolled(false);
    }, 2800);
  };

  return (
    <div 
      className={`fixed inset-0 z-50 flex flex-col overflow-hidden bg-[#06080e] select-none transition-all duration-500 ${
        isFullscreen ? 'p-0' : 'p-4 sm:p-8'
      }`}
    >
      {/* Dynamic Ambient Background - Fluid Blurred Album Glow (Apple Music / Spicy Lyrics) */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div 
          className="absolute -top-[20%] -left-[15%] w-[75vw] h-[75vw] rounded-full blur-[140px] opacity-45 animate-drift-1 transition-colors duration-1000"
          style={{ background: `radial-gradient(circle, ${palette.primary} 0%, transparent 70%)` }}
        />
        <div 
          className="absolute top-[30%] -right-[20%] w-[70vw] h-[70vw] rounded-full blur-[150px] opacity-40 animate-drift-2 transition-colors duration-1000"
          style={{ background: `radial-gradient(circle, ${palette.secondary} 0%, transparent 70%)` }}
        />
        <div 
          className="absolute -bottom-[25%] left-[20%] w-[80vw] h-[80vw] rounded-full blur-[160px] opacity-35 animate-drift-3 transition-colors duration-1000"
          style={{ background: `radial-gradient(circle, ${palette.tertiary} 0%, transparent 70%)` }}
        />
        {/* Contrast Darkening Overlay */}
        <div className="absolute inset-0 bg-black/65 backdrop-blur-[75px]" />
      </div>

      {/* Floating Minimal Controls (Top Right: Timing Calibrator, Fullscreen & Close) */}
      <div className="absolute top-4 right-4 sm:top-6 sm:right-8 z-30 flex items-center gap-2">
        {/* Real-time Lyrics Timing Calibrator */}
        <div className="flex items-center gap-1 px-2.5 py-1 rounded-full bg-white/10 backdrop-blur-md border border-white/10 text-xs font-semibold text-white/80 shadow-lg">
          <button
            onClick={() => updateSyncOffset(-0.2)}
            className="px-1.5 py-0.5 rounded hover:bg-white/20 text-white font-mono transition-colors active:scale-90"
            title="Percepat lirik 0.2s (jika lirik telat)"
          >
            -0.2s
          </button>
          <button
            onClick={resetSyncOffset}
            className="px-2 py-0.5 hover:text-white font-mono text-[11px] transition-colors"
            title="Klik untuk reset sinkronisasi ke 0s"
          >
            Sync {syncOffsetSec >= 0 ? `+${syncOffsetSec.toFixed(1)}s` : `${syncOffsetSec.toFixed(1)}s`}
          </button>
          <button
            onClick={() => updateSyncOffset(0.2)}
            className="px-1.5 py-0.5 rounded hover:bg-white/20 text-white font-mono transition-colors active:scale-90"
            title="Perlambat lirik 0.2s (jika lirik kecepetan)"
          >
            +0.2s
          </button>
        </div>

        <button
          onClick={() => setIsFullscreen(!isFullscreen)}
          className="p-2.5 rounded-full bg-white/10 hover:bg-white/20 text-white/80 hover:text-white backdrop-blur-md transition-all active:scale-95"
          title={isFullscreen ? 'Keluar Layar Penuh' : 'Layar Penuh'}
        >
          {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
        </button>
        <button
          onClick={onClose}
          className="p-2.5 rounded-full bg-white/10 hover:bg-white/20 text-white backdrop-blur-md transition-all active:scale-95"
          title="Tutup Lirik"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Main Container - 100% Immersive Typography */}
      <div className="relative z-10 flex-1 grid grid-cols-1 lg:grid-cols-12 gap-8 min-h-0 max-w-7xl w-full mx-auto overflow-hidden">
        {/* Left Column: Artwork & Track Details (Desktop) */}
        <div className="hidden lg:flex lg:col-span-4 flex-col justify-center items-start p-8 select-none">
          <div className="relative group mb-8">
            <img
              src={getHighResArtworkUrl(track?.artwork)} 
              alt={track?.title} 
              onError={(e) => {
                e.currentTarget.onerror = null;
                e.currentTarget.src = DEFAULT_ARTWORK;
              }}
              className="w-72 h-72 xl:w-84 xl:h-84 rounded-3xl object-cover shadow-2xl border border-white/10 bg-neutral-900 transition-transform duration-700 group-hover:scale-105"
              style={{
                boxShadow: `0 25px 60px -15px ${palette.primary}88`,
              }}
            />
          </div>

          <div className="max-w-xs space-y-2">
            <h1 className="text-white text-3xl font-black tracking-tight line-clamp-2 leading-tight">
              {track?.title}
            </h1>
            <p className="text-neutral-300 text-lg font-bold truncate">
              {track?.artist}
            </p>
            {track?.album && (
              <p className="text-neutral-500 text-sm font-semibold truncate">
                {track?.album}
              </p>
            )}
          </div>
        </div>

        {/* Right Column: Massive Immersive Flowing Lyrics */}
        <div 
          ref={containerRef}
          onScroll={handleUserScroll}
          className="col-span-1 lg:col-span-8 overflow-y-auto px-4 sm:px-10 pt-16 pb-48 scroll-smooth relative no-scrollbar"
        >
          {isLoadingLyrics ? (
            <div className="h-full flex flex-col items-center justify-center gap-4 text-white/50">
              <div className="w-10 h-10 border-4 border-white/20 border-t-[#3B82F6] rounded-full animate-spin" />
              <p className="text-sm font-medium animate-pulse">Menghubungkan lirik sinkron studio...</p>
            </div>
          ) : lines.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center p-8 space-y-4 text-white/40">
              <Music className="w-16 h-16 opacity-30 stroke-[1.5]" />
              <div className="space-y-1">
                <h3 className="text-xl font-bold text-white">Lirik Belum Tersedia</h3>
                <p className="text-sm max-w-md">
                  Lirik untuk lagu ini belum terdaftar di database sinkronisasi.
                </p>
              </div>
            </div>
          ) : (
            <div className="space-y-8 sm:space-y-10 py-32 select-none">
              {lines.map((line, idx) => {
                const isActive = idx === activeIndex;
                const isPast = idx < activeIndex;

                // Instrumental interlude line (3 dots)
                if (line.isInstrumental || line.isInterlude) {
                  return (
                    <div key={line.id || idx} ref={isActive ? activeLineRef : null}>
                      <InterludeLine
                        line={line}
                        currentTimeSec={effectiveTime}
                        isActive={isActive}
                      />
                    </div>
                  );
                }

                return (
                  <div
                    key={line.id || idx}
                    ref={isActive ? activeLineRef : null}
                    onClick={() => onSeek(line.time)}
                    className={`cursor-pointer transition-all duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] transform origin-left leading-snug ${
                      isActive
                        ? 'opacity-100 scale-100 font-black blur-0 text-3xl sm:text-4xl md:text-5xl text-white'
                        : isPast
                        ? 'opacity-30 hover:opacity-75 scale-[0.96] font-extrabold blur-[1.2px] hover:blur-0 text-2xl sm:text-3xl md:text-4xl text-white/40'
                        : 'opacity-25 hover:opacity-70 scale-[0.94] font-extrabold blur-[1.8px] hover:blur-0 text-2xl sm:text-3xl md:text-4xl text-white/30'
                    }`}
                  >
                    {isActive ? (
                      line.words && line.words.length > 0 ? (
                        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-2">
                          {line.words.map((w) => (
                            <KaraokeWord
                              key={w.id}
                              word={w}
                              currentTimeSec={effectiveTime}
                              onTap={() => onSeek(w.startTime)}
                            />
                          ))}
                        </div>
                      ) : (
                        <KaraokeLineFallback
                          line={line}
                          currentTimeSec={effectiveTime}
                        />
                      )
                    ) : (
                      <span>{line.text}</span>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
