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

/**
 * Robust YouTube URL Parser supporting all mobile share links,
 * youtu.be, music.youtube.com, shorts, query string parameters (?si=),
 * and share text with embedded links.
 */
export function extractYouTubeInfo(rawUrl) {
  if (!rawUrl || typeof rawUrl !== 'string') {
    return { videoId: null, listId: null, isValid: false };
  }
  try {
    const cleaned = rawUrl.trim();
    // Support share messages containing embedded URLs (e.g. "Dengarkan: https://youtu.be/...")
    const urlMatch = cleaned.match(/https?:\/\/[^\s]+/i);
    const target = urlMatch ? urlMatch[0] : cleaned;

    const url = new URL(target.startsWith('http') ? target : `https://${target}`);
    const listId = url.searchParams.get('list');
    let videoId = url.searchParams.get('v');

    if (!videoId) {
      if (url.hostname.includes('youtu.be')) {
        videoId = url.pathname.slice(1).split('/')[0];
      } else if (url.pathname.includes('/shorts/') || url.pathname.includes('/embed/') || url.pathname.includes('/live/')) {
        const parts = url.pathname.split('/').filter(Boolean);
        videoId = parts[parts.length - 1];
      }
    }
    if (videoId) {
      if (videoId.includes('?')) videoId = videoId.split('?')[0];
      if (videoId.includes('&')) videoId = videoId.split('&')[0];
    }
    if (!videoId && /^[a-zA-Z0-9_-]{11}$/.test(cleaned)) {
      videoId = cleaned;
    }
    return { videoId, listId, isValid: Boolean(videoId || listId) };
  } catch {
    const match = rawUrl.match(/(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:embed\/|v\/|watch\?.*v=|shorts\/|live\/))([a-zA-Z0-9_-]{11})/i);
    const listMatch = rawUrl.match(/[?&]list=([a-zA-Z0-9_-]+)/i);
    const videoId = match ? match[1] : (/^[a-zA-Z0-9_-]{11}$/.test(rawUrl.trim()) ? rawUrl.trim() : null);
    const listId = listMatch ? listMatch[1] : null;
    return { videoId, listId, isValid: Boolean(videoId || listId) };
  }
}

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
          const info = extractYouTubeInfo(text);
          const effective = info.videoId ? `https://www.youtube.com/watch?v=${info.videoId}` : text.trim();
          setInputVal(effective);
          handleResolve(effective);
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
        setErrorMsg('Lagu tidak ditemukan dari link atau pencarian YouTube ini. Pastikan link video publik & valid.');
      }
    } catch {
      setErrorMsg('Gagal memuat info video YouTube. Silakan periksa koneksi atau coba link lain.');
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
    <div 
      className="fixed inset-0 z-[80] flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/85 backdrop-blur-sm animate-view-fade-in"
      onClick={(e) => {
        if (e.target === e.currentTarget) handleClose();
      }}
    >
      <div 
        className="relative w-full max-w-lg max-h-[88dvh] bg-[#181818] rounded-t-2xl sm:rounded-xl shadow-2xl overflow-hidden flex flex-col text-white"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/[0.06] flex-shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-[#ff0000]/15 text-[#ff4e4e] flex items-center justify-center flex-shrink-0">
              <YoutubeIcon className="w-5 h-5 fill-current" />
            </div>
            <div>
              <h2 className="text-sm sm:text-base font-bold text-white tracking-tight flex items-center gap-2">
                Import Lagu dari YouTube
                <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded bg-white/10 text-white/80">
                  Full Audio
                </span>
              </h2>
              <p className="text-xs text-[#b3b3b3]">
                Putar lagu langsung atau tambahkan musik ke playlist kamu
              </p>
            </div>
          </div>

          <button
            onClick={handleClose}
            className="p-1.5 rounded-full hover:bg-white/10 text-[#b3b3b3] hover:text-white transition-colors flex-shrink-0"
            title="Tutup"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Scrollable Body - Keyboard safe with dvh constraint */}
        <div className="p-4 sm:p-5 space-y-4 overflow-y-auto overscroll-contain">
          {/* Mobile-Safe Input Form */}
          <form 
            onSubmit={(e) => {
              e.preventDefault();
              if (!isLoading && inputVal.trim()) handleResolve();
            }}
            className="space-y-2"
          >
            <div className="flex items-center justify-between text-xs text-[#b3b3b3]">
              <span className="font-semibold">Link YouTube / YouTube Music:</span>
              <button
                type="button"
                onClick={handlePaste}
                onPointerDown={(e) => e.stopPropagation()}
                className="text-xs text-[#1ed760] hover:underline flex items-center gap-1 font-semibold"
              >
                <ClipboardPaste className="w-3.5 h-3.5" />
                Tempel Link
              </button>
            </div>

            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Link className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[#727272]" />
                <input
                  type="url"
                  inputMode="url"
                  enterKeyHint="go"
                  autoFocus
                  value={inputVal}
                  onChange={(e) => setInputVal(e.target.value)}
                  placeholder="https://youtu.be/... atau judul lagu"
                  className="w-full pl-9 pr-3 py-2.5 bg-[#242424] rounded-md text-white placeholder-[#727272] text-xs focus:outline-none focus:ring-1 focus:ring-[#1ed760] transition-colors"
                />
              </div>

              <button
                type="submit"
                disabled={isLoading || !inputVal.trim()}
                onPointerDown={(e) => e.stopPropagation()}
                className="px-4 py-2.5 rounded-md bg-[#1ed760] hover:bg-[#3be477] disabled:opacity-40 disabled:hover:bg-[#1ed760] text-black font-bold text-xs flex items-center gap-1.5 transition-all shadow-md flex-shrink-0"
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
            <div className="p-3 rounded-md bg-red-500/10 text-red-400 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {/* Resolved Track Preview Card */}
          {resolvedTrack && (
            <div className="p-3.5 sm:p-4 rounded-md bg-[#242424] space-y-4 animate-view-fade-in">
              <div className="flex items-center gap-3">
                <div className="w-14 h-14 rounded-[4px] overflow-hidden flex-shrink-0 bg-[#181818] shadow-md">
                  <img
                    src={resolvedTrack.artwork || DEFAULT_ARTWORK}
                    alt={resolvedTrack.title}
                    onError={(e) => {
                      e.currentTarget.onerror = null;
                      e.currentTarget.src = DEFAULT_ARTWORK;
                    }}
                    className="w-full h-full object-cover scale-[1.35]"
                  />
                </div>
                <div className="min-w-0 flex-1">
                  <span className="inline-block px-1.5 py-0.5 rounded text-[10px] font-bold bg-[#ff0000]/15 text-[#ff5252] mb-1">
                    YouTube Stream
                  </span>
                  <h3 className="text-sm font-bold text-white truncate tracking-tight">
                    {resolvedTrack.title}
                  </h3>
                  <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                    {resolvedTrack.artist}
                  </p>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 pt-2 border-t border-white/[0.06]">
                <button
                  type="button"
                  onClick={handlePlayNow}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="flex items-center justify-center gap-2 px-3 py-2 rounded-full bg-[#1ed760] hover:bg-[#3be477] text-black font-bold text-xs transition-colors"
                >
                  <Play className="w-3.5 h-3.5 fill-black" />
                  <span>{addedStatus === 'played' ? 'Sedang Diputar' : 'Putar Sekarang'}</span>
                </button>

                <button
                  type="button"
                  onClick={handlePlayNext}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-full bg-white/10 hover:bg-white/15 text-white font-semibold text-xs transition-colors"
                >
                  <ListMusic className="w-3.5 h-3.5 text-[#1ed760]" />
                  <span>{addedStatus === 'next' ? 'Diputar Berikutnya' : 'Setelah Ini'}</span>
                </button>

                <button
                  type="button"
                  onClick={handleAddQueue}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="flex items-center justify-center gap-1.5 px-3 py-2 rounded-full bg-white/10 hover:bg-white/15 text-white font-semibold text-xs transition-colors col-span-2 sm:col-span-1"
                >
                  <ListPlus className="w-3.5 h-3.5" />
                  <span>{addedStatus === 'queue' ? 'Di Antrean' : 'Ke Antrean'}</span>
                </button>
              </div>

              {/* Add to Playlist or Favorites */}
              <div className="pt-2 border-t border-white/[0.06] flex flex-col sm:flex-row items-stretch sm:items-center gap-2">
                <div className="flex-1 flex items-center gap-2">
                  <select
                    value={selectedPlaylistId}
                    onChange={(e) => setSelectedPlaylistId(e.target.value)}
                    className="flex-1 px-3 py-2 bg-[#181818] rounded-md text-xs text-white focus:outline-none"
                  >
                    <option value="">Pilih Playlist Tujuan...</option>
                    {playlists.map((pl) => (
                      <option key={pl.id} value={pl.id}>
                        {pl.name}
                      </option>
                    ))}
                  </select>

                  <button
                    type="button"
                    disabled={!selectedPlaylistId}
                    onClick={handleAddToPlaylistClick}
                    onPointerDown={(e) => e.stopPropagation()}
                    className="px-3 py-2 bg-white/10 hover:bg-white/20 disabled:opacity-30 rounded-md text-xs font-semibold flex items-center gap-1"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Tambah</span>
                  </button>
                </div>

                <button
                  type="button"
                  onClick={handleSaveToLiked}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="px-3 py-2 rounded-md bg-white/5 hover:bg-white/10 text-xs font-semibold flex items-center justify-center gap-1.5 text-[#b3b3b3] hover:text-white"
                >
                  <Heart className={`w-3.5 h-3.5 ${addedStatus === 'liked' ? 'fill-[#1ed760] text-[#1ed760]' : ''}`} />
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
