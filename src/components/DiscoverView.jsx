import React, { useState, useEffect } from 'react';
import {
  Play,
  Pause,
  Heart,
  ListPlus,
  Sparkles,
  MoreHorizontal,
  RotateCw,
} from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';
import { extractPaletteFromImage } from '../utils/colorExtractor';

export default function DiscoverView({
  trendingTracks = [],
  playlists = [],
  personalizedFeed = null,
  isLoadingFeed = false,
  onRefreshFeed,
  currentTrack,
  isPlaying,
  likedTrackIds = new Set(),
  onPlayTrack,
  onPlayTrackWithRadio,
  onTogglePlayPause,
  onToggleLike,
  onOpenLyrics,
  onOpenImportModal,
  onSelectPlaylist,
  onSelectLiked,
  onOpenArtist,
  onTrackContextMenu,
  onPlaylistContextMenu,
}) {
  const [activeTab, setActiveTab] = useState('Semua'); // 'Semua' | 'Musik' | 'Mix & Radio' | 'Trending'
  const [ambientHex, setAmbientHex] = useState('#1d4ed8');
  const [hoveredArtwork, setHoveredArtwork] = useState(null);

  const candidatePool =
    personalizedFeed?.quickCards?.length > 0 ? personalizedFeed.quickCards : trendingTracks;

  // Slot #1 is Liked Songs + 7 quick picks = 8 tiles matching Spotify Desktop Web Player
  const quickCards = candidatePool.slice(0, 7);

  const sections =
    personalizedFeed?.sections?.length > 0
      ? personalizedFeed.sections
      : [
          {
            id: 'default-trending',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Musik yang sedang viral dan menduduki puncak tangga lagu',
            badge: 'Trending',
            tracks: trendingTracks.slice(0, 14),
          },
        ];

  // Dynamically extract ambient color for hovered quick card OR current playing track
  useEffect(() => {
    const targetArt = hoveredArtwork || currentTrack?.artwork || quickCards[0]?.artwork;
    if (!targetArt) return;

    let cancelled = false;
    extractPaletteFromImage(targetArt).then((pal) => {
      if (!cancelled && pal?.primary) {
        setAmbientHex(pal.primary);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [hoveredArtwork, currentTrack?.artwork, quickCards[0]?.artwork]);

  // Build Spotify-style Daily Mixes from dynamic tracks pool
  const allPoolTracks = [
    ...quickCards,
    ...(sections.flatMap((s) => s.tracks || [])),
    ...trendingTracks,
  ].filter((t, i, arr) => t && arr.findIndex((x) => x.id === t.id) === i);

  const dailyMixConfigs = [
    { id: 'mix-1', title: 'Daily Mix 01', badge: '01', accent: '#3B82F6', offset: 0 },
    { id: 'mix-2', title: 'Daily Mix 02', badge: '02', accent: '#10B981', offset: 3 },
    { id: 'mix-3', title: 'Release Radar', badge: 'NEW', accent: '#A855F7', offset: 6 },
    { id: 'mix-4', title: 'Discover Weekly', badge: 'MIX', accent: '#F59E0B', offset: 9 },
  ];

  const dailyMixes = allPoolTracks.length > 0
    ? dailyMixConfigs.map((cfg) => {
        const len = allPoolTracks.length;
        const start = cfg.offset % len;
        const mixTracks = [
          ...allPoolTracks.slice(start),
          ...allPoolTracks.slice(0, start),
        ].slice(0, 12);
        const topArtists = [...new Set(mixTracks.map((t) => t.artist.split(',')[0].trim()))]
          .slice(0, 3)
          .join(', ');
        return {
          ...cfg,
          cover: mixTracks[0]?.artwork || DEFAULT_ARTWORK,
          subtitle: `${topArtists || 'Beragam Artis'} & lainnya`,
          tracks: mixTracks,
        };
      })
    : [];

  // Derive top unique artists for circular artist portraits row
  const featuredArtists = [];
  const seenArtists = new Set();
  for (const t of allPoolTracks) {
    const primary = (t.artist || '').split(',')[0].trim();
    const key = primary.toLowerCase();
    if (primary && !seenArtists.has(key)) {
      seenArtists.add(key);
      featuredArtists.push({ name: primary, artwork: t.artwork || DEFAULT_ARTWORK });
      if (featuredArtists.length >= 6) break;
    }
  }

  const hour = new Date().getHours();
  const greeting =
    hour < 11
      ? 'Selamat Pagi'
      : hour < 15
      ? 'Selamat Siang'
      : hour < 19
      ? 'Selamat Sore'
      : 'Selamat Malam';

  const isInitialLoading = isLoadingFeed && quickCards.length === 0;

  return (
    <div className="flex-1 overflow-y-auto select-none bg-[#121212] text-white relative">
      {/* Dynamic Interactive Spotify Ambient Hero Gradient */}
      <div
        className="absolute top-0 left-0 right-0 h-80 pointer-events-none z-0 transition-all duration-700 ease-out"
        style={{
          background: `linear-gradient(180deg, ${ambientHex}66 0%, ${ambientHex}22 45%, #121212 100%)`,
        }}
      />

      {/* Sticky Filter Pills Header */}
      <div className="sticky top-0 z-20 px-4 sm:px-8 py-3 bg-[#121212]/80 backdrop-blur-md flex items-center justify-between gap-2 border-b border-white/[0.04]">
        <div className="flex items-center gap-2 overflow-x-auto no-scrollbar">
          {['Semua', 'Musik', 'Mix & Radio', 'Trending'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-3.5 py-1.5 rounded-full text-xs font-bold whitespace-nowrap transition-all ${
                activeTab === tab
                  ? 'bg-white text-black'
                  : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2 flex-shrink-0">
          {onRefreshFeed && (
            <button
              onClick={onRefreshFeed}
              disabled={isLoadingFeed}
              className="p-2 rounded-full bg-white/10 hover:bg-white/20 text-white transition-all active:scale-95 disabled:opacity-50"
              title="Segarkan Rekomendasi"
            >
              <RotateCw className={`w-3.5 h-3.5 ${isLoadingFeed ? 'animate-spin text-[#3B82F6]' : ''}`} />
            </button>
          )}
          <button
            onClick={onOpenImportModal}
            className="px-3.5 py-1.5 rounded-full bg-white/10 hover:bg-white/20 text-white font-bold text-xs flex items-center gap-1.5 transition-all active:scale-95"
          >
            <ListPlus className="w-3.5 h-3.5 stroke-[2.5]" />
            <span>Impor Playlist</span>
          </button>
        </div>
      </div>

      <div className="relative z-10 px-4 sm:px-8 pb-32 md:pb-16 space-y-8 pt-4">
        {/* Skeleton Shimmer Loader while loading */}
        {isInitialLoading && (
          <div className="space-y-8">
            <div className="space-y-4">
              <div className="h-8 w-44 skeleton-box" />
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                {[...Array(8)].map((_, i) => (
                  <div key={i} className="h-16 skeleton-box" />
                ))}
              </div>
            </div>
            <div className="space-y-4">
              <div className="h-7 w-48 skeleton-box" />
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-5">
                {[...Array(4)].map((_, i) => (
                  <div key={i} className="aspect-square skeleton-box" />
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Section 1: Greeting + Spotify 8-Tile Shortcuts Grid */}
        {!isInitialLoading && (activeTab === 'Semua' || activeTab === 'Musik') && (
          <div className="space-y-4">
            <div>
              <h1 className="text-2xl sm:text-3xl font-black tracking-tight text-white">{greeting}</h1>
              {personalizedFeed?.isPersonalized && (
                <p className="text-xs text-[#b3b3b3] mt-1 flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5 text-[#3B82F6]" />
                  <span>Dipersonalisasi berdasarkan lagu & artis yang sering kamu putar</span>
                </p>
              )}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2 sm:gap-3">
              {/* Slot #1: Lagu yang Disukai Shortcut */}
              <div
                onClick={() => onSelectLiked?.()}
                onMouseEnter={() => setAmbientHex('#450af5')}
                onMouseLeave={() => setHoveredArtwork(null)}
                className="group relative flex items-center h-14 sm:h-16 bg-white/[0.08] hover:bg-white/[0.16] rounded-md overflow-hidden cursor-pointer transition-colors duration-200 select-none shadow-sm"
              >
                <div className="w-14 h-14 sm:w-16 sm:h-16 flex-shrink-0 bg-gradient-to-br from-[#450af5] to-[#8e8ee5] flex items-center justify-center shadow-md">
                  <Heart className="w-6 h-6 text-white fill-white" />
                </div>
                <div className="flex-1 min-w-0 px-3 sm:px-4">
                  <h4 className="font-bold text-xs sm:text-sm truncate text-white tracking-tight">
                    Lagu yang Disukai
                  </h4>
                  <p className="text-[11px] text-[#b3b3b3] truncate mt-0.5">
                    {likedTrackIds.size} lagu favorit
                  </p>
                </div>
                <div className="mr-3 w-10 h-10 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-xl opacity-0 translate-y-1 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-200 flex-shrink-0">
                  <Play className="w-4 h-4 fill-black ml-0.5" />
                </div>
              </div>

              {/* Slots #2-#8: Dynamic Recent & Personalized Quick Cards */}
              {quickCards.map((t) => {
                const isCurrent = currentTrack?.id === t.id;
                return (
                  <div
                    key={t.id}
                    onMouseEnter={() => setHoveredArtwork(t.artwork || DEFAULT_ARTWORK)}
                    onMouseLeave={() => setHoveredArtwork(null)}
                    onClick={() => {
                      if (isCurrent) {
                        onTogglePlayPause();
                      } else if (onPlayTrackWithRadio) {
                        onPlayTrackWithRadio(t);
                      } else {
                        onPlayTrack(t, quickCards);
                      }
                    }}
                    onContextMenu={(e) => {
                      e.preventDefault();
                      onTrackContextMenu?.(e, t);
                    }}
                    className={`group relative flex items-center h-14 sm:h-16 rounded-md overflow-hidden cursor-pointer transition-colors duration-200 select-none shadow-sm ${
                      isCurrent
                        ? 'bg-[#3B82F6]/20 ring-1 ring-[#3B82F6]/40'
                        : 'bg-white/[0.08] hover:bg-white/[0.16]'
                    }`}
                  >
                    <div className="w-14 h-14 sm:w-16 sm:h-16 flex-shrink-0 overflow-hidden bg-[#242424] shadow-md">
                      <img
                        src={t.artwork || DEFAULT_ARTWORK}
                        alt={t.title}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className="w-full h-full object-cover"
                      />
                    </div>
                    <div className="flex-1 min-w-0 px-3 sm:px-4">
                      <h4
                        className={`font-bold text-xs sm:text-sm truncate tracking-tight ${
                          isCurrent ? 'text-[#3B82F6]' : 'text-white'
                        }`}
                      >
                        {t.title}
                      </h4>
                      <p className="text-[11px] sm:text-xs text-[#b3b3b3] truncate mt-0.5">{t.artist}</p>
                    </div>

                    <div
                      className={`mr-3 w-10 h-10 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-xl transition-all duration-200 hover:scale-105 active:scale-95 flex-shrink-0 ${
                        isCurrent
                          ? 'opacity-100 translate-y-0'
                          : 'opacity-0 translate-y-1 group-hover:opacity-100 group-hover:translate-y-0'
                      }`}
                    >
                      {isCurrent && isPlaying ? (
                        <Pause className="w-4 h-4 fill-black" />
                      ) : (
                        <Play className="w-4 h-4 fill-black ml-0.5" />
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Section 2: Dibuat Untuk Kamu (Daily Mixes 01..04) */}
        {dailyMixes.length > 0 && (activeTab === 'Semua' || activeTab === 'Mix & Radio') && (
          <div className="space-y-4">
            <div className="flex items-end justify-between">
              <div>
                <h2 className="text-xl sm:text-2xl font-black tracking-tight text-white">
                  Dibuat Untuk Kamu
                </h2>
                <p className="text-xs text-[#b3b3b3] mt-0.5">
                  Campuran musik otomatis berdasarkan artis & lagu favoritmu
                </p>
              </div>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-5">
              {dailyMixes.map((mix) => (
                <div
                  key={mix.id}
                  onClick={() => onPlayTrack(mix.tracks[0], mix.tracks)}
                  className="group p-3 sm:p-4 rounded-lg bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col justify-between"
                >
                  <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-lg">
                    <img
                      src={mix.cover}
                      alt={mix.title}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-full h-full object-cover"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-black/75 via-transparent to-transparent" />
                    {/* Spotify Left Colored Stripe Label */}
                    <div
                      className="absolute left-0 bottom-3 px-2.5 py-1 rounded-r text-xs font-black text-black shadow-md"
                      style={{ backgroundColor: mix.accent }}
                    >
                      {mix.title}
                    </div>
                    <div
                      className="absolute top-2.5 right-2.5 px-1.5 py-0.5 rounded bg-black/70 text-[10px] font-black"
                      style={{ color: mix.accent }}
                    >
                      {mix.badge}
                    </div>

                    <div className="absolute right-2.5 bottom-2.5 w-11 h-11 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 hover:scale-105 transition-all duration-300">
                      <Play className="w-5 h-5 fill-black ml-0.5" />
                    </div>
                  </div>

                  <div>
                    <h4 className="font-bold text-sm sm:text-base truncate text-white">{mix.title}</h4>
                    <p className="text-xs text-[#b3b3b3] line-clamp-2 mt-1 leading-snug">
                      {mix.subtitle}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Section 3: Artis Populer (Circular Spotify Artist Shelf) */}
        {featuredArtists.length > 0 && (activeTab === 'Semua' || activeTab === 'Mix & Radio') && (
          <div className="space-y-4">
            <h2 className="text-xl sm:text-2xl font-black tracking-tight text-white">
              Artis Populer Untukmu
            </h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-3 sm:gap-5">
              {featuredArtists.map((art) => (
                <div
                  key={art.name}
                  onClick={() => onOpenArtist?.({ name: art.name, artwork: art.artwork })}
                  className="group p-3 sm:p-4 rounded-lg bg-[#181818] hover:bg-[#282828] transition-colors cursor-pointer text-center flex flex-col items-center"
                >
                  <div className="relative aspect-square w-full rounded-full overflow-hidden mb-3 shadow-lg bg-[#242424]">
                    <img
                      src={art.artwork}
                      alt={art.name}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                    />
                    <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#3B82F6] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300">
                      <Play className="w-4 h-4 fill-black ml-0.5" />
                    </div>
                  </div>
                  <h4 className="font-bold text-sm truncate w-full text-white">{art.name}</h4>
                  <p className="text-xs text-[#b3b3b3] mt-0.5">Artis</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Section 4: Playlist Kamu */}
        {playlists.length > 0 && (activeTab === 'Semua' || activeTab === 'Musik') && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-xl sm:text-2xl font-black tracking-tight text-white">
                Playlist kamu
              </h2>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3 sm:gap-5">
              {playlists.map((pl) => (
                <div
                  key={pl.id}
                  onClick={() => onSelectPlaylist(pl.id)}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    onPlaylistContextMenu?.(e, pl);
                  }}
                  className="group p-3 sm:p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col justify-between"
                >
                  <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                    <img
                      src={pl.cover || DEFAULT_ARTWORK}
                      alt={pl.name}
                      onError={(e) => {
                        e.currentTarget.onerror = null;
                        e.currentTarget.src = DEFAULT_ARTWORK;
                      }}
                      className="w-full h-full object-cover"
                    />
                    <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 hover:scale-105 active:scale-95 transition-all duration-300">
                      <Play className="w-4 h-4 fill-black ml-0.5" />
                    </div>
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

        {/* Section 5: Personalized Dynamic Sections */}
        {sections.map((section) => (
          <div key={section.id} className="space-y-4">
            <div className="flex items-end justify-between">
              <div>
                <div className="flex items-center gap-2.5">
                  <h2 className="text-xl sm:text-2xl font-black tracking-tight text-white">
                    {section.title}
                  </h2>
                  {section.badge && (
                    <span className="hidden sm:inline-block px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-[#3B82F6]/15 text-[#3B82F6] border border-[#3B82F6]/30">
                      {section.badge}
                    </span>
                  )}
                </div>
                {section.subtitle && (
                  <p className="text-xs text-[#b3b3b3] mt-0.5">{section.subtitle}</p>
                )}
              </div>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-7 gap-3 sm:gap-6">
              {section.tracks?.map((t) => {
                const isCurrent = currentTrack?.id === t.id;
                const isLiked = likedTrackIds.has(t.id);

                return (
                  <div
                    key={t.id}
                    onClick={() => {
                      if (isCurrent) {
                        onTogglePlayPause();
                      } else if (onPlayTrackWithRadio) {
                        onPlayTrackWithRadio(t);
                      } else {
                        onPlayTrack(t, section.tracks);
                      }
                    }}
                    onContextMenu={(e) => {
                      e.preventDefault();
                      onTrackContextMenu?.(e, t);
                    }}
                    className="group p-3 sm:p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer relative flex flex-col justify-between"
                  >
                    <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                      <img
                        src={t.artwork || DEFAULT_ARTWORK}
                        alt={t.title}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className="w-full h-full object-cover"
                      />

                      <div
                        className={`absolute right-2 bottom-2 w-10 h-10 sm:w-11 sm:h-11 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl transition-all duration-300 hover:scale-105 active:scale-95 ${
                          isCurrent
                            ? 'opacity-100 translate-y-0'
                            : 'opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0'
                        }`}
                      >
                        {isCurrent && isPlaying ? (
                          <Pause className="w-5 h-5 fill-black" />
                        ) : (
                          <Play className="w-5 h-5 fill-black ml-0.5" />
                        )}
                      </div>
                    </div>

                    <div className="min-w-0">
                      <h4 className="font-bold text-sm sm:text-base truncate text-white tracking-tight leading-snug">
                        {t.title}
                      </h4>
                      <p className="font-normal text-xs sm:text-sm text-[#b3b3b3] line-clamp-2 mt-1 leading-snug">
                        {t.artist}
                      </p>
                    </div>

                    <div className="flex items-center justify-between pt-3 mt-2 border-t border-white/[0.04] text-xs text-[#b3b3b3]">
                      <span className="tabular-nums text-[11px] text-[#a7a7a7]">
                        {Math.floor(t.duration / 60)}:{(t.duration % 60).toString().padStart(2, '0')}
                      </span>

                      <div className="flex items-center gap-1">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onToggleLike(t);
                          }}
                          className={`p-1.5 rounded-full transition-colors ${
                            isLiked ? 'text-[#3B82F6]' : 'text-[#b3b3b3] hover:text-white'
                          }`}
                          title="Sukai"
                        >
                          <Heart className={`w-4 h-4 ${isLiked ? 'fill-current' : ''}`} />
                        </button>

                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onTrackContextMenu?.(e, t);
                          }}
                          className="p-1.5 rounded-full text-[#b3b3b3] hover:text-white transition-colors"
                          title="Opsi Lainnya"
                        >
                          <MoreHorizontal className="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
