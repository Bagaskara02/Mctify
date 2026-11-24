import React, { useState, useRef, useMemo, useEffect } from 'react';
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
  Check,
  Pencil,
  Camera,
  Upload,
  GripVertical
} from 'lucide-react';
import { playlistImporter } from '../services/playlistImporter';
import { DEFAULT_ARTWORK } from '../services/musicApi';
import { sanitizeMediaUrl } from '../services/storageService';
import { extractPaletteFromImage } from '../utils/colorExtractor';

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
  onUpdatePlaylist,
  onSaveMixToLibrary,
  isSavedInLibrary = false,
  onTrackContextMenu,
  onReorderTracks,
}) {
  const [isHeaderSticky, setIsHeaderSticky] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const [sortBy, setSortBy] = useState('custom'); // 'custom' | 'title' | 'artist' | 'duration-desc' | 'duration-asc'
  const [isSortMenuOpen, setIsSortMenuOpen] = useState(false);
  const [bannerColor, setBannerColor] = useState('#1e3264');
  const scrollContainerRef = useRef(null);

  // Drag and drop reordering state
  const [draggedIndex, setDraggedIndex] = useState(null);
  const [dragOverIndex, setDragOverIndex] = useState(null);

  // Reorder is enabled in custom sort order without active text search filter
  const canDrag = !searchQuery.trim() && sortBy === 'custom' && typeof onReorderTracks === 'function';

  const handleDragStart = (e, index) => {
    if (!canDrag) return;
    setDraggedIndex(index);
    e.dataTransfer.effectAllowed = 'move';
    try {
      e.dataTransfer.setData('text/plain', String(index));
    } catch (_) {}
  };

  const handleDragOver = (e, index) => {
    if (!canDrag || draggedIndex === null) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (dragOverIndex !== index) {
      setDragOverIndex(index);
    }
  };

  const handleDrop = (e, targetIndex) => {
    if (!canDrag || draggedIndex === null) return;
    e.preventDefault();
    if (draggedIndex !== targetIndex) {
      const currentList = Array.isArray(playlist?.tracks) ? Array.from(playlist.tracks) : [];
      if (currentList.length > 0) {
        const [moved] = currentList.splice(draggedIndex, 1);
        currentList.splice(targetIndex, 0, moved);
        onReorderTracks(playlist.id, currentList);
      }
    }
    setDraggedIndex(null);
    setDragOverIndex(null);
  };

  const handleDragEnd = () => {
    setDraggedIndex(null);
    setDragOverIndex(null);
  };

  // Edit Playlist Modal state
  const isEditable = playlist?.id !== 'pl-liked' && playlist?.id !== 'pl-history';
  const [isEditModalOpen, setIsEditModalOpen] = useState(false);
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editCover, setEditCover] = useState('');

  useEffect(() => {
    const artUrl = playlist?.id === 'pl-liked' ? null : (playlist?.cover || playlist?.tracks?.[0]?.artwork);
    if (playlist?.id === 'pl-liked') {
      setBannerColor('#450af5');
      return;
    }
    if (!artUrl) return;
    let cancelled = false;
    extractPaletteFromImage(artUrl).then((pal) => {
      if (!cancelled && pal?.primary) {
        setBannerColor(pal.primary);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [playlist?.id, playlist?.cover]);

  const rawTracks = playlist?.tracks || [];
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

  if (!playlist) {
    return (
      <div className="flex-1 flex items-center justify-center text-neutral-400 bg-[#121212]">
        <p>Tidak ada playlist yang dipilih</p>
      </div>
    );
  }

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
            className="w-10 h-10 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-md hover:scale-105 active:scale-95 transition-all flex-shrink-0"
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

      {/* Dynamic Spotify Playlist Banner Header matching Cover Artwork */}
      <div
        style={{
          background: `linear-gradient(180deg, ${bannerColor} 0%, #161616 78%, #121212 100%)`,
        }}
        className="p-4 sm:p-8 flex flex-col sm:flex-row items-center sm:items-end gap-5 sm:gap-8 pb-6 border-b border-white/[0.04] transition-colors duration-700"
      >
        <div 
          onClick={() => {
            if (isEditable) {
              setEditName(playlist.name);
              setEditDesc(playlist.description || '');
              setEditCover(playlist.cover || '');
              setIsEditModalOpen(true);
            }
          }}
          className={`relative group/cover ${isEditable ? 'cursor-pointer' : ''}`}
        >
          <img
            src={
              (playlist.cover && playlist.cover.replace(/hq(hq)?720\.jpg/gi, 'hqdefault.jpg')) ||
              (rawTracks[0]?.artwork && rawTracks[0].artwork.replace(/hq(hq)?720\.jpg/gi, 'hqdefault.jpg')) ||
              (rawTracks[0]?.videoId ? `https://i.ytimg.com/vi/${rawTracks[0].videoId}/hqdefault.jpg` : DEFAULT_ARTWORK)
            }
            alt={playlist.name}
            onLoad={(e) => {
              // YouTube 120x90 404 placeholder detection
              if (e.currentTarget.naturalWidth === 120 && e.currentTarget.naturalHeight === 90) {
                if (rawTracks[0]?.artwork && !rawTracks[0].artwork.includes('hqdefault.jpg')) {
                  e.currentTarget.src = rawTracks[0].artwork;
                } else {
                  e.currentTarget.src = DEFAULT_ARTWORK;
                }
              }
            }}
            onError={(e) => {
              e.currentTarget.onerror = null;
              if (rawTracks[0]?.artwork && !e.currentTarget.src.includes('hqdefault.jpg')) {
                e.currentTarget.src = rawTracks[0].artwork.replace(/hq(hq)?720\.jpg/gi, 'hqdefault.jpg');
              } else if (rawTracks[0]?.videoId) {
                e.currentTarget.src = `https://i.ytimg.com/vi/${rawTracks[0].videoId}/hqdefault.jpg`;
              } else {
                e.currentTarget.src = DEFAULT_ARTWORK;
              }
            }}
            className="w-40 h-40 sm:w-52 sm:h-52 rounded-md object-cover shadow-2xl flex-shrink-0 bg-[#282828]"
          />
          {isEditable && (
            <div className="absolute inset-0 bg-black/60 opacity-0 group-hover/cover:opacity-100 transition-opacity flex flex-col items-center justify-center rounded-md gap-1 text-white">
              <Camera className="w-8 h-8 text-white/90" />
              <span className="text-xs font-bold">Ubah Foto</span>
            </div>
          )}
        </div>

        <div className="space-y-2 text-center sm:text-left flex-1 min-w-0">
          <span className="text-[11px] font-bold uppercase tracking-wider text-neutral-300">
            {playlist.source === 'spotify'
              ? '🟢 Playlist Spotify'
              : playlist.source === 'youtube'
              ? '🔴 YouTube Music'
              : playlist.source === 'mix'
              ? '✨ Dibuat Untuk Kamu'
              : playlist.source === 'album'
              ? '💿 Album'
              : 'Playlist Publik'}
          </span>

          <div className="flex items-center justify-center sm:justify-start gap-3">
            <h1 
              onClick={() => {
                if (isEditable) {
                  setEditName(playlist.name);
                  setEditDesc(playlist.description || '');
                  setEditCover(playlist.cover || '');
                  setIsEditModalOpen(true);
                }
              }}
              className={`text-white text-2xl sm:text-5xl font-black tracking-tight truncate leading-tight ${
                isEditable ? 'hover:underline cursor-pointer' : ''
              }`}
            >
              {playlist.name}
            </h1>
            {isEditable && (
              <button
                onClick={() => {
                  setEditName(playlist.name);
                  setEditDesc(playlist.description || '');
                  setEditCover(playlist.cover || '');
                  setIsEditModalOpen(true);
                }}
                className="p-1.5 rounded-full hover:bg-white/10 text-white/50 hover:text-white transition-colors flex-shrink-0"
                title="Edit Nama & Foto Playlist"
              >
                <Pencil className="w-4 h-4" />
              </button>
            )}
          </div>

          <p className="text-[#b3b3b3] text-xs sm:text-sm max-w-2xl line-clamp-2">
            {playlist.description || 'Dibuat untuk Kamu • Disimpan lokal di browser tanpa database.'}
          </p>

          <div className="flex items-center justify-center sm:justify-start gap-2 text-xs text-neutral-300 font-semibold pt-1">
            <span className="text-white font-bold">McTify</span>
            <span>•</span>
            <span>{rawTracks.length} lagu</span>
            <span>•</span>
            <span className="text-[#b3b3b3]">{totalMinutes} mnt</span>
          </div>
        </div>
      </div>

      {/* Action Bar (Spotify Circular Green Play Button + In-Playlist Search & Sort) */}
      <div className="px-4 sm:px-8 py-4 flex flex-wrap items-center justify-between gap-4">
        {/* Left: Play, Shuffle, Export, Delete */}
        <div className="flex items-center gap-4 sm:gap-6">
          <button
            onClick={() => onPlayAll(processedTracks.length > 0 ? processedTracks : rawTracks)}
            disabled={rawTracks.length === 0}
            className="w-12 h-12 sm:w-14 sm:h-14 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-xl hover:scale-105 active:scale-95 transition-all disabled:opacity-40"
            title="Putar Semua"
          >
            <Play className="w-5 h-5 sm:w-6 sm:h-6 fill-black ml-0.5" />
          </button>

          <button
            onClick={() => onShuffleAll(processedTracks.length > 0 ? processedTracks : rawTracks)}
            disabled={rawTracks.length === 0}
            className="p-2 text-[#b3b3b3] hover:text-[#3B82F6] transition-colors"
            title="Putar Acak"
          >
            <Shuffle className="w-5 h-5 sm:w-6 sm:h-6" />
          </button>

          {onSaveMixToLibrary && (
            <button
              onClick={() => onSaveMixToLibrary(playlist)}
              disabled={isSavedInLibrary}
              className={`px-3.5 py-1.5 rounded-full text-xs font-bold flex items-center gap-1.5 border transition-all ${
                isSavedInLibrary
                  ? 'border-[#3B82F6]/40 bg-[#3B82F6]/15 text-[#3B82F6]'
                  : 'border-white/30 hover:border-white text-white hover:bg-white/10'
              }`}
              title={isSavedInLibrary ? 'Tersimpan di Koleksi Kamu' : 'Simpan ke Koleksi Kamu'}
            >
              {isSavedInLibrary ? <Check className="w-3.5 h-3.5" /> : null}
              <span>{isSavedInLibrary ? 'Tersimpan di Koleksi' : '+ Simpan ke Koleksi'}</span>
            </button>
          )}

          {isEditable && (
            <button
              onClick={() => {
                setEditName(playlist.name);
                setEditDesc(playlist.description || '');
                setEditCover(playlist.cover || '');
                setIsEditModalOpen(true);
              }}
              className="p-2 text-[#b3b3b3] hover:text-[#3B82F6] transition-colors"
              title="Edit Nama & Foto Playlist"
            >
              <Pencil className="w-5 h-5 sm:w-6 sm:h-6" />
            </button>
          )}

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
              <ArrowUpDown className="w-3.5 h-3.5 text-[#3B82F6]" />
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
                    { key: 'custom', label: 'Urutan Kustom (Drag & Drop)' },
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
                        sortBy === opt.key ? 'text-[#3B82F6] font-bold bg-white/5' : 'text-neutral-200'
                      }`}
                    >
                      <span>{opt.label}</span>
                      {sortBy === opt.key && <Check className="w-3.5 h-3.5 text-[#3B82F6]" />}
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
              className="mt-2 text-xs font-semibold text-[#3B82F6] hover:underline"
            >
              Hapus pencarian
            </button>
          </div>
        ) : (
          <div className="divide-y divide-[#282828]/50">
            {/* Table Header */}
            <div className="flex items-center justify-between px-3 py-2 text-xs font-bold uppercase tracking-wider text-[#b3b3b3] border-b border-[#282828]">
              <div className="flex items-center gap-2.5 sm:gap-4 min-w-0 flex-1">
                {canDrag && <span className="w-4 text-center opacity-40 text-[10px]" title="Drag & drop aktif">::</span>}
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
              const isBeingDragged = draggedIndex === idx;
              const isDragOver = dragOverIndex === idx && draggedIndex !== idx;

              return (
                <div
                  key={t.id || idx}
                  draggable={canDrag}
                  onDragStart={(e) => handleDragStart(e, idx)}
                  onDragOver={(e) => handleDragOver(e, idx)}
                  onDrop={(e) => handleDrop(e, idx)}
                  onDragEnd={handleDragEnd}
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
                  className={`group relative flex items-center justify-between px-3 py-2.5 rounded-lg cursor-pointer transition-all duration-150 ${
                    isBeingDragged
                      ? 'opacity-35 scale-[0.99] bg-[#222] border border-dashed border-white/20'
                      : isDragOver
                      ? 'bg-[#3B82F6]/15 border-t-2 border-[#3B82F6]'
                      : isCurrent
                      ? 'bg-[#242424] text-white'
                      : 'hover:bg-[#1a1a1a] text-neutral-300'
                  }`}
                >
                  {/* Left: Grip, Rank/Equalizer, Art, Title, Artist */}
                  <div className="flex items-center gap-2 sm:gap-3.5 min-w-0 flex-1 pr-3">
                    {/* Drag Grip Handle */}
                    {canDrag && (
                      <div 
                        className="opacity-0 group-hover:opacity-70 hover:!opacity-100 cursor-grab active:cursor-grabbing text-neutral-400 p-0.5 -ml-1 flex-shrink-0 transition-opacity"
                        title="Tahan & geser untuk mengubah urutan lagu"
                        onMouseDown={(e) => e.stopPropagation()}
                      >
                        <GripVertical className="w-3.5 h-3.5" />
                      </div>
                    )}

                    <div className="w-6 flex items-center justify-center flex-shrink-0">
                      {isCurrent && isPlaying ? (
                        <div className="flex items-end gap-0.5 h-3.5 group-hover:hidden">
                          <span className="w-1 bg-[#3B82F6] rounded-full animate-eq-1" />
                          <span className="w-1 bg-[#3B82F6] rounded-full animate-eq-2" />
                          <span className="w-1 bg-[#3B82F6] rounded-full animate-eq-3" />
                        </div>
                      ) : (
                        <span className={`tabular-nums text-xs text-[#b3b3b3] group-hover:hidden ${isCurrent ? 'text-[#3B82F6] font-bold' : ''}`}>
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
                      src={
                        (t.videoId ? `https://i.ytimg.com/vi/${t.videoId}/hqdefault.jpg` : (t.artwork ? t.artwork.split('?')[0].replace(/hq(hq)?720\.jpg/, 'hqdefault.jpg') : DEFAULT_ARTWORK))
                      }
                      alt={t.title}
                      onLoad={(e) => {
                        // YouTube 120x90 404 placeholder detection
                        if (e.currentTarget.naturalWidth === 120 && e.currentTarget.naturalHeight === 90) {
                          if (t.artwork && !t.artwork.includes('ytimg.com') && !t.artwork.includes('default.jpg')) {
                            e.currentTarget.src = t.artwork;
                          } else {
                            e.currentTarget.src = DEFAULT_ARTWORK;
                          }
                        }
                      }}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        if (t.videoId && !e.currentTarget.src.includes('hqdefault.jpg')) {
                          e.currentTarget.src = `https://i.ytimg.com/vi/${t.videoId}/hqdefault.jpg`;
                        } else {
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }
                      }}
                      className="w-10 h-10 rounded-md object-cover flex-shrink-0 bg-[#282828]"
                    />

                    <div className="truncate min-w-0">
                      <p className={`text-sm font-bold truncate tracking-tight ${isCurrent ? 'text-[#3B82F6]' : 'text-white'}`}>
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
                          ? '!opacity-100 text-[#3B82F6]' 
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
                      className="p-1.5 rounded-full opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-[#3B82F6] transition-all"
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

      {/* Modal Edit Detail Playlist */}
      {isEditModalOpen && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/75 backdrop-blur-sm p-4 animate-fade-in">
          <div className="bg-[#282828] border border-white/10 rounded-xl p-6 w-full max-w-md shadow-2xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-white/10">
              <h3 className="text-white font-bold text-lg">Edit Detail Playlist</h3>
              <button 
                onClick={() => setIsEditModalOpen(false)}
                className="text-white/60 hover:text-white p-1 rounded-full hover:bg-white/10"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="flex flex-col sm:flex-row gap-4 items-center">
              <div className="relative w-32 h-32 flex-shrink-0 group rounded-lg overflow-hidden bg-black/40 border border-white/10 shadow-lg">
                <img 
                  src={editCover || DEFAULT_ARTWORK} 
                  alt="Cover preview"
                  onError={(e) => {
                    e.currentTarget.onerror = null;
                    e.currentTarget.src = DEFAULT_ARTWORK;
                  }}
                  className="w-full h-full object-cover"
                />
                <label className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col items-center justify-center cursor-pointer text-white gap-1 text-[11px] font-bold">
                  <Upload className="w-5 h-5" />
                  <span>Pilih File</span>
                  <input 
                    type="file" 
                    accept="image/*" 
                    className="hidden" 
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      if (file) {
                        if (!file.type.startsWith('image/') || file.type === 'image/svg+xml' || file.size > 2 * 1024 * 1024) {
                          return;
                        }
                        const reader = new FileReader();
                        reader.onload = (evt) => {
                          if (typeof evt.target?.result === 'string') {
                            const safeUrl = sanitizeMediaUrl(evt.target.result, '');
                            if (safeUrl) setEditCover(safeUrl);
                          }
                        };
                        reader.readAsDataURL(file);
                      }
                    }}
                  />
                </label>
              </div>

              <div className="flex-1 w-full space-y-3">
                <div>
                  <label className="text-xs font-semibold text-neutral-400 block mb-1">Nama Playlist</label>
                  <input 
                    type="text" 
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    placeholder="Nama playlist..."
                    className="w-full px-3 py-2 rounded-lg bg-[#3e3e3e] text-white text-sm focus:outline-none focus:ring-2 focus:ring-[#3B82F6]"
                  />
                </div>
                <div>
                  <label className="text-xs font-semibold text-neutral-400 block mb-1">URL Foto Sampul</label>
                  <input 
                    type="text" 
                    value={editCover.startsWith('data:') ? '(File Gambar Lokal)' : editCover}
                    onChange={(e) => setEditCover(e.target.value)}
                    placeholder="https://... (atau klik foto)"
                    className="w-full px-3 py-2 rounded-lg bg-[#3e3e3e] text-white text-xs focus:outline-none focus:ring-2 focus:ring-[#3B82F6]"
                  />
                </div>
              </div>
            </div>

            <div>
              <label className="text-xs font-semibold text-neutral-400 block mb-1">Deskripsi (Opsional)</label>
              <textarea 
                value={editDesc}
                onChange={(e) => setEditDesc(e.target.value)}
                rows={2}
                placeholder="Beri deskripsi singkat..."
                className="w-full px-3 py-2 rounded-lg bg-[#3e3e3e] text-white text-xs focus:outline-none focus:ring-2 focus:ring-[#3B82F6] resize-none"
              />
            </div>

            <div className="flex justify-end gap-3 pt-2">
              <button 
                onClick={() => setIsEditModalOpen(false)}
                className="px-4 py-2 rounded-full text-white/80 hover:text-white text-sm font-semibold hover:bg-white/10"
              >
                Batal
              </button>
              <button 
                onClick={() => {
                  if (editName.trim()) {
                    const safeCover = sanitizeMediaUrl(editCover.trim(), '') || playlist.cover || DEFAULT_ARTWORK;
                    onUpdatePlaylist?.({
                      ...playlist,
                      name: editName.trim().slice(0, 120),
                      description: editDesc.trim().slice(0, 400),
                      cover: safeCover,
                    });
                    setIsEditModalOpen(false);
                  }
                }}
                disabled={!editName.trim()}
                className="px-5 py-2 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] disabled:opacity-40 text-black font-bold text-sm shadow-lg transition-all"
              >
                Simpan
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
