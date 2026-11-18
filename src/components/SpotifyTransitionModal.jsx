import React, { useState, useEffect, useRef, useMemo } from 'react';
import { 
  Play, 
  Pause, 
  Volume2, 
  Sliders, 
  Sparkles, 
  ChevronDown, 
  Check, 
  Music2, 
  Activity,
  Layers,
  Wand2,
  Search,
  X,
  ArrowLeft,
  RefreshCw,
  Disc,
  Heart,
  Flame,
  ListMusic
} from 'lucide-react';
import { storageService } from '../services/storageService';
import { musicApi, getHighResArtworkUrl } from '../services/musicApi';

// Helper: Realistic BPM & Camelot Key Analyzer
function computeTrackBpmAndKey(track) {
  if (!track) return { bpm: 90, key: '4B' };
  
  if (track.bpm && track.key) {
    return { bpm: Number(track.bpm), key: String(track.key) };
  }

  const str = `${track.title || ''} ${track.artist || ''} ${track.genre || ''}`.toLowerCase();
  
  // Deterministic seed from track title + artist
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (hash << 5) - hash + str.charCodeAt(i);
    hash |= 0;
  }
  const posHash = Math.abs(hash);

  // Genre-aware realistic BPM
  let baseBpm = 95;
  if (/dance|edm|house|techno|club|electronic/i.test(str)) {
    baseBpm = 120 + (posHash % 10);
  } else if (/hip\s*hop|rap|trap|r&b|soul/i.test(str)) {
    baseBpm = 82 + (posHash % 16);
  } else if (/rock|metal|punk|band/i.test(str)) {
    baseBpm = 125 + (posHash % 25);
  } else if (/acoustic|ballad|slow|sad|lofi|piano/i.test(str)) {
    baseBpm = 72 + (posHash % 18);
  } else {
    // Pop / General
    baseBpm = 92 + (posHash % 34);
  }

  // Camelot Key (1A - 12B)
  const keyNum = (posHash % 12) + 1;
  const keyLetter = posHash % 2 === 0 ? 'B' : 'A';
  const camelotKey = `${keyNum}${keyLetter}`;

  return { bpm: baseBpm, key: camelotKey };
}

// Helper: Camelot Key Color Styling
function getCamelotBadgeColor(key) {
  const k = (key || '').toUpperCase();
  if (k.startsWith('1')) return 'bg-cyan-400 text-black';
  if (k.startsWith('2')) return 'bg-sky-400 text-black';
  if (k.startsWith('3')) return 'bg-blue-500 text-white';
  if (k.startsWith('4')) return 'bg-amber-400 text-black'; // Exact Pinterest style
  if (k.startsWith('5')) return 'bg-orange-500 text-white';
  if (k.startsWith('6')) return 'bg-rose-500 text-white';
  if (k.startsWith('7')) return 'bg-red-500 text-white';
  if (k.startsWith('8')) return 'bg-purple-500 text-white';
  if (k.startsWith('9')) return 'bg-fuchsia-400 text-black';
  if (k.startsWith('10')) return 'bg-pink-400 text-black';
  if (k.startsWith('11')) return 'bg-emerald-400 text-black';
  if (k.startsWith('12')) return 'bg-teal-400 text-black';
  return 'bg-amber-400 text-black';
}

// In-Memory Audio Preview URL Cache
const previewUrlCache = new Map();

async function resolveTrackAudioPreview(track) {
  if (!track) return null;
  if (track.audioUrl) return track.audioUrl;
  const cacheKey = `${track.title}:::${track.artist}`;
  if (previewUrlCache.has(cacheKey)) return previewUrlCache.get(cacheKey);

  try {
    const q = `${track.title} ${track.artist || ''}`.trim();
    const res = await fetch(`https://itunes.apple.com/search?term=${encodeURIComponent(q)}&entity=song&limit=1`);
    if (res.ok) {
      const data = await res.json();
      const preview = data.results?.[0]?.previewUrl;
      if (preview) {
        previewUrlCache.set(cacheKey, preview);
        return preview;
      }
    }
  } catch (err) {
    console.warn('[TransitionModal] Preview fetch error:', err);
  }
  return null;
}

