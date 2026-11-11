import React, { useState, useEffect, useRef } from 'react';
import {
  Search,
  Play,
  Home,
  Compass,
  Heart,
  Sliders,
  Headphones,
  Download,
  Mic2,
  ListPlus,
  Video,
  X,
  CornerDownLeft,
  Sparkles,
} from 'lucide-react';
import { musicApi, DEFAULT_ARTWORK } from '../services/musicApi';

export default function CommandPaletteModal({
  isOpen,
  onClose,
  onNavigate,
  onPlayTrackFromSearch,
  onOpenImportSpotify,
  onOpenImportYouTube,
  onOpenEqualizer,
  onOpenAudioQuality,
  onOpenLyrics,
  onOpenDownloadApp,
}) {
  const [query, setQuery] = useState('');
  const [songs, setSongs] = useState([]);
  const [isSearching, setIsSearching] = useState(false);
  const [selectedIdx, setSelectedIdx] = useState(0);
  const inputRef = useRef(null);

  const quickCommands = [
    { id: 'home', label: 'Buka Beranda', hint: 'Navigasi', icon: Home, action: () => onNavigate('discover') },
    { id: 'search', label: 'Jelajahi Semua Genre & Search', hint: 'Navigasi', icon: Compass, action: () => onNavigate('search') },
    { id: 'liked', label: 'Lagu yang Disukai', hint: 'Koleksi', icon: Heart, action: () => onNavigate('liked') },
    { id: 'lyrics', label: 'Buka Lirik Karaoke Penuh', hint: 'Pemutar', icon: Mic2, action: onOpenLyrics },
    { id: 'eq', label: 'Equalizer Studio & Bass Boost', hint: 'Audio', icon: Sliders, action: onOpenEqualizer },
    { id: 'quality', label: 'Pengaturan Kualitas Audio (Bitrate)', hint: 'Audio', icon: Headphones, action: onOpenAudioQuality },
    { id: 'spotify', label: 'Impor Playlist Spotify', hint: 'Alat', icon: ListPlus, action: onOpenImportSpotify },
    { id: 'youtube', label: 'Putar dari Link YouTube', hint: 'Alat', icon: Video, action: onOpenImportYouTube },
    { id: 'apk', label: 'Unduh Aplikasi Android (APK)', hint: 'Mobile', icon: Download, action: onOpenDownloadApp },
  ];

  useEffect(() => {
    if (isOpen) {
      setQuery('');
      setSongs([]);
      setSelectedIdx(0);
      setTimeout(() => inputRef.current?.focus(), 40);
    }
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return;
    const trimmed = query.trim();
    if (!trimmed) {
      setSongs([]);
      setIsSearching(false);
      setSelectedIdx(0);
      return;
    }

    setIsSearching(true);
    const t = setTimeout(async () => {
      try {
        const res = await musicApi.searchAll(trimmed);
        let list = res.songs || [];
        if (list.length === 0 && trimmed.split(' ').length >= 3) {
          list = await musicApi.searchTracksByLyrics(trimmed);
        }
        setSongs((list || []).slice(0, 6));
        setSelectedIdx(0);
      } catch (_) {
        setSongs([]);
      } finally {
        setIsSearching(false);
      }
    }, 220);

    return () => clearTimeout(t);
  }, [query, isOpen]);

  if (!isOpen) return null;

  const filteredCommands = quickCommands.filter((c) =>
    !query.trim() ? true : c.label.toLowerCase().includes(query.toLowerCase()) || c.hint.toLowerCase().includes(query.toLowerCase())
  );

  const items = [
    ...songs.map((s) => ({ kind: 'track', id: s.id, data: s })),
    ...filteredCommands.map((c) => ({ kind: 'cmd', id: c.id, data: c })),
  ];

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      onClose();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      setSelectedIdx((prev) => (items.length ? (prev + 1) % items.length : 0));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setSelectedIdx((prev) => (items.length ? (prev - 1 + items.length) % items.length : 0));
    } else if (e.key === 'Enter' && items[selectedIdx]) {
      e.preventDefault();
      const chosen = items[selectedIdx];
      if (chosen.kind === 'track') {
        onPlayTrackFromSearch(chosen.data);
      } else {
        chosen.data.action?.();
      }
      onClose();
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-start justify-center pt-16 sm:pt-24 px-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xl bg-[#18181c] border border-white/15 rounded-2xl shadow-2xl overflow-hidden animate-spotify-popup"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Top Input */}
        <div className="flex items-center gap-3 px-4 py-3.5 border-b border-white/10">
          <Search className="w-5 h-5 text-[#3B82F6] flex-shrink-0" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ketik judul lagu, artis, penggalan lirik, atau perintah..."
            className="flex-1 bg-transparent text-white text-sm sm:text-base font-medium placeholder-[#888] focus:outline-none"
          />
          {query && (
            <button
              onClick={() => setQuery('')}
              className="p-1 text-[#888] hover:text-white rounded-full"
            >
              <X className="w-4 h-4" />
            </button>
          )}
          <kbd className="hidden sm:inline-flex items-center px-2 py-0.5 text-[10px] font-bold text-[#999] bg-white/5 border border-white/10 rounded">
            ESC
          </kbd>
        </div>

        {/* Results & Commands List */}
        <div className="max-h-[400px] overflow-y-auto p-2 space-y-1">
          {isSearching && (
            <div className="px-3 py-2 text-xs text-[#999] flex items-center gap-2">
              <Sparkles className="w-3.5 h-3.5 text-[#3B82F6] animate-pulse" />
              <span>Mencari lagu & lirik di katalog McTify...</span>
            </div>
          )}

          {songs.length > 0 && (
            <div className="pb-1">
              <div className="px-3 py-1 text-[10px] font-bold uppercase tracking-wider text-[#888]">
                Lagu Cocok Langsung
              </div>
              {songs.map((track, i) => {
                const isSelected = selectedIdx === i;
                return (
                  <button
                    key={track.id}
                    onClick={() => {
                      onPlayTrackFromSearch(track);
                      onClose();
                    }}
                    onMouseEnter={() => setSelectedIdx(i)}
                    className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                      isSelected ? 'bg-[#3B82F6]/20 text-white' : 'hover:bg-white/5 text-white'
                    }`}
                  >
                    <img
                      src={track.artwork || DEFAULT_ARTWORK}
                      alt={track.title}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-9 h-9 rounded object-cover flex-shrink-0"
                    />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-bold truncate">{track.title}</p>
                      <p className="text-xs text-[#b3b3b3] truncate">{track.artist}</p>
                    </div>
                    <Play className="w-4 h-4 text-[#3B82F6] flex-shrink-0" />
                  </button>
                );
              })}
            </div>
          )}

          {filteredCommands.length > 0 && (
            <div>
              <div className="px-3 py-1 text-[10px] font-bold uppercase tracking-wider text-[#888]">
                Aksi Cepat & Navigasi
              </div>
              {filteredCommands.map((cmd, idx) => {
                const globalIndex = songs.length + idx;
                const isSelected = selectedIdx === globalIndex;
                const IconComp = cmd.icon;
                return (
                  <button
                    key={cmd.id}
                    onClick={() => {
                      cmd.action?.();
                      onClose();
                    }}
                    onMouseEnter={() => setSelectedIdx(globalIndex)}
                    className={`w-full flex items-center justify-between px-3 py-2.5 rounded-lg text-left transition-colors ${
                      isSelected ? 'bg-[#3B82F6]/20 text-white' : 'hover:bg-white/5 text-[#e4e4e7]'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <IconComp className={`w-4 h-4 ${isSelected ? 'text-[#3B82F6]' : 'text-[#b3b3b3]'}`} />
                      <span className="text-sm font-semibold">{cmd.label}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-white/5 text-[#888]">
                        {cmd.hint}
                      </span>
                      {isSelected && <CornerDownLeft className="w-3.5 h-3.5 text-[#3B82F6]" />}
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>

        {/* Footer Hints */}
        <div className="px-4 py-2 bg-black/40 border-t border-white/5 flex items-center justify-between text-[11px] text-[#888]">
          <span>↑↓ Pilih • Enter Jalankan</span>
          <span className="text-[#3B82F6] font-semibold">McTify Spotlight Search</span>
        </div>
      </div>
    </div>
  );
}
