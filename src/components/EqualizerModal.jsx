import React, { useState, useEffect } from 'react';
import { X, Sliders, RotateCcw, Volume2, Sparkles, Waves } from 'lucide-react';

const PRESETS = [
  { name: 'Flat', bands: [0.0, 0.0, 0.0, 0.0, 0.0], bass: 0, virt: 0 },
  { name: 'Bass Boost', bands: [7.5, 4.5, 0.0, -1.0, -2.0], bass: 70, virt: 30 },
  { name: 'Vocal Booster', bands: [-2.0, 1.0, 5.0, 4.0, 1.5], bass: 10, virt: 20 },
  { name: 'Treble Booster', bands: [-2.5, -1.0, 1.0, 5.5, 7.0], bass: 15, virt: 25 },
  { name: 'Electronic', bands: [5.0, 3.5, -1.5, 3.0, 4.5], bass: 60, virt: 40 },
  { name: 'Rock', bands: [6.0, 3.0, -2.0, 3.5, 5.5], bass: 50, virt: 30 },
  { name: 'Pop', bands: [-1.0, 2.5, 5.0, 2.0, -1.5], bass: 35, virt: 25 },
  { name: 'Akustik', bands: [3.5, 2.0, 1.0, 3.5, 3.0], bass: 20, virt: 35 },
];

const BAND_LABELS = [
  { label: '60Hz', sub: 'Sub-bass' },
  { label: '230Hz', sub: 'Bass' },
  { label: '910Hz', sub: 'Mid' },
  { label: '3.6kHz', sub: 'Vocal' },
  { label: '14kHz', sub: 'Treble' },
];

const STORAGE_KEY = 'mcmusic_web_equalizer_v1';

