import React, { useState, useEffect, useRef } from 'react';
import Sidebar from './components/Sidebar';
import PlayerBar from './components/PlayerBar';
import DiscoverView from './components/DiscoverView';
import SearchView from './components/SearchView';
import PlaylistView from './components/PlaylistView';
import BeautifulLyrics from './components/BeautifulLyrics';
import ImportPlaylistModal from './components/ImportPlaylistModal';
import DownloadAppModal from './components/DownloadAppModal';
import YouTubePlayer from './components/YouTubePlayer';
import MobileBottomNav from './components/MobileBottomNav';
import MobileMiniPlayer from './components/MobileMiniPlayer';
import MobileFullscreenPlayer from './components/MobileFullscreenPlayer';
import QueueDrawer from './components/QueueDrawer';
import RightSidebarNowPlaying from './components/RightSidebarNowPlaying';
import ContextMenu from './components/ContextMenu';
import TopNavBar from './components/TopNavBar';
import ArtistView from './components/ArtistView';
import { storageService } from './services/storageService';
import { musicApi } from './services/musicApi';
import { lyricsService } from './services/lyricsService';
import { Sparkles } from 'lucide-react';

export default function App() {
  // Navigation & View State
  const [currentView, setCurrentView] = useState('discover');
  const [selectedPlaylistId, setSelectedPlaylistId] = useState(null);
  const [selectedArtist, setSelectedArtist] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  
  // Library State
  const [playlists, setPlaylists] = useState([]);
  const [likedTracks, setLikedTracks] = useState([]);
  const [historyTracks, setHistoryTracks] = useState([]);
  const [trendingTracks, setTrendingTracks] = useState([]);

  // Audio Playback State - NO AUTOPLAY ON INITIAL LOAD
  const [currentTrack, setCurrentTrack] = useState(null);
  const [queue, setQueue] = useState([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.85);
  const [isMuted, setIsMuted] = useState(false);
  const [isShuffle, setIsShuffle] = useState(false);
  const [isRepeat, setIsRepeat] = useState(false);
  const [seekTime, setSeekTime] = useState(null);

  // Modals, Drawers, & Context Menu State
  const [isLyricsOpen, setIsLyricsOpen] = useState(false);
  const [isQueueOpen, setIsQueueOpen] = useState(false);
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(false);
  const [isMobileFullscreenOpen, setIsMobileFullscreenOpen] = useState(false);
  const [isImportModalOpen, setIsImportModalOpen] = useState(false);
  const [isDownloadModalOpen, setIsDownloadModalOpen] = useState(false);
  const [contextMenuData, setContextMenuData] = useState(null); // { type, track, playlist, x, y }
  const [lyricsData, setLyricsData] = useState(null);
  const [isLoadingLyrics, setIsLoadingLyrics] = useState(false);

  // Dynamic Personalized Feed State
  const [personalizedFeed, setPersonalizedFeed] = useState(null);
  const [isLoadingFeed, setIsLoadingFeed] = useState(false);

  // Smart Autoplay Toast Notification
  const [smartToast, setSmartToast] = useState(null);

  // Audio Element Ref (Fallback for preview if needed)
  const audioRef = useRef(null);

  // Dynamic feed loader based on user playback and taste profile
  const refreshPersonalizedFeed = async () => {
    setIsLoadingFeed(true);
    try {
      const profile = storageService.getTasteProfile();
      const feed = await musicApi.fetchPersonalizedHome(profile);
      setPersonalizedFeed(feed);
      if (feed?.trending && feed.trending.length > 0) {
        setTrendingTracks(feed.trending);
      }
    } catch (e) {
      console.warn('Failed to load personalized feed:', e);
    } finally {
      setIsLoadingFeed(false);
    }
  };

  // Initialize Library & Fetch Personalized Feed on Mount (NO INITIAL SONG PRE-LOADED)
  useEffect(() => {
    const loadedPlaylists = storageService.getPlaylists();
    const loadedLiked = storageService.getLikedTracks();
    const loadedHistory = storageService.getHistory();

    setPlaylists(loadedPlaylists);
    setLikedTracks(loadedLiked);
    setHistoryTracks(loadedHistory);

    // Initial state: currentTrack starts null, right sidebar starts closed
    refreshPersonalizedFeed();
  }, []);

  // Fetch Synchronized Lyrics whenever currentTrack changes
  useEffect(() => {
    if (!currentTrack) {
      setLyricsData(null);
      return;
    }

    let isSubscribed = true;
    setIsLoadingLyrics(true);

    lyricsService.fetchLyrics(currentTrack.artist, currentTrack.title, currentTrack.duration)
      .then(data => {
        if (isSubscribed) {
          setLyricsData(data);
          setIsLoadingLyrics(false);
        }
      })
      .catch(() => {
        if (isSubscribed) {
          setLyricsData(null);
          setIsLoadingLyrics(false);
        }
      });

    return () => {
      isSubscribed = false;
    };
  }, [currentTrack?.title, currentTrack?.artist]);

  // Handle Play Track with Full-Length YouTube Resolution
  const handlePlayTrack = async (track, newQueue = null) => {
    if (!track) return;

    if (newQueue) {
      setQueue(newQueue);
    } else if (!queue.some(t => t.id === track.id)) {
      setQueue([track, ...queue]);
    }

    setCurrentTime(0);
    setSeekTime(0);
    setIsPlaying(true);

    if (track.videoId) {
      setCurrentTrack(track);
      setDuration(track.duration || 210);
    } else {
      setCurrentTrack(track);

      try {
        const yt = await musicApi.resolveYouTubeMatch(track.title, track.artist);
        if (yt && yt.videoId) {
          const fullTrack = {
            ...track,
            videoId: yt.videoId,
            duration: yt.duration || track.duration,
          };
          setCurrentTrack(fullTrack);
          setDuration(yt.duration || track.duration);
        } else if (track.audioUrl && audioRef.current) {
          audioRef.current.src = track.audioUrl;
          audioRef.current.currentTime = 0;
          audioRef.current.play().catch(console.warn);
        }
      } catch {
        if (track.audioUrl && audioRef.current) {
          audioRef.current.src = track.audioUrl;
          audioRef.current.currentTime = 0;
          audioRef.current.play().catch(console.warn);
        }
      }
    }

    storageService.addToHistory(track);
    setHistoryTracks(storageService.getHistory());

    // Dynamically refresh personalized feed in background based on newly played track
    setTimeout(() => {
      const profile = storageService.getTasteProfile();
      musicApi.fetchPersonalizedHome(profile).then((updatedFeed) => {
        setPersonalizedFeed(updatedFeed);
      }).catch(console.warn);
    }, 1200);
  };

  // Toggle Play / Pause
  const handlePlayPause = () => {
    if (!currentTrack) {
      const first = personalizedFeed?.quickCards?.[0] || trendingTracks[0];
      if (first) {
        handlePlayTrack(first, personalizedFeed?.quickCards || trendingTracks);
      }
      return;
    }

    if (isPlaying) {
      setIsPlaying(false);
      if (audioRef.current) audioRef.current.pause();
    } else {
      setIsPlaying(true);
      if (!currentTrack.videoId && currentTrack.audioUrl && audioRef.current) {
        audioRef.current.play().catch(console.warn);
      }
    }
  };

  // Next Track in Queue with SMART AUTOPLAY (Spotify Radio)
  const handleNext = async (isAutoEnded = false) => {
    if (!currentTrack && queue.length === 0) return;

    const currentIndex = queue.findIndex(t => t.id === currentTrack?.id);

    // 1. Shuffle mode: pick random next track in queue
    if (isShuffle && queue.length > 1) {
      let randIndex;
      do {
        randIndex = Math.floor(Math.random() * queue.length);
      } while (randIndex === currentIndex && queue.length > 1);
      handlePlayTrack(queue[randIndex]);
      return;
    }

    // 2. Normal queue playback: there are more tracks left
    if (currentIndex !== -1 && currentIndex < queue.length - 1) {
      handlePlayTrack(queue[currentIndex + 1]);
      return;
    }

    // 3. Queue / Playlist Finished! -> Trigger Smart Autoplay (Spotify Radio)
    if (currentTrack) {
      setSmartToast(`Radio Pintar: Mencari musik serupa dengan ${currentTrack.artist}...`);
      try {
        const smartRecommendations = await musicApi.getSmartRecommendations(currentTrack, queue);
        if (smartRecommendations && smartRecommendations.length > 0) {
          const nextTrack = smartRecommendations[0];
          const newQueue = [...queue, ...smartRecommendations];
          setQueue(newQueue);
          handlePlayTrack(nextTrack, newQueue);
          setSmartToast(`Memutar Radio Pintar: ${nextTrack.title} • ${nextTrack.artist}`);
          setTimeout(() => setSmartToast(null), 4500);
          return;
        }
      } catch (err) {
        console.warn('Smart recommendations error:', err);
      }
    }

    // Fallback: loop to beginning if no smart recommendations found
    if (queue.length > 0) {
      handlePlayTrack(queue[0]);
    }
  };

  // Previous Track
  const handlePrev = () => {
    if (currentTime > 3) {
      handleSeek(0);
      return;
    }
    if (queue.length === 0) return;
    const currentIndex = queue.findIndex(t => t.id === currentTrack?.id);
    let prevIndex = queue.length - 1;

    if (currentIndex > 0) {
      prevIndex = currentIndex - 1;
    }

    handlePlayTrack(queue[prevIndex]);
  };

  // Track ended event
  const handleEnded = () => {
    if (isRepeat) {
      handleSeek(0);
      setIsPlaying(true);
    } else {
      handleNext(true);
    }
  };

  // Seek
  const handleSeek = (newTime) => {
    if (Number.isFinite(newTime)) {
      setCurrentTime(newTime);
      setSeekTime(newTime);
      if (audioRef.current && !currentTrack?.videoId) {
        audioRef.current.currentTime = newTime;
      }
      setTimeout(() => setSeekTime(null), 100);
    }
  };

  // Volume
  const handleVolumeChange = (newVol) => {
    setVolume(newVol);
    setIsMuted(false);
    if (audioRef.current) {
      audioRef.current.volume = newVol;
    }
  };

  const handleToggleMute = () => {
    const nextMute = !isMuted;
    setIsMuted(nextMute);
    if (audioRef.current) {
      audioRef.current.volume = nextMute ? 0 : volume;
    }
  };

  // Like Song
  const handleToggleLike = (track) => {
    const updated = storageService.toggleLikeTrack(track);
    setLikedTracks(updated);

    // Dynamically update recommendations based on liked tracks
    setTimeout(() => {
      const profile = storageService.getTasteProfile();
      musicApi.fetchPersonalizedHome(profile).then((updatedFeed) => {
        setPersonalizedFeed(updatedFeed);
      }).catch(console.warn);
    }, 800);
  };

  // Add Track to Specific Playlist
  const handleAddTrackToPlaylist = (playlistId, track) => {
    const updated = storageService.addTrackToPlaylist(playlistId, track);
    setPlaylists(updated);
    setSmartToast(`Lagu ditambahkan ke playlist!`);
    setTimeout(() => setSmartToast(null), 3000);
  };

  // Create Playlist & Add Track
  const handleCreatePlaylistWithTrack = (track) => {
    const newPl = storageService.addPlaylist({
      name: `Playlist #${playlists.length + 1}`,
      description: 'Dibuat oleh Kamu',
      cover: track?.artwork,
      tracks: track ? [track] : [],
    });
    setPlaylists(storageService.getPlaylists());
    setSelectedPlaylistId(newPl.id);
    setCurrentView('playlist');
    setSmartToast(`Playlist baru dibuat dengan "${track.title}"!`);
    setTimeout(() => setSmartToast(null), 3500);
  };

  // Create New Empty Playlist
  const handleCreatePlaylist = () => {
    const newPl = storageService.addPlaylist({
      name: `Playlist #${playlists.length + 1}`,
      description: 'Dibuat oleh Kamu',
      tracks: [],
    });
    setPlaylists(storageService.getPlaylists());
    setSelectedPlaylistId(newPl.id);
    setCurrentView('playlist');
    setSmartToast(`Playlist "${newPl.name}" berhasil dibuat!`);
    setTimeout(() => setSmartToast(null), 3000);
  };

  // Remove Track from Playlist
  const handleRemoveTrackFromPlaylist = (playlistId, trackId) => {
    const updated = storageService.removeTrackFromPlaylist(playlistId, trackId);
    setPlaylists(updated);
  };

  // Delete Playlist
  const handleDeletePlaylist = (playlistId) => {
    const updated = storageService.deletePlaylist(playlistId);
    setPlaylists(updated);
    if (selectedPlaylistId === playlistId) {
      setSelectedPlaylistId(null);
      setCurrentView('discover');
    }
  };

  // Callback when user imports new playlist from Modal
  const handlePlaylistImported = (newPlaylist) => {
    const saved = storageService.addPlaylist(newPlaylist);
    setPlaylists(storageService.getPlaylists());
    setSelectedPlaylistId(saved.id);
    setCurrentView('playlist');
    
    if (saved.tracks?.length > 0) {
      const first = saved.tracks[0];
      setCurrentTrack(first);
      setQueue(saved.tracks);
      setDuration(first.duration || 210);
    }
  };

  // --- Right-Click Context Menu Handlers ---
  const handleTrackContextMenu = (e, track) => {
    e.preventDefault();
    setContextMenuData({
      type: 'track',
      track,
      x: e.clientX,
      y: e.clientY,
    });
  };

  const handlePlaylistContextMenu = (e, playlist) => {
    e.preventDefault();
    setContextMenuData({
      type: 'playlist',
      playlist,
      x: e.clientX,
      y: e.clientY,
    });
  };

  const handleAddToQueue = (track) => {
    setQueue(prev => [...prev, track]);
    setSmartToast(`Ditambahkan ke antrean: ${track.title}`);
    setTimeout(() => setSmartToast(null), 3000);
  };

  const handleStartRadio = (track) => {
    handlePlayTrack(track);
    setSmartToast(`Memulai Radio Lagu: ${track.title} • ${track.artist}`);
    musicApi.getSmartRecommendations(track, [track]).then(recs => {
      if (recs && recs.length > 0) {
        setQueue([track, ...recs]);
      }
    });
    setTimeout(() => setSmartToast(null), 3500);
  };

  const handleOpenArtist = (artistTarget) => {
    let art = null;
    if (typeof artistTarget === 'string') {
      art = { name: artistTarget, id: null };
    } else if (artistTarget && typeof artistTarget === 'object') {
      art = artistTarget;
    }
    if (art) {
      setSelectedArtist(art);
      setCurrentView('artist');
      setSelectedPlaylistId(null);
    }
  };

  const handleCopyShare = (item) => {
    const shareText = item.title 
      ? `Dengarkan "${item.title}" oleh ${item.artist} di McMusic: ${window.location.origin}`
      : `Playlist "${item.name}" di McMusic: ${window.location.origin}`;
    
    if (navigator.clipboard) {
      navigator.clipboard.writeText(shareText);
    }
    setSmartToast(`Tautan berhasil disalin ke papan klip!`);
    setTimeout(() => setSmartToast(null), 3000);
  };

  const handleShowCredits = (track) => {
    alert(`Kredit Musik:\n\nJudul: ${track.title}\nArtis: ${track.artist}\nAlbum: ${track.album || 'Single'}\nGenre: ${track.genre || 'Pop'}\nSumber Audio: YouTube Music High-Quality Stream\nSumber Lirik: LRCLIB Community Synchronized Database`);
  };

  const likedTrackIds = new Set(likedTracks.map(t => t.id));
  const activePlaylist = playlists.find(p => p.id === selectedPlaylistId);

  return (
    <div className="flex flex-col h-screen w-screen overflow-hidden bg-black text-white select-none">
      {/* Smart Radio Toast Notification */}
      {smartToast && (
        <div className="fixed top-4 left-1/2 -translate-x-1/2 z-50 px-4 py-2 rounded-full bg-[#00a3ff] text-black font-bold text-xs flex items-center gap-2 shadow-2xl animate-in slide-in-from-top duration-300">
          <Sparkles className="w-4 h-4 fill-current stroke-[2.5]" />
          <span>{smartToast}</span>
        </div>
      )}

      {/* Top Header Bar matching Spotify Desktop media_1791347940843.png */}
      <TopNavBar
        currentView={currentView}
        setCurrentView={(view) => {
          setCurrentView(view);
          setSelectedPlaylistId(null);
        }}
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        onOpenDownloadApp={() => setIsDownloadModalOpen(true)}
        onCreatePlaylist={handleCreatePlaylist}
      />

      {/* YouTube Full-Length Audio/Video Player Engine */}
      <YouTubePlayer
        videoId={currentTrack?.videoId}
        isPlaying={isPlaying}
        volume={volume}
        isMuted={isMuted}
        seekTime={seekTime}
        onTimeUpdate={(current, dur) => {
          setCurrentTime(current);
          if (dur && Number.isFinite(dur) && dur > 0) {
            setDuration(dur);
          }
        }}
        onEnded={handleEnded}
        onError={(err) => {
          console.warn('YouTube playback error, attempting preview fallback', err);
          if (currentTrack?.audioUrl && audioRef.current) {
            audioRef.current.src = currentTrack.audioUrl;
            audioRef.current.play().catch(console.warn);
          }
        }}
      />

      {/* Fallback Native Audio Element for Preview */}
      <audio
        ref={audioRef}
        preload="metadata"
        onTimeUpdate={() => {
          if (!currentTrack?.videoId && audioRef.current) {
            setCurrentTime(audioRef.current.currentTime);
          }
        }}
        onLoadedMetadata={() => {
          if (!currentTrack?.videoId && audioRef.current) {
            setDuration(audioRef.current.duration || 30);
          }
        }}
        onEnded={handleEnded}
      />

      {/* Upper Area: Sidebar + Spotify Main View + Right Sidebar Now Playing */}
      <div className="flex flex-1 min-h-0 overflow-hidden">
        {/* Sidebar (Desktop & Tablet only) */}
        <Sidebar
          currentView={currentView}
          setCurrentView={setCurrentView}
          selectedPlaylistId={selectedPlaylistId}
          setSelectedPlaylistId={setSelectedPlaylistId}
          playlists={playlists}
          likedCount={likedTracks.length}
          onOpenImportModal={() => setIsImportModalOpen(true)}
          onCreatePlaylist={handleCreatePlaylist}
          onDeletePlaylist={handleDeletePlaylist}
          onPlaylistContextMenu={handlePlaylistContextMenu}
        />

        {/* Main View Area - Spotify Native Pane */}
        <main className="flex-1 my-0 md:my-2 mr-0 md:mr-2 rounded-none md:rounded-lg bg-[#121212] flex flex-col min-w-0 overflow-hidden relative shadow-sm">
          {currentView === 'discover' && !selectedPlaylistId && (
            <DiscoverView
              trendingTracks={trendingTracks}
              playlists={playlists}
              personalizedFeed={personalizedFeed}
              isLoadingFeed={isLoadingFeed}
              onRefreshFeed={refreshPersonalizedFeed}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onOpenImportModal={() => setIsImportModalOpen(true)}
              onSelectPlaylist={(plId) => {
                setSelectedPlaylistId(plId);
                setCurrentView('playlist');
              }}
              onTrackContextMenu={handleTrackContextMenu}
              onPlaylistContextMenu={handlePlaylistContextMenu}
            />
          )}

          {currentView === 'search' && !selectedPlaylistId && (
            <SearchView
              searchQuery={searchQuery}
              setSearchQuery={setSearchQuery}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              playlists={playlists}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onOpenArtist={handleOpenArtist}
              onAddTrackToPlaylist={handleAddTrackToPlaylist}
              onTrackContextMenu={handleTrackContextMenu}
            />
          )}

          {currentView === 'artist' && selectedArtist && !selectedPlaylistId && (
            <ArtistView
              artist={selectedArtist}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onToggleLike={handleToggleLike}
              onTrackContextMenu={handleTrackContextMenu}
              onBack={() => {
                if (searchQuery) {
                  setCurrentView('search');
                } else {
                  setCurrentView('discover');
                }
              }}
            />
          )}

          {currentView === 'liked' && !selectedPlaylistId && (
            <PlaylistView
              playlist={{
                id: 'pl-liked',
                name: 'Lagu yang Disukai',
                description: 'Kumpulan lagu favoritmu yang disimpan langsung di browser.',
                cover: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=400',
                source: 'local',
                tracks: likedTracks,
              }}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onPlayAll={(tracks) => handlePlayTrack(tracks[0], tracks)}
              onShuffleAll={(tracks) => {
                const shuffled = [...tracks].sort(() => Math.random() - 0.5);
                handlePlayTrack(shuffled[0], shuffled);
              }}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onTrackContextMenu={handleTrackContextMenu}
            />
          )}

          {currentView === 'history' && !selectedPlaylistId && (
            <PlaylistView
              playlist={{
                id: 'pl-history',
                name: 'Baru Saja Diputar',
                description: 'Riwayat lagu yang baru saja kamu dengarkan.',
                cover: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=400',
                source: 'local',
                tracks: historyTracks,
              }}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onPlayAll={(tracks) => handlePlayTrack(tracks[0], tracks)}
              onShuffleAll={(tracks) => {
                const shuffled = [...tracks].sort(() => Math.random() - 0.5);
                handlePlayTrack(shuffled[0], shuffled);
              }}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onTrackContextMenu={handleTrackContextMenu}
            />
          )}

          {currentView === 'playlist' && activePlaylist && (
            <PlaylistView
              playlist={activePlaylist}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onPlayAll={(tracks) => handlePlayTrack(tracks[0], tracks)}
              onShuffleAll={(tracks) => {
                const shuffled = [...tracks].sort(() => Math.random() - 0.5);
                handlePlayTrack(shuffled[0], shuffled);
              }}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onRemoveTrack={handleRemoveTrackFromPlaylist}
              onDeletePlaylist={handleDeletePlaylist}
              onTrackContextMenu={handleTrackContextMenu}
            />
          )}
        </main>

        {/* Right Sidebar: Now Playing & Live Lyrics Preview (Desktop XL) */}
        <RightSidebarNowPlaying
          isOpen={isRightSidebarOpen}
          onClose={() => setIsRightSidebarOpen(false)}
          currentTrack={currentTrack}
          currentTime={currentTime}
          lyricsData={lyricsData}
          isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
          onToggleLike={handleToggleLike}
          onOpenLyrics={() => setIsLyricsOpen(true)}
          onOpenArtist={handleOpenArtist}
          onStartRadio={handleStartRadio}
        />
      </div>

      {/* --- DESKTOP & TABLET PLAYER BAR --- */}
      <div className="hidden md:block">
        <PlayerBar
          currentTrack={currentTrack}
          isPlaying={isPlaying}
          currentTime={currentTime}
          duration={duration}
          volume={volume}
          isMuted={isMuted}
          isShuffle={isShuffle}
          isRepeat={isRepeat}
          isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
          isLyricsOpen={isLyricsOpen}
          isQueueOpen={isQueueOpen}
          isRightSidebarOpen={isRightSidebarOpen}
          onPlayPause={handlePlayPause}
          onPrev={handlePrev}
          onNext={() => handleNext(false)}
          onSeek={handleSeek}
          onVolumeChange={handleVolumeChange}
          onToggleMute={handleToggleMute}
          onToggleShuffle={() => setIsShuffle(!isShuffle)}
          onToggleRepeat={() => setIsRepeat(!isRepeat)}
          onToggleLike={handleToggleLike}
          onToggleLyrics={() => setIsLyricsOpen(!isLyricsOpen)}
          onToggleQueue={() => setIsQueueOpen(!isQueueOpen)}
          onToggleRightSidebar={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
          onTrackContextMenu={handleTrackContextMenu}
        />
      </div>

      {/* --- MOBILE FLOATING MINI-PLAYER --- */}
      <MobileMiniPlayer
        currentTrack={currentTrack}
        isPlaying={isPlaying}
        currentTime={currentTime}
        duration={duration}
        isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
        onPlayPause={handlePlayPause}
        onToggleLike={handleToggleLike}
        onOpenFullscreen={() => setIsMobileFullscreenOpen(true)}
      />

      {/* --- MOBILE BOTTOM NAVIGATION BAR --- */}
      <MobileBottomNav
        currentView={currentView}
        setCurrentView={(view) => {
          setCurrentView(view);
          setSelectedPlaylistId(null);
        }}
        selectedPlaylistId={selectedPlaylistId}
        setSelectedPlaylistId={setSelectedPlaylistId}
        onOpenImportModal={() => setIsImportModalOpen(true)}
      />

      {/* --- MOBILE FULLSCREEN NOW PLAYING MODAL --- */}
      <MobileFullscreenPlayer
        isOpen={isMobileFullscreenOpen}
        onClose={() => setIsMobileFullscreenOpen(false)}
        currentTrack={currentTrack}
        isPlaying={isPlaying}
        currentTime={currentTime}
        duration={duration}
        isShuffle={isShuffle}
        isRepeat={isRepeat}
        isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
        onPlayPause={handlePlayPause}
        onPrev={handlePrev}
        onNext={() => handleNext(false)}
        onSeek={handleSeek}
        onToggleShuffle={() => setIsShuffle(!isShuffle)}
        onToggleRepeat={() => setIsRepeat(!isRepeat)}
        onToggleLike={handleToggleLike}
        onOpenLyrics={() => setIsLyricsOpen(true)}
        onOpenQueue={() => setIsQueueOpen(true)}
      />

      {/* --- QUEUE DRAWER PANEL --- */}
      <QueueDrawer
        isOpen={isQueueOpen}
        onClose={() => setIsQueueOpen(false)}
        currentTrack={currentTrack}
        queue={queue}
        isPlaying={isPlaying}
        onPlayTrack={handlePlayTrack}
        onClearQueue={() => setQueue(currentTrack ? [currentTrack] : [])}
      />

      {/* --- BEAUTIFUL LYRICS OVERLAY --- */}
      {isLyricsOpen && (
        <BeautifulLyrics
          track={currentTrack}
          currentTime={currentTime}
          duration={duration}
          lyricsData={lyricsData}
          isLoadingLyrics={isLoadingLyrics}
          isPlaying={isPlaying}
          onSeek={handleSeek}
          onClose={() => setIsLyricsOpen(false)}
        />
      )}

      {/* --- IMPORT PLAYLIST MODAL --- */}
      <ImportPlaylistModal
        isOpen={isImportModalOpen}
        onClose={() => setIsImportModalOpen(false)}
        onPlaylistImported={handlePlaylistImported}
      />

      {/* --- DOWNLOAD FLUTTER APP MODAL --- */}
      <DownloadAppModal
        isOpen={isDownloadModalOpen}
        onClose={() => setIsDownloadModalOpen(false)}
      />

      {/* --- SPOTIFY CONTEXT MENU (KLIK KANAN PADA MUSIK & PLAYLIST) --- */}
      {contextMenuData && (
        <ContextMenu
          contextData={contextMenuData}
          playlists={playlists}
          isLiked={contextMenuData?.track ? likedTrackIds.has(contextMenuData.track.id) : false}
          onClose={() => setContextMenuData(null)}
          onPlayTrack={handlePlayTrack}
          onAddToQueue={handleAddToQueue}
          onToggleLike={handleToggleLike}
          onAddTrackToPlaylist={handleAddTrackToPlaylist}
          onCreatePlaylistWithTrack={handleCreatePlaylistWithTrack}
          onStartRadio={handleStartRadio}
          onOpenArtist={handleOpenArtist}
          onOpenLyrics={(track) => {
            if (track.id !== currentTrack?.id) handlePlayTrack(track);
            setIsLyricsOpen(true);
          }}
          onShowCredits={handleShowCredits}
          onCopyShare={handleCopyShare}
          onDeletePlaylist={handleDeletePlaylist}
        />
      )}
    </div>
  );
}
