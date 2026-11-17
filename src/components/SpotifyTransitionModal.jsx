import React, { useState, useEffect, useRef } from 'react';
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
  Wand2
} from 'lucide-react';
import { storageService } from '../services/storageService';

export default function SpotifyTransitionModal({
  isOpen,
  onClose,
  currentTrack,
  nextTrack,
  onSaveTransition,
}) {
  const [settings, setSettings] = useState(() => storageService.getTransitionSettings());
  const [isPlayingPreview, setIsPlayingPreview] = useState(false);
  const [previewProgress, setPreviewProgress] = useState(0); // 0 to 1
  const [activeDropdown, setActiveDropdown] = useState(null); // 'bars' | 'volume' | 'eq' | 'effect'
  const audioCtxRef = useRef(null);
  const animFrameRef = useRef(null);
  const previewTimerRef = useRef(null);

  useEffect(() => {
    setSettings(storageService.getTransitionSettings());
  }, [isOpen]);

  // Clean up audio on close or unmount
  useEffect(() => {
    return () => {
      stopPreview();
    };
  }, []);

  if (!isOpen) return null;

  // Fallback track metadata
  const outgoing = currentTrack || {
    title: 'One Of The Girls (with JENNIE, Lily-Rose Depp)',
    artist: 'The Weeknd, JENNIE, Lily-Rose Depp',
    artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
    duration: 244,
    bpm: 85,
    key: '4B',
  };

  const incoming = nextTrack || {
    title: 'Stargirl Interlude',
    artist: 'The Weeknd, Lana Del Rey',
    artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
    duration: 111,
    bpm: 90,
    key: '8B',
  };

  const formatMinSec = (sec) => {
    const s = Math.round(sec || 180);
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return `${m}:${rem < 10 ? '0' : ''}${rem}`;
  };

  // Preview Web Audio Simulation: Plays realistic crossfade audio preview
  const handleTogglePreview = () => {
    if (isPlayingPreview) {
      stopPreview();
    } else {
      startPreview();
    }
  };

  const stopPreview = () => {
    setIsPlayingPreview(false);
    setPreviewProgress(0);
    if (previewTimerRef.current) {
      clearTimeout(previewTimerRef.current);
      previewTimerRef.current = null;
    }
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = null;
    }
    if (audioCtxRef.current && audioCtxRef.current.state !== 'closed') {
      try {
        audioCtxRef.current.close();
      } catch (_) {}
      audioCtxRef.current = null;
    }
  };

  const startPreview = async () => {
    stopPreview();
    setIsPlayingPreview(true);

    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      const ctx = new AudioCtx();
      audioCtxRef.current = ctx;

      const durationSec = settings.durationSec || 5.0;
      const startTime = ctx.currentTime;
      const endTime = startTime + durationSec;

      // 1. Outgoing Track Synth Sim (mellow chords fading out)
      const osc1 = ctx.createOscillator();
      const gain1 = ctx.createGain();
      const filter1 = ctx.createBiquadFilter();

      osc1.type = 'triangle';
      osc1.frequency.setValueAtTime(220, startTime);
      osc1.frequency.exponentialRampToValueAtTime(164.81, startTime + durationSec * 0.7);

      if (settings.effect === 'high_pass') {
        filter1.type = 'highpass';
        filter1.frequency.setValueAtTime(80, startTime);
        filter1.frequency.exponentialRampToValueAtTime(2400, endTime);
      } else if (settings.effect === 'low_pass') {
        filter1.type = 'lowpass';
        filter1.frequency.setValueAtTime(3000, startTime);
        filter1.frequency.exponentialRampToValueAtTime(300, endTime);
      } else {
        filter1.type = 'allpass';
      }

      // Outgoing fade out
      gain1.gain.setValueAtTime(0.35, startTime);
      gain1.gain.linearRampToValueAtTime(0.001, endTime);

      osc1.connect(filter1);
      filter1.connect(gain1);
      gain1.connect(ctx.destination);
      osc1.start(startTime);
      osc1.stop(endTime);

      // 2. Incoming Track Synth Sim (rhythmic beat & chord fading in)
      const osc2 = ctx.createOscillator();
      const gain2 = ctx.createGain();
      const filter2 = ctx.createBiquadFilter();

      osc2.type = 'sine';
      osc2.frequency.setValueAtTime(329.63, startTime);
      osc2.frequency.setValueAtTime(392.00, startTime + durationSec * 0.4);

      if (settings.eq === 'bass_swap') {
        filter2.type = 'lowshelf';
        filter2.frequency.value = 250;
        filter2.gain.setValueAtTime(6.0, startTime + durationSec * 0.4);
      } else {
        filter2.type = 'allpass';
      }

      // Incoming fade in
      gain2.gain.setValueAtTime(0.001, startTime);
      gain2.gain.exponentialRampToValueAtTime(0.38, startTime + durationSec * 0.6);
      gain2.gain.linearRampToValueAtTime(0.35, endTime);

      osc2.connect(filter2);
      filter2.connect(gain2);
      gain2.connect(ctx.destination);
      osc2.start(startTime);
      osc2.stop(endTime);

      // Animate progress bar across transition window
      const animStart = performance.now();
      const tick = () => {
        const elapsed = (performance.now() - animStart) / 1000;
        const p = Math.min(1.0, elapsed / durationSec);
        setPreviewProgress(p);
        if (p < 1.0) {
          animFrameRef.current = requestAnimationFrame(tick);
        } else {
          setIsPlayingPreview(false);
          setPreviewProgress(0);
        }
      };
      animFrameRef.current = requestAnimationFrame(tick);

      previewTimerRef.current = setTimeout(() => {
        stopPreview();
      }, durationSec * 1000);
    } catch (e) {
      console.warn('Audio preview error:', e);
      setIsPlayingPreview(false);
    }
  };

  const handleSave = () => {
    stopPreview();
    storageService.saveTransitionSettings(settings);
    onSaveTransition?.(settings);
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

  // Generate deterministic realistic audio waveform bars
  const generateBars = (count, seed, outro = false) => {
    const bars = [];
    for (let i = 0; i < count; i++) {
      const x = i / count;
      let envelope = 1.0;
      if (outro) {
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

  const topWaveformBars = generateBars(56, 17, true);
  const bottomWaveformBars = generateBars(56, 42, false);

  return (
    <div 
      className="fixed inset-0 z-[90] flex items-center justify-center p-3 sm:p-4 bg-black/80 backdrop-blur-md animate-view-fade-in"
      onClick={(e) => {
        if (e.target === e.currentTarget) {
          stopPreview();
          onClose();
        }
      }}
    >
      <div 
        className="relative w-full max-w-[440px] bg-[#121318] border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col text-white select-none animate-in fade-in zoom-in-95 duration-200"
        onClick={(e) => {
          e.stopPropagation();
          setActiveDropdown(null);
        }}
      >
        {/* 1. Header Bar: Cancel | Edit transition (Beta) | Save */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/[0.06] bg-[#161820]">
          <button
            onClick={() => {
              stopPreview();
              onClose();
            }}
            className="text-sm font-semibold text-[#a1a1aa] hover:text-white transition-colors"
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
            className="text-sm font-bold text-emerald-400 hover:text-emerald-300 transition-colors"
          >
            Save
          </button>
        </div>

        {/* 2. Body Container */}
        <div className="p-4 sm:p-5 space-y-4">
          
          {/* Outgoing Track (Track 1) */}
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <img
                src={outgoing.artwork || 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400'}
                alt={outgoing.title}
                className="w-11 h-11 rounded-lg object-cover bg-neutral-800 shadow-md flex-shrink-0"
              />
              <div className="min-w-0">
                <h4 className="text-sm font-bold text-white truncate max-w-[190px] sm:max-w-[210px]">
                  {outgoing.title}
                </h4>
                <p className="text-xs text-[#a1a1aa] truncate max-w-[190px] sm:max-w-[210px]">
                  {outgoing.artist}
                </p>
              </div>
            </div>

            <div className="text-right flex-shrink-0 flex items-center gap-2">
              <span className="text-xs text-white/80 font-mono font-medium">
                {outgoing.bpm || 85} bpm
              </span>
              <span className="px-1.5 py-0.5 rounded text-[10px] font-black bg-amber-400 text-black">
                {outgoing.key || '4B'}
              </span>
              <span className="text-xs text-[#a1a1aa] tabular-nums font-mono">
                {formatMinSec(outgoing.duration)}
              </span>
            </div>
          </div>

          {/* Interactive Dual Waveform Overlap Canvas */}
          <div className="relative rounded-2xl bg-[#181a22] border border-white/[0.08] p-4 overflow-hidden">
            
            {/* Top Waveform (Outgoing track outro) */}
            <div className="relative h-20 flex items-center justify-between gap-[2px] opacity-80">
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
                className="w-10 h-10 rounded-full bg-white text-black flex items-center justify-center shadow-xl hover:scale-105 active:scale-95 transition-all cursor-pointer"
                title={isPlayingPreview ? 'Hentikan Preview' : 'Audisi Transisi Lagu'}
              >
                {isPlayingPreview ? (
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
            <div className="relative h-20 flex items-center justify-between gap-[2px] opacity-80">
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
                className="absolute top-0 bottom-0 w-0.5 bg-emerald-400 shadow-[0_0_12px_#34d399] pointer-events-none transition-all duration-75"
                style={{ left: `${previewProgress * 100}%` }}
              />
            )}
          </div>

          {/* Incoming Track (Track 2) */}
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <img
                src={incoming.artwork || 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400'}
                alt={incoming.title}
                className="w-11 h-11 rounded-lg object-cover bg-neutral-800 shadow-md flex-shrink-0"
              />
              <div className="min-w-0">
                <h4 className="text-sm font-bold text-white truncate max-w-[190px] sm:max-w-[210px]">
                  {incoming.title}
                </h4>
                <p className="text-xs text-[#a1a1aa] truncate max-w-[190px] sm:max-w-[210px]">
                  {incoming.artist}
                </p>
              </div>
            </div>

            <div className="text-right flex-shrink-0 flex items-center gap-2">
              <span className="text-xs text-white/80 font-mono font-medium">
                {incoming.bpm || 90} bpm
              </span>
              <span className="text-xs text-[#a1a1aa] tabular-nums font-mono">
                {formatMinSec(incoming.duration)}
              </span>
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
