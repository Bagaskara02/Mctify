import React from 'react';
import { X, Play, Sparkles, Music, Trash2 } from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';

export default function QueueDrawer({
  isOpen,
  onClose,
  currentTrack,
  queue = [],
  isPlaying,
  onPlayTrack,
  onClearQueue,
}) {
  if (!isOpen) return null;

  const currentIndex = queue.findIndex(t => t.id === currentTrack?.id);
  const upNextTracks = currentIndex !== -1 ? queue.slice(currentIndex + 1) : queue;

  return (
    <div className="fixed inset-y-0 right-0 w-full sm:w-96 bg-[#121212] border-l border-[#282828] z-50 flex flex-col shadow-2xl animate-in slide-in-from-right duration-300 select-none">
      {/* Header */}
      <div className="p-4 border-b border-[#242424] flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Music className="w-5 h-5 text-[#00a3ff]" />
          <h3 className="font-bold text-base text-white tracking-tight">
            Daftar Antrean
          </h3>
        </div>

        <button
          onClick={onClose}
          className="p-1.5 rounded-full hover:bg-[#282828] text-[#b3b3b3] hover:text-white transition-colors"
        >
          <X className="w-5 h-5" />
        </button>
      </div>

      {/* Queue Body */}
      <div className="flex-1 overflow-y-auto p-4 space-y-6">
        {/* Currently Playing Section */}
        {currentTrack && (
          <div>
            <p className="text-xs font-bold uppercase tracking-wider text-[#b3b3b3] mb-3">
              Sedang Diputar
            </p>
            <div className="flex items-center gap-3 p-2.5 rounded-lg bg-[#242424] border border-white/5">
              <img
                src={currentTrack.artwork || DEFAULT_ARTWORK}
                alt={currentTrack.title}
                onError={(e) => {
                  e.currentTarget.onerror = null;
                  e.currentTarget.src = DEFAULT_ARTWORK;
                }}
                className="w-12 h-12 rounded-md object-cover flex-shrink-0"
              />
              <div className="min-w-0 flex-1">
                <p className="text-sm font-bold text-[#00a3ff] truncate">
                  {currentTrack.title}
                </p>
                <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                  {currentTrack.artist}
                </p>
              </div>

              {/* Animated Equalizer Bars */}
              {isPlaying && (
                <div className="flex items-end gap-1 h-5 px-2 flex-shrink-0">
                  <span className="w-1 bg-[#00a3ff] rounded-full animate-eq-1" />
                  <span className="w-1 bg-[#00a3ff] rounded-full animate-eq-2" />
                  <span className="w-1 bg-[#00a3ff] rounded-full animate-eq-3" />
                </div>
              )}
            </div>
          </div>
        )}

        {/* Up Next Section */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <p className="text-xs font-bold uppercase tracking-wider text-[#b3b3b3]">
                Berikutnya Dalam Antrean
              </p>
              <span className="text-xs px-2 py-0.5 rounded-full bg-white/10 text-white/70 font-semibold">
                {upNextTracks.length}
              </span>
            </div>

            {upNextTracks.length > 0 && onClearQueue && (
              <button
                onClick={onClearQueue}
                className="text-xs text-[#b3b3b3] hover:text-white transition-colors"
              >
                Hapus
              </button>
            )}
          </div>

          {/* Smart Autoplay / Radio Indicator */}
          <div className="mb-3 p-3 rounded-lg bg-[#00a3ff]/10 border border-[#00a3ff]/20 flex items-center gap-2.5">
            <Sparkles className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
            <p className="text-xs text-white/90 leading-tight">
              <strong className="text-[#00a3ff] font-semibold">Radio Pintar Aktif:</strong> Saat daftar lagu habis, sistem otomatis mencari musik serupa.
            </p>
          </div>

          {upNextTracks.length === 0 ? (
            <div className="p-8 text-center text-[#b3b3b3] text-xs">
              Antrean kosong. Lagu baru yang serupa akan otomatis dimuat saat lagu ini selesai!
            </div>
          ) : (
            <div className="space-y-1">
              {upNextTracks.map((track, idx) => (
                <div
                  key={`${track.id}-${idx}`}
                  onClick={() => onPlayTrack(track)}
                  className="group flex items-center gap-3 p-2 rounded-md hover:bg-[#1f1f1f] cursor-pointer transition-colors"
                >
                  <span className="w-5 text-center text-xs text-[#b3b3b3] group-hover:hidden">
                    {idx + 1}
                  </span>
                  <button className="w-5 hidden group-hover:flex items-center justify-center text-white">
                    <Play className="w-3.5 h-3.5 fill-white" />
                  </button>

                  <img
                    src={track.artwork || DEFAULT_ARTWORK}
                    alt={track.title}
                    onError={(e) => {
                      e.currentTarget.onerror = null;
                      e.currentTarget.src = DEFAULT_ARTWORK;
                    }}
                    className="w-10 h-10 rounded object-cover flex-shrink-0"
                  />

                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold text-white truncate group-hover:text-[#00a3ff] transition-colors">
                      {track.title}
                    </p>
                    <p className="text-[11px] text-[#b3b3b3] truncate mt-0.5">
                      {track.artist}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
