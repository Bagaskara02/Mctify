import React, { useState } from 'react';
import { 
  X, 
  Link, 
  Loader2, 
  Play, 
  ListPlus, 
  ListMusic, 
  Heart, 
  Plus, 
  Check, 
  AlertCircle,
  ClipboardPaste,
  Sparkles
} from 'lucide-react';
import { musicApi, DEFAULT_ARTWORK } from '../services/musicApi';

const YoutubeIcon = ({ className = "w-5 h-5" }) => (
  <svg className={className} viewBox="0 0 24 24" fill="currentColor">
    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
  </svg>
);

export default function ImportYouTubeModal({
  isOpen,
  onClose,
  onPlayTrack,
  onAddToNext,
  onAddToQueue,
  onAddTrackToPlaylist,
  playlists = [],
  onToggleLike,
}) {
  const [inputVal, setInputVal] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState(null);
  const [resolvedTrack, setResolvedTrack] = useState(null);
  const [selectedPlaylistId, setSelectedPlaylistId] = useState('');
  const [addedStatus, setAddedStatus] = useState(null); // 'played' | 'next' | 'queue' | 'playlist' | 'liked'

  if (!isOpen) return null;

  const handleClose = () => {
    setInputVal('');
    setIsLoading(false);
    setErrorMsg(null);
    setResolvedTrack(null);
    setAddedStatus(null);
    onClose();
  };

  const handlePaste = async () => {
    try {
      if (navigator.clipboard) {
        const text = await navigator.clipboard.readText();
        if (text) {
          setInputVal(text.trim());
          handleResolve(text.trim());
        }
      }
    } catch (_) {}
  };

  const handleResolve = async (queryToResolve) => {
    const q = (queryToResolve || inputVal).trim();
    if (!q) return;

    setIsLoading(true);
    setErrorMsg(null);
    setResolvedTrack(null);
    setAddedStatus(null);

    try {
      const track = await musicApi.resolveYouTubeImport(q);
      if (track && track.videoId) {
        setResolvedTrack(track);
      } else {
        setErrorMsg('Lagu tidak ditemukan dari link atau pencarian YouTube ini. Pastikan link video valid.');
      }
    } catch (err) {
      setErrorMsg('Gagal memuat info video YouTube. Silakan coba link lain.');
    } finally {
      setIsLoading(false);
    }
  };

  const handlePlayNow = () => {
    if (!resolvedTrack) return;
    onPlayTrack(resolvedTrack);
    setAddedStatus('played');
    setTimeout(handleClose, 800);
  };

  const handlePlayNext = () => {
    if (!resolvedTrack) return;
    if (onAddToNext) onAddToNext(resolvedTrack);
    setAddedStatus('next');
    setTimeout(handleClose, 800);
  };

  const handleAddQueue = () => {
    if (!resolvedTrack) return;
    if (onAddToQueue) onAddToQueue(resolvedTrack);
    setAddedStatus('queue');
    setTimeout(handleClose, 800);
  };

  const handleSaveToLiked = () => {
    if (!resolvedTrack) return;
    if (onToggleLike) onToggleLike(resolvedTrack);
    setAddedStatus('liked');
  };

  const handleAddToPlaylistClick = () => {
    if (!resolvedTrack || !selectedPlaylistId) return;
    if (onAddTrackToPlaylist) onAddTrackToPlaylist(selectedPlaylistId, resolvedTrack);
    setAddedStatus('playlist');
    setTimeout(handleClose, 1000);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200">
      <div className="relative w-full max-w-lg bg-[#181818] border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col text-white">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-[#282828]">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#ff0000]/20 text-[#ff0000] flex items-center justify-center border border-[#ff0000]/30 shadow-lg shadow-[#ff0000]/10">
              <YoutubeIcon className="w-5 h-5 fill-current" />
            </div>
            <div>
              <h2 className="text-base font-bold text-white tracking-tight flex items-center gap-2">
                Import Lagu dari YouTube
                <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded-full bg-[#ff0000]/20 text-[#ff4e4e] border border-[#ff0000]/30">
                  Full Audio
                </span>
              </h2>
              <p className="text-xs text-[#b3b3b3]">
                Putar lagu favorit atau tambahkan musik yang belum ada di McMusic
              </p>
            </div>
          </div>

          <button
            onClick={handleClose}
            className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-white transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Body */}
        <div className="p-5 space-y-4 max-h-[75vh] overflow-y-auto">
          {/* Input Form */}
          <form 
            onSubmit={(e) => {
              e.preventDefault();
              handleResolve();
            }}
            className="space-y-2"
          >
            <label className="text-xs font-semibold text-[#b3b3b3] flex items-center justify-between">
              <span>Link Video YouTube atau Judul Lagu:</span>
              <button
                type="button"
                onClick={handlePaste}
                className="text-xs text-[#00a3ff] hover:underline flex items-center gap-1 font-normal"
              >
                <ClipboardPaste className="w-3.5 h-3.5" />
                Tempel dari Clipboard
              </button>
            </label>

            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Link className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[#b3b3b3]" />
                <input
                  type="text"
                  value={inputVal}
                  onChange={(e) => setInputVal(e.target.value)}
                  placeholder="https://youtu.be/... atau judul lagu"
                  className="w-full pl-9 pr-3 py-2.5 bg-[#242424] border border-white/10 rounded-xl text-white placeholder-[#727272] text-xs focus:outline-none focus:border-[#00a3ff] transition-colors"
                />
              </div>

              <button
                type="submit"
                disabled={isLoading || !inputVal.trim()}
                className="px-4 py-2.5 rounded-xl bg-[#00a3ff] hover:bg-[#008fe0] disabled:opacity-40 disabled:hover:bg-[#00a3ff] text-black font-bold text-xs flex items-center gap-1.5 transition-all shadow-md flex-shrink-0"
              >
                {isLoading ? (
                  <>
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    <span>Memuat...</span>
                  </>
                ) : (
                  <>
                    <Sparkles className="w-3.5 h-3.5 fill-current" />
                    <span>Cari</span>
                  </>
                )}
              </button>
            </div>
          </form>

          {/* Error Message */}
          {errorMsg && (
            <div className="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* Resolved Track Preview Card */}
          {resolvedTrack && (
            <div className="p-4 rounded-xl bg-[#202020] border border-white/10 space-y-4 animate-in fade-in slide-in-from-bottom-2 duration-200">
              <div className="flex items-center gap-3.5">
                <img
                  src={resolvedTrack.artwork || DEFAULT_ARTWORK}
                  alt={resolvedTrack.title}
                  onError={(e) => {
                    e.currentTarget.onerror = null;
                    e.currentTarget.src = DEFAULT_ARTWORK;
                  }}
                  className="w-16 h-16 rounded-lg object-cover flex-shrink-0 shadow-md"
                />
                <div className="min-w-0 flex-1">
                  <span className="inline-block px-2 py-0.5 rounded text-[10px] font-bold bg-[#ff0000]/20 text-[#ff5252] mb-1">
                    YouTube Stream
                  </span>
                  <h3 className="text-sm font-bold text-white truncate">
                    {resolvedTrack.title}
                  </h3>
                  <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                    {resolvedTrack.artist}
                  </p>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 pt-1 border-t border-white/5">
                <button
                  onClick={handlePlayNow}
                  className="flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-[#00a3ff] hover:bg-[#008fe0] text-black font-bold text-xs transition-colors"
                >
                  <Play className="w-3.5 h-3.5 fill-black" />
                  <span>{addedStatus === 'played' ? 'Sedang Diputar' : 'Putar Sekarang'}</span>
                </button>

                <button
                  onClick={handlePlayNext}
                  className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-white/10 hover:bg-white/15 text-white font-semibold text-xs transition-colors"
                >
                  <ListMusic className="w-3.5 h-3.5 text-[#00a3ff]" />
                  <span>{addedStatus === 'next' ? 'Diputar Berikutnya' : 'Putar Setelah Ini'}</span>
                </button>

                <button
                  onClick={handleAddQueue}
                  className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-white/10 hover:bg-white/15 text-white font-semibold text-xs transition-colors col-span-2 sm:col-span-1"
                >
                  <ListPlus className="w-3.5 h-3.5" />
                  <span>{addedStatus === 'queue' ? 'Di Antrean' : 'Ke Antrean'}</span>
                </button>
              </div>

              {/* Add to Playlist or Favorites */}
              <div className="pt-2 border-t border-white/5 flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
                <div className="flex-1 flex items-center gap-2">
                  <select
                    value={selectedPlaylistId}
                    onChange={(e) => setSelectedPlaylistId(e.target.value)}
                    className="flex-1 px-3 py-2 bg-[#282828] border border-white/10 rounded-lg text-xs text-white focus:outline-none"
                  >
                    <option value="">Pilih Playlist Tujuan...</option>
                    {playlists.map((pl) => (
                      <option key={pl.id} value={pl.id}>
                        {pl.name}
                      </option>
                    ))}
                  </select>

                  <button
                    disabled={!selectedPlaylistId}
                    onClick={handleAddToPlaylistClick}
                    className="px-3 py-2 bg-white/10 hover:bg-white/20 disabled:opacity-30 rounded-lg text-xs font-semibold flex items-center gap-1"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Tambah</span>
                  </button>
                </div>

                <button
                  onClick={handleSaveToLiked}
                  className="px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-xs font-semibold flex items-center justify-center gap-1.5 text-[#b3b3b3] hover:text-white"
                >
                  <Heart className={`w-3.5 h-3.5 ${addedStatus === 'liked' ? 'fill-[#00a3ff] text-[#00a3ff]' : ''}`} />
                  <span>{addedStatus === 'liked' ? 'Tersimpan' : 'Suka'}</span>
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
