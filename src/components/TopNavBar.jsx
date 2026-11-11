import React, { useState, useEffect, useRef } from 'react';
import {
  Home,
  Search,
  Plus,
  Download,
  Compass,
  X,
  Music,
  ChevronLeft,
  ChevronRight,
  History,
  Command,
  Mic2,
} from 'lucide-react';
import { storageService } from '../services/storageService';
import { DEFAULT_ARTWORK } from '../services/musicApi';

const YoutubeIcon = ({ className = 'w-4 h-4' }) => (
  <svg className={className} viewBox="0 0 24 24" fill="currentColor">
    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
  </svg>
);

export default function TopNavBar({
  currentView,
  setCurrentView,
  searchQuery,
  setSearchQuery,
  canGoBack = false,
  canGoForward = false,
  onGoBack,
  onGoForward,
  onOpenCommandPalette,
  onOpenDownloadApp,
  onCreatePlaylist,
  onOpenImportYouTube,
}) {
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [recentSearches, setRecentSearches] = useState([]);
  const searchWrapRef = useRef(null);

  useEffect(() => {
    setRecentSearches(storageService.getRecentSearches());
  }, [isDropdownOpen, searchQuery, currentView]);

  useEffect(() => {
    const handleOutside = (e) => {
      if (searchWrapRef.current && !searchWrapRef.current.contains(e.target)) {
        setIsDropdownOpen(false);
      }
    };
    document.addEventListener('mousedown', handleOutside);
    return () => document.removeEventListener('mousedown', handleOutside);
  }, []);

  return (
    <header className="h-16 bg-black px-3 sm:px-6 flex items-center justify-between gap-3 select-none z-30">
      {/* Left: Brand Logo + History Back/Forward (Spotify Desktop & Monochrome exact match) */}
      <div className="flex items-center gap-2 sm:gap-3 flex-shrink-0">
        <div
          onClick={() => setCurrentView('discover')}
          className="flex items-center gap-2 cursor-pointer group"
        >
          <div className="w-9 h-9 rounded-full bg-[#3B82F6] flex items-center justify-center shadow-md group-hover:scale-105 transition-transform">
            <Music className="w-5 h-5 text-black stroke-[2.5]" />
          </div>
          <span className="font-black text-lg tracking-tight text-white hidden sm:inline-block">
            McTify
          </span>
        </div>

        <div className="hidden lg:flex items-center gap-1 ml-2">
          <button
            onClick={onGoBack}
            disabled={!canGoBack}
            className="w-8 h-8 rounded-full bg-[#181818] hover:bg-[#242424] flex items-center justify-center text-white disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title="Kembali"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <button
            onClick={onGoForward}
            disabled={!canGoForward}
            className="w-8 h-8 rounded-full bg-[#181818] hover:bg-[#242424] flex items-center justify-center text-white disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title="Maju"
          >
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Center: Home Circular Button + Capsule Search Bar with Spotlight Ctrl+K & History Popover */}
      <div className="flex items-center gap-2 flex-1 max-w-2xl mx-auto">
        <button
          onClick={() => setCurrentView('discover')}
          className={`w-11 h-11 rounded-full flex items-center justify-center transition-all flex-shrink-0 hover:scale-105 active:scale-95 ${
            currentView === 'discover'
              ? 'bg-[#282828] text-white ring-1 ring-white/15'
              : 'bg-[#1f1f1f] text-[#b3b3b3] hover:text-white hover:bg-[#282828]'
          }`}
          title="Beranda"
        >
          <Home className="w-5 h-5" />
        </button>

        {/* Search Capsule */}
        <div ref={searchWrapRef} className="relative flex-1 group">
          <Search className="w-5 h-5 text-[#b3b3b3] group-hover:text-white transition-colors absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            type="text"
            value={searchQuery || ''}
            onFocus={() => {
              setIsDropdownOpen(true);
              if (currentView !== 'search') setCurrentView('search');
            }}
            onClick={() => {
              setIsDropdownOpen(true);
              if (currentView !== 'search') setCurrentView('search');
            }}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              if (currentView !== 'search') setCurrentView('search');
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                if (searchQuery?.trim()) {
                  storageService.addRecentSearch({ query: searchQuery.trim(), title: searchQuery.trim(), subtitle: 'Pencarian' });
                  setRecentSearches(storageService.getRecentSearches());
                }
                setIsDropdownOpen(false);
                if (currentView !== 'search') setCurrentView('search');
              }
            }}
            placeholder="Apa yang ingin kamu putar atau cari penggalan lirik?"
            className="w-full h-11 pl-12 pr-28 rounded-full bg-[#1f1f1f] hover:bg-[#282828] focus:bg-[#282828] border border-transparent focus:border-white/80 text-sm text-white placeholder-[#a7a7a7] focus:outline-none transition-all cursor-text"
          />

          <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
            {searchQuery ? (
              <button
                onClick={() => {
                  setSearchQuery('');
                }}
                className="p-1.5 text-[#b3b3b3] hover:text-white rounded-full"
                title="Bersihkan"
              >
                <X className="w-4 h-4" />
              </button>
            ) : (
              <>
                {onOpenCommandPalette && (
                  <button
                    onClick={onOpenCommandPalette}
                    className="hidden sm:inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/10 hover:bg-white/20 text-[10px] font-bold text-[#b3b3b3] hover:text-white border border-white/10 transition-colors"
                    title="Buka Spotlight Command Palette (Ctrl+K)"
                  >
                    <Command className="w-2.5 h-2.5" />
                    <span>K</span>
                  </button>
                )}
                <div className="h-4 w-[1px] bg-white/15 hidden sm:block mx-0.5" />
                <button
                  onClick={() => setCurrentView('search')}
                  className="p-1 text-[#b3b3b3] hover:text-white transition-colors"
                  title="Jelajahi Semua"
                >
                  <Compass className="w-4 h-4" />
                </button>
              </>
            )}
          </div>

          {/* Search History Popover Dropdown when empty & focused */}
          {isDropdownOpen && !searchQuery?.trim() && recentSearches.length > 0 && (
            <div className="absolute left-0 right-0 top-13 bg-[#242428] border border-white/10 rounded-xl shadow-2xl p-2 z-50 animate-spotify-popup">
              <div className="flex items-center justify-between px-2 py-1.5">
                <span className="text-[11px] font-bold uppercase tracking-wider text-[#b3b3b3] flex items-center gap-1.5">
                  <History className="w-3.5 h-3.5 text-[#3B82F6]" />
                  Pencarian Terkini
                </span>
                <button
                  onClick={() => setRecentSearches(storageService.clearRecentSearches())}
                  className="text-[11px] font-bold text-[#b3b3b3] hover:text-white"
                >
                  Hapus semua
                </button>
              </div>
              <div className="max-h-60 overflow-y-auto space-y-0.5">
                {recentSearches.slice(0, 6).map((item, idx) => (
                  <div
                    key={`${item.query}-${idx}`}
                    onClick={() => {
                      setSearchQuery(item.query);
                      setIsDropdownOpen(false);
                      setCurrentView('search');
                    }}
                    className="flex items-center justify-between gap-2 px-2 py-1.5 rounded-lg hover:bg-white/10 cursor-pointer group"
                  >
                    <div className="flex items-center gap-2.5 min-w-0">
                      <img
                        src={item.artwork || DEFAULT_ARTWORK}
                        alt={item.title}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className={`w-8 h-8 object-cover flex-shrink-0 ${
                          item.type === 'artist' ? 'rounded-full' : 'rounded'
                        }`}
                      />
                      <div className="min-w-0">
                        <p className="text-xs font-bold text-white truncate">{item.title}</p>
                        <p className="text-[11px] text-[#b3b3b3] truncate">{item.subtitle || 'Pencarian'}</p>
                      </div>
                    </div>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setRecentSearches(storageService.removeRecentSearch(item.query, item.type));
                      }}
                      className="p-1 text-[#777] hover:text-white opacity-0 group-hover:opacity-100"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Right: Quick Actions & Download App */}
      <div className="flex items-center gap-2 sm:gap-2.5 flex-shrink-0">
        <button
          onClick={onCreatePlaylist}
          className="hidden md:flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-[#242424] hover:bg-[#2e2e2e] text-white text-xs font-bold transition-all active:scale-95"
          title="Buat Playlist Baru"
        >
          <Plus className="w-4 h-4 text-[#3B82F6]" />
          <span>Buat</span>
        </button>

        <button
          onClick={onOpenImportYouTube}
          className="hidden sm:flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-[#242424] hover:bg-[#2e2e2e] text-white text-xs font-bold transition-all active:scale-95"
          title="Import Lagu dari YouTube"
        >
          <YoutubeIcon className="w-3.5 h-3.5 fill-[#ff4e4e]" />
          <span>Import YouTube</span>
        </button>

        <button
          onClick={onOpenDownloadApp}
          className="px-4 py-2 rounded-full bg-white hover:bg-[#e8e8e8] text-black text-xs font-bold flex items-center gap-1.5 shadow-sm transition-all hover:scale-105 active:scale-95"
          title="Download Aplikasi Mobile"
        >
          <Download className="w-4 h-4 stroke-[2.5]" />
          <span>Download App</span>
        </button>
      </div>
    </header>
  );
}
