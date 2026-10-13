import React, { useState, useEffect, useRef } from 'react';
import { X, Sliders, RotateCcw, Volume2, Sparkles, Waves, Info } from 'lucide-react';
import { webAudioEqualizer, DEFAULT_EQ_SETTINGS } from '../services/webAudioEqualizer';

const PRESETS = [
  { name: 'Flat', bands: [0.0, 0.0, 0.0, 0.0, 0.0], bass: 0, virt: 0 },
  { name: 'Bass Boost', bands: [12.0, 7.5, 0.0, -2.0, -3.5], bass: 85, virt: 40 },
  { name: 'Vocal Booster', bands: [-4.0, 0.0, 8.0, 6.5, 2.0], bass: 15, virt: 25 },
  { name: 'Treble Booster', bands: [-4.5, -2.0, 1.5, 8.5, 12.0], bass: 10, virt: 35 },
  { name: 'Electronic', bands: [9.5, 5.5, -3.0, 5.0, 8.0], bass: 75, virt: 50 },
  { name: 'Rock', bands: [9.0, 4.5, -3.5, 5.5, 8.5], bass: 65, virt: 35 },
  { name: 'Pop', bands: [-2.0, 4.0, 7.5, 3.5, -2.5], bass: 40, virt: 30 },
  { name: 'Akustik', bands: [5.0, 3.0, 1.5, 5.0, 4.5], bass: 30, virt: 45 },
];

const BAND_LABELS = [
  { label: '60Hz', sub: 'Sub-bass' },
  { label: '230Hz', sub: 'Bass' },
  { label: '910Hz', sub: 'Mid' },
  { label: '3.6kHz', sub: 'Vocal' },
  { label: '14kHz', sub: 'Treble' },
];

const MIN_DB = -15;
const MAX_DB = 15;

/**
 * Custom Pointer-Driven Vertical Band Slider
 * Resolves all HTML5 CSS rotation bugs with fluid vertical tracking & bipolar zero fill.
 */
