import React, { useState } from 'react';
import { 
  Play, 
  Pause, 
  Heart, 
  ListPlus,
  Sparkles,
  MoreHorizontal,
  RotateCw
} from 'lucide-react';
import { DEFAULT_ARTWORK } from '../services/musicApi';

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
  onTogglePlayPause,
  onToggleLike,
  onOpenLyrics,
  onOpenImportModal,
  onSelectPlaylist,
  onTrackContextMenu,
  onPlaylistContextMenu,
}) {
  const [activeTab, setActiveTab] = useState('Semua'); // 'Semua' | 'Musik' | 'Podcast'

  // Dynamic quick cards (from user's taste profile if available, else trending)
  const quickCards = personalizedFeed?.quickCards?.length > 0 
    ? personalizedFeed.quickCards 
    : trendingTracks.slice(0, 6);

  // Dynamic sections from personalizedFeed
  const sections = personalizedFeed?.sections?.length > 0 
    ? personalizedFeed.sections 
    : [
        {
          id: 'default-trending',
          title: 'Lagu Terpopuler Saat Ini',
          subtitle: 'Musik yang sedang viral dan menduduki puncak tangga lagu',
          badge: 'Trending',
          tracks: trendingTracks.slice(0, 14),
        }
      ];

  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Selamat Pagi' : hour < 18 ? 'Selamat Siang' : 'Selamat Malam';

  return (
    <div className="flex-1 overflow-y-auto select-none bg-[#121212] text-white">
      {/* Top Filter Pills matching Spotify */}
      <div className="sticky top-0 z-20 px-4 sm:px-8 py-3 bg-[#121212]/95 backdrop-blur-md flex items-center justify-between transition-colors border-b border-white/[0.04]">
        {/* Filter Pills */}
        <div className="flex items-center gap-2">
          {['Semua', 'Musik', 'Podcast'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-3.5 py-1.5 rounded-full text-xs font-bold transition-all ${
                activeTab === tab
                  ? 'bg-white text-black'
                  : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Right Action */}
        <div className="flex items-center gap-2">
          <button
            onClick={onOpenImportModal}
            className="px-3.5 py-1.5 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black font-bold text-xs flex items-center gap-1.5 shadow-md shadow-[#00a3ff]/20 transition-all hover:scale-105 active:scale-95"
          >
            <ListPlus className="w-3.5 h-3.5 stroke-[2.5]" />
            <span>Import</span>
          </button>
        </div>
      </div>

      <div className="px-4 sm:px-8 pb-32 md:pb-16 space-y-8 pt-4">
        {/* Top 6 Quick Cards */}
        <div className="space-y-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h1 className="text-2xl sm:text-3xl font-black tracking-tight text-white">{greeting}</h1>
              {personalizedFeed?.isPersonalized && (
                <p className="text-xs text-[#b3b3b3] mt-1 flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5 text-[#00a3ff]" />
                  <span>Dipersonalisasi berdasarkan lagu & artis yang sering kamu putar</span>
                </p>
              )}
            </div>

            {onRefreshFeed && (
              <button
                onClick={onRefreshFeed}
                disabled={isLoadingFeed}
                className="px-3 py-1.5 rounded-full bg-white/5 hover:bg-white/10 text-xs font-semibold text-[#b3b3b3] hover:text-white flex items-center gap-1.5 transition-all border border-white/5 disabled:opacity-50"
                title="Segarkan Rekomendasi Beranda"
              >
                <RotateCw className={`w-3.5 h-3.5 ${isLoadingFeed ? 'animate-spin text-[#00a3ff]' : ''}`} />
                <span className="hidden sm:inline">Segarkan</span>
              </button>
            )}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {quickCards.map((t) => {
              const isCurrent = currentTrack?.id === t.id;
              return (
                <div
                  key={t.id}
                  onClick={() => {
                    if (isCurrent) {
                      onTogglePlayPause();
                    } else {
                      onPlayTrack(t, quickCards);
                    }
                  }}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    onTrackContextMenu?.(e, t);
                  }}
                  className="group relative flex items-center bg-white/[0.07] hover:bg-white/[0.12] rounded-md overflow-hidden cursor-pointer transition-colors duration-200 shadow-sm"
                >
                  <img
                    src={t.artwork || DEFAULT_ARTWORK}
                    alt={t.title}
                    onError={(e) => {
                      e.currentTarget.onerror = null;
                      e.currentTarget.src = DEFAULT_ARTWORK;
                    }}
                    className="w-14 h-14 sm:w-16 sm:h-16 object-cover flex-shrink-0 shadow-md"
                  />
                  <div className="flex-1 min-w-0 px-3 sm:px-4">
                    <h4 className="font-bold text-xs sm:text-sm truncate text-white tracking-tight">{t.title}</h4>
                    <p className="text-[11px] sm:text-xs text-[#b3b3b3] truncate mt-0.5">{t.artist}</p>
                  </div>

                  {/* Floating Electric Azure Play Button */}
                  <div
                    className={`mr-3 sm:mr-4 w-10 h-10 sm:w-11 sm:h-11 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-xl transition-all duration-200 hover:scale-105 active:scale-95 flex-shrink-0 ${
                      isCurrent
                        ? 'opacity-100'
                        : 'opacity-0 translate-y-0.5 group-hover:opacity-100 group-hover:translate-y-0'
                    }`}
                  >
                    {isCurrent && isPlaying ? (
                      <Pause className="w-5 h-5 fill-black" />
                    ) : (
                      <Play className="w-5 h-5 fill-black ml-0.5" />
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* SECTION: Playlist Kamu (Matching Spotify Desktop Library) */}
        {playlists.length > 0 && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-xl sm:text-2xl font-black tracking-tight text-white hover:underline cursor-pointer">
                Playlist kamu
              </h2>
              <span className="text-xs font-bold text-[#b3b3b3] hover:underline cursor-pointer">
                Tampilkan semua
              </span>
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

                    <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 hover:scale-105 active:scale-95 transition-all duration-300">
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

        {/* Promo Import Spotify Card */}
        <div className="p-5 sm:p-6 rounded-xl bg-gradient-to-r from-[#0d223f] via-[#161616] to-[#181818] border border-[#00a3ff]/20 flex flex-col sm:flex-row items-center justify-between gap-4 shadow-lg">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-xl bg-[#00a3ff]/20 flex items-center justify-center flex-shrink-0 border border-[#00a3ff]/30">
              <Sparkles className="w-6 h-6 text-[#00a3ff]" />
            </div>
            <div>
              <h3 className="text-white font-bold text-base tracking-tight">Punya Playlist di Spotify?</h3>
              <p className="text-[#b3b3b3] text-xs sm:text-sm mt-0.5">
                Impor langsung link playlist publik. Klik kanan lagu apa saja untuk menambah ke playlist favoritmu!
              </p>
            </div>
          </div>

          <button
            onClick={onOpenImportModal}
            className="w-full sm:w-auto px-5 py-2.5 rounded-full bg-white hover:bg-neutral-200 text-black font-bold text-xs flex items-center justify-center gap-2 flex-shrink-0 shadow-lg active:scale-95 transition-all"
          >
            <ListPlus className="w-4 h-4 stroke-[2.5]" />
            <span>Impor Playlist Sekarang</span>
          </button>
        </div>

        {/* Dynamic Personalized Sections */}
        {sections.map((section) => (
          <div key={section.id} className="space-y-4">
            <div className="flex items-end justify-between">
              <div>
                <div className="flex items-center gap-2.5">
                  <h2 className="text-xl sm:text-2xl font-black tracking-tight text-white hover:underline cursor-pointer">
                    {section.title}
                  </h2>
                  {section.badge && (
                    <span className="hidden sm:inline-block px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-[#00a3ff]/15 text-[#00a3ff] border border-[#00a3ff]/30">
                      {section.badge}
                    </span>
                  )}
                </div>
                {section.subtitle && (
                  <p className="text-xs text-[#b3b3b3] mt-0.5">{section.subtitle}</p>
                )}
              </div>
              <span className="text-xs font-bold text-[#b3b3b3] hover:underline cursor-pointer flex-shrink-0">
                Tampilkan Semua
              </span>
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
                    {/* Square Artwork */}
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

                      {/* Floating Azure Play Button */}
                      <div
                        className={`absolute right-2 bottom-2 w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black flex items-center justify-center shadow-2xl transition-all duration-300 hover:scale-105 active:scale-95 ${
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

                    {/* Title & Artist */}
                    <div className="min-w-0">
                      <h4 className="font-bold text-sm sm:text-base truncate text-white tracking-tight leading-snug">
                        {t.title}
                      </h4>
                      <p className="font-normal text-xs sm:text-sm text-[#b3b3b3] line-clamp-2 mt-1 leading-snug">
                        {t.artist}
                      </p>
                    </div>

                    {/* Actions Bar */}
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
                            isLiked ? 'text-[#00a3ff]' : 'text-[#b3b3b3] hover:text-white'
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
