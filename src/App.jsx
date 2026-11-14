import React, { useState, useEffect, useRef } from 'react';
import Sidebar from './components/Sidebar';
import PlayerBar from './components/PlayerBar';
import DiscoverView from './components/DiscoverView';
import SearchView from './components/SearchView';
import PlaylistView from './components/PlaylistView';
import BeautifulLyrics from './components/BeautifulLyrics';
import ImportPlaylistModal from './components/ImportPlaylistModal';
import ImportYouTubeModal from './components/ImportYouTubeModal';
import DownloadAppModal from './components/DownloadAppModal';
import EqualizerModal from './components/EqualizerModal';
import AudioQualityModal from './components/AudioQualityModal';
import SleepTimerModal from './components/SleepTimerModal';
import { webAudioEqualizer } from './services/webAudioEqualizer';
import YouTubePlayer from './components/YouTubePlayer';
import MobileBottomNav from './components/MobileBottomNav';
import MobileMiniPlayer from './components/MobileMiniPlayer';
import MobileFullscreenPlayer from './components/MobileFullscreenPlayer';
import QueueDrawer from './components/QueueDrawer';
import RightSidebarNowPlaying from './components/RightSidebarNowPlaying';
import ContextMenu from './components/ContextMenu';
import TopNavBar from './components/TopNavBar';
import ArtistView from './components/ArtistView';
import CommandPaletteModal from './components/CommandPaletteModal';
import { storageService } from './services/storageService';
import { musicApi, getHighResArtworkUrl } from './services/musicApi';
import { lyricsService } from './services/lyricsService';
import { buildSpotifyShuffleDeck } from './utils/shuffle';
import { parseUrlSyncParams, generateUrlSyncLink, formatPlaybackSeconds } from './utils/urlSync';
import { Sparkles } from 'lucide-react';

