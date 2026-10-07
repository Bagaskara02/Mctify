import React from 'react';
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
  MoreHorizontal
} from 'lucide-react';
import { playlistImporter } from '../services/playlistImporter';
import { DEFAULT_ARTWORK } from '../services/musicApi';

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
  if (!playlist) {
    return (
      <div className="flex-1 flex items-center justify-center text-neutral-400 bg-[#121212]">
        <p>Tidak ada playlist yang dipilih</p>
      </div>
    );
  }

  const tracks = playlist.tracks || [];
  const totalDuration = tracks.reduce((acc, t) => acc + (t.duration || 0), 0);
  const totalMinutes = Math.floor(totalDuration / 60);

  return (
    <div className="flex-1 overflow-y-auto select-none bg-[#121212] text-white">
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
            <span>{tracks.length} lagu</span>
            <span>•</span>
            <span className="text-[#b3b3b3]">{totalMinutes} mnt</span>
          </div>
        </div>
      </div>

      {/* Action Bar (Spotify Circular Electric Azure Play Button) */}
      <div className="px-4 sm:px-8 py-4 flex items-center gap-5 sm:gap-6">
        <button
          onClick={() => onPlayAll(tracks)}
          disabled={tracks.length === 0}
          className="w-12 h-12 sm:w-14 sm:h-14 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-xl hover:scale-105 active:scale-95 transition-all disabled:opacity-40"
          title="Putar Semua"
        >
          <Play className="w-5 h-5 sm:w-6 sm:h-6 fill-black ml-0.5" />
        </button>

        <button
          onClick={() => onShuffleAll(tracks)}
          disabled={tracks.length === 0}
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

      {/* Tracks Table */}
      <div className="px-3 sm:px-8 pb-32 md:pb-16">
        {tracks.length === 0 ? (
          <div className="py-20 text-center text-neutral-500 space-y-3">
            <Music className="w-12 h-12 mx-auto opacity-40" />
            <p className="text-base font-semibold text-neutral-300">Playlist ini masih kosong</p>
            <p className="text-xs">Cari lagu di tab Cari atau impor playlist dari Spotify!</p>
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
            {tracks.map((t, idx) => {
              const isCurrent = currentTrack?.id === t.id;
              const isLiked = likedTrackIds.has(t.id);

              return (
                <div
                  key={t.id || idx}
                  onClick={() => {
                    if (isCurrent) {
                      onTogglePlayPause();
                    } else {
                      onPlayTrack(t, tracks);
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
                        {t.title}
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
                        onPlayTrack(t, tracks);
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
