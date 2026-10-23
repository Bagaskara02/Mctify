import React, { useState, useEffect } from 'react';
import { 
  X, 
  Headphones, 
  Speaker, 
  Check, 
  Sparkles, 
  Info, 
  Radio, 
  Volume2, 
  RefreshCw,
  ExternalLink
} from 'lucide-react';
import { audioOutputService } from '../services/audioOutputService';

export default function AudioOutputModal({ isOpen, onClose, audioRef, audioContext }) {
  const [devices, setDevices] = useState([]);
  const [selectedId, setSelectedId] = useState(() => audioOutputService.getDeviceId());
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    return audioOutputService.subscribe((devs, selId) => {
      setDevices(devs || []);
      setSelectedId(selId);
    });
  }, []);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await audioOutputService.refreshDevices();
    setTimeout(() => setIsRefreshing(false), 400);
  };

  const handleSelect = async (deviceId) => {
    await audioOutputService.setOutputDevice(
      deviceId, 
      audioRef?.current, 
      audioContext
    );
    setSelectedId(deviceId);
  };

  const handleSelectSystem = async () => {
    await audioOutputService.selectSystemDevice(
      audioRef?.current, 
      audioContext
    );
  };

  if (!isOpen) return null;

  const getDeviceIcon = (label = '') => {
    const l = label.toLowerCase();
    if (l.includes('headphone') || l.includes('headset') || l.includes('earphone') || l.includes('airpods') || l.includes('buds')) {
      return <Headphones className="w-5 h-5 text-[#3B82F6]" />;
    }
    return <Speaker className="w-5 h-5 text-[#3B82F6]" />;
  };

  // Ensure default device is always available in the list
  const hasDefault = devices.some((d) => d.deviceId === 'default' || d.deviceId === '');
  const displayDevices = hasDefault 
    ? devices 
    : [
        { deviceId: 'default', label: 'Speaker / Output Default Sistem' },
        ...devices
      ];

  const hasSystemSelector = typeof navigator !== 'undefined' && !!navigator.mediaDevices?.selectAudioOutput;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200 select-none"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg bg-[#141414] border border-white/10 rounded-2xl p-6 sm:p-7 shadow-2xl relative space-y-5 text-white"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between pb-3 border-b border-white/10">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#3B82F6]/20 border border-[#3B82F6]/40 flex items-center justify-center text-[#3B82F6] shadow-lg shadow-[#3B82F6]/20">
              <Headphones className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg sm:text-xl font-bold tracking-tight">
                Pilih Output Audio
              </h3>
              <p className="text-xs text-[#b3b3b3]">
                Ganti speaker, earphone, atau headphone Bluetooth
              </p>
            </div>
          </div>

          <div className="flex items-center gap-1.5">
            <button
              onClick={handleRefresh}
              className={`p-1.5 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors ${
                isRefreshing ? 'animate-spin text-[#3B82F6]' : ''
              }`}
              title="Pindai Ulang Perangkat Audio"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
            <button
              onClick={onClose}
              className="p-1.5 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Device List */}
        <div className="space-y-2.5 max-h-72 overflow-y-auto pr-1">
          {displayDevices.map((d, idx) => {
            const devId = d.deviceId || 'default';
            const isSelected = selectedId === devId || (devId === 'default' && (!selectedId || selectedId === 'default'));
            const labelText = d.label || (devId === 'default' ? 'Speaker / Output Default Sistem' : `Perangkat Audio #${idx + 1}`);

            return (
              <div
                key={devId || idx}
                onClick={() => handleSelect(devId)}
                className={`p-3.5 rounded-xl border transition-all cursor-pointer relative flex items-center justify-between gap-3 ${
                  isSelected
                    ? 'bg-[#3B82F6]/15 border-[#3B82F6] shadow-lg shadow-[#3B82F6]/10'
                    : 'bg-white/5 border-white/5 hover:bg-white/10 hover:border-white/15'
                }`}
              >
                <div className="flex items-center gap-3 min-w-0 flex-1">
                  <div className={`p-2 rounded-lg ${isSelected ? 'bg-[#3B82F6]/20' : 'bg-white/5'}`}>
                    {getDeviceIcon(labelText)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="font-bold text-sm text-white truncate">
                      {labelText}
                    </p>
                    <p className="text-[11px] text-[#b3b3b3] flex items-center gap-1 mt-0.5">
                      <Radio className="w-3 h-3 text-[#3B82F6]" />
                      {devId === 'default' ? 'Perangkat Bawaan Sistem' : 'Saluran Audio Eksternal'}
                    </p>
                  </div>
                </div>

                {isSelected && (
                  <div className="w-6 h-6 rounded-full bg-[#3B82F6] text-black flex items-center justify-center flex-shrink-0">
                    <Check className="w-3.5 h-3.5 stroke-[3]" />
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* System Selector Button if browser supports selectAudioOutput */}
        {hasSystemSelector && (
          <button
            onClick={handleSelectSystem}
            className="w-full py-2.5 px-4 rounded-xl bg-white/5 hover:bg-white/10 border border-white/10 text-xs font-bold text-white flex items-center justify-center gap-2 transition-colors active:scale-98"
          >
            <ExternalLink className="w-3.5 h-3.5 text-[#3B82F6]" />
            <span>Buka Pemilih Perangkat Sistem Browser</span>
          </button>
        )}

        {/* Info Note */}
        <div className="p-3.5 rounded-xl bg-white/5 border border-white/10 text-xs text-[#b3b3b3] flex items-start gap-2.5">
          <Info className="w-4 h-4 text-[#3B82F6] flex-shrink-0 mt-0.5" />
          <p className="leading-relaxed text-[11px]">
            Audio akan disalurkan ke perangkat yang dipilih. Pastikan earphone kabel atau headphone Bluetooth Anda sudah terhubung aktif ke komputer/laptop atau perangkat Anda.
          </p>
        </div>
      </div>
    </div>
  );
}
