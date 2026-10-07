import React from 'react';
import { 
  X, 
  Heart, 
  CheckCircle2, 
  Mic2, 
  Maximize2, 
  Radio, 
  Music2, 
  UserPlus,
  Sparkles
} from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';

export default function RightSidebarNowPlaying({
  isOpen,
  onClose,
  currentTrack,
  currentTime,
  lyricsData,
  isLiked,
  onToggleLike,
  onOpenLyrics,
  onOpenArtist,
  onStartRadio,
}) {
  if (!isOpen || !currentTrack) return null;

  // Extract current active line for the "Pratinjau lirik" widget
  const lines = lyricsData?.lines || [];
  let activeIndex = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].time <= currentTime) {
      if (i === lines.length - 1 || lines[i + 1].time > currentTime) {
        activeIndex = i;
        break;
      }
    }
  }

  const previewLines = activeIndex !== -1 
    ? lines.slice(Math.max(0, activeIndex), activeIndex + 3)
    : lines.slice(0, 3);

  return (
    <aside className="hidden xl:flex w-80 lg:w-96 flex-col bg-[#121212] my-2 mr-2 rounded-lg border-l border-white/5 select-none overflow-hidden relative shadow-lg text-white">
      {/* Top Header */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-white/[0.04]">
        <h3 className="font-bold text-sm text-white truncate max-w-[220px]" title={currentTrack.album || currentTrack.title}>
          {currentTrack.album || currentTrack.title}
        </h3>
        <button
          onClick={onClose}
          className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-white transition-colors"
          title="Tutup panel"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Body Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-5 no-scrollbar">
        {/* Cover Art / Video Hero */}
        <div className="relative aspect-square w-full rounded-lg overflow-hidden shadow-2xl bg-[#242424] group">
          <img
            src={currentTrack.artwork || DEFAULT_ARTWORK}
            alt={currentTrack.title}
            onError={(e) => {
              e.currentTarget.onerror = null;
              e.currentTarget.src = DEFAULT_ARTWORK;
            }}
            className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
          />
        </div>

        {/* Title, Artist, & Like */}
        <div className="flex items-center justify-between">
          <div className="min-w-0 pr-3">
            <h2 className="text-xl font-black text-white truncate tracking-tight hover:underline cursor-pointer">
              {currentTrack.title}
            </h2>
            <div className="flex items-center gap-1.5 mt-0.5">
              <p className="text-sm text-[#b3b3b3] font-semibold truncate hover:underline hover:text-white cursor-pointer">
                {currentTrack.artist}
              </p>
              <CheckCircle2 className="w-4 h-4 text-[#00a3ff] fill-[#00a3ff]/20 flex-shrink-0" title="Terverifikasi" />
            </div>
          </div>

          <button
            onClick={() => onToggleLike(currentTrack)}
            className={`p-2 rounded-full transition-all active:scale-90 flex-shrink-0 ${
              isLiked ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
            }`}
            title={isLiked ? 'Disukai' : 'Sukai'}
          >
            <Heart className={`w-5 h-5 ${isLiked ? 'fill-current' : ''}`} />
          </button>
        </div>

        {/* PRATINJAU LIRIK (Spotify-Exact Lyrics Preview Widget) */}
        <div 
          onClick={onOpenLyrics}
          className="p-4 rounded-xl bg-gradient-to-br from-[#0c3966] via-[#09223e] to-[#0f1d2e] border border-[#00a3ff]/30 cursor-pointer group hover:border-[#00a3ff]/60 transition-all shadow-xl relative overflow-hidden"
        >
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Mic2 className="w-4 h-4 text-[#00a3ff]" />
              <span className="text-xs font-bold text-white tracking-wide">
                Pratinjau lirik
              </span>
            </div>
            <button className="p-1 rounded-full text-white/60 group-hover:text-white transition-colors">
              <Maximize2 className="w-3.5 h-3.5" />
            </button>
          </div>

          {lines.length === 0 ? (
            <p className="text-xs text-white/50 italic py-2">
              Lirik bersinkronisasi sedang dimuat...
            </p>
          ) : (
            <div className="space-y-2 py-1 select-none">
              {previewLines.map((line, idx) => {
                const isCurrentLine = idx === 0 && activeIndex !== -1;
                return (
                  <p
                    key={line.id || idx}
                    className={`text-sm sm:text-base transition-all font-bold line-clamp-2 leading-snug ${
                      isCurrentLine 
                        ? 'text-white font-black text-lg scale-[1.02] drop-shadow-md' 
                        : 'text-white/40 font-semibold'
                    }`}
                  >
                    {line.text}
                  </p>
                );
              })}
            </div>
          )}

          <div className="mt-4 pt-2 border-t border-white/10 flex items-center justify-between text-[11px] text-[#00a3ff] font-semibold">
            <span>Buka Beautiful Lyrics Karaoke</span>
            <span>&rarr;</span>
          </div>
        </div>

        {/* TENTANG ARTIS (About the Artist Card) */}
        <div className="rounded-xl bg-[#1e1e1e] overflow-hidden border border-white/5">
          <div className="h-32 bg-gradient-to-b from-[#2a3e59] to-[#1e1e1e] p-4 flex flex-col justify-end relative">
            <p className="text-xs font-bold text-white/70 uppercase tracking-wider">
              Tentang Artis
            </p>
            <h4 
              onClick={() => onOpenArtist?.(currentTrack.artist)}
              className="text-lg font-black text-white truncate hover:underline cursor-pointer"
              title={`Buka profil ${currentTrack.artist}`}
            >
              {currentTrack.artist}
            </h4>
          </div>

          <div className="p-4 space-y-3">
            <div className="flex items-center justify-between text-xs text-[#b3b3b3]">
              <span>Genre: {currentTrack.genre || 'Pop'}</span>
              <span>Rilis: {currentTrack.releaseYear || '2024'}</span>
            </div>

            <button
              onClick={() => onStartRadio(currentTrack)}
              className="w-full py-2 px-3 rounded-full bg-white/10 hover:bg-[#00a3ff] hover:text-black text-white text-xs font-bold flex items-center justify-center gap-2 transition-all active:scale-95"
            >
              <Radio className="w-3.5 h-3.5" />
              <span>Mulai Radio Lagu Ini</span>
            </button>
          </div>
        </div>
      </div>
    </aside>
  );
}