export default function EqualizerModal({ isOpen, onClose }) {
  const [isEnabled, setIsEnabled] = useState(true);
  const [selectedPreset, setSelectedPreset] = useState('Bass Boost');
  const [bands, setBands] = useState([7.5, 4.5, 0.0, -1.0, -2.0]);
  const [bassBoost, setBassBoost] = useState(65);
  const [virtualizer, setVirtualizer] = useState(30);

  // Load saved settings from localStorage
  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const parsed = JSON.parse(saved);
        if (parsed) {
          setIsEnabled(parsed.isEnabled ?? true);
          setSelectedPreset(parsed.selectedPreset ?? 'Bass Boost');
          if (Array.isArray(parsed.bands) && parsed.bands.length === 5) {
            setBands(parsed.bands);
          }
          setBassBoost(parsed.bassBoost ?? 65);
          setVirtualizer(parsed.virtualizer ?? 30);
        }
      }
    } catch (_) {}
  }, []);

  // Save settings on change
  const saveSettings = (newEnabled, newPreset, newBands, newBass, newVirt) => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({
        isEnabled: newEnabled,
        selectedPreset: newPreset,
        bands: newBands,
        bassBoost: newBass,
        virtualizer: newVirt,
      }));
    } catch (_) {}
  };

  const handleToggleEnabled = () => {
    const next = !isEnabled;
    setIsEnabled(next);
    saveSettings(next, selectedPreset, bands, bassBoost, virtualizer);
  };

  const handleSelectPreset = (preset) => {
    setSelectedPreset(preset.name);
    setBands([...preset.bands]);
    setBassBoost(preset.bass);
    setVirtualizer(preset.virt);
    saveSettings(isEnabled, preset.name, preset.bands, preset.bass, preset.virt);
  };

  const handleBandChange = (index, value) => {
    const nextBands = [...bands];
    nextBands[index] = parseFloat(value);
    setBands(nextBands);
    setSelectedPreset('Kustom');
    saveSettings(isEnabled, 'Kustom', nextBands, bassBoost, virtualizer);
  };

  const handleBassChange = (value) => {
    const num = parseInt(value, 10);
    setBassBoost(num);
    saveSettings(isEnabled, selectedPreset, bands, num, virtualizer);
  };

  const handleVirtChange = (value) => {
    const num = parseInt(value, 10);
    setVirtualizer(num);
    saveSettings(isEnabled, selectedPreset, bands, bassBoost, num);
  };

  const handleReset = () => {
    const flat = PRESETS[0];
    setIsEnabled(true);
    setSelectedPreset('Flat');
    setBands([...flat.bands]);
    setBassBoost(0);
    setVirtualizer(0);
    saveSettings(true, 'Flat', flat.bands, 0, 0);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200 select-none">
      <div 
        className="w-full max-w-xl bg-[#141414] border border-white/10 rounded-2xl p-6 sm:p-7 shadow-2xl relative space-y-5 text-white"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between pb-3 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#00a3ff]/20 border border-[#00a3ff]/40 flex items-center justify-center text-[#00a3ff]">
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
            <div className={`p-2 rounded-lg transition-colors ${isEnabled ? 'bg-[#00a3ff]/20 text-[#00a3ff]' : 'bg-white/5 text-[#666]'}`}>
              <Waves className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-bold">Aktifkan Equalizer</div>
              <div className="text-xs text-[#b3b3b3]">
                {isEnabled ? `Preset aktif: ${selectedPreset}` : 'Nonaktif (Profil Audio Datar)'}
              </div>
            </div>
          </div>
          <button
            onClick={handleToggleEnabled}
            className={`w-12 h-6.5 rounded-full transition-colors relative flex items-center p-0.5 ${
              isEnabled ? 'bg-[#00a3ff]' : 'bg-[#333]'
            }`}
          >
            <div 
              className={`w-5 h-5 rounded-full bg-white shadow-md transition-transform ${
                isEnabled ? 'translate-x-5.5' : 'translate-x-0'
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
              const isActive = isEnabled && selectedPreset === p.name;
              return (
                <button
                  key={p.name}
                  onClick={() => handleSelectPreset(p)}
                  disabled={!isEnabled}
                  className={`px-3 py-1.5 rounded-full text-xs font-semibold transition-all ${
                    isActive
                      ? 'bg-[#00a3ff] text-black shadow-lg shadow-[#00a3ff]/25 scale-105'
                      : isEnabled
                      ? 'bg-white/5 hover:bg-white/10 text-white/90 border border-white/5'
                      : 'bg-white/5 text-white/30 cursor-not-allowed'
                  }`}
                >
                  {p.name}
                </button>
              );
            })}
            {selectedPreset === 'Kustom' && (
              <span className="px-3 py-1.5 rounded-full text-xs font-semibold bg-[#00a3ff]/20 text-[#00a3ff] border border-[#00a3ff]/30">
                Kustom
              </span>
            )}
          </div>
        </div>

        {/* 5-Band Vertical Equalizer Section */}
        <div className={`p-4 bg-white/5 rounded-xl border border-white/5 transition-opacity ${isEnabled ? 'opacity-100' : 'opacity-40 pointer-events-none'}`}>
          <div className="flex justify-between items-center mb-3">
            <span className="text-xs font-semibold text-[#b3b3b3] uppercase tracking-wider">
              Frekuensi Grafis (5-Band)
            </span>
            <span className="text-[11px] text-[#00a3ff] font-medium">
              -10 dB s/d +10 dB
            </span>
          </div>

          <div className="grid grid-cols-5 gap-2 sm:gap-4 items-center justify-items-center pt-2">
            {bands.map((val, idx) => (
              <div key={BAND_LABELS[idx].label} className="flex flex-col items-center gap-2 w-full">
                {/* dB Readout */}
                <span className="text-[11px] font-mono font-bold text-[#00a3ff]">
                  {val > 0 ? `+${val.toFixed(1)}` : val.toFixed(1)}
                </span>

                {/* Vertical Slider Wrapper */}
                <div className="h-32 flex items-center justify-center relative w-full">
                  <input
                    type="range"
                    min="-10"
                    max="10"
                    step="0.5"
                    value={val}
                    onChange={(e) => handleBandChange(idx, e.target.value)}
                    className="w-28 -rotate-90 appearance-none bg-[#2a2a2a] h-1.5 rounded-full cursor-pointer accent-[#00a3ff]"
                    style={{
                      WebkitAppearance: 'slider-vertical',
                    }}
                  />
                </div>

                {/* Band Label & Description */}
                <div className="text-center">
                  <div className="text-xs font-bold text-white">{BAND_LABELS[idx].label}</div>
                  <div className="text-[10px] text-[#888]">{BAND_LABELS[idx].sub}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Extra Sound FX: Bass Boost & 3D Virtualizer */}
        <div className={`grid grid-cols-1 sm:grid-cols-2 gap-3 transition-opacity ${isEnabled ? 'opacity-100' : 'opacity-40 pointer-events-none'}`}>
          {/* Bass Boost */}
          <div className="p-3.5 bg-white/5 rounded-xl border border-white/5 space-y-2">
            <div className="flex justify-between items-center text-xs">
              <span className="font-semibold text-white flex items-center gap-1.5">
                <Volume2 className="w-3.5 h-3.5 text-[#00a3ff]" />
                <span>Bass Boost</span>
              </span>
              <span className="font-mono text-[#00a3ff] font-bold">{bassBoost}%</span>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              value={bassBoost}
              onChange={(e) => handleBassChange(e.target.value)}
              className="w-full h-1.5 bg-[#2a2a2a] rounded-lg appearance-none cursor-pointer accent-[#00a3ff]"
            />
          </div>

          {/* 3D Virtualizer / Surround */}
          <div className="p-3.5 bg-white/5 rounded-xl border border-white/5 space-y-2">
            <div className="flex justify-between items-center text-xs">
              <span className="font-semibold text-white flex items-center gap-1.5">
                <Waves className="w-3.5 h-3.5 text-[#00a3ff]" />
                <span>3D Surround</span>
              </span>
              <span className="font-mono text-[#00a3ff] font-bold">{virtualizer}%</span>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              value={virtualizer}
              onChange={(e) => handleVirtChange(e.target.value)}
              className="w-full h-1.5 bg-[#2a2a2a] rounded-lg appearance-none cursor-pointer accent-[#00a3ff]"
            />
          </div>
        </div>
      </div>
    </div>
  );
}