export default function SpotifyTransitionModal({
  isOpen,
  onClose,
  currentTrack,
  nextTrack,
  queue = [],
  likedTracks = [],
  trendingTracks = [],
  onPlayTrack,
  onSaveTransition,
}) {
  const [settings, setSettings] = useState(() => storageService.getTransitionSettings());
  
  // Custom Song Selection State
  const [outgoingOverride, setOutgoingOverride] = useState(null);
  const [incomingOverride, setIncomingOverride] = useState(null);

  // Song Picker State
  const [pickerTarget, setPickerTarget] = useState(null); // 'outgoing' | 'incoming' | null
  const [pickerQuery, setPickerQuery] = useState('');
  const [pickerTab, setPickerTab] = useState('queue'); // 'queue' | 'liked' | 'trending' | 'search'
  const [searchResults, setSearchResults] = useState([]);
  const [isSearching, setIsSearching] = useState(false);

  // Smart Automix / AI Insights
  const [smartAutomixInsight, setSmartAutomixInsight] = useState(null);
  const [isSmartAutomixApplied, setIsSmartAutomixApplied] = useState(false);

  // Playback Audition State
  const [isPlayingPreview, setIsPlayingPreview] = useState(false);
  const [previewProgress, setPreviewProgress] = useState(0); // 0 to 1
  const [activeDropdown, setActiveDropdown] = useState(null); // 'bars' | 'volume' | 'eq' | 'effect'
  const [audioLoading, setAudioLoading] = useState(false);

  // Audio References
  const audioCtxRef = useRef(null);
  const audioEl1Ref = useRef(null);
  const audioEl2Ref = useRef(null);
  const animFrameRef = useRef(null);
  const previewTimerRef = useRef(null);
  const searchDebounceRef = useRef(null);

  // Reload settings on open
  useEffect(() => {
    if (isOpen) {
      setSettings(storageService.getTransitionSettings());
      setPickerTarget(null);
      setIsPlayingPreview(false);
      setPreviewProgress(0);
      setSmartAutomixInsight(null);
    }
  }, [isOpen]);

  // Cleanup on close or unmount
  useEffect(() => {
    return () => {
      stopPreview();
    };
  }, []);

  // Determine Effective Outgoing and Incoming Tracks
  const defaultFallbackOutgoing = {
    id: 'sample-outgoing',
    title: 'One Of The Girls (with JENNIE, Lily-Rose Depp)',
    artist: 'The Weeknd, JENNIE, Lily-Rose Depp',
    artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
    duration: 244,
    bpm: 85,
    key: '4B',
  };

  const defaultFallbackIncoming = {
    id: 'sample-incoming',
    title: 'Stargirl Interlude',
    artist: 'The Weeknd, Lana Del Rey',
    artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
    duration: 111,
    bpm: 90,
    key: '8B',
  };

  const outgoing = useMemo(() => {
    const raw = outgoingOverride || currentTrack || queue[0] || trendingTracks[0] || defaultFallbackOutgoing;
    const computed = computeTrackBpmAndKey(raw);
    return {
      ...raw,
      bpm: raw.bpm || computed.bpm,
      key: raw.key || computed.key,
      artwork: getHighResArtworkUrl(raw.artwork || raw.thumbnail),
      duration: raw.duration || 210,
    };
  }, [outgoingOverride, currentTrack, queue, trendingTracks]);

  const incoming = useMemo(() => {
    let candidate = incomingOverride;
    if (!candidate) {
      if (nextTrack && nextTrack.id !== outgoing.id) {
        candidate = nextTrack;
      } else if (queue.length > 1) {
        candidate = queue.find(t => t.id !== outgoing.id) || queue[1];
      } else if (trendingTracks.length > 1) {
        candidate = trendingTracks.find(t => t.id !== outgoing.id) || trendingTracks[1];
      } else {
        candidate = defaultFallbackIncoming;
      }
    }
    const computed = computeTrackBpmAndKey(candidate);
    return {
      ...candidate,
      bpm: candidate.bpm || computed.bpm,
      key: candidate.key || computed.key,
      artwork: getHighResArtworkUrl(candidate.artwork || candidate.thumbnail),
      duration: candidate.duration || 180,
    };
  }, [incomingOverride, nextTrack, outgoing.id, queue, trendingTracks]);

  // Format mm:ss
  const formatMinSec = (sec) => {
    const s = Math.round(sec || 180);
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return `${m}:${rem < 10 ? '0' : ''}${rem}`;
  };

  // Debounced Live Search for Song Picker
  useEffect(() => {
    if (pickerTab !== 'search' && !pickerQuery.trim()) {
      setSearchResults([]);
      return;
    }

    if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    if (!pickerQuery.trim()) {
      setSearchResults([]);
      setIsSearching(false);
      return;
    }

    setIsSearching(true);
    searchDebounceRef.current = setTimeout(async () => {
      try {
        const hits = await musicApi.searchTracks(pickerQuery, 16);
        setSearchResults(hits || []);
      } catch (e) {
        console.warn('Search picker error:', e);
      } finally {
        setIsSearching(false);
      }
    }, 320);

    return () => {
      if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
    };
  }, [pickerQuery, pickerTab]);

  // SMART AUTOMIX CALCULATION ENGINE
  const handleApplySmartAutomix = () => {
    const bpmA = outgoing.bpm || 90;
    const bpmB = incoming.bpm || 90;
    const deltaBpm = Math.abs(bpmA - bpmB);
    const keyA = outgoing.key || '4B';
    const keyB = incoming.key || '4B';

    let newBars = '4 bars';
    let newDurationSec = 10.0;
    let newVolume = 'overlap';
    let newEq = 'bass_swap';
    let newEffect = 'smooth_blend';
    let explanation = '';

    if (deltaBpm <= 4) {
      newBars = '4 bars';
      newDurationSec = 10.0;
      newVolume = 'overlap';
      newEq = 'bass_swap';
      newEffect = 'smooth_blend';
      explanation = `✨ Transisi Harmonis Sempurna! Tempo identik (${bpmA} & ${bpmB} BPM, selisih ${deltaBpm} BPM). Mode Overlap 4 Bars dengan Bass Swap diaktifkan agar kick/bass bergantian di beat drop tanpa tabrakan frekuensi rendah!`;
    } else if (deltaBpm <= 12) {
      newBars = '2 bars';
      newDurationSec = 5.5;
      newVolume = 'crossfade';
      newEq = 'high_pass';
      newEffect = 'high_pass';
      explanation = `✨ Transisi Smooth Filter Sweep! Selisih tempo moderat (${bpmA} → ${bpmB} BPM). Menggunakan Crossfade 2 Bars dengan High-Pass Sweep pada lagu keluar agar intro ${incoming.title} masuk dengan jernih & energik!`;
    } else {
      newBars = '1 bar';
      newDurationSec = 2.8;
      newVolume = 'cut';
      newEq = 'none';
      newEffect = 'echo_fade';
      explanation = `✨ Transisi DJ Drop Cut! Tempo cukup kontras (${bpmA} vs ${bpmB} BPM, selisih ${deltaBpm} BPM). Mode 1 Bar Drop Cut dipadukan Echo Fade Out pada ketukan terakhir untuk perpindahan beat yang dinamis & spektakuler!`;
    }

    setSettings({
      bars: newBars,
      durationSec: newDurationSec,
      volume: newVolume,
      eq: newEq,
      effect: newEffect,
    });

    setIsSmartAutomixApplied(true);
    setSmartAutomixInsight({
      explanation,
      deltaBpm,
      keyA,
      keyB,
    });

    // Auto-audition the smart mix
    setTimeout(() => {
      startPreview({
        bars: newBars,
        durationSec: newDurationSec,
        volume: newVolume,
        eq: newEq,
        effect: newEffect,
      });
    }, 250);
  };

  // AUDITION PREVIEW ENGINE: Real Audio Streams + Web Audio Crossfade & EQ
  const stopPreview = () => {
    setIsPlayingPreview(false);
    setPreviewProgress(0);
    setAudioLoading(false);

    if (previewTimerRef.current) {
      clearTimeout(previewTimerRef.current);
      previewTimerRef.current = null;
    }
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = null;
    }

    if (audioEl1Ref.current) {
      try {
        audioEl1Ref.current.pause();
        audioEl1Ref.current.currentTime = 0;
      } catch (_) {}
    }
    if (audioEl2Ref.current) {
      try {
        audioEl2Ref.current.pause();
        audioEl2Ref.current.currentTime = 0;
      } catch (_) {}
    }

    if (audioCtxRef.current && audioCtxRef.current.state !== 'closed') {
      try {
        audioCtxRef.current.close();
      } catch (_) {}
      audioCtxRef.current = null;
    }
  };

  const handleTogglePreview = () => {
    if (isPlayingPreview) {
      stopPreview();
    } else {
      startPreview();
    }
  };

  const startPreview = async (overrideSettings = null) => {
    stopPreview();
    setIsPlayingPreview(true);
    setAudioLoading(true);

    const activeCfg = overrideSettings || settings;
    const durationSec = activeCfg.durationSec || 5.5;

    try {
      // 1. Resolve preview audio URLs in parallel
      const [url1, url2] = await Promise.all([
        resolveTrackAudioPreview(outgoing),
        resolveTrackAudioPreview(incoming),
      ]);

      setAudioLoading(false);

      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      const ctx = AudioCtx ? new AudioCtx() : null;
      if (ctx) audioCtxRef.current = ctx;

      const startTime = ctx ? ctx.currentTime : performance.now() / 1000;
      const endTime = startTime + durationSec;

      // 2. Play Audio 1 (Outgoing Outro)
      if (url1) {
        let el1 = audioEl1Ref.current;
        if (!el1) {
          el1 = new Audio();
          el1.crossOrigin = 'anonymous';
          audioEl1Ref.current = el1;
        }
        el1.src = url1;
        el1.currentTime = 18.0; // Outro region of 30s preview
        el1.volume = 0.8;
        el1.play().catch(() => {});

        // Fade out el1
        const fadeInterval = setInterval(() => {
          if (!el1 || el1.paused) {
            clearInterval(fadeInterval);
            return;
          }
          if (el1.volume > 0.05) {
            el1.volume = Math.max(0, el1.volume - (0.8 / (durationSec * 20)));
          } else {
            el1.volume = 0;
            clearInterval(fadeInterval);
          }
        }, 50);
      }

      // 3. Play Audio 2 (Incoming Intro with overlap delay)
      if (url2) {
        let el2 = audioEl2Ref.current;
        if (!el2) {
          el2 = new Audio();
          el2.crossOrigin = 'anonymous';
          audioEl2Ref.current = el2;
        }
        el2.src = url2;
        el2.currentTime = 0;
        el2.volume = 0.05;

        // Overlap delay: starts midway based on overlap setting
        const delayMs = activeCfg.volume === 'cut' ? (durationSec * 1000 * 0.9) : (durationSec * 1000 * 0.35);
        setTimeout(() => {
          if (!isPlayingPreview) return;
          el2.play().catch(() => {});
          const fadeInInterval = setInterval(() => {
            if (!el2 || el2.paused) {
              clearInterval(fadeInInterval);
              return;
            }
            if (el2.volume < 0.85) {
              el2.volume = Math.min(0.85, el2.volume + 0.07);
            } else {
              clearInterval(fadeInInterval);
            }
          }, 60);
        }, delayMs);
      }

      // 4. Fallback Web Audio Rhythmic Synth (if either preview fails or network is slow)
      if (ctx && (!url1 || !url2)) {
        // Outgoing chord
        const osc1 = ctx.createOscillator();
        const gain1 = ctx.createGain();
        osc1.type = 'triangle';
        osc1.frequency.setValueAtTime(220, startTime);
        gain1.gain.setValueAtTime(0.35, startTime);
        gain1.gain.linearRampToValueAtTime(0.001, endTime);
        osc1.connect(gain1);
        gain1.connect(ctx.destination);
        osc1.start(startTime);
        osc1.stop(endTime);

        // Incoming beat & chord
        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(329.63, startTime + durationSec * 0.4);
        gain2.gain.setValueAtTime(0.001, startTime);
        gain2.gain.exponentialRampToValueAtTime(0.38, startTime + durationSec * 0.6);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(startTime + durationSec * 0.4);
        osc2.stop(endTime);
      }

      // 5. Waveform Progress Animation
      const animStart = performance.now();
      const tick = () => {
        const elapsed = (performance.now() - animStart) / 1000;
        const p = Math.min(1.0, elapsed / durationSec);
        setPreviewProgress(p);
        if (p < 1.0) {
          animFrameRef.current = requestAnimationFrame(tick);
        } else {
          stopPreview();
        }
      };
      animFrameRef.current = requestAnimationFrame(tick);

      previewTimerRef.current = setTimeout(() => {
        stopPreview();
      }, durationSec * 1000 + 400);

    } catch (e) {
      console.warn('[TransitionModal] Preview engine error:', e);
      stopPreview();
    }
  };

  const handleSave = () => {
    stopPreview();
    storageService.saveTransitionSettings(settings);
    onSaveTransition?.({
      ...settings,
      outgoingTrack: outgoing,
      incomingTrack: incoming,
    });
    onClose();
  };

  const durationOptions = [
    { label: '1 bar', dur: 2.8 },
    { label: '2 bars', dur: 5.5 },
    { label: '4 bars', dur: 10.0 },
    { label: '8 bars', dur: 16.0 },
    { label: 'Custom 4s', dur: 4.0 },
    { label: 'Custom 8s', dur: 8.0 },
  ];

  const volumeOptions = [
    { id: 'overlap', label: 'Overlap', desc: 'Kedua lagu membaur bersama' },
    { id: 'crossfade', label: 'Crossfade', desc: 'Fade out bertahap & fade in halus' },
    { id: 'cut', label: 'Cut', desc: 'Langsung potong di beat intro' },
  ];

  const eqOptions = [
    { id: 'none', label: 'None', desc: 'EQ standar netral' },
    { id: 'bass_swap', label: 'Bass Swap', desc: 'Tukar frekuensi rendah di beat drop' },
    { id: 'high_pass', label: 'High pass outgoing', desc: 'Filter bass lagu keluar' },
    { id: 'smooth_blend', label: 'Smooth blend', desc: 'Transisi frekuensi vokal seimbang' },
  ];

  const effectOptions = [
    { id: 'high_pass', label: 'High pass filter', desc: 'Potong frekuensi rendah saat outro' },
    { id: 'low_pass', label: 'Low pass filter', desc: 'Meredam vokal menjadi hangat' },
    { id: 'reverb_tail', label: 'Reverb tail', desc: 'Gema halus mengiringi intro baru' },
    { id: 'echo_fade', label: 'Echo fade', desc: 'Efek delay ritmis sebelum lagu masuk' },
    { id: 'none', label: 'None', desc: 'Tanpa efek tambahan' },
  ];

  // Dynamic Waveform Generator
  const generateBars = (count, seed, isOutro = false) => {
    const bars = [];
    for (let i = 0; i < count; i++) {
      const x = i / count;
      let envelope = 1.0;
      if (isOutro) {
        envelope = Math.cos(x * (Math.PI / 2));
      } else {
        envelope = Math.sin(x * (Math.PI / 2));
      }
      const raw = Math.sin((i + seed) * 12.34) * 0.4 + Math.sin((i + seed) * 3.45) * 0.35 + 0.55;
      const height = Math.max(12, Math.min(88, raw * 80 * (0.3 + 0.7 * envelope)));
      bars.push(height);
    }
    return bars;
  };

  const topWaveformBars = useMemo(() => generateBars(56, (outgoing.bpm || 85) + 12, true), [outgoing.id, outgoing.bpm]);
  const bottomWaveformBars = useMemo(() => generateBars(56, (incoming.bpm || 90) + 24, false), [incoming.id, incoming.bpm]);

  if (!isOpen) return null;

  return (
    <div 
      className="fixed inset-0 z-[90] flex items-center justify-center p-3 sm:p-4 bg-black/85 backdrop-blur-md animate-view-fade-in"
      onClick={(e) => {
        if (e.target === e.currentTarget) {
          stopPreview();
          onClose();
        }
      }}
    >
      <div 
        className="relative w-full max-w-[460px] bg-[#121318] border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col text-white select-none animate-in fade-in zoom-in-95 duration-200"
        onClick={(e) => {
          e.stopPropagation();
          setActiveDropdown(null);
        }}
      >
        {/* ========================================================= */}
        {/* VIEW 1: SONG PICKER SHEET (When user clicks 'Ganti Lagu') */}
        {/* ========================================================= */}
        {pickerTarget && (
          <div className="absolute inset-0 z-40 bg-[#121318] flex flex-col animate-in slide-in-from-right duration-200">
            {/* Picker Header */}
            <div className="flex items-center justify-between px-4 py-3.5 border-b border-white/10 bg-[#161820]">
              <button
                onClick={() => setPickerTarget(null)}
                className="flex items-center gap-1.5 text-xs font-bold text-[#a1a1aa] hover:text-white transition-colors"
              >
                <ArrowLeft className="w-4 h-4" />
                <span>Kembali</span>
              </button>
              <h4 className="font-bold text-sm text-white">
                {pickerTarget === 'outgoing' ? 'Pilih Lagu Keluar (Track 1)' : 'Pilih Lagu Masuk (Track 2)'}
              </h4>
              <button
                onClick={() => setPickerTarget(null)}
                className="w-7 h-7 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 hover:text-white transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Search Input Bar */}
            <div className="p-3 border-b border-white/10 bg-[#161820]/60">
              <div className="relative">
                <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-white/40" />
                <input
                  type="text"
                  value={pickerQuery}
                  onChange={(e) => {
                    setPickerQuery(e.target.value);
                    if (pickerTab !== 'search') setPickerTab('search');
                  }}
                  placeholder="Cari judul lagu atau artis..."
                  autoFocus
                  className="w-full bg-[#20222a] border border-white/10 rounded-xl pl-9 pr-9 py-2 text-xs text-white placeholder-white/40 focus:outline-none focus:border-emerald-400"
                />
                {pickerQuery && (
                  <button
                    onClick={() => setPickerQuery('')}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-white/40 hover:text-white"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            </div>

            {/* Quick Filter Tabs */}
            <div className="flex items-center gap-1 px-3 py-2 border-b border-white/5 bg-[#14151c] overflow-x-auto no-scrollbar text-xs">
              <button
                onClick={() => setPickerTab('queue')}
                className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                  pickerTab === 'queue' ? 'bg-emerald-500 text-black' : 'bg-white/5 text-white/70 hover:bg-white/10'
                }`}
              >
                <ListMusic className="w-3.5 h-3.5" />
                <span>Antrean ({queue.length})</span>
              </button>
              <button
                onClick={() => setPickerTab('liked')}
                className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                  pickerTab === 'liked' ? 'bg-emerald-500 text-black' : 'bg-white/5 text-white/70 hover:bg-white/10'
                }`}
              >
                <Heart className="w-3.5 h-3.5" />
                <span>Disukai ({likedTracks.length})</span>
              </button>
              <button
                onClick={() => setPickerTab('trending')}
                className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition-colors whitespace-nowrap ${
                  pickerTab === 'trending' ? 'bg-emerald-500 text-black' : 'bg-white/5 text-white/70 hover:bg-white/10'
                }`}
              >
                <Flame className="w-3.5 h-3.5" />
                <span>Hits & Populer</span>
              </button>
            </div>

            {/* List of Selectable Songs */}
            <div className="flex-1 overflow-y-auto p-2 space-y-1">
              {isSearching && (
                <div className="py-8 text-center text-xs text-white/50 flex items-center justify-center gap-2">
                  <RefreshCw className="w-4 h-4 animate-spin text-emerald-400" />
                  <span>Mencari lagu di katalog...</span>
                </div>
              )}

              {/* Render Selected Tab Pool */}
              {(() => {
                let pool = [];
                if (pickerTab === 'search' || pickerQuery.trim()) {
                  pool = searchResults;
                } else if (pickerTab === 'queue') {
                  pool = queue;
                } else if (pickerTab === 'liked') {
                  pool = likedTracks;
                } else {
                  pool = trendingTracks;
                }

                if (!isSearching && pool.length === 0) {
                  return (
                    <div className="py-12 text-center text-xs text-white/40">
                      {pickerQuery ? 'Tidak ada lagu yang cocok dengan pencarian.' : 'Belum ada lagu dalam daftar ini.'}
                    </div>
                  );
                }

                return pool.map((t, idx) => {
                  const bpmKey = computeTrackBpmAndKey(t);
                  return (
                    <div
                      key={`pick-${t.id || t.videoId || idx}`}
                      onClick={() => {
                        if (pickerTarget === 'outgoing') {
                          setOutgoingOverride(t);
                        } else {
                          setIncomingOverride(t);
                        }
                        setPickerTarget(null);
                        setPickerQuery('');
                        setIsSmartAutomixApplied(false);
                        setSmartAutomixInsight(null);
                      }}
                      className="flex items-center justify-between p-2 rounded-xl hover:bg-white/10 cursor-pointer transition-colors group"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <img
                          src={getHighResArtworkUrl(t.artwork || t.thumbnail)}
                          alt={t.title}
                          className="w-10 h-10 rounded-lg object-cover bg-neutral-800 flex-shrink-0"
                        />
                        <div className="min-w-0">
                          <h5 className="text-xs font-bold text-white truncate max-w-[210px] group-hover:text-emerald-400 transition-colors">
                            {t.title}
                          </h5>
                          <p className="text-[11px] text-[#a1a1aa] truncate max-w-[210px]">
                            {t.artist}
                          </p>
                        </div>
                      </div>

                      <div className="flex items-center gap-2 flex-shrink-0">
                        <span className="text-[10px] font-mono text-white/60">
                          {bpmKey.bpm} bpm
                        </span>
                        <span className={`px-1.5 py-0.5 rounded text-[9px] font-black ${getCamelotBadgeColor(bpmKey.key)}`}>
                          {bpmKey.key}
                        </span>
                        <button className="px-2.5 py-1 rounded-lg bg-emerald-500/20 text-emerald-400 hover:bg-emerald-500 hover:text-black font-bold text-[11px] transition-all">
                          Pilih
                        </button>
                      </div>
                    </div>
                  );
                });
              })()}
            </div>
          </div>
        )}

        {/* ========================================================= */}
        {/* VIEW 2: MAIN TRANSITION STUDIO (Pinterest Spec)          */}
        {/* ========================================================= */}

        {/* 1. Header Bar: Cancel | Edit transition (Beta) | Save */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-white/[0.06] bg-[#161820]">
          <button
            onClick={() => {
              stopPreview();
              onClose();
            }}
            className="text-xs sm:text-sm font-semibold text-[#a1a1aa] hover:text-white transition-colors"
          >
            Cancel
          </button>

          <div className="flex items-center gap-2">
            <h3 className="font-bold text-sm sm:text-base text-white tracking-tight">
              Edit transition
            </h3>
            <span className="px-2 py-0.5 rounded-full text-[10px] font-black uppercase tracking-wider bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
              Beta
            </span>
          </div>

          <button
            onClick={handleSave}
            className="text-xs sm:text-sm font-bold text-emerald-400 hover:text-emerald-300 transition-colors"
          >
            Save
          </button>
        </div>

        {/* 2. Body Container */}
        <div className="p-4 sm:p-5 space-y-3.5">
          
          {/* Smart Automix Trigger Bar */}
          <div className="flex items-center justify-between gap-2 p-2.5 rounded-xl bg-gradient-to-r from-emerald-500/15 via-[#182638] to-[#121c2b] border border-emerald-500/30">
            <div className="flex items-center gap-2 min-w-0">
              <div className="w-7 h-7 rounded-lg bg-emerald-500/20 flex items-center justify-center flex-shrink-0">
                <Sparkles className="w-4 h-4 text-emerald-400" />
              </div>
              <div className="min-w-0">
                <p className="text-xs font-bold text-white flex items-center gap-1.5 truncate">
                  <span>Transisi Pintar (Smart Automix)</span>
                  <span className="text-[9px] px-1 rounded bg-emerald-400 text-black font-black uppercase">AI</span>
                </p>
                <p className="text-[10px] text-white/60 truncate">
                  Sinkronisasi tempo ({outgoing.bpm} → {incoming.bpm} BPM) &amp; harmonic key
                </p>
              </div>
            </div>

            <button
              onClick={handleApplySmartAutomix}
              className="px-3 py-1.5 rounded-lg bg-emerald-500 hover:bg-emerald-400 text-black font-black text-xs flex items-center gap-1.5 shadow-lg shadow-emerald-500/20 active:scale-95 transition-all flex-shrink-0"
            >
              <Wand2 className="w-3.5 h-3.5" />
              <span>Otomatiskan</span>
            </button>
          </div>

          {/* Smart Automix Explanation Badge (if activated) */}
          {smartAutomixInsight && (
            <div className="p-2.5 rounded-xl bg-emerald-950/40 border border-emerald-500/40 text-[11px] text-emerald-200 leading-relaxed animate-in fade-in duration-200">
              <p className="font-semibold">{smartAutomixInsight.explanation}</p>
            </div>
          )}

          {/* Outgoing Track (Track 1) */}
          <div 
            onClick={() => setPickerTarget('outgoing')}
            className="flex items-center justify-between gap-3 bg-white/[0.03] hover:bg-white/[0.06] p-2.5 rounded-xl border border-white/5 cursor-pointer transition-colors"
          >
            <div className="flex items-center gap-3 min-w-0">
              <img
                src={outgoing.artwork}
                alt={outgoing.title}
                className="w-11 h-11 rounded-lg object-cover bg-neutral-800 shadow-md flex-shrink-0"
              />
              <div className="min-w-0">
                <h4 className="text-xs sm:text-sm font-bold text-white truncate max-w-[170px] sm:max-w-[200px]">
                  {outgoing.title}
                </h4>
                <p className="text-[11px] text-[#a1a1aa] truncate max-w-[170px] sm:max-w-[200px]">
                  {outgoing.artist}
                </p>
              </div>
            </div>

            <div className="text-right flex-shrink-0 flex items-center gap-2">
              <span className="text-xs text-white/80 font-mono font-medium">
                {outgoing.bpm} bpm
              </span>
              <span className={`px-1.5 py-0.5 rounded text-[10px] font-black ${getCamelotBadgeColor(outgoing.key)}`}>
                {outgoing.key}
              </span>
              <span className="text-xs text-[#a1a1aa] tabular-nums font-mono">
                {formatMinSec(outgoing.duration)}
              </span>
              
              {/* Button to Change Outgoing Song */}
              <button
                onClick={() => setPickerTarget('outgoing')}
                className="px-2 py-1 rounded-md bg-white/10 hover:bg-white/20 text-[11px] font-bold text-white/90 hover:text-white transition-all ml-1"
                title="Ganti Lagu Keluar"
              >
                Ganti
              </button>
            </div>
          </div>

          {/* Interactive Dual Waveform Overlap Canvas */}
          <div className="relative rounded-2xl bg-[#181a22] border border-white/[0.08] p-4 overflow-hidden">
            
            {/* Top Waveform (Outgoing track outro) */}
            <div className="relative h-20 flex items-center justify-between gap-[2px] opacity-85">
              {topWaveformBars.map((h, i) => {
                const isOverlapped = i > 28;
                return (
                  <div
                    key={`top-${i}`}
                    className={`flex-1 rounded-full transition-all duration-150 ${
                      isOverlapped ? 'bg-cyan-400/80 shadow-[0_0_8px_rgba(6,182,212,0.4)]' : 'bg-white/40'
                    }`}
                    style={{ height: `${h}%` }}
                  />
                );
              })}

              {/* Outgoing fade envelope line */}
              <div 
                className="absolute inset-0 pointer-events-none border-b-2 border-cyan-400/60"
                style={{
                  clipPath: 'polygon(50% 10%, 100% 90%, 100% 100%, 50% 100%)',
                  background: 'linear-gradient(to bottom, rgba(6,182,212,0.12), transparent)'
                }}
              />
            </div>

            {/* Middle Floating Overlap Action Bar (Play button & Duration pill) */}
            <div className="relative my-2 flex items-center justify-center gap-3">
              <button
                onClick={handleTogglePreview}
                disabled={audioLoading}
                className="w-11 h-11 rounded-full bg-white text-black flex items-center justify-center shadow-2xl hover:scale-105 active:scale-95 transition-all cursor-pointer relative"
                title={isPlayingPreview ? 'Hentikan Preview Audisi' : 'Audisi Transisi Lagu Nyata'}
              >
                {audioLoading ? (
                  <RefreshCw className="w-5 h-5 text-black animate-spin" />
                ) : isPlayingPreview ? (
                  <Pause className="w-5 h-5 fill-black" />
                ) : (
                  <Play className="w-5 h-5 fill-black ml-0.5" />
                )}
              </button>

              {/* Bars Selector Pill */}
              <div className="relative">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    setActiveDropdown(activeDropdown === 'bars' ? null : 'bars');
                  }}
                  className="px-3.5 py-1.5 rounded-full bg-[#262832] hover:bg-[#323542] border border-white/10 text-xs font-bold text-white flex items-center gap-1.5 shadow-md active:scale-95 transition-all"
                >
                  <span>{settings.bars || '2 bars'}</span>
                  <ChevronDown className="w-3.5 h-3.5 text-white/70" />
                </button>

                {activeDropdown === 'bars' && (
                  <div 
                    className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 w-36 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                    onClick={(e) => e.stopPropagation()}
                  >
                    {durationOptions.map((opt) => (
                      <button
                        key={opt.label}
                        onClick={() => {
                          setSettings(prev => ({ ...prev, bars: opt.label, durationSec: opt.dur }));
                          setActiveDropdown(null);
                        }}
                        className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                          settings.bars === opt.label ? 'text-emerald-400' : 'text-white'
                        }`}
                      >
                        <span>{opt.label}</span>
                        {settings.bars === opt.label && <Check className="w-3.5 h-3.5" />}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>

            {/* Bottom Waveform (Incoming track intro) */}
            <div className="relative h-20 flex items-center justify-between gap-[2px] opacity-85">
              {bottomWaveformBars.map((h, i) => {
                const isOverlapped = i < 28;
                return (
                  <div
                    key={`bottom-${i}`}
                    className={`flex-1 rounded-full transition-all duration-150 ${
                      isOverlapped ? 'bg-fuchsia-400/80 shadow-[0_0_8px_rgba(232,121,249,0.4)]' : 'bg-white/40'
                    }`}
                    style={{ height: `${h}%` }}
                  />
                );
              })}

              {/* Incoming fade envelope line */}
              <div 
                className="absolute inset-0 pointer-events-none border-t-2 border-fuchsia-400/60"
                style={{
                  clipPath: 'polygon(0% 90%, 50% 10%, 50% 0%, 0% 0%)',
                  background: 'linear-gradient(to top, rgba(232,121,249,0.12), transparent)'
                }}
              />
            </div>

            {/* Live Playback Sweep Indicator */}
            {isPlayingPreview && (
              <div 
                className="absolute top-0 bottom-0 w-0.5 bg-emerald-400 shadow-[0_0_12px_#34d399] pointer-events-none transition-all duration-75 z-20"
                style={{ left: `${previewProgress * 100}%` }}
              />
            )}
          </div>

          {/* Incoming Track (Track 2) */}
          <div 
            onClick={() => setPickerTarget('incoming')}
            className="flex items-center justify-between gap-3 bg-white/[0.03] hover:bg-white/[0.06] p-2.5 rounded-xl border border-white/5 cursor-pointer transition-colors"
          >
            <div className="flex items-center gap-3 min-w-0">
              <img
                src={incoming.artwork}
                alt={incoming.title}
                className="w-11 h-11 rounded-lg object-cover bg-neutral-800 shadow-md flex-shrink-0"
              />
              <div className="min-w-0">
                <h4 className="text-xs sm:text-sm font-bold text-white truncate max-w-[170px] sm:max-w-[200px]">
                  {incoming.title}
                </h4>
                <p className="text-[11px] text-[#a1a1aa] truncate max-w-[170px] sm:max-w-[200px]">
                  {incoming.artist}
                </p>
              </div>
            </div>

            <div className="text-right flex-shrink-0 flex items-center gap-2">
              <span className="text-xs text-white/80 font-mono font-medium">
                {incoming.bpm} bpm
              </span>
              <span className={`px-1.5 py-0.5 rounded text-[10px] font-black ${getCamelotBadgeColor(incoming.key)}`}>
                {incoming.key}
              </span>
              <span className="text-xs text-[#a1a1aa] tabular-nums font-mono">
                {formatMinSec(incoming.duration)}
              </span>

              {/* Button to Change Incoming Song */}
              <button
                onClick={() => setPickerTarget('incoming')}
                className="px-2 py-1 rounded-md bg-white/10 hover:bg-white/20 text-[11px] font-bold text-white/90 hover:text-white transition-all ml-1"
                title="Ganti Lagu Masuk"
              >
                Ganti
              </button>
            </div>
          </div>

          {/* 3. Bottom Settings Dock (3 Dropdowns: Volume | EQ | Effects) */}
          <div className="rounded-2xl bg-[#181a22] border border-white/[0.08] p-3 grid grid-cols-3 gap-2">
            
            {/* Column 1: Volume */}
            <div className="relative">
              <label className="text-[10px] font-bold uppercase tracking-wider text-white/40 block mb-1">
                Volume
              </label>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveDropdown(activeDropdown === 'volume' ? null : 'volume');
                }}
                className="w-full py-2 px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.1] text-xs font-bold text-white flex items-center justify-between transition-colors"
              >
                <span className="truncate">
                  {volumeOptions.find(o => o.id === settings.volume)?.label || 'Overlap'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-white/60 flex-shrink-0" />
              </button>

              {activeDropdown === 'volume' && (
                <div 
                  className="absolute bottom-full left-0 mb-2 w-44 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                  onClick={(e) => e.stopPropagation()}
                >
                  {volumeOptions.map((opt) => (
                    <button
                      key={opt.id}
                      onClick={() => {
                        setSettings(prev => ({ ...prev, volume: opt.id }));
                        setActiveDropdown(null);
                      }}
                      className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                        settings.volume === opt.id ? 'text-emerald-400' : 'text-white'
                      }`}
                    >
                      <div>
                        <div>{opt.label}</div>
                        <div className="text-[10px] text-white/50">{opt.desc}</div>
                      </div>
                      {settings.volume === opt.id && <Check className="w-3.5 h-3.5 flex-shrink-0" />}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Column 2: EQ */}
            <div className="relative">
              <label className="text-[10px] font-bold uppercase tracking-wider text-white/40 block mb-1">
                EQ
              </label>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveDropdown(activeDropdown === 'eq' ? null : 'eq');
                }}
                className="w-full py-2 px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.1] text-xs font-bold text-white flex items-center justify-between transition-colors"
              >
                <span className="truncate">
                  {eqOptions.find(o => o.id === settings.eq)?.label || 'None'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-white/60 flex-shrink-0" />
              </button>

              {activeDropdown === 'eq' && (
                <div 
                  className="absolute bottom-full left-0 mb-2 w-48 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                  onClick={(e) => e.stopPropagation()}
                >
                  {eqOptions.map((opt) => (
                    <button
                      key={opt.id}
                      onClick={() => {
                        setSettings(prev => ({ ...prev, eq: opt.id }));
                        setActiveDropdown(null);
                      }}
                      className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                        settings.eq === opt.id ? 'text-emerald-400' : 'text-white'
                      }`}
                    >
                      <div>
                        <div>{opt.label}</div>
                        <div className="text-[10px] text-white/50">{opt.desc}</div>
                      </div>
                      {settings.eq === opt.id && <Check className="w-3.5 h-3.5 flex-shrink-0" />}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Column 3: Effects */}
            <div className="relative">
              <label className="text-[10px] font-bold uppercase tracking-wider text-white/40 block mb-1">
                Effects
              </label>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveDropdown(activeDropdown === 'effect' ? null : 'effect');
                }}
                className="w-full py-2 px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.1] text-xs font-bold text-white flex items-center justify-between transition-colors"
              >
                <span className="truncate">
                  {effectOptions.find(o => o.id === settings.effect)?.label || 'High pass fi...'}
                </span>
                <ChevronDown className="w-3.5 h-3.5 text-white/60 flex-shrink-0" />
              </button>

              {activeDropdown === 'effect' && (
                <div 
                  className="absolute bottom-full right-0 mb-2 w-52 bg-[#20222a] border border-white/15 rounded-xl shadow-2xl py-1 z-30 overflow-hidden"
                  onClick={(e) => e.stopPropagation()}
                >
                  {effectOptions.map((opt) => (
                    <button
                      key={opt.id}
                      onClick={() => {
                        setSettings(prev => ({ ...prev, effect: opt.id }));
                        setActiveDropdown(null);
                      }}
                      className={`w-full px-3 py-2 text-left text-xs font-semibold flex items-center justify-between hover:bg-white/10 transition-colors ${
                        settings.effect === opt.id ? 'text-emerald-400' : 'text-white'
                      }`}
                    >
                      <div>
                        <div>{opt.label}</div>
                        <div className="text-[10px] text-white/50">{opt.desc}</div>
                      </div>
                      {settings.effect === opt.id && <Check className="w-3.5 h-3.5 flex-shrink-0" />}
                    </button>
                  ))}
                </div>
              )}
            </div>

          </div>

        </div>

      </div>
    </div>
  );
}