function VerticalBandSlider({ value, onChange, label, sub, disabled }) {
  const trackRef = useRef(null);
  const [isDragging, setIsDragging] = useState(false);

  // Position percentage: 0% at -15 dB, 50% at 0 dB, 100% at +15 dB
  const clampedVal = Math.max(MIN_DB, Math.min(MAX_DB, value));
  const percent = ((clampedVal - MIN_DB) / (MAX_DB - MIN_DB)) * 100;
  const zeroPercent = 50;

  const handlePointer = (e) => {
    if (disabled || !trackRef.current) return;
    const rect = trackRef.current.getBoundingClientRect();
    // Invert Y so top is max and bottom is min
    const ratio = Math.max(0, Math.min(1, 1 - (e.clientY - rect.top) / rect.height));
    const rawVal = MIN_DB + ratio * (MAX_DB - MIN_DB);

    // Snap to 0 dB within ±0.6 dB for easy centering
    let snappedVal;
    if (Math.abs(rawVal) < 0.6) {
      snappedVal = 0.0;
    } else {
      snappedVal = Math.round(rawVal * 2) / 2; // 0.5 dB step
    }
    onChange(snappedVal);
  };

  const onPointerDown = (e) => {
    if (disabled) return;
    e.preventDefault();
    setIsDragging(true);
    e.currentTarget.setPointerCapture(e.pointerId);
    handlePointer(e);
  };

  const onPointerMove = (e) => {
    if (!isDragging) return;
    handlePointer(e);
  };

  const onPointerUp = (e) => {
    if (!isDragging) return;
    setIsDragging(false);
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch (_) {}
  };

  const onDoubleClick = () => {
    if (disabled) return;
    onChange(0.0);
  };

  // Bipolar Fill calculations
  const isPositive = clampedVal >= 0;
  const fillBottom = isPositive ? zeroPercent : percent;
  const fillHeight = isPositive ? (percent - zeroPercent) : (zeroPercent - percent);

  return (
    <div className={`flex flex-col items-center gap-2 w-full select-none ${disabled ? 'opacity-35 pointer-events-none' : ''}`}>
      {/* dB Badge Indicator */}
      <button
        type="button"
        onClick={onDoubleClick}
        title="Klik 2x untuk reset ke 0 dB"
        className={`text-[11px] font-mono font-bold px-2 py-0.5 rounded cursor-pointer transition-all ${
          clampedVal > 0 
            ? 'text-[#00a3ff] bg-[#00a3ff]/20 border border-[#00a3ff]/40 shadow-sm shadow-[#00a3ff]/20' 
            : clampedVal < 0 
            ? 'text-cyan-300 bg-cyan-950/40 border border-cyan-800/30' 
            : 'text-white/60 bg-white/5 border border-white/5'
        }`}
      >
        {clampedVal > 0 ? `+${clampedVal.toFixed(1)}` : clampedVal.toFixed(1)} dB
      </button>

      {/* Vertical Interactive Track Container */}
      <div
        ref={trackRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onDoubleClick={onDoubleClick}
        className="h-36 w-11 flex items-center justify-center cursor-pointer relative group touch-none select-none py-2"
        title="Geser vertikal untuk menyesuaikan desibel. Klik 2x untuk 0 dB."
      >
        {/* Background Rail */}
        <div className="w-2.5 h-full bg-[#202020] group-hover:bg-[#282828] rounded-full relative overflow-hidden transition-colors border border-white/10 shadow-inner">
          {/* Bipolar Dynamic Fill Bar */}
          <div
            className={`absolute left-0 right-0 rounded-full transition-all ${
              clampedVal > 0 
                ? 'bg-gradient-to-t from-[#0088cc] to-[#00a3ff] shadow-[0_0_10px_#00a3ff]' 
                : 'bg-gradient-to-b from-[#0088cc] to-[#005588]'
            }`}
            style={{
              bottom: `${fillBottom}%`,
              height: `${Math.max(2, fillHeight)}%`,
            }}
          />
          {/* Center 0 dB Divider Tick */}
          <div className="absolute top-1/2 left-0 right-0 h-[2px] bg-white/50 -translate-y-1/2 z-10" />
        </div>

        {/* 0 dB Alignment Guides */}
        <div className="absolute top-1/2 left-0.5 w-1.5 h-[1px] bg-white/30 pointer-events-none" />
        <div className="absolute top-1/2 right-0.5 w-1.5 h-[1px] bg-white/30 pointer-events-none" />

        {/* Draggable Glowing Thumb */}
        <div
          className={`absolute w-5 h-5 rounded-full bg-white border-2 border-[#00a3ff] shadow-[0_0_12px_rgba(0,163,255,0.85)] pointer-events-none transition-transform ${
            isDragging ? 'scale-125' : 'group-hover:scale-110'
          }`}
          style={{
            bottom: `calc(${percent}% - 10px)`,
          }}
        />
      </div>

      {/* Frequency Labels */}
      <div className="text-center">
        <div className="text-xs font-bold text-white tracking-tight">{label}</div>
        <div className="text-[10px] text-[#888] font-medium">{sub}</div>
      </div>
    </div>
  );
}

export default function EqualizerModal({ isOpen, onClose }) {
  const [settings, setSettings] = useState(() => webAudioEqualizer.loadSettings());

  // Subscribe to equalizer changes
  useEffect(() => {
    return webAudioEqualizer.subscribe((updated) => {
      setSettings(updated);
    });
  }, []);

  const handleToggleEnabled = () => {
    const updated = { ...settings, isEnabled: !settings.isEnabled };
    setSettings(updated);
    webAudioEqualizer.applySettings(updated);
  };

  const handleSelectPreset = (preset) => {
    const updated = {
      ...settings,
      selectedPreset: preset.name,
      bands: [...preset.bands],
      bassBoost: preset.bass,
      virtualizer: preset.virt,
    };
    setSettings(updated);
    webAudioEqualizer.applySettings(updated);
  };

  const handleBandChange = (index, value) => {
    const nextBands = [...settings.bands];
    nextBands[index] = value;
    const updated = {
      ...settings,
      selectedPreset: 'Kustom',
      bands: nextBands,
    };
    setSettings(updated);
    webAudioEqualizer.applySettings(updated);
  };

  const handleBassChange = (e) => {
    const val = parseInt(e.target.value, 10);
    const updated = { ...settings, bassBoost: val };
    setSettings(updated);
    webAudioEqualizer.applySettings(updated);
  };

  const handleVirtChange = (e) => {
    const val = parseInt(e.target.value, 10);
    const updated = { ...settings, virtualizer: val };
    setSettings(updated);
    webAudioEqualizer.applySettings(updated);
  };

  const handleReset = () => {
    const flat = PRESETS[0];
    const updated = {
      isEnabled: true,
      selectedPreset: 'Flat',
      bands: [...flat.bands],
      bassBoost: 0,
      virtualizer: 0,
    };
    setSettings(updated);
    webAudioEqualizer.applySettings(updated);
  };

  if (!isOpen) return null;

  return (
    <div 
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200 select-none"
      onClick={onClose}
    >
      <div 
        className="w-full max-w-xl bg-[#141414] border border-white/10 rounded-2xl p-6 sm:p-7 shadow-2xl relative space-y-5 text-white"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between pb-3 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#00a3ff]/20 border border-[#00a3ff]/40 flex items-center justify-center text-[#00a3ff] shadow-lg shadow-[#00a3ff]/20">
              <Sliders className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg sm:text-xl font-bold tracking-tight">
                Equalizer & Audio Master
              </h3>
              <p className="text-xs text-[#b3b3b3]">
                Kustomisasi kurva frekuensi dan profil akustik suara
              </p>
            </div>
          </div>
          
          <div className="flex items-center gap-2">
            <button
              onClick={handleReset}
              className="px-3 py-1.5 rounded-lg text-xs font-semibold text-[#b3b3b3] hover:text-[#00a3ff] hover:bg-white/5 transition-colors flex items-center gap-1.5"
              title="Reset ke Flat"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              <span>Reset</span>
            </button>
            <button
              onClick={onClose}
              className="p-1.5 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Master Switch Card */}
        <div className="flex items-center justify-between p-3.5 bg-white/5 rounded-xl border border-white/5">
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-lg transition-colors ${settings.isEnabled ? 'bg-[#00a3ff]/20 text-[#00a3ff]' : 'bg-white/5 text-[#666]'}`}>
              <Waves className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-bold">Aktifkan Equalizer</div>
              <div className="text-xs text-[#b3b3b3]">
                {settings.isEnabled ? `Preset aktif: ${settings.selectedPreset}` : 'Nonaktif (Profil Audio Datar)'}
              </div>
            </div>
          </div>
          <button
            onClick={handleToggleEnabled}
            className={`w-12 h-6.5 rounded-full transition-colors relative flex items-center p-0.5 cursor-pointer ${
              settings.isEnabled ? 'bg-[#00a3ff]' : 'bg-[#333]'
            }`}
          >
            <div 
              className={`w-5 h-5 rounded-full bg-white shadow-md transition-transform ${
                settings.isEnabled ? 'translate-x-5.5' : 'translate-x-0'
              }`}
            />
          </button>
        </div>

        {/* Preset Selector Chips */}
        <div>
          <div className="text-xs font-semibold text-[#b3b3b3] uppercase tracking-wider mb-2.5 flex items-center gap-1.5">
            <Sparkles className="w-3.5 h-3.5 text-[#00a3ff]" />
            <span>Preset Akustik</span>
          </div>
          <div className="flex flex-wrap gap-2">
            {PRESETS.map((p) => {
              const isActive = settings.isEnabled && settings.selectedPreset === p.name;
              return (
                <button
                  key={p.name}
                  onClick={() => handleSelectPreset(p)}
                  disabled={!settings.isEnabled}
                  className={`px-3 py-1.5 rounded-full text-xs font-semibold transition-all cursor-pointer ${
                    isActive
                      ? 'bg-[#00a3ff] text-black shadow-lg shadow-[#00a3ff]/25 scale-105'
                      : settings.isEnabled
                      ? 'bg-white/5 hover:bg-white/10 text-white/90 border border-white/5'
                      : 'bg-white/5 text-white/30 cursor-not-allowed'
                  }`}
                >
                  {p.name}
                </button>
              );
            })}
            {settings.selectedPreset === 'Kustom' && (
              <span className="px-3 py-1.5 rounded-full text-xs font-semibold bg-[#00a3ff]/20 text-[#00a3ff] border border-[#00a3ff]/30">
                Kustom
              </span>
            )}
          </div>
        </div>

        {/* 5-Band Vertical Equalizer Section */}
        <div className={`p-4 bg-white/5 rounded-xl border border-white/5 transition-opacity ${settings.isEnabled ? 'opacity-100' : 'opacity-40 pointer-events-none'}`}>
          <div className="flex justify-between items-center mb-3">
            <span className="text-xs font-semibold text-[#b3b3b3] uppercase tracking-wider">
              Frekuensi Grafis (5-Band)
            </span>
            <span className="text-[11px] text-[#00a3ff] font-medium flex items-center gap-1">
              <Info className="w-3 h-3" />
              <span>Rentang -15 dB s/d +15 dB (Klik 2x untuk 0 dB)</span>
            </span>
          </div>

          <div className="grid grid-cols-5 gap-2 sm:gap-4 items-center justify-items-center pt-1">
            {settings.bands.map((val, idx) => (
              <VerticalBandSlider
                key={BAND_LABELS[idx].label}
                value={val}
                onChange={(newVal) => handleBandChange(idx, newVal)}
                label={BAND_LABELS[idx].label}
                sub={BAND_LABELS[idx].sub}
                disabled={!settings.isEnabled}
              />
            ))}
          </div>
        </div>

        {/* Sound FX: Bass Boost & 3D Surround */}
        <div className={`grid grid-cols-1 sm:grid-cols-2 gap-3 transition-opacity ${settings.isEnabled ? 'opacity-100' : 'opacity-40 pointer-events-none'}`}>
          {/* Bass Boost */}
          <div className="p-3.5 bg-white/5 rounded-xl border border-white/5 space-y-2">
            <div className="flex justify-between items-center text-xs">
              <span className="font-semibold text-white flex items-center gap-1.5">
                <Volume2 className="w-3.5 h-3.5 text-[#00a3ff]" />
                <span>Bass Boost</span>
              </span>
              <span className="font-mono text-[#00a3ff] font-bold">{settings.bassBoost}%</span>
            </div>
            <div className="relative flex items-center">
              <input
                type="range"
                min="0"
                max="100"
                value={settings.bassBoost}
                onChange={handleBassChange}
                disabled={!settings.isEnabled}
                className="w-full h-2 bg-[#202020] rounded-lg appearance-none cursor-pointer accent-[#00a3ff]"
              />
            </div>
          </div>

          {/* 3D Virtualizer / Surround */}
          <div className="p-3.5 bg-white/5 rounded-xl border border-white/5 space-y-2">
            <div className="flex justify-between items-center text-xs">
              <span className="font-semibold text-white flex items-center gap-1.5">
                <Waves className="w-3.5 h-3.5 text-[#00a3ff]" />
                <span>3D Surround</span>
              </span>
              <span className="font-mono text-[#00a3ff] font-bold">{settings.virtualizer}%</span>
            </div>
            <div className="relative flex items-center">
              <input
                type="range"
                min="0"
                max="100"
                value={settings.virtualizer}
                onChange={handleVirtChange}
                disabled={!settings.isEnabled}
                className="w-full h-2 bg-[#202020] rounded-lg appearance-none cursor-pointer accent-[#00a3ff]"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
