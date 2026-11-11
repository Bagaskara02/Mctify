import React, { useState, useEffect } from 'react';
import {
  Play,
  Pause,
  Heart,
  Loader2,
  MoreHorizontal,
  Sparkles,
  X,
  Mic2,
  Disc3,
  Clock,
} from 'lucide-react';
import { musicApi, DEFAULT_ARTWORK } from '../services/musicApi';
import { storageService } from '../services/storageService';

export default function SearchView({
  searchQuery = '',
  setSearchQuery,
  currentTrack,
  isPlaying,
  likedTrackIds = new Set(),
  playlists = [],
  onPlayTrack,
  onPlayTrackFromSearch,
  onTogglePlayPause,
  onToggleLike,
  onOpenLyrics,
  onOpenArtist,
  onSelectPlaylist,
  onAddTrackToPlaylist,
  onTrackContextMenu,
  onOpenImportYouTube,
}) {
  const [activeTab, setActiveTab] = useState('Semua'); // 'Semua' | 'Lagu' | 'Artis' | 'Album' | 'Playlist' | 'Cocok Lirik'
  const [songs, setSongs] = useState([]);
  const [artists, setArtists] = useState([]);
  const [recentSearches, setRecentSearches] = useState(() => storageService.getRecentSearches());
  const [isLoading, setIsLoading] = useState(false);

  const lyricPrompts = [
    'if you want me take a chance',
    'hati-hati di jalan tulus',
    'ooh i am blinded by the lights',
    'television so far so good',
  ];

  const browseCategories = [
    {
      name: 'Pop Hits',
      query: 'Pop Hits Terbaru 2025',
      bg: '#E13300',
      image: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Indo Terbaik',
      query: 'Tulus Bernadya Mahalini',
      bg: '#006450',
      image: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'K-Pop ON!',
      query: 'K-Pop Hits NewJeans BTS',
      bg: '#8D67AB',
      image: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Hip-Hop',
      query: 'Hip Hop Rap Kendrick Lamar Drake',
      bg: '#BA5D07',
      image: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Dibuat Untukmu',
      query: 'Rex Orange County Daniel Caesar NIKI',
      bg: '#1E3264',
      image: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Chill & Lofi',
      query: 'Chill Lofi Beats Acoustic',
      bg: '#27856A',
      image: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'R&B & Soul',
      query: 'R&B Soul Frank Ocean SZA',
      bg: '#DC148C',
      image: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Rock & Alt',
      query: 'Rock Coldplay Arctic Monkeys',
      bg: '#E91429',
      image: 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Galau & Senja',
      query: 'Lagu Galau Akustik Indonesia',
      bg: '#477D95',
      image: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Dance & EDM',
      query: 'Electronic Dance Calvin Harris',
      bg: '#0077C2',
      image: 'https://images.unsplash.com/photo-1571266028243-d220c6a22db2?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Rilis Terbaru',
      query: 'New Music Friday Hits',
      bg: '#7D4B32',
      image: 'https://images.unsplash.com/photo-1487180144351-b8472da7d491?auto=format&fit=crop&q=80&w=240',
    },
    {
      name: 'Cari Lewat Lirik',
      query: 'take a chance with me niki',
      bg: '#503750',
      image: 'https://images.unsplash.com/photo-1511379938547-c1f69419868d?auto=format&fit=crop&q=80&w=240',
      forceLyrics: true,
    },
  ];

  // Perform multi-search across tracks, artists, and lyrics
  useEffect(() => {
    const trimmed = (searchQuery || '').trim();
    if (!trimmed) {
      setSongs([]);
      setArtists([]);
      setIsLoading(false);
      setRecentSearches(storageService.getRecentSearches());
      return;
    }

    setIsLoading(true);
    const timeout = setTimeout(async () => {
      try {
        if (activeTab === 'Cocok Lirik') {
          const lyricSongs = await musicApi.searchTracksByLyrics(trimmed);
          setSongs(lyricSongs || []);
          const artistData = await musicApi.searchAll(trimmed).catch(() => ({ artists: [] }));
          setArtists(artistData.artists || []);
        } else {
          const data = await musicApi.searchAll(trimmed);
          const rawSongs = data.songs || [];
          if (rawSongs.length === 0 && trimmed.split(' ').length >= 3) {
            const lyricSongs = await musicApi.searchTracksByLyrics(trimmed);
            setSongs(lyricSongs || []);
          } else {
            setSongs(rawSongs);
          }
          setArtists(data.artists || []);
        }
      } catch (err) {
        console.warn('Search failed:', err);
      } finally {
        setIsLoading(false);
      }
    }, 260);

    return () => clearTimeout(timeout);
  }, [searchQuery, activeTab]);

  const recordTrackHistory = (track) => {
    const updated = storageService.addRecentSearch({
      query: track.title,
      title: track.title,
      subtitle: `Lagu • ${track.artist}`,
      artwork: track.artwork || DEFAULT_ARTWORK,
      type: 'track',
    });
    setRecentSearches(updated);
  };

  const recordArtistHistory = (artist) => {
    const updated = storageService.addRecentSearch({
      query: artist.name,
      title: artist.name,
      subtitle: 'Artis',
      artwork: artist.artwork || DEFAULT_ARTWORK,
      type: 'artist',
    });
    setRecentSearches(updated);
  };

  const triggerQuickQuery = (q, forceLyrics = false) => {
    setSearchQuery(q);
    if (forceLyrics) setActiveTab('Cocok Lirik');
    const updated = storageService.addRecentSearch({
      query: q,
      title: q,
      subtitle: forceLyrics ? 'Cari Lirik' : 'Pencarian',
    });
    setRecentSearches(updated);
  };

  // Group distinct albums from tracks for Spotify Album grid & tab
  const albumMap = new Map();
  for (const t of songs) {
    const albTitle =
      t.album && !String(t.album).startsWith('Lirik:') ? String(t.album).trim() : t.title;
    const key = `${albTitle.toLowerCase()}__${(t.artist || '').toLowerCase()}`;
    if (!albumMap.has(key)) {
      albumMap.set(key, {
        id: `alb-${key}`,
        title: albTitle,
        artist: t.artist,
        artwork: t.artwork || DEFAULT_ARTWORK,
        tracks: [t],
      });
    } else {
      albumMap.get(key).tracks.push(t);
    }
  }
  const albums = Array.from(albumMap.values());

  const cleanQ = (searchQuery || '').trim().toLowerCase();
  const topArtist = artists[0];
  const topSong = songs[0];
  const promoteArtistTopResult =
    topArtist &&
    cleanQ &&
    (topArtist.name.toLowerCase() === cleanQ ||
      (topArtist.name.toLowerCase().includes(cleanQ) && cleanQ.split(' ').length <= 2));

  const matchingPlaylists = playlists.filter(
    (p) => !cleanQ || p.name.toLowerCase().includes(cleanQ)
  );

  const formatDuration = (sec) => {
    const mins = Math.floor(sec / 60);
    const secs = Math.floor(sec % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  return (
    <div className="flex-1 overflow-y-auto p-4 sm:px-8 py-5 space-y-6 select-none bg-[#121212] text-white pb-32 md:pb-16">
      {/* Filter Tabs Row (Spotify Desktop Search Spec) */}
      <div className="flex items-center justify-between gap-2 overflow-x-auto pb-1 no-scrollbar">
        <div className="flex items-center gap-2">
          {['Semua', 'Lagu', 'Artis', 'Album', 'Playlist', 'Cocok Lirik'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-3.5 py-1.5 rounded-full text-xs font-bold transition-all flex-shrink-0 flex items-center gap-1.5 ${
                activeTab === tab
                  ? 'bg-white text-black'
                  : 'bg-[#242424] hover:bg-[#2e2e2e] text-white'
              }`}
            >
              {tab === 'Cocok Lirik' && <Mic2 className="w-3.5 h-3.5 text-[#3B82F6]" />}
              <span>{tab}</span>
            </button>
          ))}
        </div>

        {onOpenImportYouTube && (
          <button
            onClick={onOpenImportYouTube}
            className="px-3.5 py-1.5 rounded-full bg-[#ff0000]/15 hover:bg-[#ff0000]/25 text-[#ff4e4e] text-xs font-bold transition-all flex-shrink-0 border border-[#ff0000]/30 flex items-center gap-1.5"
          >
            <span>Import YouTube</span>
          </button>
        )}
      </div>

      {/* Loading Shimmer Skeleton */}
      {isLoading && (
        <div className="space-y-6 pt-2">
          <div className="flex items-center gap-2.5 text-xs text-neutral-400">
            <Loader2 className="w-4 h-4 animate-spin text-[#3B82F6]" />
            <span>Mencari "{searchQuery}" di katalog & indeks lirik...</span>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            <div className="lg:col-span-5 space-y-3">
              <div className="h-6 w-32 skeleton-box" />
              <div className="h-56 skeleton-box" />
            </div>
            <div className="lg:col-span-7 space-y-3">
              <div className="h-6 w-24 skeleton-box" />
              <div className="space-y-2.5">
                {[...Array(4)].map((_, i) => (
                  <div key={i} className="h-14 skeleton-box" />
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* EMPTY SEARCH QUERY STATE: Recent Searches + Lyric Prompts + Spotify Browse All */}
      {!searchQuery.trim() && !isLoading && (
        <div className="space-y-8 pt-1">
          {/* 1. Pencarian Terkini (Removable Spotify History Cards) */}
          {recentSearches.length > 0 && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-xl sm:text-2xl font-black text-white tracking-tight">
                  Pencarian terkini
                </h2>
                <button
                  onClick={() => setRecentSearches(storageService.clearRecentSearches())}
                  className="text-xs font-bold text-[#b3b3b3] hover:text-white"
                >
                  Hapus semua
                </button>
              </div>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
                {recentSearches.slice(0, 6).map((item, idx) => (
                  <div
                    key={`${item.query}-${idx}`}
                    onClick={() => triggerQuickQuery(item.query)}
                    className="group relative p-3.5 rounded-lg bg-[#181818] hover:bg-[#282828] transition-colors cursor-pointer"
                  >
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        setRecentSearches(
                          storageService.removeRecentSearch(item.query, item.type)
                        );
                      }}
                      className="absolute top-2 right-2 w-7 h-7 rounded-full bg-black/70 hover:bg-black text-white/80 hover:text-white flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity z-10"
                      title="Hapus dari riwayat"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>

                    <div
                      className={`aspect-square overflow-hidden mb-3 bg-[#242424] shadow-md ${
                        item.type === 'artist' ? 'rounded-full' : 'rounded-md'
                      }`}
                    >
                      <img
                        src={item.artwork || DEFAULT_ARTWORK}
                        alt={item.title}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className="w-full h-full object-cover"
                      />
                    </div>
                    <h4 className="font-bold text-sm text-white truncate">{item.title}</h4>
                    <p className="text-xs text-[#b3b3b3] truncate mt-0.5">
                      {item.subtitle || 'Pencarian'}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 2. Coba Cari Penggalan Lirik */}
          <div className="space-y-3">
            <p className="text-xs font-bold uppercase tracking-wider text-[#b3b3b3] flex items-center gap-1.5">
              <Mic2 className="w-3.5 h-3.5 text-[#3B82F6]" />
              <span>Lupa judul? Ketik penggalan lirik lagu</span>
            </p>
            <div className="flex flex-wrap gap-2">
              {lyricPrompts.map((p) => (
                <button
                  key={p}
                  onClick={() => triggerQuickQuery(p, true)}
                  className="px-3.5 py-1.5 rounded-full bg-[#1a2232] hover:bg-[#22304a] text-xs font-semibold text-white border border-[#3B82F6]/30 transition-all"
                >
                  🎙️ "{p}"
                </button>
              ))}
            </div>
          </div>

          {/* 3. Jelajahi Semua (12 Vibrant Genre Cards with 25deg Angled Covers) */}
          <div className="space-y-4">
            <h2 className="text-xl sm:text-2xl font-black text-white tracking-tight">
              Jelajahi semua
            </h2>

            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
              {browseCategories.map((cat) => (
                <div
                  key={cat.name}
                  onClick={() => triggerQuickQuery(cat.query, Boolean(cat.forceLyrics))}
                  style={{ backgroundColor: cat.bg }}
                  className="relative h-28 sm:h-36 rounded-lg p-4 overflow-hidden cursor-pointer shadow-lg hover:brightness-110 transition-all group"
                >
                  <h3 className="font-black text-base sm:text-xl text-white tracking-tight max-w-[68%] leading-tight">
                    {cat.name}
                  </h3>
                  <img
                    src={cat.image}
                    alt={cat.name}
                    className="w-20 h-20 sm:w-24 sm:h-24 rounded-md object-cover absolute -right-3 -bottom-2 rotate-[25deg] shadow-2xl group-hover:scale-105 transition-transform duration-300 pointer-events-none"
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* SEARCH RESULTS DISPLAY */}
      {searchQuery.trim() && !isLoading && (
        <>
          {/* No matches state */}
          {songs.length === 0 && artists.length === 0 && (
            <div className="py-16 text-center space-y-3">
              <p className="text-lg font-bold text-white">
                Tidak ada hasil ditemukan untuk "{searchQuery}"
              </p>
              <p className="text-sm text-[#b3b3b3]">
                Coba periksa ejaanmu, gunakan kata kunci lain, atau tempel tautan YouTube.
              </p>
            </div>
          )}

          {/* TAB: SEMUA (Spotify Authentic Top Result + Songs + Artists + Albums) */}
          {activeTab === 'Semua' && (songs.length > 0 || artists.length > 0) && (
            <div className="space-y-8">
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                {/* Left 5 Cols: Top Result Hero Card (Artist OR Track) */}
                {(topSong || topArtist) && (
                  <div className="lg:col-span-5 space-y-3">
                    <h2 className="text-xl font-black text-white tracking-tight">Hasil Teratas</h2>
                    {promoteArtistTopResult ? (
                      <div
                        onClick={() => {
                          recordArtistHistory(topArtist);
                          onOpenArtist?.(topArtist);
                        }}
                        className="group p-5 rounded-lg bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer relative flex flex-col justify-between h-56 shadow-md"
                      >
                        <img
                          src={topArtist.artwork || DEFAULT_ARTWORK}
                          alt={topArtist.name}
                          onError={(e) => {
                            e.currentTarget.onerror = null;
                            e.currentTarget.src = DEFAULT_ARTWORK;
                          }}
                          className="w-24 h-24 rounded-full object-cover shadow-xl"
                        />
                        <div className="mt-4">
                          <h3 className="text-2xl sm:text-3xl font-black text-white tracking-tight truncate">
                            {topArtist.name}
                          </h3>
                          <span className="inline-block mt-1.5 px-2.5 py-0.5 rounded-full bg-white/10 text-white text-xs font-bold">
                            Artis
                          </span>
                        </div>
                        <div className="absolute right-5 bottom-5 w-12 h-12 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-200">
                          <Play className="w-5 h-5 fill-black ml-0.5" />
                        </div>
                      </div>
                    ) : (
                      topSong && (
                        <div
                          onClick={() => {
                            recordTrackHistory(topSong);
                            if (currentTrack?.id === topSong.id) {
                              onTogglePlayPause();
                            } else if (onPlayTrackFromSearch) {
                              onPlayTrackFromSearch(topSong);
                            } else {
                              onPlayTrack(topSong, [topSong]);
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
                            <p className="text-xs text-[#b3b3b3] mt-1 flex items-center gap-1.5 flex-wrap">
                              <span
                                className="font-semibold text-white hover:underline cursor-pointer"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onOpenArtist?.({ name: topSong.artist, artwork: topSong.artwork });
                                }}
                              >
                                {topSong.artist}
                              </span>
                              <span>•</span>
                              <span className="px-2 py-0.5 rounded-full bg-white/10 text-white font-bold text-[10px]">
                                Lagu
                              </span>
                              {topSong.isLyricMatch && (
                                <span className="px-2 py-0.5 rounded-full bg-[#3B82F6]/20 text-[#60A5FA] border border-[#3B82F6]/30 text-[10px] font-bold flex items-center gap-1">
                                  <Sparkles className="w-2.5 h-2.5" />
                                  Cocok Lirik
                                </span>
                              )}
                            </p>
                          </div>

                          <div
                            className={`absolute right-5 bottom-5 w-12 h-12 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl transition-all duration-200 hover:scale-105 active:scale-95 ${
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
                      )
                    )}
                  </div>
                )}

                {/* Right 7 Cols: Top 4 Songs */}
                <div className={`${topSong || topArtist ? 'lg:col-span-7' : 'lg:col-span-12'} space-y-3`}>
                  <div className="flex items-center justify-between">
                    <h2 className="text-xl font-black text-white tracking-tight">Lagu</h2>
                    {songs.length > 4 && (
                      <button
                        onClick={() => setActiveTab('Lagu')}
                        className="text-xs font-bold text-[#b3b3b3] hover:text-white"
                      >
                        Lihat semua
                      </button>
                    )}
                  </div>
                  <div className="space-y-1">
                    {songs.slice(0, 4).map((t) => {
                      const isCurrent = currentTrack?.id === t.id;
                      const isLiked = likedTrackIds.has(t.id);

                      return (
                        <div
                          key={t.id}
                          onClick={() => {
                            recordTrackHistory(t);
                            if (isCurrent) {
                              onTogglePlayPause();
                            } else if (onPlayTrackFromSearch) {
                              onPlayTrackFromSearch(t);
                            } else {
                              onPlayTrack(t, [t]);
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
                              <div className="absolute inset-0 bg-black/45 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity">
                                <Play className="w-4 h-4 fill-white text-white ml-0.5" />
                              </div>
                            </div>

                            <div className="min-w-0 flex-1">
                              <p
                                className={`font-bold text-sm truncate tracking-tight ${
                                  isCurrent ? 'text-[#3B82F6]' : 'text-white'
                                }`}
                              >
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
                                isLiked ? 'text-[#3B82F6]' : 'text-[#b3b3b3] hover:text-white'
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

              {/* Artis Carousel */}
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
                        onClick={() => {
                          recordArtistHistory(art);
                          onOpenArtist?.(art);
                        }}
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
                          <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300">
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

              {/* Album Carousel */}
              {albums.length > 0 && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <h2 className="text-xl font-black text-white tracking-tight">Album & Single</h2>
                    <span
                      onClick={() => setActiveTab('Album')}
                      className="text-xs font-bold text-[#b3b3b3] hover:underline cursor-pointer"
                    >
                      Tampilkan semua
                    </span>
                  </div>

                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                    {albums.slice(0, 6).map((alb) => (
                      <div
                        key={alb.id}
                        onClick={() => onPlayTrack(alb.tracks[0], alb.tracks)}
                        className="group p-3 sm:p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors cursor-pointer flex flex-col justify-between"
                      >
                        <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                          <img
                            src={alb.artwork}
                            alt={alb.title}
                            onError={(e) => {
                              e.currentTarget.onerror = null;
                              e.currentTarget.src = DEFAULT_ARTWORK;
                            }}
                            className="w-full h-full object-cover"
                          />
                          <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#3B82F6] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300">
                            <Play className="w-4 h-4 fill-black ml-0.5" />
                          </div>
                        </div>
                        <div>
                          <h4 className="font-bold text-sm truncate text-white">{alb.title}</h4>
                          <p className="text-xs text-[#b3b3b3] truncate mt-1">{alb.artist}</p>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* TAB: LAGU / COCOK LIRIK */}
          {(activeTab === 'Lagu' || activeTab === 'Cocok Lirik') && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <h2 className="text-xl font-black text-white tracking-tight">
                  {activeTab === 'Cocok Lirik'
                    ? `Hasil Pencarian Lirik (${songs.length})`
                    : `Semua Lagu (${songs.length})`}
                </h2>
                <span className="text-xs text-[#b3b3b3] flex items-center gap-1">
                  <Clock className="w-3.5 h-3.5" /> Durasi
                </span>
              </div>

              <div className="space-y-1">
                {songs.map((t, index) => {
                  const isCurrent = currentTrack?.id === t.id;
                  const isLiked = likedTrackIds.has(t.id);

                  return (
                    <div
                      key={t.id || index}
                      onClick={() => {
                        recordTrackHistory(t);
                        if (isCurrent) {
                          onTogglePlayPause();
                        } else if (onPlayTrackFromSearch) {
                          onPlayTrackFromSearch(t);
                        } else {
                          onPlayTrack(t, [t]);
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
                          <div className="flex items-center gap-2">
                            <p
                              className={`font-bold text-sm truncate tracking-tight ${
                                isCurrent ? 'text-[#3B82F6]' : 'text-white'
                              }`}
                            >
                              {t.title}
                            </p>
                            {t.isLyricMatch && (
                              <span className="px-1.5 py-0.5 rounded bg-[#3B82F6]/20 text-[#60A5FA] text-[10px] font-bold flex-shrink-0">
                                Lirik
                              </span>
                            )}
                          </div>
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
                            isLiked ? 'text-[#3B82F6]' : 'text-[#b3b3b3] hover:text-white'
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

          {/* TAB: ARTIS */}
          {activeTab === 'Artis' && (
            <div className="space-y-4">
              <h2 className="text-xl font-black text-white tracking-tight">
                Artis ({artists.length})
              </h2>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                {artists.map((art) => (
                  <div
                    key={art.id}
                    onClick={() => {
                      recordArtistHistory(art);
                      onOpenArtist?.(art);
                    }}
                    className="group p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors duration-200 cursor-pointer flex flex-col items-center text-center"
                  >
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

                      <div className="absolute right-2 bottom-2 w-11 h-11 rounded-full bg-[#3B82F6] hover:bg-[#2563EB] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 hover:scale-105 active:scale-95 transition-all duration-300">
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

          {/* TAB: ALBUM */}
          {activeTab === 'Album' && (
            <div className="space-y-4">
              <h2 className="text-xl font-black text-white tracking-tight">
                Album & Single ({albums.length})
              </h2>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                {albums.map((alb) => (
                  <div
                    key={alb.id}
                    onClick={() => onPlayTrack(alb.tracks[0], alb.tracks)}
                    className="group p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors cursor-pointer flex flex-col justify-between"
                  >
                    <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                      <img
                        src={alb.artwork}
                        alt={alb.title}
                        onError={(e) => {
                          e.currentTarget.onerror = null;
                          e.currentTarget.src = DEFAULT_ARTWORK;
                        }}
                        className="w-full h-full object-cover"
                      />
                      <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#3B82F6] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300">
                        <Play className="w-4 h-4 fill-black ml-0.5" />
                      </div>
                    </div>
                    <div>
                      <h4 className="font-bold text-sm sm:text-base text-white truncate">
                        {alb.title}
                      </h4>
                      <p className="text-xs text-[#b3b3b3] truncate mt-1 flex items-center gap-1">
                        <Disc3 className="w-3 h-3 flex-shrink-0" />
                        <span>{alb.artist}</span>
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB: PLAYLIST */}
          {activeTab === 'Playlist' && (
            <div className="space-y-4">
              <h2 className="text-xl font-black text-white tracking-tight">
                Playlist ({matchingPlaylists.length + (songs.length > 0 ? 1 : 0)})
              </h2>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                {songs.length > 0 && (
                  <div
                    onClick={() => onPlayTrack(songs[0], songs)}
                    className="group p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors cursor-pointer flex flex-col justify-between"
                  >
                    <div className="relative aspect-square rounded-md overflow-hidden mb-3 bg-[#282828] shadow-md">
                      <img
                        src={songs[0].artwork || DEFAULT_ARTWORK}
                        alt="Mix"
                        className="w-full h-full object-cover"
                      />
                      <div className="absolute right-2 bottom-2 w-10 h-10 rounded-full bg-[#3B82F6] text-black flex items-center justify-center shadow-2xl opacity-0 translate-y-2 group-hover:opacity-100 group-hover:translate-y-0 transition-all duration-300">
                        <Play className="w-4 h-4 fill-black ml-0.5" />
                      </div>
                    </div>
                    <div>
                      <h4 className="font-bold text-sm sm:text-base truncate text-white">
                        Mix McTify: {searchQuery}
                      </h4>
                      <p className="text-xs text-[#b3b3b3] truncate mt-1">{songs.length} lagu</p>
                    </div>
                  </div>
                )}

                {matchingPlaylists.map((pl) => (
                  <div
                    key={pl.id}
                    onClick={() => onSelectPlaylist?.(pl.id)}
                    className="group p-4 rounded-md bg-[#181818] hover:bg-[#282828] transition-colors cursor-pointer flex flex-col justify-between"
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
