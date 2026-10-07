import React, { useState, useEffect } from 'react';
import { 
  Play, 
  Pause, 
  Shuffle, 
  Heart, 
  MoreHorizontal, 
  CheckCircle2, 
  ArrowLeft,
  Loader2,
  Music2,
  Sparkles
} from 'lucide-react';
import { musicApi, DEFAULT_ARTWORK } from '../services/musicApi';

export default function ArtistView({
  artist,
  currentTrack,
  isPlaying,
  likedTrackIds = new Set(),
  onPlayTrack,
  onTogglePlayPause,
  onToggleLike,
  onTrackContextMenu,
  onBack,
}) {
  const [artistData, setArtistData] = useState(null);
  const [topSongs, setTopSongs] = useState([]);
  const [allSongs, setAllSongs] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isFollowing, setIsFollowing] = useState(false);

  // Fetch artist details and popular singles
  useEffect(() => {
    if (!artist) return;

    let isSubscribed = true;
    setIsLoading(true);

    musicApi.getArtistDetails(artist.id, artist.name)
      .then((data) => {
        if (isSubscribed) {
          setArtistData(data.artist || artist);
          setTopSongs(data.topSongs || []);
          setAllSongs(data.allSongs || []);
          setIsLoading(false);
        }
      })
      .catch((err) => {
        console.warn('Failed to load artist details:', err);
        if (isSubscribed) {
          setArtistData(artist);
          setIsLoading(false);
        }
      });

    return () => {
      isSubscribed = false;
    };
  }, [artist?.id, artist?.name]);

  const activeArtist = artistData || artist;
  const isPlayingThisArtist = isPlaying && currentTrack?.artist?.toLowerCase().includes(activeArtist?.name?.toLowerCase());

  // Formatter for realistic play counts matching Spotify screenshot
  const getPlayCount = (index) => {
    const counts = [
      '310.756.981',
      '207.620.762',
      '226.808.384',
      '114.835.312',
      '89.412.050',
      '74.320.190',
      '51.290.412',
      '42.100.871',
    ];
    return counts[index] || `${(150 - index * 12).toLocaleString('id-ID')}.000`;
  };

  const formatDuration = (sec) => {
    const mins = Math.floor(sec / 60);
    const secs = Math.floor(sec % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  const handlePlayAll = () => {
    if (topSongs.length === 0) return;
    if (isPlayingThisArtist) {
      onTogglePlayPause();
    } else {
      onPlayTrack(topSongs[0], allSongs.length > 0 ? allSongs : topSongs);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto select-none bg-[#121212] text-white pb-32 md:pb-16 relative">
      {/* Top Floating Back Bar */}
      <div className="sticky top-0 z-30 px-4 sm:px-8 py-3 bg-[#121212]/80 backdrop-blur-md flex items-center justify-between border-b border-white/[0.04]">
        <button
          onClick={onBack}
          className="w-9 h-9 rounded-full bg-black/60 hover:bg-black/90 text-white flex items-center justify-center transition-all hover:scale-105 active:scale-95 shadow-md"
          title="Kembali"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>

        <h3 className="font-bold text-sm text-white truncate max-w-xs opacity-90">
          {activeArtist?.name || 'Artis'}
        </h3>

        <div className="w-9" />
      </div>

      {/* Hero Header Banner (matching media_1791353080300.png) */}
      <div className="relative h-64 sm:h-80 md:h-96 w-full overflow-hidden bg-neutral-900 flex flex-col justify-end p-6 sm:p-10 select-none">
        {/* Background Banner Image */}
        {(activeArtist?.headerBanner || activeArtist?.avatar || activeArtist?.artwork) ? (
          <img
            src={activeArtist?.headerBanner || activeArtist?.avatar || activeArtist?.artwork}
            alt={activeArtist?.name}
            className="absolute inset-0 w-full h-full object-cover object-center filter brightness-[0.78]"
          />
        ) : (
          <div className="absolute inset-0 bg-gradient-to-b from-[#1e3a5f] to-[#121212]" />
        )}

        {/* Ambient Dark Gradient Overlays */}
        <div className="absolute inset-0 bg-gradient-to-t from-[#121212] via-[#121212]/50 to-transparent" />
        <div className="absolute inset-0 bg-black/30" />

        {/* Artist Header Text Details */}
        <div className="relative z-10 space-y-2">
          {/* Verified Badge */}
          <div className="flex items-center gap-1.5 text-xs sm:text-sm font-bold text-white drop-shadow">
            <CheckCircle2 className="w-4 h-4 sm:w-5 sm:h-5 text-[#00a3ff] fill-[#00a3ff]" />
            <span>Diverifikasi oleh Spotify</span>
          </div>

          {/* Giant Artist Name */}
          <h1 className="text-4xl sm:text-6xl md:text-8xl font-black text-white tracking-tight drop-shadow-2xl">
            {activeArtist?.name}
          </h1>

          {/* Monthly Listeners */}
          <p className="text-xs sm:text-sm font-semibold text-white/90 drop-shadow">
            {activeArtist?.monthlyListeners || '4,9 jt pendengar bulanan'}
          </p>
        </div>
      </div>

      {/* Action Bar (matching media_1791353080300.png) */}
      <div className="px-4 sm:px-8 py-5 flex items-center gap-4 sm:gap-6 bg-gradient-to-b from-[#121212] to-transparent">
        {/* Giant Azure Play Button */}
        <button
          onClick={handlePlayAll}
          className="w-14 h-14 sm:w-16 sm:h-16 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-xl shadow-[#00a3ff]/20 hover:scale-105 active:scale-95 transition-all flex-shrink-0"
          title={isPlayingThisArtist ? 'Jeda' : 'Putar'}
        >
          {isPlayingThisArtist ? (
            <Pause className="w-6 h-6 sm:w-7 sm:h-7 fill-black" />
          ) : (
            <Play className="w-6 h-6 sm:w-7 sm:h-7 fill-black ml-1" />
          )}
        </button>

        {/* Follow Button */}
        <button
          onClick={() => setIsFollowing(!isFollowing)}
          className={`px-4 sm:px-5 py-1.5 rounded-full text-xs sm:text-sm font-bold border transition-all active:scale-95 ${
            isFollowing 
              ? 'border-[#00a3ff] text-[#00a3ff] bg-[#00a3ff]/10' 
              : 'border-white/40 hover:border-white text-white bg-transparent'
          }`}
        >
          {isFollowing ? 'Mengikuti' : 'Ikuti'}
        </button>

        {/* More Options */}
        <button
          onClick={(e) => onTrackContextMenu?.(e, topSongs[0])}
          className="p-2 text-[#b3b3b3] hover:text-white transition-colors"
          title="Opsi Lainnya"
        >
          <MoreHorizontal className="w-6 h-6" />
        </button>
      </div>

      {/* Popular Tracks Section (matching media_1791353080300.png) */}
      <div className="px-4 sm:px-8 space-y-4">
        <h2 className="text-xl sm:text-2xl font-black text-white tracking-tight">
          Populer
        </h2>

        {isLoading ? (
          <div className="py-12 flex items-center justify-center gap-3 text-neutral-400">
            <Loader2 className="w-6 h-6 animate-spin text-[#00a3ff]" />
            <span className="text-sm">Memuat lagu populer {activeArtist?.name}...</span>
          </div>
        ) : (
          <div className="space-y-1">
            {topSongs.map((track, index) => {
              const isCurrent = currentTrack?.id === track.id || currentTrack?.videoId === track.videoId;
              const isLiked = likedTrackIds.has(track.id) || likedTrackIds.has(track.videoId);

              return (
                <div
                  key={track.id || index}
                  onClick={() => {
                    if (isCurrent) {
                      onTogglePlayPause();
                    } else {
                      onPlayTrack(track, allSongs.length > 0 ? allSongs : topSongs);
                    }
                  }}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    onTrackContextMenu?.(e, track);
                  }}
                  className={`group flex items-center justify-between px-3 sm:px-4 py-2.5 rounded-md transition-colors cursor-pointer ${
                    isCurrent ? 'bg-white/10' : 'hover:bg-white/5'
                  }`}
                >
                  {/* Left: Index / Play Icon + Artwork + Title */}
                  <div className="flex items-center gap-3.5 min-w-0 flex-1 mr-4">
                    {/* Index or Play icon */}
                    <div className="w-6 text-center tabular-nums text-sm font-semibold text-[#b3b3b3] flex-shrink-0">
                      {isCurrent && isPlaying ? (
                        <div className="flex items-end justify-center gap-0.5 h-3.5">
                          <span className="w-0.5 h-3.5 bg-[#00a3ff] animate-pulse" />
                          <span className="w-0.5 h-2.5 bg-[#00a3ff] animate-pulse delay-75" />
                          <span className="w-0.5 h-3.5 bg-[#00a3ff] animate-pulse delay-150" />
                        </div>
                      ) : (
                        <span className="group-hover:hidden">{index + 1}</span>
                      )}
                      <Play className="w-4 h-4 fill-white hidden group-hover:block mx-auto text-white" />
                    </div>

                    {/* Artwork Thumbnail */}
                    <img
                      src={track.artwork || DEFAULT_ARTWORK}
                      alt={track.title}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-10 h-10 sm:w-11 sm:h-11 rounded object-cover flex-shrink-0 shadow bg-[#242424]"
                    />

                    {/* Title & Explicit Badge */}
                    <div className="min-w-0 flex-1">
                      <p className={`font-bold text-sm truncate tracking-tight ${
                        isCurrent ? 'text-[#00a3ff]' : 'text-white'
                      }`}>
                        {track.title}
                      </p>
                      <div className="flex items-center gap-1.5 mt-0.5">
                        <span className="px-1 py-0.2 rounded text-[9px] font-black bg-[#404040] text-[#b3b3b3]">
                          E
                        </span>
                        <span className="text-xs text-[#b3b3b3] truncate sm:hidden">
                          {getPlayCount(index)}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Middle: Stream / Play Count (Desktop only, matches screenshot) */}
                  <div className="hidden sm:block text-xs text-[#b3b3b3] tabular-nums w-36 text-right pr-4">
                    {getPlayCount(index)}
                  </div>

                  {/* Right: Like + Duration + Context Menu */}
                  <div className="flex items-center gap-3 text-xs text-[#b3b3b3] flex-shrink-0">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onToggleLike(track);
                      }}
                      className={`p-1.5 rounded-full transition-transform active:scale-90 ${
                        isLiked 
                          ? 'text-[#00a3ff] opacity-100' 
                          : 'opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-white'
                      }`}
                      title={isLiked ? 'Disukai' : 'Sukai'}
                    >
                      <Heart className={`w-4 h-4 ${isLiked ? 'fill-current' : ''}`} />
                    </button>

                    <span className="tabular-nums text-xs text-[#b3b3b3] w-10 text-right">
                      {formatDuration(track.duration || 190)}
                    </span>

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onTrackContextMenu?.(e, track);
                      }}
                      className="p-1 opacity-0 group-hover:opacity-100 text-[#b3b3b3] hover:text-white transition-opacity"
                      title="Opsi"
                    >
                      <MoreHorizontal className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Diskografi / Single & EP Section */}
      {allSongs.length > topSongs.length && (
        <div className="px-4 sm:px-8 pt-10 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-xl sm:text-2xl font-black text-white tracking-tight">
              Diskografi & Rilis Lainnya
            </h2>
            <span className="text-xs font-bold text-[#b3b3b3] hover:underline cursor-pointer">
              Tampilkan Semua ({allSongs.length})
            </span>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3 sm:gap-5">
            {allSongs.slice(topSongs.length, topSongs.length + 12).map((song) => {
              const isCurrent = currentTrack?.id === song.id || currentTrack?.videoId === song.videoId;

              return (
                <div
                  key={song.id}
                  onClick={() => {
                    if (isCurrent) {
                      onTogglePlayPause();
                    } else {
                      onPlayTrack(song, allSongs);
                    }
                  }}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    onTrackContextMenu?.(e, song);
                  }}
                  className="group p-3 sm:p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col justify-between"
                >
                  <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                    <img
                      src={song.artwork || DEFAULT_ARTWORK}
                      alt={song.title}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-full h-full object-cover"
                    />

                    <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 hover:scale-105 active:scale-95 transition-all duration-300">
                      <Play className="w-4 h-4 fill-black ml-0.5" />
                    </div>
                  </div>

                  <div>
                    <h4 className="font-bold text-sm truncate text-white tracking-tight">
                      {song.title}
                    </h4>
                    <p className="text-xs text-[#b3b3b3] truncate mt-1">
                      Single • {activeArtist?.name}
                    </p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
