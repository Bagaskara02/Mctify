import React from 'react';
import { Moon, Timer, X, Check } from 'lucide-react';

export default function SleepTimerModal({
  isOpen,
  onClose,
  sleepTimerSeconds, // null if inactive, number if active, or 'endOfTrack'
  onSetTimer,        // (minutes: number | 'endOfTrack') => void
  onCancelTimer,     // () => void
}) {
  if (!isOpen) return null;

  const timerOptions = [
    { label: '5 Menit', value: 5 },
    { label: '15 Menit', value: 15 },
    { label: '30 Menit', value: 30 },
    { label: '45 Menit', value: 45 },
    { label: '1 Jam', value: 60 },
    { label: 'Akhir Lagu Ini', value: 'endOfTrack' },
  ];

  const formatRemaining = () => {
    if (sleepTimerSeconds === 'endOfTrack') return 'Di akhir lagu ini';
    if (typeof sleepTimerSeconds === 'number' && sleepTimerSeconds > 0) {
      const mins = Math.floor(sleepTimerSeconds / 60);
      const secs = sleepTimerSeconds % 60;
      return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
    }
    return null;
  };

  const isActive = sleepTimerSeconds !== null && sleepTimerSeconds !== undefined;

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4 bg-black/70 backdrop-blur-md animate-in fade-in duration-200">
      <div 
        className="w-full max-w-sm bg-[#181818] border border-white/10 rounded-2xl p-6 shadow-2xl relative text-white space-y-5"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-[#00a3ff]/10 flex items-center justify-center text-[#00a3ff]">
              <Moon className="w-5 h-5" />
            </div>
            <div>
              <h3 className="font-bold text-base text-white">Pengatur Waktu Tidur</h3>
              <p className="text-xs text-neutral-400">Hentikan musik secara otomatis</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-full hover:bg-white/10 text-neutral-400 hover:text-white transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Active Timer Status Banner */}
        {isActive && (
          <div className="p-3 bg-[#00a3ff]/10 border border-[#00a3ff]/30 rounded-xl flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs text-[#00a3ff] font-semibold">
              <Timer className="w-4 h-4 animate-pulse" />
              <span>Musik akan berhenti: <strong className="text-white">{formatRemaining()}</strong></span>
            </div>
            <button
              onClick={() => {
                onCancelTimer();
                onClose();
              }}
              className="text-xs font-bold text-rose-400 hover:text-rose-300 ml-2"
            >
              Matikan
            </button>
          </div>
        )}

        {/* Options List */}
        <div className="space-y-1">
          {timerOptions.map((opt) => {
            const isSelected = 
              (opt.value === 'endOfTrack' && sleepTimerSeconds === 'endOfTrack') ||
              (typeof opt.value === 'number' && typeof sleepTimerSeconds === 'number' && Math.ceil(sleepTimerSeconds / 60) === opt.value);

            return (
              <button
                key={String(opt.value)}
                onClick={() => {
                  onSetTimer(opt.value);
                  onClose();
                }}
                className={`w-full flex items-center justify-between px-4 py-3 rounded-xl text-sm font-semibold transition-all ${
                  isSelected
                    ? 'bg-[#00a3ff]/20 text-[#00a3ff] border border-[#00a3ff]/40'
                    : 'hover:bg-white/5 text-neutral-200'
                }`}
              >
                <span>{opt.label}</span>
                {isSelected && <Check className="w-4 h-4 text-[#00a3ff]" />}
              </button>
            );
          })}
        </div>

        {/* Cancel Timer Button (if active) */}
        {isActive && (
          <button
            onClick={() => {
              onCancelTimer();
              onClose();
            }}
            className="w-full py-2.5 rounded-xl bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 border border-rose-500/20 text-xs font-bold transition-colors"
          >
            Matikan Pengatur Waktu Tidur
          </button>
        )}
      </div>
    </div>
  );
}