export default function App() {
  // Navigation & View State
  const [currentView, setCurrentView] = useState('discover');
  const [selectedPlaylistId, setSelectedPlaylistId] = useState(null);
  const [virtualPlaylist, setVirtualPlaylist] = useState(null);
  const [selectedArtist, setSelectedArtist] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [navHistory, setNavHistory] = useState([{ view: 'discover', plId: null }]);
  const [navIdx, setNavIdx] = useState(0);

  const navigateTo = (view, plId = null) => {
    setCurrentView(view);
    setSelectedPlaylistId(plId);
    setNavHistory((prev) => {
      const sliced = prev.slice(0, navIdx + 1);
      const last = sliced[sliced.length - 1];
      if (last && last.view === view && last.plId === plId) return sliced;
      const next = [...sliced, { view, plId }];
      setNavIdx(next.length - 1);
      return next;
    });
  };

  const handleGoBack = () => {
    if (navIdx > 0) {
      const targetIdx = navIdx - 1;
      const entry = navHistory[targetIdx];
      setNavIdx(targetIdx);
      setCurrentView(entry.view);
      setSelectedPlaylistId(entry.plId);
    }
  };

  const handleGoForward = () => {
    if (navIdx < navHistory.length - 1) {
      const targetIdx = navIdx + 1;
      const entry = navHistory[targetIdx];
      setNavIdx(targetIdx);
      setCurrentView(entry.view);
      setSelectedPlaylistId(entry.plId);
    }
  };
  
  // Library State
  const [playlists, setPlaylists] = useState([]);
  const [likedTracks, setLikedTracks] = useState([]);
  const [historyTracks, setHistoryTracks] = useState([]);
  const [trendingTracks, setTrendingTracks] = useState([]);

  // Audio Playback State - NO AUTOPLAY ON INITIAL LOAD
  const [currentTrack, setCurrentTrack] = useState(null);
  const [originalQueue, setOriginalQueue] = useState([]);
  const [queue, setQueue] = useState([]);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.85);
  const [isMuted, setIsMuted] = useState(false);
  const [isShuffle, setIsShuffle] = useState(false);
  const [repeatMode, setRepeatMode] = useState('off'); // 'off' | 'all' | 'one'
  const isRepeat = repeatMode !== 'off';
  const [seekTime, setSeekTime] = useState(null);

  // Modals, Drawers, & Context Menu State
  const [isLyricsOpen, setIsLyricsOpen] = useState(false);
  const [isQueueOpen, setIsQueueOpen] = useState(false);
  const [isRightSidebarOpen, setIsRightSidebarOpen] = useState(false);
  const [isMobileFullscreenOpen, setIsMobileFullscreenOpen] = useState(false);
  const [isImportModalOpen, setIsImportModalOpen] = useState(false);
  const [isYouTubeModalOpen, setIsYouTubeModalOpen] = useState(false);
  const [isDownloadModalOpen, setIsDownloadModalOpen] = useState(false);
  const [isEqualizerOpen, setIsEqualizerOpen] = useState(false);
  const [isAudioQualityOpen, setIsAudioQualityOpen] = useState(false);
  const [isCommandPaletteOpen, setIsCommandPaletteOpen] = useState(false);
  const [isSleepTimerModalOpen, setIsSleepTimerModalOpen] = useState(false);
  const [sleepTimerSeconds, setSleepTimerSeconds] = useState(null); // null | number | 'endOfTrack'
  const sleepTimerIntervalRef = useRef(null);
  const [playbackRate, setPlaybackRate] = useState(1.0);
  const [contextMenuData, setContextMenuData] = useState(null); // { type, track, playlist, x, y }
  const [lyricsData, setLyricsData] = useState(null);
  const [isLoadingLyrics, setIsLoadingLyrics] = useState(false);
  const [isLyricsBarVisible, setIsLyricsBarVisible] = useState(true);
  const hideLyricsBarTimerRef = useRef(null);

  // Dynamic Personalized Feed State
  const [personalizedFeed, setPersonalizedFeed] = useState(null);
  const [isLoadingFeed, setIsLoadingFeed] = useState(false);

  // Smart Autoplay Toast Notification
  const [smartToast, setSmartToast] = useState(null);

  // Audio Element Ref (Fallback for preview if needed)
  const audioRef = useRef(null);

  // Live Refs & Background Tab Keep-Alive (prevents Chrome/Edge pausing hidden tabs & stale closures)
  const currentTrackRef = useRef(currentTrack);
  const queueRef = useRef(queue);
  const originalQueueRef = useRef(originalQueue);
  const isPlayingRef = useRef(isPlaying);
  const isShuffleRef = useRef(isShuffle);
  const repeatModeRef = useRef(repeatMode);
  const sleepTimerRef = useRef(sleepTimerSeconds);
  const playGenRef = useRef(0);
  const failedVideoIdsRef = useRef(new Map());
  const lastEndedRef = useRef({ key: '', at: 0 });
  const bgKeepAliveRef = useRef(null);

  currentTrackRef.current = currentTrack;
  queueRef.current = queue;
  originalQueueRef.current = originalQueue;
  isPlayingRef.current = isPlaying;
  isShuffleRef.current = isShuffle;
  repeatModeRef.current = repeatMode;
  sleepTimerRef.current = sleepTimerSeconds;

  const startBgKeepAlive = () => {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      if (!bgKeepAliveRef.current) {
        const ctx = new Ctx();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.frequency.value = 20;
        gain.gain.value = 0.00001; // Sub-audible waveform keeps Chromium background tab audio session alive
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start();
        bgKeepAliveRef.current = { ctx, osc, gain };
      }
      if (bgKeepAliveRef.current.ctx.state === 'suspended') {
        bgKeepAliveRef.current.ctx.resume().catch(() => {});
      }
    } catch {}
  };

  const stopBgKeepAlive = () => {
    try {
      if (bgKeepAliveRef.current?.ctx?.state === 'running') {
        bgKeepAliveRef.current.ctx.suspend().catch(() => {});
      }
    } catch {}
  };

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

    // Connect native audio to studio Equalizer DSP & Sound Output Device router
    if (audioRef.current) {
      webAudioEqualizer.connectMediaElement(audioRef.current);
    }
  }, []);

  // Handle "Dengarkan Bareng" / Shared Link / Discord RPC sync via URL parameters (?song=...&artist=...&t=...)
  useEffect(() => {
    const handleUrlSync = async () => {
      try {
        const syncData = parseUrlSyncParams(window.location.search);
        if (!syncData) return;

        const { song, artist, videoId, targetSeconds } = syncData;
        const songTitle = song || 'Lagu Bersama';
        const artistName = artist || '';
        const timeBadge = targetSeconds > 0 ? ` di detik ${formatPlaybackSeconds(targetSeconds)}` : '';

        setSmartToast(`🎧 Dengarkan Bareng: Menghubungkan "${songTitle}"${timeBadge}...`);

        let matchedTrack = null;

        // 1. Direct YouTube videoId parameter (?id=... or ?videoId=...)
        if (videoId) {
          matchedTrack = {
            id: `yt-${videoId}`,
            title: songTitle,
            artist: artistName || 'YouTube Audio',
            album: 'Dengarkan Bareng',
            artwork: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
            videoId: videoId,
            duration: 240,
          };
        } else {
          // 2. Search song via musicApi search
          const searchQuery = artistName ? `${songTitle} ${artistName}` : songTitle;
          const searchResults = await musicApi.searchTracks(searchQuery);

          if (searchResults && searchResults.length > 0) {
            // Pick track with closest title match, or first result
            matchedTrack = searchResults.find(t => 
              t.title.toLowerCase().includes(songTitle.toLowerCase())
            ) || searchResults[0];
          } else {
            // 3. Fallback: resolve directly to YouTube
            const yt = await musicApi.resolveYouTubeMatch(songTitle, artistName);
            if (yt && yt.videoId) {
              matchedTrack = {
                id: `yt-${yt.videoId}`,
                title: songTitle,
                artist: artistName || 'YouTube Audio',
                album: 'Dengarkan Bareng',
                artwork: yt.thumbnail ? getHighResArtworkUrl(yt.thumbnail) : '/icon-192.png',
                videoId: yt.videoId,
                duration: yt.duration || 210,
              };
            }
          }
        }

        if (matchedTrack) {
          await handlePlayTrack(matchedTrack, [matchedTrack], targetSeconds);
          setSmartToast(`🎧 Dengarkan Bareng: Memutar "${matchedTrack.title}"${timeBadge}!`);
          setTimeout(() => setSmartToast(null), 4000);

          // Bersihkan parameter URL tanpa reload agar rapi
          try {
            const cleanUrl = window.location.origin + window.location.pathname;
            window.history.replaceState({}, document.title, cleanUrl);
          } catch (_) {}

          // Browser Autoplay Policy Fallback: Sentuh/klik layar sekali untuk membuka proteksi audio browser
          const unlockAutoplay = () => {
            setIsPlaying(true);
            window.removeEventListener('pointerdown', unlockAutoplay);
            window.removeEventListener('keydown', unlockAutoplay);
          };
          window.addEventListener('pointerdown', unlockAutoplay, { once: true });
          window.addEventListener('keydown', unlockAutoplay, { once: true });
        } else {
          setSmartToast(`Lagu "${songTitle}" tidak dapat ditemukan.`);
          setTimeout(() => setSmartToast(null), 3000);
        }
      } catch (err) {
        console.warn('URL Sync Error:', err);
      }
    };

    handleUrlSync();
  }, []);

  // Realtime Broadcast for McTify Discord RPC Bridge & Extensions
  useEffect(() => {
    if (!currentTrack) return;
    try {
      window.postMessage({
        type: 'MCTIFY_TRACK_STATE',
        data: {
          title: currentTrack.title || '',
          artist: currentTrack.artist || '',
          album: currentTrack.album || '',
          artwork: currentTrack.artwork || '',
          currentTime: Math.floor(currentTime || 0),
          duration: Math.floor(duration || 0),
          paused: !isPlaying,
          videoId: currentTrack.videoId || '',
        }
      }, '*');
    } catch (_) {}
  }, [currentTrack?.title, currentTrack?.artist, currentTrack?.artwork, currentTrack?.videoId, isPlaying, Math.floor(currentTime), Math.floor(duration)]);

  // Fetch Synchronized Lyrics whenever currentTrack changes (clear stale lyrics immediately & match exact duration)
  const effectiveTrackDur = Math.round(currentTrack?.duration || duration || 0);
  const lyricsDurBucket = effectiveTrackDur > 10 ? Math.round(effectiveTrackDur / 5) : 0;

  useEffect(() => {
    if (!currentTrack) {
      setLyricsData(null);
      return;
    }

    let isSubscribed = true;
    setLyricsData(null);
    setIsLoadingLyrics(true);

    lyricsService
      .fetchLyrics(currentTrack.artist, currentTrack.title, effectiveTrackDur > 5 ? effectiveTrackDur : undefined)
      .then((data) => {
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
  }, [currentTrack?.id, currentTrack?.title, currentTrack?.artist, lyricsDurBucket]);

  // Auto-hide bottom player bar in lyrics mode when not hovered or touched
  useEffect(() => {
    if (!isLyricsOpen) {
      setIsLyricsBarVisible(true);
      return;
    }

    const showBar = () => {
      setIsLyricsBarVisible(true);
      if (hideLyricsBarTimerRef.current) clearTimeout(hideLyricsBarTimerRef.current);
      hideLyricsBarTimerRef.current = setTimeout(() => {
        setIsLyricsBarVisible(false);
      }, 2800);
    };

    window.addEventListener('mousemove', showBar);
    window.addEventListener('touchstart', showBar);
    showBar();

    return () => {
      window.removeEventListener('mousemove', showBar);
      window.removeEventListener('touchstart', showBar);
      if (hideLyricsBarTimerRef.current) clearTimeout(hideLyricsBarTimerRef.current);
    };
  }, [isLyricsOpen]);

  // Pre-resolve next 2 queued tracks in background so background-tab song transitions have 0ms gap!
  useEffect(() => {
    const active = currentTrackRef.current;
    const liveQ = queueRef.current;
    if (!active || liveQ.length === 0) return;

    const idx = liveQ.findIndex((t) => t.id === active.id);
    if (idx === -1) return;

    const upcoming = [liveQ[idx + 1], liveQ[idx + 2]].filter(Boolean);
    let cancelled = false;

    for (const nextItem of upcoming) {
      if (nextItem.videoId) continue;
      musicApi
        .resolveYouTubeMatch(nextItem.title, nextItem.artist, nextItem.duration)
        .then((yt) => {
          if (cancelled || !yt?.videoId) return;
          const patched = {
            ...nextItem,
            videoId: yt.videoId,
            duration: yt.duration || nextItem.duration,
            artwork: yt.thumbnail ? getHighResArtworkUrl(yt.thumbnail) : getHighResArtworkUrl(nextItem.artwork),
          };
          setQueue((prev) => prev.map((it) => (it.id === nextItem.id && !it.videoId ? patched : it)));
          setOriginalQueue((prev) => prev.map((it) => (it.id === nextItem.id && !it.videoId ? patched : it)));
        })
        .catch(() => {});
    }

    return () => {
      cancelled = true;
    };
  }, [currentTrack?.id, queue.length]);

  // Handle Play Track with Full-Length YouTube Resolution & Generation Cancellation
  const handlePlayTrack = async (track, newQueue = null, initialSeekTime = 0) => {
    if (!track) return;

    const gen = ++playGenRef.current;
    startBgKeepAlive();

    const liveQueue = queueRef.current;
    const liveShuffle = isShuffleRef.current;

    if (newQueue && Array.isArray(newQueue) && newQueue.length > 0) {
      setOriginalQueue(newQueue);
      const nextDeck = liveShuffle ? buildSpotifyShuffleDeck(newQueue, track) : newQueue;
      queueRef.current = nextDeck;
      setQueue(nextDeck);
    } else if (!liveQueue.some(t => t.id === track.id)) {
      setOriginalQueue(prev => [track, ...prev]);
      const updatedQ = [track, ...liveQueue];
      queueRef.current = updatedQ;
      setQueue(updatedQ);
    }

    const startSecs = typeof initialSeekTime === 'number' && initialSeekTime > 0 ? initialSeekTime : 0;
    setCurrentTime(startSecs);
    setSeekTime(startSecs);
    setIsPlaying(true);

    const failedSet = failedVideoIdsRef.current.get(track.id);
    const hasUsableVideoId = track.videoId && (!failedSet || !failedSet.has(track.videoId));

    if (hasUsableVideoId) {
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.src = '';
      }
      const hdTrack = {
        ...track,
        artwork: getHighResArtworkUrl(track.artwork),
      };
      currentTrackRef.current = hdTrack;
      setCurrentTrack(hdTrack);
      setDuration(track.duration || 210);
    } else {
      // Clear native audio preview immediately
      if (audioRef.current) {
        audioRef.current.pause();
        audioRef.current.src = '';
      }
      const pendingTrack = { ...track, videoId: null, artwork: getHighResArtworkUrl(track.artwork) };
      currentTrackRef.current = pendingTrack;
      setCurrentTrack(pendingTrack);

      try {
        const excludeList = failedSet ? [...failedSet] : [];
        const yt = await musicApi.resolveYouTubeMatch(track.title, track.artist, track.duration, excludeList);
        if (gen !== playGenRef.current) return;

        if (yt && yt.videoId) {
          const fullTrack = {
            ...track,
            videoId: yt.videoId,
            duration: yt.duration || track.duration,
            artwork: yt.thumbnail ? getHighResArtworkUrl(yt.thumbnail) : getHighResArtworkUrl(track.artwork),
          };
          currentTrackRef.current = fullTrack;
          setCurrentTrack(fullTrack);
          setDuration(yt.duration || track.duration);
          setQueue(prev => prev.map(item => (item.id === track.id ? fullTrack : item)));
          setOriginalQueue(prev => prev.map(item => (item.id === track.id ? fullTrack : item)));
        } else if (track.audioUrl && audioRef.current) {
          audioRef.current.src = track.audioUrl;
          audioRef.current.currentTime = startSecs;
          audioRef.current.play().catch(console.warn);
        } else {
          setSmartToast(`Melewati "${track.title}" (sumber audio tidak tersedia)`);
          setTimeout(() => setSmartToast(null), 2800);
          if (queueRef.current.length > 1) {
            setTimeout(() => {
              if (gen === playGenRef.current) handleNext(true);
            }, 250);
          } else {
            setIsPlaying(false);
          }
          return;
        }
      } catch {
        if (gen !== playGenRef.current) return;
        if (track.audioUrl && audioRef.current) {
          audioRef.current.src = track.audioUrl;
          audioRef.current.currentTime = startSecs;
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

  // Handle Play Track from Search: Builds an Artist & Genre Radio queue (randomized)
  // preventing next playback from continuing down raw search results
  const handlePlayTrackFromSearch = async (track) => {
    if (!track) return;

    // 1. Start playing immediately with zero latency
    await handlePlayTrack(track, [track]);

    // 2. Display notification
    setSmartToast(`Radio Hits: Menyiapkan lagu populer untuk ${track.artist || track.title}...`);

    // 3. Asynchronously fetch popular artist & genre tracks
    try {
      const radioTracks = await musicApi.getArtistGenreRadio(track, 18, [track]);
      if (radioTracks && radioTracks.length > 0) {
        const baseQueue = [
          track,
          ...radioTracks.filter(
            t => t.id !== track.id && t.title?.toLowerCase().trim() !== track.title?.toLowerCase().trim()
          ),
        ];
        setOriginalQueue(baseQueue);
        const nextDeck = isShuffleRef.current ? buildSpotifyShuffleDeck(baseQueue, track) : baseQueue;
        queueRef.current = nextDeck;
        setQueue(nextDeck);
        setSmartToast(`Radio Hits: Lagu terpopuler dari ${track.artist} & lagu favorit siap diputar`);
        setTimeout(() => setSmartToast(null), 3500);
      }
    } catch (err) {
      console.warn('Failed to load search radio tracks:', err);
    }
  };

  // Toggle Play / Pause
  const handlePlayPause = () => {
    const activeTrack = currentTrackRef.current;
    if (!activeTrack) {
      const first = personalizedFeed?.quickCards?.[0] || trendingTracks[0];
      if (first) {
        handlePlayTrack(first, personalizedFeed?.quickCards || trendingTracks);
      }
      return;
    }

    if (isPlayingRef.current) {
      setIsPlaying(false);
      stopBgKeepAlive();
      if (audioRef.current) audioRef.current.pause();
    } else {
      startBgKeepAlive();
      setIsPlaying(true);
      if (audioRef.current && audioRef.current.src) {
        audioRef.current.play().catch(console.warn);
      }
    }
  };

  // Toggle Shuffle (Spotify Balanced Fisher-Yates Deck Shuffle)
  const handleToggleShuffle = () => {
    const nextState = !isShuffle;
    setIsShuffle(nextState);
    const base = originalQueue.length > 0 ? originalQueue : queue;
    if (base.length <= 1) return;

    if (nextState) {
      if (originalQueue.length === 0) setOriginalQueue(queue);
      setQueue(buildSpotifyShuffleDeck(base, currentTrack));
    } else if (originalQueue.length > 0) {
      setQueue(originalQueue);
    }
  };

  // Shuffle Play All from a Playlist / Daily Mix / Album
  const handleShuffleAll = (tracks) => {
    if (!tracks || tracks.length === 0) return;
    setIsShuffle(true);
    setOriginalQueue(tracks);
    const deck = buildSpotifyShuffleDeck(tracks, null);
    setQueue(deck);
    handlePlayTrack(deck[0], deck);
  };

  // Next Track in Queue with Deterministic Shuffled Deck + SMART AUTOPLAY (Live refs safe for background tabs!)
  const handleNext = async (isAutoEnded = false) => {
    const activeTrack = currentTrackRef.current;
    const liveQueue = queueRef.current;
    const liveOrigQueue = originalQueueRef.current;
    const liveRepeat = repeatModeRef.current;
    const liveShuffle = isShuffleRef.current;

    if (!activeTrack && liveQueue.length === 0) return;

    const currentIndex = liveQueue.findIndex(t => t.id === activeTrack?.id);

    // 1. Sequential step on queue (already Fisher-Yates balanced when Shuffle is ON!)
    if (currentIndex !== -1 && currentIndex < liveQueue.length - 1) {
      handlePlayTrack(liveQueue[currentIndex + 1]);
      return;
    }

    // 2. End of playlist / shuffled deck reached -> Repeat All re-shuffles cleanly if Shuffle ON
    if (liveRepeat === 'all' && liveQueue.length > 0) {
      const base = liveOrigQueue.length > 0 ? liveOrigQueue : liveQueue;
      const nextDeck = liveShuffle ? buildSpotifyShuffleDeck(base, null) : base;
      queueRef.current = nextDeck;
      setQueue(nextDeck);
      handlePlayTrack(nextDeck[0]);
      return;
    }

    // 3. Queue / Playlist Finished! -> Trigger Smart Autoplay (Spotify Radio)
    if (activeTrack) {
      setSmartToast(`Radio Pintar: Mencari musik serupa dengan ${activeTrack.artist}...`);
      try {
        const smartRecommendations = await musicApi.getSmartRecommendations(activeTrack, liveQueue);
        if (smartRecommendations && smartRecommendations.length > 0) {
          const nextTrack = smartRecommendations[0];
          const newQueue = [...liveQueue, ...smartRecommendations];
          queueRef.current = newQueue;
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
    if (liveQueue.length > 0) {
      handlePlayTrack(liveQueue[0]);
    }
  };

  // Previous Track
  const handlePrev = () => {
    if (currentTime > 3) {
      handleSeek(0);
      return;
    }
    const liveQueue = queueRef.current;
    const activeTrack = currentTrackRef.current;
    if (liveQueue.length === 0) return;
    const currentIndex = liveQueue.findIndex(t => t.id === activeTrack?.id);
    let prevIndex = liveQueue.length - 1;

    if (currentIndex > 0) {
      prevIndex = currentIndex - 1;
    }

    handlePlayTrack(liveQueue[prevIndex]);
  };

  // 3-State Repeat Handler ('off' -> 'all' -> 'one' -> 'off')
  const handleToggleRepeat = () => {
    setRepeatMode((prev) => {
      if (prev === 'off') return 'all';
      if (prev === 'all') return 'one';
      return 'off';
    });
  };

  // Dedicated Pause function (used by Sleep Timer & UI)
  const handlePause = () => {
    setIsPlaying(false);
    stopBgKeepAlive();
    if (audioRef.current) audioRef.current.pause();
  };

  // Sleep Timer handlers
  const handleSetSleepTimer = (target) => {
    if (sleepTimerIntervalRef.current) {
      clearInterval(sleepTimerIntervalRef.current);
      sleepTimerIntervalRef.current = null;
    }

    if (target === 'endOfTrack') {
      setSleepTimerSeconds('endOfTrack');
      setSmartToast('Timer tidur aktif: Musik akan berhenti di akhir lagu ini.');
      setTimeout(() => setSmartToast(null), 3000);
      return;
    }

    const totalSeconds = target * 60;
    setSleepTimerSeconds(totalSeconds);
    setSmartToast(`Timer tidur aktif: Musik akan berhenti dalam ${target} menit.`);
    setTimeout(() => setSmartToast(null), 3000);

    sleepTimerIntervalRef.current = setInterval(() => {
      setSleepTimerSeconds((prev) => {
        if (typeof prev !== 'number') return prev;
        if (prev <= 1) {
          clearInterval(sleepTimerIntervalRef.current);
          sleepTimerIntervalRef.current = null;
          handlePause();
          setSmartToast('Waktu tidur selesai. Musik dihentikan.');
          setTimeout(() => setSmartToast(null), 4000);
          return null;
        }
        return prev - 1;
      });
    }, 1000);
  };

  const handleCancelSleepTimer = () => {
    if (sleepTimerIntervalRef.current) {
      clearInterval(sleepTimerIntervalRef.current);
      sleepTimerIntervalRef.current = null;
    }
    setSleepTimerSeconds(null);
    setSmartToast('Timer tidur dimatikan.');
    setTimeout(() => setSmartToast(null), 2500);
  };

  // Track ended event (deduped & backed by live refs so background tabs always advance)
  const handleEnded = () => {
    const activeTrack = currentTrackRef.current;
    const liveQueue = queueRef.current;
    const liveRepeat = repeatModeRef.current;
    const liveSleep = sleepTimerRef.current;

    const now = Date.now();
    const endedKey = `${activeTrack?.id || ''}__${activeTrack?.videoId || ''}`;
    if (lastEndedRef.current.key === endedKey && now - lastEndedRef.current.at < 1500) {
      return;
    }
    lastEndedRef.current = { key: endedKey, at: now };

    if (liveSleep === 'endOfTrack') {
      handlePause();
      handleCancelSleepTimer();
      setSmartToast('Musik berhenti di akhir lagu sesuai pengatur waktu tidur.');
      setTimeout(() => setSmartToast(null), 4000);
      return;
    }

    if (liveRepeat === 'one') {
      handleSeek(0);
      setIsPlaying(true);
      startBgKeepAlive();
    } else if (liveRepeat === 'all') {
      if (liveQueue.length === 0) return;
      const currentIndex = liveQueue.findIndex(t => t.id === activeTrack?.id);
      const nextIndex = (currentIndex + 1) % liveQueue.length;
      handlePlayTrack(liveQueue[nextIndex]);
    } else {
      handleNext(true);
    }
  };

  // Automatic embed/playback recovery when YouTube Iframe returns 101/150 (embed disabled) or 100/5
  const handleYouTubeError = async (err) => {
    const track = currentTrackRef.current;
    if (!track) return;

    const errCode = err?.data;
    const genSnapshot = playGenRef.current;
    console.warn('[App] YouTube playback error code:', errCode, 'for track:', track.title, 'vid:', track.videoId);

    const existingFailed = failedVideoIdsRef.current.get(track.id) || new Set();
    if (track.videoId) existingFailed.add(track.videoId);
    failedVideoIdsRef.current.set(track.id, existingFailed);

    if (existingFailed.size <= 3) {
      try {
        const alt = await musicApi.resolveYouTubeMatch(
          track.title,
          track.artist,
          track.duration,
          [...existingFailed]
        );
        if (genSnapshot !== playGenRef.current) return;
        if (alt && alt.videoId && !existingFailed.has(alt.videoId)) {
          const recovered = {
            ...track,
            videoId: alt.videoId,
            duration: alt.duration || track.duration,
            artwork: alt.thumbnail ? getHighResArtworkUrl(alt.thumbnail) : track.artwork,
          };
          currentTrackRef.current = recovered;
          setCurrentTrack(recovered);
          setQueue(prev => prev.map(it => (it.id === track.id ? recovered : it)));
          setOriginalQueue(prev => prev.map(it => (it.id === track.id ? recovered : it)));
          return;
        }
      } catch (resolveErr) {
        console.warn('[App] Alternative YouTube resolution error:', resolveErr);
      }
    }

    if (genSnapshot !== playGenRef.current) return;

    if (track.audioUrl && audioRef.current) {
      audioRef.current.src = track.audioUrl;
      audioRef.current.currentTime = 0;
      audioRef.current.play().catch(console.warn);
      return;
    }

    if (queueRef.current.length > 1) {
      setSmartToast(`"${track.title}" dibatasi YouTube, beralih ke lagu berikutnya...`);
      setTimeout(() => setSmartToast(null), 3000);
      handleNext(true);
    } else {
      setSmartToast(`"${track.title}" tidak mengizinkan pemutaran embed di browser.`);
      setTimeout(() => setSmartToast(null), 3500);
    }
  };

  // Seek
  const handleSeek = (newTime) => {
    if (Number.isFinite(newTime)) {
      setCurrentTime(newTime);
      setSeekTime(newTime);
      if (audioRef.current && audioRef.current.src) {
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

  // TWS Bluetooth Earphone (2x Tap Skip, 3x Tap Undo) & System Media Notification
  useEffect(() => {
    if (!('mediaSession' in navigator) || !currentTrack) return;

    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: currentTrack.title || 'McMusic',
        artist: currentTrack.artist || 'McMusic Artist',
        album: currentTrack.album || 'McMusic',
        artwork: [
          { src: currentTrack.artwork || '/icon-192.png', sizes: '96x96', type: 'image/jpeg' },
          { src: currentTrack.artwork || '/icon-192.png', sizes: '128x128', type: 'image/jpeg' },
          { src: currentTrack.artwork || '/icon-192.png', sizes: '256x256', type: 'image/jpeg' },
          { src: currentTrack.artwork || '/icon-192.png', sizes: '512x512', type: 'image/jpeg' },
        ],
      });

      navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';

      navigator.mediaSession.setActionHandler('play', () => {
        setIsPlaying(true);
        if (!currentTrack.videoId && currentTrack.audioUrl && audioRef.current) {
          audioRef.current.play().catch(console.warn);
        }
      });

      navigator.mediaSession.setActionHandler('pause', () => {
        setIsPlaying(false);
        if (audioRef.current) audioRef.current.pause();
      });

      // TWS 2x Tap (Skip next song)
      navigator.mediaSession.setActionHandler('nexttrack', () => {
        handleNext();
      });

      // TWS 3x Tap / Undo (Previous song)
      navigator.mediaSession.setActionHandler('previoustrack', () => {
        handlePrev();
      });

      // Bluetooth / Car skip -10s
      navigator.mediaSession.setActionHandler('seekbackward', (details) => {
        const skip = details.seekOffset || 10;
        handleSeek(Math.max(0, currentTime - skip));
      });

      // Bluetooth / Car skip +10s
      navigator.mediaSession.setActionHandler('seekforward', (details) => {
        const skip = details.seekOffset || 10;
        handleSeek(Math.min(duration, currentTime + skip));
      });

      navigator.mediaSession.setActionHandler('seekto', (details) => {
        if (details.seekTime != null) {
          handleSeek(details.seekTime);
        }
      });
    } catch (e) {
      console.warn('MediaSession note:', e);
    }
  }, [currentTrack?.id, currentTrack?.title, currentTrack?.artist, currentTrack?.artwork, isPlaying, currentTime, duration]);

  // Sync Lockscreen / Notification Bar Scrubber position state
  useEffect(() => {
    if (!('mediaSession' in navigator) || !currentTrack) return;
    if ('setPositionState' in navigator.mediaSession && Number.isFinite(duration) && duration > 0 && Number.isFinite(currentTime)) {
      try {
        navigator.mediaSession.setPositionState({
          duration: Math.max(0, duration),
          playbackRate: 1,
          position: Math.max(0, Math.min(currentTime, duration)),
        });
      } catch (_) {}
    }
  }, [currentTime, duration, currentTrack?.id]);

  // Global Desktop Spotify Keyboard Shortcuts
  useEffect(() => {
    const handleKeyDown = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setIsCommandPaletteOpen((prev) => !prev);
        return;
      }

      // Don't trigger playback keys if user is actively typing in an input or textarea
      const target = e.target;
      if (
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.isContentEditable)
      ) {
        if (e.key === 'Escape') {
          target.blur();
        }
        return;
      }

      // Space: Toggle Play/Pause
      if (e.code === 'Space') {
        e.preventDefault();
        handlePlayPause();
      } else if (e.key === 'Escape') {
        // Escape: Close Command Palette, Right Sidebar, Lyrics, Modals, Menus
        if (isCommandPaletteOpen) setIsCommandPaletteOpen(false);
        if (isRightSidebarOpen) setIsRightSidebarOpen(false);
        if (isLyricsOpen) setIsLyricsOpen(false);
        if (isQueueOpen) setIsQueueOpen(false);
        if (isImportModalOpen) setIsImportModalOpen(false);
        if (isDownloadModalOpen) setIsDownloadModalOpen(false);
        if (contextMenuData) setContextMenuData(null);
      } else if ((e.ctrlKey || e.metaKey) && e.key === 'ArrowRight') {
        // Ctrl+Right / Cmd+Right: Skip Next
        e.preventDefault();
        handleNext();
      } else if ((e.ctrlKey || e.metaKey) && e.key === 'ArrowLeft') {
        // Ctrl+Left / Cmd+Left: Previous
        e.preventDefault();
        handlePrev();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [
    isPlaying,
    currentTrack,
    queue,
    isCommandPaletteOpen,
    isRightSidebarOpen,
    isLyricsOpen,
    isQueueOpen,
    isImportModalOpen,
    isDownloadModalOpen,
    contextMenuData,
    personalizedFeed,
    trendingTracks,
  ]);

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
    if (!track) return;
    if (!currentTrack) {
      handlePlayTrack(track);
      setSmartToast(`Memutar: ${track.title}`);
      setTimeout(() => setSmartToast(null), 3000);
      return;
    }
    setQueue(prev => [...prev, track]);
    setSmartToast(`Ditambahkan ke antrean: ${track.title}`);
    setTimeout(() => setSmartToast(null), 3000);
  };

  const handleAddToNext = (track) => {
    if (!track) return;
    if (!currentTrack) {
      handlePlayTrack(track);
      return;
    }
    setQueue((prevQueue) => {
      const currentIndex = prevQueue.findIndex(t => t.id === currentTrack.id);
      // Remove any existing duplicate of this track from elsewhere in the queue
      const filtered = prevQueue.filter((t, idx) => t.id !== track.id || idx === currentIndex);
      const newCurrentIndex = filtered.findIndex(t => t.id === currentTrack.id);
      if (newCurrentIndex !== -1) {
        const nextQueue = [...filtered];
        nextQueue.splice(newCurrentIndex + 1, 0, track);
        return nextQueue;
      }
      return [track, ...filtered];
    });
    setSmartToast(`Akan diputar setelah lagu ini: ${track.title}`);
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

  const handleOpenVirtualPlaylist = async (pl) => {
    if (!pl) return;
    setVirtualPlaylist(pl);
    navigateTo('virtual-playlist', null);
    // Enrich Daily Mix asynchronously if fewer than 10 tracks
    if ((pl.tracks?.length || 0) < 10 && pl.queryHint) {
      try {
        const extra = await musicApi.searchTracks(pl.queryHint, 15);
        if (extra && extra.length > 0) {
          const existingIds = new Set((pl.tracks || []).map(t => t.id));
          const merged = [...(pl.tracks || []), ...extra.filter(t => !existingIds.has(t.id))].slice(0, 16);
          setVirtualPlaylist((curr) =>
            curr && curr.id === pl.id ? { ...curr, tracks: merged } : curr
          );
        }
      } catch (_) {}
    }
  };

  const handleSaveVirtualPlaylist = (pl) => {
    if (!pl) return;
    const exists = playlists.some((p) => p.name.toLowerCase() === pl.name.toLowerCase());
    if (exists) {
      setSmartToast(`"${pl.name}" sudah ada di Koleksi Kamu.`);
      setTimeout(() => setSmartToast(null), 2500);
      return;
    }
    const newPl = {
      id: `pl-mix-${Date.now()}`,
      name: pl.name,
      description: pl.description || 'Disimpan dari McTify Mix',
      cover: pl.cover,
      source: pl.source || 'mix',
      tracks: pl.tracks || [],
    };
    const updated = storageService.addPlaylist(newPl);
    setPlaylists(updated);
    setSmartToast(`"${pl.name}" disimpan ke Koleksi Kamu!`);
    setTimeout(() => setSmartToast(null), 3000);
  };

  const handleCopyShare = (item) => {
    if (!item) return;
    let shareUrl = window.location.origin;
    if (item.title) {
      const isCurrentlyPlayingThis = currentTrack?.id === item.id;
      const liveTime = isCurrentlyPlayingThis ? Math.floor(currentTime || 0) : 0;
      shareUrl = generateUrlSyncLink({
        song: item.title,
        artist: item.artist,
        videoId: item.videoId,
        seconds: liveTime,
        baseUrl: window.location.origin,
      });
    }

    if (navigator.clipboard) {
      navigator.clipboard.writeText(shareUrl).catch(() => {});
    }
    const timeNotice = item.title && currentTrack?.id === item.id && currentTime > 0
      ? ` (di detik ${formatPlaybackSeconds(currentTime)})`
      : '';
    setSmartToast(`🔗 Tautan Dengarkan Bareng disalin${timeNotice}!`);
    setTimeout(() => setSmartToast(null), 3200);
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

      {/* Top Header Bar matching Spotify Desktop & Monochrome Web */}
      <TopNavBar
        currentView={currentView}
        setCurrentView={(view) => navigateTo(view, null)}
        searchQuery={searchQuery}
        setSearchQuery={setSearchQuery}
        canGoBack={navIdx > 0}
        canGoForward={navIdx < navHistory.length - 1}
        onGoBack={handleGoBack}
        onGoForward={handleGoForward}
        onOpenCommandPalette={() => setIsCommandPaletteOpen(true)}
        onOpenDownloadApp={() => setIsDownloadModalOpen(true)}
        onCreatePlaylist={handleCreatePlaylist}
        onOpenImportYouTube={() => setIsYouTubeModalOpen(true)}
      />

      {/* Primary YouTube Player Engine - Always mounted for continuous background auto-advance */}
      <YouTubePlayer
        videoId={currentTrack?.videoId}
        isPlaying={isPlaying}
        volume={volume}
        isMuted={isMuted}
        playbackRate={playbackRate}
        seekTime={seekTime}
        onTimeUpdate={(current, dur) => {
          setCurrentTime(current);
          if (dur && Number.isFinite(dur) && dur > 0) {
            setDuration(dur);
            // Safety auto-advance if playback is within 0.6s of end
            if (dur > 5 && current >= dur - 0.6 && isPlayingRef.current) {
              handleEnded();
            }
          }
        }}
        onEnded={handleEnded}
        onError={handleYouTubeError}
      />

      {/* Primary Native Audio Stream Element (Powers setSinkId & Real Windows Hardware Output Switching) */}
      <audio
        ref={audioRef}
        crossOrigin="anonymous"
        preload="auto"
        onTimeUpdate={() => {
          if (audioRef.current) {
            const cur = audioRef.current.currentTime;
            const dur = audioRef.current.duration;
            setCurrentTime(cur);
            if (dur && Number.isFinite(dur) && dur > 0) {
              setDuration(dur);
            }
            if (dur && cur >= dur - 0.5 && isPlayingRef.current) {
              handleEnded();
            }
          }
        }}
        onLoadedMetadata={() => {
          if (audioRef.current) {
            const dur = audioRef.current.duration;
            if (dur && Number.isFinite(dur) && dur > 0) {
              setDuration(dur);
            }
          }
        }}
        onEnded={handleEnded}
        onError={() => {
          console.warn('[App] Audio fallback stream error for:', currentTrackRef.current?.title);
          if (!currentTrackRef.current?.videoId && isPlayingRef.current && queueRef.current.length > 1) {
            handleNext(true);
          }
        }}
      />

      {/* Upper Area: 3 Detached Islands (Sidebar + Main Content + Right Sidebar) */}
      <div className="flex flex-1 min-h-0 px-0 sm:px-2 pb-0 sm:pb-2 gap-2 overflow-hidden bg-black">
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

        {/* Main View Area - Spotify Native Detached Island */}
        <main 
          key={`${currentView}-${selectedPlaylistId || 'root'}-${selectedArtist?.name || 'none'}`}
          className="flex-1 rounded-none sm:rounded-lg bg-[#121212] flex flex-col min-w-0 overflow-hidden relative shadow-none animate-view-fade-in"
        >
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
              onPlayTrackWithRadio={handlePlayTrackFromSearch}
              onTogglePlayPause={handlePlayPause}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onOpenImportModal={() => setIsImportModalOpen(true)}
              onOpenAudioQuality={() => setIsAudioQualityOpen(true)}
              onSelectPlaylist={(plId) => navigateTo('playlist', plId)}
              onOpenVirtualPlaylist={handleOpenVirtualPlaylist}
              onSelectLiked={() => navigateTo('liked', null)}
              onOpenArtist={handleOpenArtist}
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
              onPlayTrackFromSearch={handlePlayTrackFromSearch}
              onTogglePlayPause={handlePlayPause}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onOpenArtist={handleOpenArtist}
              onSelectPlaylist={(plId) => navigateTo('playlist', plId)}
              onOpenVirtualPlaylist={handleOpenVirtualPlaylist}
              onAddTrackToPlaylist={handleAddTrackToPlaylist}
              onTrackContextMenu={handleTrackContextMenu}
              onOpenImportYouTube={() => setIsYouTubeModalOpen(true)}
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
              onShuffleAll={handleShuffleAll}
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
              onShuffleAll={handleShuffleAll}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onTrackContextMenu={handleTrackContextMenu}
            />
          )}

          {currentView === 'virtual-playlist' && virtualPlaylist && !selectedPlaylistId && (
            <PlaylistView
              playlist={virtualPlaylist}
              currentTrack={currentTrack}
              isPlaying={isPlaying}
              likedTrackIds={likedTrackIds}
              onPlayTrack={handlePlayTrack}
              onTogglePlayPause={handlePlayPause}
              onPlayAll={(tracks) => handlePlayTrack(tracks[0], tracks)}
              onShuffleAll={handleShuffleAll}
              onToggleLike={handleToggleLike}
              onOpenLyrics={() => setIsLyricsOpen(true)}
              onSaveMixToLibrary={handleSaveVirtualPlaylist}
              isSavedInLibrary={playlists.some((p) => p.name.toLowerCase() === virtualPlaylist.name.toLowerCase())}
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
              onShuffleAll={handleShuffleAll}
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

      {/* Hover detection strip at the bottom of the screen to reveal player bar when cursor moves to the bottom in lyrics mode */}
      {isLyricsOpen && !isLyricsBarVisible && (
        <div 
          className="fixed bottom-0 left-0 right-0 h-10 z-[59] hidden md:block cursor-pointer"
          onMouseEnter={() => {
            setIsLyricsBarVisible(true);
            if (hideLyricsBarTimerRef.current) clearTimeout(hideLyricsBarTimerRef.current);
            hideLyricsBarTimerRef.current = setTimeout(() => setIsLyricsBarVisible(false), 2800);
          }}
        />
      )}

      {/* --- DESKTOP & TABLET PLAYER BAR (DENGAN AUTO-HIDE SAAT DI DALAM PLAYER LIRIK) --- */}
      <div 
        className={`hidden md:block transition-all duration-300 ease-out ${
          isLyricsOpen 
            ? `fixed bottom-0 left-0 right-0 z-[60] shadow-2xl ${
                isLyricsBarVisible 
                  ? 'translate-y-0 opacity-100 pointer-events-auto' 
                  : 'translate-y-full opacity-0 pointer-events-none'
              }` 
            : 'relative z-40'
        }`}
        onMouseEnter={() => {
          setIsLyricsBarVisible(true);
          if (hideLyricsBarTimerRef.current) clearTimeout(hideLyricsBarTimerRef.current);
        }}
        onMouseLeave={() => {
          if (isLyricsOpen) {
            hideLyricsBarTimerRef.current = setTimeout(() => setIsLyricsBarVisible(false), 1800);
          }
        }}
      >
        <PlayerBar
          currentTrack={currentTrack}
          isPlaying={isPlaying}
          currentTime={currentTime}
          duration={duration}
          volume={volume}
          isMuted={isMuted}
          isShuffle={isShuffle}
          isRepeat={isRepeat}
          repeatMode={repeatMode}
          isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
          playbackRate={playbackRate}
          onPlaybackRateChange={setPlaybackRate}
          isSleepTimerActive={sleepTimerSeconds !== null}
          onOpenSleepTimer={() => setIsSleepTimerModalOpen(true)}
          isLyricsOpen={isLyricsOpen}
          isQueueOpen={isQueueOpen}
          isRightSidebarOpen={isRightSidebarOpen}
          isEqualizerOpen={isEqualizerOpen}
          isAudioQualityOpen={isAudioQualityOpen}
          onPlayPause={handlePlayPause}
          onPrev={handlePrev}
          onNext={() => handleNext(false)}
          onSeek={handleSeek}
          onVolumeChange={handleVolumeChange}
          onToggleMute={handleToggleMute}
          onToggleShuffle={handleToggleShuffle}
          onToggleRepeat={handleToggleRepeat}
          onToggleLike={handleToggleLike}
          onToggleLyrics={() => setIsLyricsOpen(!isLyricsOpen)}
          onToggleQueue={() => setIsQueueOpen(!isQueueOpen)}
          onToggleRightSidebar={() => setIsRightSidebarOpen(!isRightSidebarOpen)}
          onToggleEqualizer={() => setIsEqualizerOpen(!isEqualizerOpen)}
          onToggleAudioQuality={() => setIsAudioQualityOpen(!isAudioQualityOpen)}
          onTrackContextMenu={handleTrackContextMenu}
          onShareTrack={() => currentTrack && handleCopyShare(currentTrack)}
        />
      </div>

      {/* --- MOBILE FLOATING MINI-PLAYER (ViMusic/RiMusic Swipe Support) --- */}
      <MobileMiniPlayer
        currentTrack={currentTrack}
        isPlaying={isPlaying}
        currentTime={currentTime}
        duration={duration}
        isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
        onPlayPause={handlePlayPause}
        onToggleLike={handleToggleLike}
        onOpenFullscreen={() => setIsMobileFullscreenOpen(true)}
        onNext={handleNext}
        onPrev={handlePrev}
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
        repeatMode={repeatMode}
        isLiked={currentTrack ? likedTrackIds.has(currentTrack.id) : false}
        lyricsData={lyricsData}
        playbackRate={playbackRate}
        onPlaybackRateChange={setPlaybackRate}
        isSleepTimerActive={sleepTimerSeconds !== null}
        onOpenSleepTimer={() => setIsSleepTimerModalOpen(true)}
        onPlayPause={handlePlayPause}
        onPrev={handlePrev}
        onNext={() => handleNext(false)}
        onSeek={handleSeek}
        onToggleShuffle={handleToggleShuffle}
        onToggleRepeat={handleToggleRepeat}
        onToggleLike={handleToggleLike}
        onOpenLyrics={() => setIsLyricsOpen(true)}
        onOpenQueue={() => setIsQueueOpen(true)}
        onOpenEqualizer={() => setIsEqualizerOpen(true)}
        onOpenAudioQuality={() => setIsAudioQualityOpen(true)}
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

      {/* --- IMPORT YOUTUBE TRACK MODAL --- */}
      <ImportYouTubeModal
        isOpen={isYouTubeModalOpen}
        onClose={() => setIsYouTubeModalOpen(false)}
        onPlayTrack={handlePlayTrack}
        onAddToNext={handleAddToNext}
        onAddToQueue={handleAddToQueue}
        onAddTrackToPlaylist={handleAddTrackToPlaylist}
        playlists={playlists}
        onToggleLike={handleToggleLike}
      />

      {/* --- DOWNLOAD FLUTTER APP MODAL --- */}
      <DownloadAppModal
        isOpen={isDownloadModalOpen}
        onClose={() => setIsDownloadModalOpen(false)}
      />

      {/* --- EQUALIZER & AUDIO MASTER MODAL --- */}
      <EqualizerModal
        isOpen={isEqualizerOpen}
        onClose={() => setIsEqualizerOpen(false)}
      />

      {/* --- AUDIO QUALITY SETTINGS MODAL --- */}
      <AudioQualityModal
        isOpen={isAudioQualityOpen}
        onClose={() => setIsAudioQualityOpen(false)}
      />

      {/* --- SPOTLIGHT COMMAND PALETTE (CTRL+K - FMHY Monochrome Spec) --- */}
      <CommandPaletteModal
        isOpen={isCommandPaletteOpen}
        onClose={() => setIsCommandPaletteOpen(false)}
        onNavigate={(view) => navigateTo(view, null)}
        onPlayTrackFromSearch={handlePlayTrackFromSearch}
        onOpenImportSpotify={() => setIsImportModalOpen(true)}
        onOpenImportYouTube={() => setIsYouTubeModalOpen(true)}
        onOpenEqualizer={() => setIsEqualizerOpen(true)}
        onOpenAudioQuality={() => setIsAudioQualityOpen(true)}
        onOpenLyrics={() => setIsLyricsOpen(true)}
        onOpenDownloadApp={() => setIsDownloadModalOpen(true)}
      />

      {/* --- SLEEP TIMER MODAL --- */}
      <SleepTimerModal
        isOpen={isSleepTimerModalOpen}
        onClose={() => setIsSleepTimerModalOpen(false)}
        sleepTimerSeconds={sleepTimerSeconds}
        onSetTimer={handleSetSleepTimer}
        onCancelTimer={handleCancelSleepTimer}
      />

      {/* --- SPOTIFY CONTEXT MENU (KLIK KANAN PADA MUSIK & PLAYLIST) --- */}
      {contextMenuData && (
        <ContextMenu
          contextData={contextMenuData}
          playlists={playlists}
          isLiked={contextMenuData?.track ? likedTrackIds.has(contextMenuData.track.id) : false}
          onClose={() => setContextMenuData(null)}
          onPlayTrack={handlePlayTrack}
          onAddToNext={handleAddToNext}
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
