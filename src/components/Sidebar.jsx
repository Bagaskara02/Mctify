import React, { useState } from 'react';
import { 
  Home, 
  Search, 
  Library, 
  Plus, 
  Heart, 
  Trash2, 
  Download,
  ListPlus,
  Pin,
  ListFilter
} from 'lucide-react';
import { playlistImporter } from '../services/playlistImporter';
import { DEFAULT_ARTWORK } from '../services/musicApi';

export default function Sidebar({
  currentView,
  setCurrentView,
  selectedPlaylistId,
  setSelectedPlaylistId,
  playlists = [],
  likedCount = 0,
  onOpenImportModal,
  onCreatePlaylist,
  onDeletePlaylist,
  onPlaylistContextMenu,
}) {
  const [filterTag, setFilterTag] = useState('all');
  const [searchFilter, setSearchFilter] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  const filteredPlaylists = playlists.filter(pl => {
    if (!searchFilter.trim()) return true;
    return pl.name.toLowerCase().includes(searchFilter.toLowerCase());
  });

  return (
    <aside className="hidden md:flex w-[260px] lg:w-[290px] xl:w-[320px] flex-shrink-0 flex-col gap-2 p-2 bg-black select-none h-full text-white">
      {/* Box 1: Navigasi Atas (Spotify Native Style) */}
      <div className="bg-[#121212] rounded-lg px-5 py-4 space-y-4">
        <button
          onClick={() => { setCurrentView('discover'); setSelectedPlaylistId(null); }}
          className={`w-full flex items-center gap-4 text-sm lg:text-base font-bold transition-colors ${
            currentView === 'discover' && !selectedPlaylistId
              ? 'text-white'
              : 'text-[#b3b3b3] hover:text-white'
          }`}
        >
          <Home className="w-6 h-6 stroke-[2.3]" />
          <span>Beranda</span>
        </button>

        <button
          onClick={() => { setCurrentView('search'); setSelectedPlaylistId(null); }}
          className={`w-full flex items-center gap-4 text-sm lg:text-base font-bold transition-colors ${
            currentView === 'search' && !selectedPlaylistId
              ? 'text-white'
              : 'text-[#b3b3b3] hover:text-white'
          }`}
        >
          <Search className="w-6 h-6 stroke-[2.3]" />
          <span>Cari</span>
        </button>
      </div>

      {/* Box 2: Koleksi Kamu (Matching Screenshot media_1791347940843.png) */}
      <div className="flex-1 flex flex-col min-h-0 bg-[#121212] rounded-lg p-3 overflow-hidden">
        {/* Header Library with "+ Buat" button */}
        <div className="flex items-center justify-between px-2 py-2 mb-2">
          <div 
            onClick={() => { setCurrentView('discover'); setSelectedPlaylistId(null); }}
            className="flex items-center gap-3 text-[#b3b3b3] hover:text-white cursor-pointer transition-colors"
          >
            <Library className="w-6 h-6 stroke-[2.2]" />
            <span className="font-bold text-sm lg:text-base tracking-tight">Koleksi Kamu</span>
          </div>

          <div className="flex items-center gap-1">
            <button
              onClick={onCreatePlaylist}
              className="flex items-center gap-1 px-2.5 py-1 rounded-full bg-[#242424] hover:bg-[#2e2e2e] text-white text-xs font-bold transition-all hover:scale-105"
              title="Buat Playlist Baru"
            >
              <Plus className="w-3.5 h-3.5 text-[#00a3ff]" />
              <span>Buat</span>
            </button>
          </div>
        </div>

        {/* Filter Pills */}
        <div className="flex items-center gap-2 px-1 pb-2 overflow-x-auto no-scrollbar">
          <button
            onClick={() => setFilterTag('all')}
            className={`px-3 py-1.5 rounded-full text-xs font-semibold whitespace-nowrap transition-colors ${
              filterTag === 'all'
                ? 'bg-white text-black font-bold'
                : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
            }`}
          >
            Semua
          </button>
          <button
            onClick={() => setFilterTag('playlists')}
            className={`px-3 py-1.5 rounded-full text-xs font-semibold whitespace-nowrap transition-colors ${
              filterTag === 'playlists'
                ? 'bg-white text-black font-bold'
                : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
            }`}
          >
            Playlist
          </button>
          <button
            onClick={() => {
              setCurrentView('liked');
              setSelectedPlaylistId(null);
            }}
            className={`px-3 py-1.5 rounded-full text-xs font-semibold whitespace-nowrap transition-colors ${
              currentView === 'liked'
                ? 'bg-white text-black font-bold'
                : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
            }`}
          >
            Disukai
          </button>
        </div>

        {/* Search in library & Baru Diputar sort */}
        <div className="flex items-center justify-between px-2 py-1.5 text-xs text-[#b3b3b3]">
          <div className="flex items-center gap-2 flex-1">
            <button
              onClick={() => setIsSearchOpen(!isSearchOpen)}
              className="p-1 rounded-full hover:bg-white/10 hover:text-white transition-colors"
              title="Cari di Koleksi"
            >
              <Search className="w-4 h-4" />
            </button>
            {isSearchOpen && (
              <input
                type="text"
                value={searchFilter}
                onChange={(e) => setSearchFilter(e.target.value)}
                placeholder="Cari di Koleksi..."
                className="w-full bg-[#242424] px-2 py-1 rounded text-xs text-white placeholder-[#777] focus:outline-none"
                autoFocus
              />
            )}
          </div>

          {!isSearchOpen && (
            <div className="flex items-center gap-1 hover:text-white cursor-pointer">
              <span>Baru diputar</span>
              <ListFilter className="w-3.5 h-3.5" />
            </div>
          )}
        </div>

        {/* Playlists List Container */}
        <div className="flex-1 overflow-y-auto space-y-0.5 px-0.5 pr-1">
          {/* Liked Songs Item (With Pin Icon matching screenshot) */}
          <div
            onClick={() => {
              setCurrentView('liked');
              setSelectedPlaylistId(null);
            }}
            className={`group flex items-center justify-between p-2 rounded-md cursor-pointer transition-colors ${
              currentView === 'liked' ? 'bg-[#282828]' : 'hover:bg-[#1a1a1a]'
            }`}
          >
            <div className="flex items-center gap-3 min-w-0">
              <div className="w-12 h-12 rounded-md bg-gradient-to-br from-[#00a3ff] to-[#0055b3] flex items-center justify-center flex-shrink-0 shadow-md">
                <Heart className="w-5 h-5 text-white fill-white" />
              </div>
              <div className="truncate">
                <p className={`text-sm font-semibold truncate ${currentView === 'liked' ? 'text-[#00a3ff]' : 'text-white'}`}>
                  Lagu yang Disukai
                </p>
                <div className="flex items-center gap-1.5 text-xs text-[#b3b3b3] mt-0.5">
                  <Pin className="w-3 h-3 text-[#00a3ff] rotate-45 flex-shrink-0" />
                  <span className="truncate">Playlist • {likedCount} lagu</span>
                </div>
              </div>
            </div>
          </div>

          {/* User Playlist Items */}
          {filteredPlaylists.map((pl) => {
            const isSelected = selectedPlaylistId === pl.id;
            return (
              <div
                key={pl.id}
                onClick={() => {
                  setSelectedPlaylistId(pl.id);
                  setCurrentView('playlist');
                }}
                onContextMenu={(e) => {
                  e.preventDefault();
                  onPlaylistContextMenu?.(e, pl);
                }}
                className={`group flex items-center justify-between p-2 rounded-md cursor-pointer transition-colors ${
                  isSelected ? 'bg-[#282828]' : 'hover:bg-[#1a1a1a]'
                }`}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <img
                    src={pl.cover || DEFAULT_ARTWORK}
                    alt={pl.name}
                    onError={(e) => {
                      e.currentTarget.onerror = null;
                      e.currentTarget.src = DEFAULT_ARTWORK;
                    }}
                    className="w-12 h-12 rounded-md object-cover flex-shrink-0 bg-[#282828]"
                  />
                  <div className="truncate">
                    <p className={`text-sm font-semibold truncate ${isSelected ? 'text-[#00a3ff]' : 'text-white'}`}>
                      {pl.name}
                    </p>
                    <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                      Playlist • Bagas Kara
                    </p>
                  </div>
                </div>

                {/* Actions */}
                <div className="hidden group-hover:flex items-center gap-1">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      playlistImporter.exportToJson(pl);
                    }}
                    className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-white"
                    title="Export JSON"
                  >
                    <Download className="w-3.5 h-3.5" />
                  </button>
                  {pl.id !== 'pl-favorites' && onDeletePlaylist && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        if (confirm(`Hapus playlist "${pl.name}"?`)) {
                          onDeletePlaylist(pl.id);
                        }
                      }}
                      className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-rose-400"
                      title="Hapus"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </aside>
  );
}
