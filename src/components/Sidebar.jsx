import React, { useState } from 'react';
import { 
  Library, 
  Plus, 
  Heart, 
  Trash2, 
  Download,
  ListPlus,
  Pin,
  ListFilter,
  Search
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
  const [filterTag, setFilterTag] = useState('all'); // 'all' | 'playlists' | 'liked'
  const [searchFilter, setSearchFilter] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  const filteredPlaylists = playlists.filter(pl => {
    if (!searchFilter.trim()) return true;
    return pl.name.toLowerCase().includes(searchFilter.toLowerCase());
  });

  return (
    <aside className="hidden md:flex w-[280px] lg:w-[320px] xl:w-[360px] flex-shrink-0 flex-col bg-[#121212] rounded-lg select-none h-full text-white overflow-hidden p-3 min-h-0">
      {/* Header Library with "+ Buat" and "Import" buttons */}
      <div className="flex items-center justify-between px-2 py-2 mb-2 flex-shrink-0">
        <div 
          onClick={() => { setCurrentView('discover'); setSelectedPlaylistId(null); }}
          className="flex items-center gap-3 text-[#b3b3b3] hover:text-white cursor-pointer transition-colors group"
          title="Buka Koleksi Kamu"
        >
          <Library className="w-6 h-6 stroke-[2.2] group-hover:text-white transition-colors" />
          <span className="font-bold text-sm lg:text-base tracking-tight">Koleksi Kamu</span>
        </div>

        <div className="flex items-center gap-1">
          <button
            onClick={onCreatePlaylist}
            className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-white transition-all active:scale-95"
            title="Buat Playlist Baru"
          >
            <Plus className="w-5 h-5" />
          </button>

          <button
            onClick={onOpenImportModal}
            className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-white transition-all active:scale-95"
            title="Impor Playlist dari Spotify / JSON"
          >
            <ListPlus className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Filter Chips */}
      <div className="flex items-center gap-2 px-1 pb-2 overflow-x-auto no-scrollbar flex-shrink-0">
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
      <div className="flex items-center justify-between px-2 py-1.5 text-xs text-[#b3b3b3] flex-shrink-0">
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
          <div className="flex items-center gap-1 hover:text-white cursor-pointer select-none">
            <span>Baru diputar</span>
            <ListFilter className="w-3.5 h-3.5" />
          </div>
        )}
      </div>

      {/* Playlists List Container */}
      <div className="flex-1 overflow-y-auto space-y-0.5 px-0.5 pr-1 min-h-0">
        {/* Liked Songs Item (Spotify iconic purple gradient + pin icon) */}
        {(filterTag === 'all' || filterTag === 'liked') && (
          <div
            onClick={() => {
              setCurrentView('liked');
              setSelectedPlaylistId(null);
            }}
            className={`group flex items-center justify-between p-2 rounded-md cursor-pointer transition-colors ${
              currentView === 'liked' && !selectedPlaylistId
                ? 'bg-[#242424]'
                : 'hover:bg-white/[0.07]'
            }`}
          >
            <div className="flex items-center gap-3 min-w-0">
              <div className="w-12 h-12 rounded-md bg-gradient-to-br from-[#450af5] to-[#8e8ee5] flex items-center justify-center flex-shrink-0 shadow-md">
                <Heart className="w-5 h-5 text-white fill-white" />
              </div>
              <div className="truncate">
                <p className={`text-sm font-semibold truncate ${
                  currentView === 'liked' && !selectedPlaylistId ? 'text-[#1ed760]' : 'text-white'
                }`}>
                  Lagu yang Disukai
                </p>
                <div className="flex items-center gap-1.5 text-xs text-[#b3b3b3] mt-0.5">
                  <Pin className="w-3 h-3 text-[#1ed760] rotate-45 flex-shrink-0" />
                  <span className="truncate">Playlist • {likedCount} lagu</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* User Playlist Items */}
        {(filterTag === 'all' || filterTag === 'playlists') && filteredPlaylists.map((pl) => {
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
                isSelected ? 'bg-[#242424]' : 'hover:bg-white/[0.07]'
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
                  <p className={`text-sm font-semibold truncate ${isSelected ? 'text-[#1ed760]' : 'text-white'}`}>
                    {pl.name}
                  </p>
                  <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                    Playlist • {pl.tracks?.length || 0} lagu
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
    </aside>
  );
}
