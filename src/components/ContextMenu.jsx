import React, { useEffect, useRef, useState } from 'react';
import { 
  Plus, 
  Heart, 
  ListPlus, 
  Ban, 
  Radio, 
  User, 
  Disc, 
  FileText, 
  Share2, 
  ChevronRight, 
  Check, 
  Mic2,
  Trash2,
  Play,
  Download,
  Copy
} from 'lucide-react';

export default function ContextMenu({
  contextData, // { type: 'track' | 'playlist', track, playlist, x, y }
  playlists = [],
  isLiked = false,
  onClose,
  onPlayTrack,
  onAddToQueue,
  onToggleLike,
  onAddTrackToPlaylist,
  onCreatePlaylistWithTrack,
  onStartRadio,
  onOpenArtist,
  onOpenLyrics,
  onShowCredits,
  onCopyShare,
  onDeletePlaylist,
}) {
  const menuRef = useRef(null);
  const [activeSubmenu, setActiveSubmenu] = useState(null); // 'playlist' | 'share'

  // Handle outside click, escape, and window resize/scroll to close
  useEffect(() => {
    const handleOutsideClick = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        onClose();
      }
    };

    const handleKeyDown = (e) => {
      if (e.key === 'Escape') onClose();
    };

    const handleScroll = () => {
      onClose();
    };

    window.addEventListener('mousedown', handleOutsideClick);
    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('scroll', handleScroll, true);

    return () => {
      window.removeEventListener('mousedown', handleOutsideClick);
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('scroll', handleScroll, true);
    };
  }, [onClose]);

  if (!contextData) return null;

  // Calculate position & transform origin synchronously so there's zero jumping/flicker on first frame
  const menuWidth = 260;
  const menuHeight = contextData.type === 'track' ? 380 : 180;
  const windowWidth = typeof window !== 'undefined' ? window.innerWidth : 1200;
  const windowHeight = typeof window !== 'undefined' ? window.innerHeight : 800;

  let posX = contextData.x;
  let posY = contextData.y;
  let originX = 'left';
  let originY = 'top';

  if (posX + menuWidth > windowWidth - 10) {
    posX = Math.max(10, windowWidth - menuWidth - 15);
    originX = 'right';
  }
  if (posY + menuHeight > windowHeight - 10) {
    posY = Math.max(10, windowHeight - menuHeight - 15);
    originY = 'bottom';
  }

  const transformOrigin = `${originY} ${originX}`;
  const { type, track, playlist } = contextData;

  return (
    <div
      ref={menuRef}
      style={{ 
        top: `${posY}px`, 
        left: `${posX}px`,
        transformOrigin: transformOrigin,
      }}
      className="fixed z-50 w-64 bg-[#282828] border border-white/10 rounded-md shadow-[0_16px_28px_rgba(0,0,0,0.65)] p-1 text-white select-none text-xs font-semibold animate-spotify-popup"
      onClick={(e) => e.stopPropagation()}
      onContextMenu={(e) => e.preventDefault()}
    >
      {type === 'track' && track && (
        <div className="space-y-0.5">
          {/* Header track mini info */}
          <div className="px-3 py-2 border-b border-white/10 mb-1 flex items-center gap-2.5 bg-white/[0.02] rounded-t">
            <img 
              src={track.artwork} 
              alt="" 
              className="w-8 h-8 rounded object-cover flex-shrink-0 shadow" 
            />
            <div className="min-w-0 flex-1">
              <p className="truncate text-white font-bold text-xs">{track.title}</p>
              <p className="truncate text-[#b3b3b3] text-[11px]">{track.artist}</p>
            </div>
          </div>

          {/* 1. Tambah ke playlist (with Nested Submenu) */}
          <div 
            className="relative"
            onMouseEnter={() => setActiveSubmenu('playlist')}
            onMouseLeave={() => setActiveSubmenu(null)}
          >
            <div className="flex items-center justify-between px-3 py-2 rounded-[4px] hover:bg-white/10 cursor-pointer transition-colors group">
              <div className="flex items-center gap-3">
                <Plus className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
                <span>Tambah ke playlist</span>
              </div>
              <ChevronRight className="w-3.5 h-3.5 text-[#b3b3b3]" />
            </div>

            {/* Submenu with Pop-Up Animation */}
            {activeSubmenu === 'playlist' && (
              <div 
                className="absolute left-full top-0 ml-1 w-56 bg-[#282828] border border-white/10 rounded-md shadow-2xl p-1 text-white space-y-0.5 max-h-60 overflow-y-auto animate-spotify-popup"
                style={{ transformOrigin: 'top left' }}
              >
                <button
                  onClick={() => {
                    onCreatePlaylistWithTrack(track);
                    onClose();
                  }}
                  className="w-full text-left flex items-center gap-2 px-3 py-2 rounded-[4px] hover:bg-white/10 text-white font-semibold transition-colors"
                >
                  <Plus className="w-3.5 h-3.5 text-[#00a3ff]" />
                  <span>Buat playlist baru</span>
                </button>

                <div className="h-px bg-white/10 my-1" />

                {playlists.length === 0 ? (
                  <p className="px-3 py-2 text-[11px] text-[#b3b3b3]">Belum ada playlist</p>
                ) : (
                  playlists.map((pl) => (
                    <button
                      key={pl.id}
                      onClick={() => {
                        onAddTrackToPlaylist(pl.id, track);
                        onClose();
                      }}
                      className="w-full text-left px-3 py-2 rounded-[4px] hover:bg-white/10 text-white truncate transition-colors flex items-center justify-between"
                    >
                      <span className="truncate">{pl.name}</span>
                      {pl.tracks?.some(t => t.id === track.id) && (
                        <Check className="w-3.5 h-3.5 text-[#00a3ff] flex-shrink-0" />
                      )}
                    </button>
                  ))
                )}
              </div>
            )}
          </div>

          {/* 2. Simpan / Hapus dari Lagu yang Disukai */}
          <button
            onClick={() => {
              onToggleLike(track);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <Heart className={`w-4 h-4 ${isLiked ? 'text-[#00a3ff] fill-[#00a3ff]' : 'text-[#b3b3b3] group-hover:text-white'}`} />
            <span>{isLiked ? 'Hapus dari Lagu yang Disukai' : 'Simpan ke Lagu yang Disukai'}</span>
          </button>

          {/* 3. Tambahkan ke antrean */}
          <button
            onClick={() => {
              onAddToQueue(track);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <ListPlus className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
            <span>Tambahkan ke antrean</span>
          </button>

          {/* 4. Ke radio lagu */}
          <button
            onClick={() => {
              onStartRadio(track);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <Radio className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
            <span>Ke radio lagu</span>
          </button>

          {/* 5. Buka artis */}
          <button
            onClick={() => {
              onOpenArtist(track.artist);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <User className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
            <span>Buka artis</span>
          </button>

          {/* 6. Buka Lirik Karaoke */}
          <button
            onClick={() => {
              onOpenLyrics(track);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <Mic2 className="w-4 h-4 text-[#00a3ff]" />
            <span className="text-[#00a3ff]">Buka lirik karaoke</span>
          </button>

          {/* 7. Lihat kredit */}
          <button
            onClick={() => {
              onShowCredits(track);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <FileText className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
            <span>Lihat kredit lagu</span>
          </button>

          <div className="h-px bg-white/10 my-1" />

          {/* 8. Bagikan (Salin link) */}
          <button
            onClick={() => {
              onCopyShare(track);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <Share2 className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
            <span>Bagikan / Salin Tautan</span>
          </button>
        </div>
      )}

      {/* Type: Playlist Context Menu */}
      {type === 'playlist' && playlist && (
        <div className="space-y-0.5">
          <div className="px-3 py-1.5 border-b border-white/10 mb-1">
            <p className="truncate text-white font-bold">{playlist.name}</p>
            <p className="text-[#b3b3b3] text-[11px]">{playlist.tracks?.length || 0} lagu</p>
          </div>

          <button
            onClick={() => {
              onPlayTrack(playlist.tracks?.[0], playlist.tracks);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <Play className="w-4 h-4 text-[#00a3ff] fill-[#00a3ff]" />
            <span>Putar playlist</span>
          </button>

          <button
            onClick={() => {
              onCopyShare(playlist);
              onClose();
            }}
            className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-white/10 transition-colors group"
          >
            <Share2 className="w-4 h-4 text-[#b3b3b3] group-hover:text-white" />
            <span>Salin tautan playlist</span>
          </button>

          {playlist.id !== 'pl-favorites' && onDeletePlaylist && (
            <>
              <div className="h-px bg-white/10 my-1" />
              <button
                onClick={() => {
                  onDeletePlaylist(playlist.id);
                  onClose();
                }}
                className="w-full text-left flex items-center gap-3 px-3 py-2 rounded-[4px] hover:bg-rose-500/20 text-rose-400 transition-colors"
              >
                <Trash2 className="w-4 h-4" />
                <span>Hapus dari Koleksi</span>
              </button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
