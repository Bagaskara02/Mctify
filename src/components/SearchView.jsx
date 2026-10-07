import React, { useState, useEffect } from 'react';
import { 
  Play, 
  Pause,
  Heart, 
  Loader2, 
  Music,
  Plus,
  MoreHorizontal,
  User,
  Sparkles
} from 'lucide-react';
import { musicApi, DEFAULT_ARTWORK } from '../services/musicApi';

export default function SearchView({
  searchQuery = '',
  setSearchQuery,
  currentTrack,
  isPlaying,
  likedTrackIds = new Set(),
  playlists = [],
  onPlayTrack,
  onTogglePlayPause,
  onToggleLike,
  onOpenLyrics,
  onOpenArtist,
  onAddTrackToPlaylist,
  onTrackContextMenu,
}) {
  const [activeTab, setActiveTab] = useState('Semua'); // 'Semua' | 'Lagu' | 'Artis' | 'Playlist'
  const [songs, setSongs] = useState([]);
  const [artists, setArtists] = useState([]);
  const [isLoading, setIsLoading] = useState(false);

  const quickPills = [
    'Tenxi',
    'mejikuhibiniu',
    'Coldplay',
    'Naykilla',
    'Taylor Swift',
    'The Weeknd',
    'Billie Eilish',
    'Bernadya',
    'Bruno Mars',
  ];

  const browseCategories = [
    { name: 'Pop', color: 'from-[#8d67ab] to-[#452b61]' },
    { name: 'Hip-Hop', color: 'from-[#ba5d07] to-[#5c2a00]' },
    { name: 'Indie & Folk', color: 'from-[#1e6f5c] to-[#0d3b31]' },
    { name: 'Rock & Metal', color: 'from-[#e91429] to-[#6e050f]' },
    { name: 'R&B & Soul', color: 'from-[#dc148c] to-[#680540]' },
    { name: 'Akustik & Chill', color: 'from-[#27856a] to-[#123e32]' },
    { name: 'K-Pop', color: 'from-[#148a08] to-[#084003]' },
    { name: 'Dance & EDM', color: 'from-[#00a3ff] to-[#004780]' },
  ];

  // Perform multi-search with debounce
  useEffect(() => {
    if (!searchQuery || !searchQuery.trim()) {
      setSongs([]);
      setArtists([]);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    const timeout = setTimeout(async () => {
      try {
        const data = await musicApi.searchAll(searchQuery);
        setSongs(data.songs || []);
        setArtists(data.artists || []);
      } catch (err) {
        console.warn('Search failed:', err);
      } finally {
        setIsLoading(false);
      }
    }, 280);

    return () => clearTimeout(timeout);
  }, [searchQuery]);

  const topSong = songs[0];
  const topArtist = artists[0];

  const formatDuration = (sec) => {
    const mins = Math.floor(sec / 60);
    const secs = Math.floor(sec % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  return (
    <div className="flex-1 overflow-y-auto p-4 sm:px-8 py-5 space-y-6 select-none bg-[#121212] text-white pb-32 md:pb-16">
      {/* Filter Tabs matching Spotify Screenshot media_1791353069505.png */}
      <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none">
        {['Semua', 'Lagu', 'Artis', 'Playlist'].map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-3.5 py-1.5 rounded-full text-xs font-bold transition-all flex-shrink-0 ${
              activeTab === tab
                ? 'bg-white text-black'
                : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Quick Search Suggestion Pills */}
      <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none text-xs">
        <span className="text-[#b3b3b3] font-semibold flex-shrink-0 mr-1">Tren:</span>
        {quickPills.map((p) => (
          <button
            key={p}
            onClick={() => setSearchQuery(p)}
            className={`px-3 py-1 rounded-full text-xs font-semibold flex-shrink-0 transition-all ${
              searchQuery.toLowerCase() === p.toLowerCase()
                ? 'bg-[#00a3ff] text-black font-bold'
                : 'bg-white/5 hover:bg-white/10 text-[#b3b3b3] hover:text-white border border-white/5'
            }`}
          >
            {p}
          </button>
        ))}
      </div>

      {/* Loading Indicator */}
      {isLoading && (
        <div className="py-12 flex items-center justify-center gap-3 text-neutral-400">
          <Loader2 className="w-6 h-6 animate-spin text-[#00a3ff]" />
          <span className="text-sm">Mencari "{searchQuery}"...</span>
        </div>
      )}

      {/* Empty Search Query: Show Browse Genre Cards (matching media_1791353002996.png) */}
      {!searchQuery.trim() && !isLoading && (
        <div className="space-y-4 pt-2">
          <h2 className="text-xl sm:text-2xl font-black text-white tracking-tight">
            Jelajahi Semua Genre
          </h2>

          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
            {browseCategories.map((cat) => (
              <div
                key={cat.name}
                onClick={() => setSearchQuery(cat.name)}
                className={`relative h-28 sm:h-36 rounded-lg p-4 bg-gradient-to-br ${cat.color} overflow-hidden cursor-pointer shadow-md hover:scale-[1.02] active:scale-[0.98] transition-transform`}
              >
                <h3 className="font-black text-lg sm:text-xl text-white tracking-tight">
                  {cat.name}
                </h3>
                <Music className="w-16 h-16 sm:w-20 sm:h-20 absolute -right-3 -bottom-3 text-white/20 transform rotate-12 pointer-events-none" />
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Search Results Display */}
      {searchQuery.trim() && !isLoading && (
        <>
          {/* TAB: SEMUA */}
          {activeTab === 'Semua' && (
            <div className="space-y-8">
              {/* Top Result + Songs Section */}
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                {/* Top Result Card */}
                {topSong && (
                  <div className="lg:col-span-5 space-y-3">
                    <h2 className="text-xl font-black text-white tracking-tight">Hasil Teratas</h2>
                    <div
                      onClick={() => {
                        if (currentTrack?.id === topSong.id) {
                          onTogglePlayPause();
                        } else {
                          onPlayTrack(topSong, songs);
                        }
                      }}
                      onContextMenu={(e) => {
                        e.preventDefault();
                        onTrackContextMenu?.(e, topSong);
                      }}
                      className="group p-5 rounded-lg bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer relative flex flex-col justify-between h-56 shadow-md"
                    >
                      <img
                        src={topSong.artwork || DEFAULT_ARTWORK}
                        alt={topSong.title}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className="w-24 h-24 rounded-md object-cover shadow-lg"
                      />

                      <div className="mt-4">
                        <h3 className="text-2xl font-black text-white tracking-tight truncate">
                          {topSong.title}
                        </h3>
                        <p className="text-xs text-[#b3b3b3] mt-1 flex items-center gap-1.5">
                          <span className="font-semibold text-white hover:underline cursor-pointer" onClick={(e) => {
                            e.stopPropagation();
                            onOpenArtist?.({ name: topSong.artist, artwork: topSong.artwork });
                          }}>
                            {topSong.artist}
                          </span>
                          <span>•</span>
                          <span className="px-2 py-0.5 rounded-full bg-white/10 text-white font-bold text-[10px]">
                            Lagu
                          </span>
                        </p>
                      </div>

                      {/* Floating Play Button */}
                      <div
                        className={`absolute right-5 bottom-5 w-12 h-12 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-2xl transition-all duration-200 hover:scale-105 active:scale-95 ${
                          currentTrack?.id === topSong.id
                            ? 'opacity-100 translate-y-0'
                            : 'opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0'
                        }`}
                      >
                        {currentTrack?.id === topSong.id && isPlaying ? (
                          <Pause className="w-5 h-5 fill-black" />
                        ) : (
                          <Play className="w-5 h-5 fill-black ml-0.5" />
                        )}
                      </div>
                    </div>
                  </div>
                )}

                {/* Top Songs List */}
                <div className={`${topSong ? 'lg:col-span-7' : 'lg:col-span-12'} space-y-3`}>
                  <h2 className="text-xl font-black text-white tracking-tight">Lagu</h2>
                  <div className="space-y-1">
                    {songs.slice(0, 4).map((t) => {
                      const isCurrent = currentTrack?.id === t.id;
                      const isLiked = likedTrackIds.has(t.id);

                      return (
                        <div
                          key={t.id}
                          onClick={() => {
                            if (isCurrent) {
                              onTogglePlayPause();
                            } else {
                              onPlayTrack(t, songs);
                            }
                          }}
                          onContextMenu={(e) => {
                            e.preventDefault();
                            onTrackContextMenu?.(e, t);
                          }}
                          className={`group flex items-center justify-between p-2 sm:px-3 rounded-md transition-colors cursor-pointer ${
                            isCurrent ? 'bg-white/10' : 'hover:bg-white/5'
                          }`}
                        >
                          <div className="flex items-center gap-3 min-w-0 flex-1 mr-3">
                            <div className="relative w-10 h-10 rounded flex-shrink-0 overflow-hidden bg-black">
                              <img
                                src={t.artwork || DEFAULT_ARTWORK}
                                alt={t.title}
                                onError={(e) => {
                                  e.currentTarget.onerror = null;
                                  e.currentTarget.src = DEFAULT_ARTWORK;
                                }}
                                className="w-full h-full object-cover"
                              />
                              <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity">
                                <Play className="w-4 h-4 fill-white text-white ml-0.5" />
                              </div>
                            </div>

                            <div className="min-w-0 flex-1">
                              <p className={`font-bold text-sm truncate tracking-tight ${
                                isCurrent ? 'text-[#00a3ff]' : 'text-white'
                              }`}>
                                {t.title}
                              </p>
                              <p 
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onOpenArtist?.({ name: t.artist, artwork: t.artwork });
                                }}
                                className="text-xs text-[#b3b3b3] truncate mt-0.5 hover:underline cursor-pointer hover:text-white"
                              >
                                {t.artist}
                              </p>
                            </div>
                          </div>

                          <div className="flex items-center gap-3 text-xs text-[#b3b3b3] flex-shrink-0">
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                onToggleLike(t);
                              }}
                              className={`p-1.5 rounded-full transition-transform active:scale-90 ${
                                isLiked ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
                              }`}
                            >
                              <Heart className={`w-4 h-4 ${isLiked ? 'fill-current' : ''}`} />
                            </button>

                            <span className="tabular-nums text-[11px] w-9 text-right">
                              {formatDuration(t.duration || 180)}
                            </span>

                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                onTrackContextMenu?.(e, t);
                              }}
                              className="p-1 text-[#b3b3b3] hover:text-white"
                            >
                              <MoreHorizontal className="w-4 h-4" />
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              </div>

              {/* Artists Row matching media_1791353069505.png */}
              {artists.length > 0 && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <h2 className="text-xl font-black text-white tracking-tight">Artis</h2>
                    <span 
                      onClick={() => setActiveTab('Artis')}
                      className="text-xs font-bold text-[#b3b3b3] hover:underline cursor-pointer"
                    >
                      Tampilkan semua
                    </span>
                  </div>

                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                    {artists.slice(0, 6).map((art) => (
                      <div
                        key={art.id}
                        onClick={() => onOpenArtist?.(art)}
                        className="group p-3 sm:p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col items-center text-center"
                      >
                        <div className="relative w-28 h-28 sm:w-32 sm:h-32 rounded-full overflow-hidden mb-3 bg-[#282828] shadow-lg">
                          <img
                            src={art.artwork || DEFAULT_ARTWORK}
                            alt={art.name}
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

                        <h4 className="font-bold text-sm sm:text-base text-white truncate max-w-full tracking-tight">
                          {art.name}
                        </h4>
                        <p className="text-xs text-[#b3b3b3] mt-1">Artis</p>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* TAB: LAGU */}
          {activeTab === 'Lagu' && (
            <div className="space-y-4">
              <h2 className="text-xl font-black text-white tracking-tight">
                Semua Lagu ({songs.length})
              </h2>

              <div className="space-y-1">
                {songs.map((t, index) => {
                  const isCurrent = currentTrack?.id === t.id;
                  const isLiked = likedTrackIds.has(t.id);

                  return (
                    <div
                      key={t.id || index}
                      onClick={() => {
                        if (isCurrent) {
                          onTogglePlayPause();
                        } else {
                          onPlayTrack(t, songs);
                        }
                      }}
                      onContextMenu={(e) => {
                        e.preventDefault();
                        onTrackContextMenu?.(e, t);
                      }}
                      className={`group flex items-center justify-between px-3 sm:px-4 py-2.5 rounded-md transition-colors cursor-pointer ${
                        isCurrent ? 'bg-white/10' : 'hover:bg-white/5'
                      }`}
                    >
                      <div className="flex items-center gap-3.5 min-w-0 flex-1 mr-4">
                        <span className="w-5 text-right tabular-nums text-xs font-semibold text-[#b3b3b3] group-hover:hidden">
                          {index + 1}
                        </span>
                        <Play className="w-5 h-5 fill-white text-white hidden group-hover:block" />

                        <img
                          src={t.artwork || DEFAULT_ARTWORK}
                          alt={t.title}
                          onError={(e) => {
                            e.currentTarget.onerror = null;
                            e.currentTarget.src = DEFAULT_ARTWORK;
                          }}
                          className="w-10 h-10 rounded object-cover flex-shrink-0 shadow bg-[#242424]"
                        />

                        <div className="min-w-0 flex-1">
                          <p className={`font-bold text-sm truncate tracking-tight ${
                            isCurrent ? 'text-[#00a3ff]' : 'text-white'
                          }`}>
                            {t.title}
                          </p>
                          <p 
                            onClick={(e) => {
                              e.stopPropagation();
                              onOpenArtist?.({ name: t.artist, artwork: t.artwork });
                            }}
                            className="text-xs text-[#b3b3b3] truncate mt-0.5 hover:underline cursor-pointer hover:text-white"
                          >
                            {t.artist}
                          </p>
                        </div>
                      </div>

                      <div className="flex items-center gap-3 text-xs text-[#b3b3b3] flex-shrink-0">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onToggleLike(t);
                          }}
                          className={`p-1.5 rounded-full transition-transform active:scale-90 ${
                            isLiked ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
                          }`}
                        >
                          <Heart className={`w-4 h-4 ${isLiked ? 'fill-current' : ''}`} />
                        </button>

                        <span className="tabular-nums text-xs text-[#b3b3b3] w-10 text-right">
                          {formatDuration(t.duration || 180)}
                        </span>

                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onTrackContextMenu?.(e, t);
                          }}
                          className="p-1 text-[#b3b3b3] hover:text-white"
                        >
                          <MoreHorizontal className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* TAB: ARTIS (matching media_1791353069505.png) */}
          {activeTab === 'Artis' && (
            <div className="space-y-4">
              <h2 className="text-xl font-black text-white tracking-tight">
                Artis ({artists.length})
              </h2>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                {artists.map((art) => (
                  <div
                    key={art.id}
                    onClick={() => onOpenArtist?.(art)}
                    className="group p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col items-center text-center"
                  >
                    {/* Circular Artwork */}
                    <div className="relative w-32 h-32 sm:w-36 sm:h-36 rounded-full overflow-hidden mb-3 bg-[#282828] shadow-lg">
                      <img
                        src={art.artwork || DEFAULT_ARTWORK}
                        alt={art.name}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className="w-full h-full object-cover"
                      />

                      {/* Floating Play Button */}
                      <div className="absolute right-2 bottom-2 w-11 h-11 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 hover:scale-105 active:scale-95 transition-all duration-300">
                        <Play className="w-5 h-5 fill-black ml-0.5" />
                      </div>
                    </div>

                    <h4 className="font-bold text-base text-white truncate max-w-full tracking-tight">
                      {art.name}
                    </h4>
                    <p className="text-xs text-[#b3b3b3] mt-1">Artis</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB: PLAYLIST */}
          {activeTab === 'Playlist' && (
            <div className="space-y-4">
              <h2 className="text-xl font-black text-white tracking-tight">
                Playlist ({playlists.length})
              </h2>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                {playlists.map((pl) => (
                  <div
                    key={pl.id}
                    className="group p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col justify-between"
                  >
                    <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                      <img
                        src={pl.cover || DEFAULT_ARTWORK}
                        alt={pl.name}
                        className="w-full h-full object-cover"
                      />
                    </div>
                    <div>
                      <h4 className="font-bold text-sm sm:text-base truncate text-white tracking-tight">
                        {pl.name}
                      </h4>
                      <p className="text-xs text-[#b3b3b3] truncate mt-1">
                        {pl.tracks?.length || 0} lagu
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
