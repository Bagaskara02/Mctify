import React, { useState, useRef, useMemo } from 'react';
import { 
  Play, 
  Pause,
  Shuffle, 
  Download, 
  Trash2, 
  Clock, 
  Heart, 
  Mic2, 
  Music,
  MoreHorizontal,
  Search,
  ArrowUpDown,
  X,
  ChevronDown,
  Check
} from 'lucide-react';
import { playlistImporter } from '../services/playlistImporter';
import { DEFAULT_ARTWORK } from '../services/musicApi';

function cleanTrackTitle(title) {
  if (!title) return '';
  return title
    .replace(/\s*[\(\[](official\s*(music\s*)?video|audio|mv|visualizer|lyric(s)?(\s*video)?|remastered|single|hd|4k|session|brooklyn session|10 years)[\)\]]/gi, '')
    .replace(/\s*-\s*Official Video.*$/i, '')
    .trim() || title;
}

export default function PlaylistView({
  playlist,
  currentTrack,
  isPlaying,
  likedTrackIds = new Set(),
  onPlayTrack,
  onTogglePlayPause,
  onPlayAll,
  onShuffleAll,
  onToggleLike,
  onOpenLyrics,
  onRemoveTrack,
  onDeletePlaylist,
  onTrackContextMenu,
}) {
  const [isHeaderSticky, setIsHeaderSticky] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [sortBy, setSortBy] = useState('custom'); // 'custom' | 'title' | 'artist' | 'duration-desc' | 'duration-asc'
  const [isSortMenuOpen, setIsSortMenuOpen] = useState(false);
  const scrollContainerRef = useRef(null);

  if (!playlist) {
    return (
      <div className="flex-1 flex items-center justify-center text-neutral-400 bg-[#121212]">
        <p>Tidak ada playlist yang dipilih</p>
      </div>
    );
  }

  const rawTracks = playlist.tracks || [];
  const totalDuration = rawTracks.reduce((acc, t) => acc + (t.duration || 0), 0);
  const totalMinutes = Math.floor(totalDuration / 60);

  // Search filter & Spotify-style sorting
  const processedTracks = useMemo(() => {
    let result = rawTracks;

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      result = result.filter((t) => {
        const titleMatch = (t.title || '').toLowerCase().includes(q);
        const artistMatch = (t.artist || '').toLowerCase().includes(q);
        const albumMatch = (t.album || '').toLowerCase().includes(q);
        return titleMatch || artistMatch || albumMatch;
      });
    }

    if (sortBy !== 'custom') {
      result = [...result].sort((a, b) => {
        if (sortBy === 'title') {
          return (a.title || '').localeCompare(b.title || '');
        }
        if (sortBy === 'artist') {
          return (a.artist || '').localeCompare(b.artist || '');
        }
        if (sortBy === 'duration-desc') {
          return (b.duration || 0) - (a.duration || 0);
        }
        if (sortBy === 'duration-asc') {
          return (a.duration || 0) - (b.duration || 0);
        }
        return 0;
      });
    }

    return result;
  }, [rawTracks, searchQuery, sortBy]);

  const handleScroll = (e) => {
    if (e.currentTarget.scrollTop > 240) {
      if (!isHeaderSticky) setIsHeaderSticky(true);
    } else {
      if (isHeaderSticky) setIsHeaderSticky(false);
    }
  };

  return (
    <div 
      ref={scrollContainerRef}
      onScroll={handleScroll}
      className="flex-1 overflow-y-auto select-none bg-[#121212] text-white relative"
    >
      {/* Spotify Desktop Sticky Top Header */}
      <div 
        className={`sticky top-0 z-30 px-4 sm:px-8 py-3 bg-[#121212]/95 backdrop-blur-md border-b border-white/10 flex items-center justify-between transition-all duration-200 ${
          isHeaderSticky ? 'opacity-100 translate-y-0 shadow-lg' : 'opacity-0 -translate-y-2 pointer-events-none'
        }`}
      >
        <div className="flex items-center gap-4 min-w-0">
          <button
            onClick={() => onPlayAll(processedTracks.length > 0 ? processedTracks : rawTracks)}
            disabled={rawTracks.length === 0}
            className="w-10 h-10 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-md hover:scale-105 active:scale-95 transition-all flex-shrink-0"
            title="Putar Playlist"
          >
            <Play className="w-4 h-4 fill-black ml-0.5" />
          </button>
          <div className="min-w-0">
            <h2 className="text-white font-black text-lg truncate tracking-tight">
              {playlist.name}
            </h2>
          </div>
        </div>
        <span className="text-xs text-[#a7a7a7] hidden sm:block font-medium">
          {processedTracks.length} / {rawTracks.length} lagu
        </span>
      </div>

      {/* Spotify Playlist Banner Header */}
      <div className="p-4 sm:p-8 bg-gradient-to-b from-[#092b52] via-[#161616] to-[#121212] flex flex-col sm:flex-row items-center sm:items-end gap-5 sm:gap-8 pb-6 border-b border-white/[0.04]">
        <img
          src={playlist.cover || DEFAULT_ARTWORK}
          alt={playlist.name}
          onError={(e) => {
            e.currentTarget.onerror = null;
            e.currentTarget.src = DEFAULT_ARTWORK;
          }}
          className="w-40 h-40 sm:w-52 sm:h-52 rounded-md object-cover shadow-2xl flex-shrink-0 bg-[#282828]"
        />

        <div className="space-y-2 text-center sm:text-left flex-1 min-w-0">
          <span className="text-[11px] font-bold uppercase tracking-wider text-neutral-300">
            {playlist.source === 'spotify' ? '🟢 Playlist Spotify' : playlist.source === 'youtube' ? '🔴 YouTube Music' : 'Playlist Publik'}
          </span>

          <h1 className="text-white text-2xl sm:text-5xl font-black tracking-tight truncate leading-tight">
            {playlist.name}
          </h1>

          <p className="text-[#b3b3b3] text-xs sm:text-sm max-w-2xl line-clamp-2">
            {playlist.description || 'Dibuat untuk Kamu • Disimpan lokal di browser tanpa database.'}
          </p>

          <div className="flex items-center justify-center sm:justify-start gap-2 text-xs text-neutral-300 font-semibold pt-1">
            <span className="text-white font-bold">McMusic</span>
            <span>•</span>
            <span>{rawTracks.length} lagu</span>
            <span>•</span>
            <span className="text-[#b3b3b3]">{totalMinutes} mnt</span>
          </div>
        </div>
      </div>

      {/* Action Bar (Spotify Circular Electric Azure Play Button + In-Playlist Search & Sort) */}
      <div className="px-4 sm:px-8 py-4 flex flex-wrap items-center justify-between gap-4">
        {/* Left: Play, Shuffle, Export, Delete */}
        <div className="flex items-center gap-4 sm:gap-6">
          <button
            onClick={() => onPlayAll(processedTracks.length > 0 ? processedTracks : rawTracks)}
            disabled={rawTracks.length === 0}
            className="w-12 h-12 sm:w-14 sm:h-14 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-xl hover:scale-105 active:scale-95 transition-all disabled:opacity-40"
            title="Putar Semua"
          >
            <Play className="w-5 h-5 sm:w-6 sm:h-6 fill-black ml-0.5" />
          </button>

          <button
            onClick={() => onShuffleAll(processedTracks.length > 0 ? processedTracks : rawTracks)}
            disabled={rawTracks.length === 0}
            className="p-2 text-[#b3b3b3] hover:text-white transition-colors"
            title="Putar Acak"
          >
            <Shuffle className="w-5 h-5 sm:w-6 sm:h-6" />
          </button>

          <button
            onClick={() => playlistImporter.exportToJson(playlist)}
            className="p-2 text-[#b3b3b3] hover:text-white transition-colors"
            title="Download Backup JSON"
          >
            <Download className="w-5 h-5" />
          </button>

          {playlist.id !== 'pl-favorites' && onDeletePlaylist && (
            <button
              onClick={() => {
                if (confirm(`Hapus playlist "${playlist.name}"?`)) {
                  onDeletePlaylist(playlist.id);
                }
              }}
              className="p-2 text-[#b3b3b3] hover:text-rose-400 transition-colors"
              title="Hapus Playlist"
            >
              <Trash2 className="w-5 h-5" />
            </button>
          )}
        </div>

        {/* Right: In-Playlist Search & Sort Menu */}
        <div className="flex items-center gap-2 sm:gap-3 ml-auto">
          {/* Search Toggle / Input */}
          <div className="relative flex items-center">
            {isSearchOpen ? (
              <div className="flex items-center bg-[#242424] rounded-full px-3 py-1.5 border border-white/10 animate-in fade-in duration-150">
                <Search className="w-3.5 h-3.5 text-[#b3b3b3] mr-2 flex-shrink-0" />
                <input
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Cari dalam playlist..."
                  className="bg-transparent text-xs text-white placeholder-neutral-400 focus:outline-none w-32 sm:w-44"
                  autoFocus
                />
                {searchQuery && (
                  <button
                    onClick={() => setSearchQuery('')}
                    className="p-0.5 text-[#b3b3b3] hover:text-white mr-1"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                )}
                <button
                  onClick={() => {
                    setIsSearchOpen(false);
                    setSearchQuery('');
                  }}
                  className="text-[11px] text-neutral-400 hover:text-white pl-1 border-l border-white/10"
                >
                  Batal
                </button>
              </div>
            ) : (
              <button
                onClick={() => setIsSearchOpen(true)}
                className="p-2 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
                title="Cari lagu dalam playlist"
              >
                <Search className="w-4 h-4 sm:w-5 sm:h-5" />
              </button>
            )}
          </div>

          {/* Sort Dropdown */}
          <div className="relative">
            <button
              onClick={() => setIsSortMenuOpen(!isSortMenuOpen)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold text-[#b3b3b3] hover:text-white bg-white/5 hover:bg-white/10 transition-colors border border-white/5"
              title="Urutkan Playlist"
            >
              <ArrowUpDown className="w-3.5 h-3.5 text-[#00a3ff]" />
              <span className="hidden sm:inline">
                {sortBy === 'custom' && 'Urutan Kustom'}
                {sortBy === 'title' && 'Judul (A-Z)'}
                {sortBy === 'artist' && 'Artis (A-Z)'}
                {sortBy === 'duration-desc' && 'Durasi Terlama'}
                {sortBy === 'duration-asc' && 'Durasi Terpendek'}
              </span>
              <ChevronDown className="w-3.5 h-3.5 opacity-60" />
            </button>

            {isSortMenuOpen && (
              <>
                <div
                  className="fixed inset-0 z-30"
                  onClick={() => setIsSortMenuOpen(false)}
                />
                <div className="absolute right-0 mt-2 w-48 bg-[#242424] rounded-xl shadow-2xl border border-white/10 py-1.5 z-40 text-xs">
                  <p className="px-3 py-1 text-[10px] font-bold uppercase tracking-wider text-neutral-400">
                    Urutkan Berdasarkan
                  </p>
                  {[
                    { key: 'custom', label: 'Urutan Kustom' },
                    { key: 'title', label: 'Judul (A - Z)' },
                    { key: 'artist', label: 'Nama Artis (A - Z)' },
                    { key: 'duration-desc', label: 'Durasi Terlama' },
                    { key: 'duration-asc', label: 'Durasi Terpendek' },
                  ].map((opt) => (
                    <button
                      key={opt.key}
                      onClick={() => {
                        setSortBy(opt.key);
                        setIsSortMenuOpen(false);
                      }}
                      className={`w-full flex items-center justify-between px-3 py-2 text-left hover:bg-white/10 transition-colors ${
                        sortBy === opt.key ? 'text-[#00a3ff] font-bold bg-white/5' : 'text-neutral-200'
                      }`}
                    >
                      <span>{opt.label}</span>
                      {sortBy === opt.key && <Check className="w-3.5 h-3.5 text-[#00a3ff]" />}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Tracks Table */}
      <div className="px-3 sm:px-8 pb-32 md:pb-16">
        {rawTracks.length === 0 ? (
          <div className="py-20 text-center text-neutral-500 space-y-3">
            <Music className="w-12 h-12 mx-auto opacity-40" />
            <p className="text-base font-semibold text-neutral-300">Playlist ini masih kosong</p>
            <p className="text-xs">Cari lagu di tab Cari atau impor playlist dari Spotify!</p>
          </div>
        ) : processedTracks.length === 0 ? (
          <div className="py-20 text-center text-neutral-500 space-y-3">
            <Search className="w-12 h-12 mx-auto opacity-40 text-neutral-400" />
            <p className="text-base font-semibold text-neutral-300">Tidak ada lagu yang cocok</p>
            <p className="text-xs">Tidak ditemukan lagu untuk "{searchQuery}" di playlist ini.</p>
            <button
              onClick={() => setSearchQuery('')}
              className="mt-2 text-xs font-semibold text-[#00a3ff] hover:underline"
            >
              Hapus pencarian
            </button>
          </div>
        ) : (
          <div className="divide-y divide-[#282828]/50">
            {/* Table Header */}
            <div className="flex items-center justify-between px-3 py-2 text-xs font-bold uppercase tracking-wider text-[#b3b3b3] border-b border-[#282828]">
              <div className="flex items-center gap-4 min-w-0 flex-1">
                <span className="w-6 text-center">#</span>
                <span>Judul</span>
              </div>
              <span className="hidden md:block w-48 text-left">Album</span>
              <div className="flex items-center justify-end gap-8 w-24 pr-2">
                <Clock className="w-4 h-4" />
              </div>
            </div>

            {/* Track Rows */}
            {processedTracks.map((t, idx) => {
              const isCurrent = currentTrack?.id === t.id;
              const isLiked = likedTrackIds.has(t.id);

              return (
                <div
                  key={t.id || idx}
                  onClick={() => {
                    if (isCurrent) {
                      onTogglePlayPause();
                    } else {
                      onPlayTrack(t, processedTracks);
                    }
                  }}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    onTrackContextMenu?.(e, t);
                  }}
                  className={`group flex items-center justify-between px-3 py-2.5 rounded-lg cursor-pointer transition-colors ${
                    isCurrent
                      ? 'bg-[#242424] text-white'
                      : 'hover:bg-[#1a1a1a] text-neutral-300'
                  }`}
                >
                  {/* Left: Rank/Equalizer, Art, Title, Artist */}
                  <div className="flex items-center gap-3 sm:gap-4 min-w-0 flex-1 pr-3">
                    <div className="w-6 flex items-center justify-center flex-shrink-0">
                      {isCurrent && isPlaying ? (
                        <div className="flex items-end gap-0.5 h-3.5 group-hover:hidden">
                          <span className="w-1 bg-[#00a3ff] rounded-full animate-eq-1" />
                          <span className="w-1 bg-[#00a3ff] rounded-full animate-eq-2" />
                          <span className="w-1 bg-[#00a3ff] rounded-full animate-eq-3" />
                        </div>
                      ) : (
                        <span className={`tabular-nums text-xs text-[#b3b3b3] group-hover:hidden ${isCurrent ? 'text-[#00a3ff] font-bold' : ''}`}>
                          {idx + 1}
                        </span>
                      )}

                      <button className="hidden group-hover:flex items-center justify-center text-white">
                        {isCurrent && isPlaying ? (
                          <Pause className="w-3.5 h-3.5 fill-white" />
                        ) : (
                          <Play className="w-3.5 h-3.5 fill-white ml-0.5" />
                        )}
                      </button>
                    </div>

                    <img
                      src={t.artwork || DEFAULT_ARTWORK}
                      alt={t.title}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-10 h-10 rounded-md object-cover flex-shrink-0 bg-[#282828]"
                    />

                    <div className="truncate min-w-0">
                      <p className={`text-sm font-bold truncate tracking-tight ${isCurrent ? 'text-[#00a3ff]' : 'text-white'}`}>
                        {cleanTrackTitle(t.title)}
                      </p>
                      <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                        {t.artist}
                      </p>
                    </div>
                  </div>

                  {/* Album (Tablet & Desktop) */}
                  <div className="hidden md:block w-48 truncate text-xs text-[#b3b3b3] pr-4">
                    {t.album || 'Single'}
                  </div>

                  {/* Actions & Duration */}
                  <div className="flex items-center justify-end gap-2 sm:gap-3 w-28 flex-shrink-0">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onToggleLike(t);
                      }}
                      className={`p-1.5 rounded-full transition-all ${
                        isLiked 
                          ? '!opacity-100 text-[#00a3ff]' 
                          : 'opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-white'
                      }`}
                      title="Sukai"
                    >
                      <Heart className={`w-3.5 h-3.5 ${isLiked ? 'fill-current' : ''}`} />
                    </button>

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onPlayTrack(t, processedTracks);
                        onOpenLyrics();
                      }}
                      className="p-1.5 rounded-full opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-[#00a3ff] transition-all"
                      title="Lirik Karaoke"
                    >
                      <Mic2 className="w-3.5 h-3.5" />
                    </button>

                    <span className="text-xs tabular-nums text-[#a7a7a7] min-w-[32px] text-right">
                      {Math.floor(t.duration / 60)}:{(t.duration % 60).toString().padStart(2, '0')}
                    </span>

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onTrackContextMenu?.(e, t);
                      }}
                      className="p-1.5 rounded-full opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-white transition-all"
                      title="Opsi Lainnya"
                    >
                      <MoreHorizontal className="w-3.5 h-3.5" />
                    </button>

                    {onRemoveTrack && playlist.id !== 'pl-favorites' && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onRemoveTrack(playlist.id, t.id);
                        }}
                        className="p-1.5 rounded-full opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-rose-400 transition-all"
                        title="Hapus lagu"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
