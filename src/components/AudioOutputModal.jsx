import React, { useState, useEffect } from 'react';
import { 
  ArrowLeft, 
  X, 
  Headphones, 
  Speaker, 
  Tv, 
  Usb, 
  Sparkles, 
  RefreshCw, 
  ExternalLink,
  ShieldCheck
} from 'lucide-react';
import { audioOutputService } from '../services/audioOutputService';

export default function AudioOutputModal({ isOpen, onClose, audioRef, audioContext }) {
  const [devices, setDevices] = useState([]);
  const [selectedId, setSelectedId] = useState(() => audioOutputService.getDeviceId());
  const [selectedLabel, setSelectedLabel] = useState(() => audioOutputService.getDeviceLabel());
  const [isRequesting, setIsRequesting] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    return audioOutputService.subscribe((devs, selId, selLabel) => {
      setDevices(devs || []);
      setSelectedId(selId);
      if (selLabel) setSelectedLabel(selLabel);
    });
  }, []);

  const handleSelect = async (item) => {
    // If real device IDs are not yet unlocked, prompt Windows device selector / permission
    const isPlaceholder = !hasDeviceLabels || 
      item.deviceId.includes('_default') || 
      item.deviceId.includes('usb_') || 
      item.deviceId.includes('hdmi_');

    if (isPlaceholder) {
      setIsRequesting(true);
      await audioOutputService.requestDeviceAccess(
        audioRef?.current,
        audioContext
      );
      setIsRequesting(false);
      return;
    }

    await audioOutputService.setOutputDevice(
      item.deviceId, 
      audioRef?.current, 
      audioContext,
      item.label
    );
    setSelectedId(item.deviceId);
    setSelectedLabel(item.label);
  };

  const handleRequestAccess = async () => {
    setIsRequesting(true);
    await audioOutputService.requestDeviceAccess(
      audioRef?.current,
      audioContext
    );
    setIsRequesting(false);
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await audioOutputService.refreshDevices();
    setTimeout(() => setIsRefreshing(false), 300);
  };

  if (!isOpen) return null;

  const getDeviceIcon = (label = '') => {
    const l = label.toLowerCase();
    if (l.includes('headphone') || l.includes('headset') || l.includes('earphone') || l.includes('airpods') || l.includes('buds')) {
      return <Headphones className="w-5 h-5 text-white/90 flex-shrink-0" />;
    }
    if (l.includes('hdmi') || l.includes('digital audio') || l.includes('display audio') || l.includes('tv') || l.includes('monitor')) {
      return <Tv className="w-5 h-5 text-white/90 flex-shrink-0" />;
    }
    if (l.includes('usb')) {
      return <Speaker className="w-5 h-5 text-white/90 flex-shrink-0" />;
    }
    return <Speaker className="w-5 h-5 text-white/90 flex-shrink-0" />;
  };

  const hasDeviceLabels = devices.some((d) => d.label && d.label.trim().length > 0);

  // Fallback realistic Windows audio devices if permission is not yet granted
  const renderedDevices = hasDeviceLabels
    ? devices.map((d) => ({
        deviceId: d.deviceId || 'default',
        label: d.label || 'Speakers (Realtek(R) Audio)',
      }))
    : [
        { deviceId: 'default', label: 'Speakers (Realtek(R) Audio)' },
        { deviceId: 'headphones_default', label: 'Headphones (Realtek(R) Audio)' },
        { deviceId: 'usb_audio', label: 'Speakers (USB Audio Device)' },
        { deviceId: 'hdmi_audio', label: 'Digital Audio (HDMI) (HD Audio Driver for Display Audio)' },
      ];

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm select-none animate-in fade-in duration-150"
      onClick={onClose}
    >
      {/* Windows 11 Sound Output Flyout Container */}
      <div
        className="w-full max-w-sm bg-[#1f1f1f]/95 border border-white/10 rounded-xl p-4 shadow-2xl relative space-y-4 text-white backdrop-blur-xl font-sans"
        onClick={(e) => e.stopPropagation()}
        style={{
          boxShadow: '0 20px 50px rgba(0, 0, 0, 0.7), 0 0 0 1px rgba(255, 255, 255, 0.08)',
        }}
      >
        {/* Windows 11 Header: ← Sound output */}
        <div className="flex items-center justify-between pb-1">
          <div className="flex items-center gap-2.5">
            <button
              onClick={onClose}
              className="p-1 rounded-md hover:bg-white/10 text-white/90 hover:text-white transition-colors"
              title="Kembali / Tutup"
            >
              <ArrowLeft className="w-4 h-4" />
            </button>
            <h2 className="text-sm font-semibold tracking-wide text-white">
              Sound output
            </h2>
          </div>

          <div className="flex items-center gap-1">
            <button
              onClick={handleRefresh}
              className={`p-1.5 rounded-md text-white/60 hover:text-white hover:bg-white/10 transition-colors ${
                isRefreshing ? 'animate-spin text-[#00a3ff]' : ''
              }`}
              title="Pindai Ulang Perangkat"
            >
              <RefreshCw className="w-3.5 h-3.5" />
            </button>
            <button
              onClick={onClose}
              className="p-1.5 rounded-md text-white/60 hover:text-white hover:bg-white/10 transition-colors"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Windows 11 Subheader: Output device */}
        <div className="px-1">
          <p className="text-xs font-semibold text-white/80">
            Output device
          </p>
        </div>

        {/* Prompt to unlock live hardware names from Windows if needed */}
        {!hasDeviceLabels && (
          <div className="mx-1 p-3 rounded-lg bg-white/[0.05] border border-white/10 space-y-2">
            <div className="flex items-center gap-1.5 text-xs font-semibold text-[#00a3ff]">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Deteksi Otomatis Perangkat Windows</span>
            </div>
            <p className="text-[11px] text-white/70 leading-relaxed">
              Izinkan akses agar peramban dapat membaca daftar nama perangkat audio aktif di laptop/komputer Anda.
            </p>
            <button
              onClick={handleRequestAccess}
              disabled={isRequesting}
              className="w-full py-1.5 px-3 rounded-md bg-[#00a3ff] hover:bg-[#0092e6] text-black font-bold text-xs flex items-center justify-center gap-1.5 transition-transform active:scale-98 shadow-sm"
            >
              {isRequesting ? (
                <RefreshCw className="w-3 h-3 animate-spin" />
              ) : (
                <ShieldCheck className="w-3.5 h-3.5" />
              )}
              <span>{isRequesting ? 'Menghubungkan...' : 'Izinkan & Deteksi Perangkat Windows'}</span>
            </button>
          </div>
        )}

        {/* Windows 11 Device List */}
        <div className="space-y-1 max-h-72 overflow-y-auto px-0.5 scrollbar-thin">
          {renderedDevices.map((item, index) => {
            const isSelected = selectedId === item.deviceId ||
              (item.deviceId === 'default' && (!selectedId || selectedId === 'default')) ||
              (selectedLabel && item.label.toLowerCase() === selectedLabel.toLowerCase());

            return (
              <div
                key={item.deviceId + index}
                onClick={() => handleSelect(item)}
                className={`group relative flex items-center p-2.5 rounded-md cursor-pointer transition-colors ${
                  isSelected
                    ? 'bg-white/[0.12] text-white'
                    : 'hover:bg-white/[0.06] text-white/90'
                }`}
              >
                {/* Windows 11 Left Active Blue Indicator Pill */}
                {isSelected ? (
                  <span className="w-1 h-5 bg-[#00a3ff] rounded-full mr-3 flex-shrink-0" />
                ) : (
                  <span className="w-1 h-5 mr-3 flex-shrink-0" />
                )}

                {/* Device Icon matching Windows 11 */}
                <div className="mr-3">
                  {getDeviceIcon(item.label)}
                </div>

                {/* Device Label matching Windows 11 Output flyout */}
                <span className="text-xs font-normal truncate tracking-normal flex-1">
                  {item.label}
                </span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
