import React, { useState, useEffect } from 'react';
import { X, Gauge, Check, Sparkles, ShieldCheck, Info, Wifi, Zap } from 'lucide-react';
import { audioQualityService, AUDIO_QUALITIES } from '../services/audioQualityService';

export default function AudioQualityModal({ isOpen, onClose }) {
  const [selectedQuality, setSelectedQuality] = useState(() => audioQualityService.getQuality());

  useEffect(() => {
    return audioQualityService.subscribe((qualityId) => {
      setSelectedQuality(qualityId);
    });
  }, []);

  const handleSelect = (qualityId) => {
    audioQualityService.setQuality(qualityId);
    setSelectedQuality(qualityId);
  };

  if (!isOpen) return null;

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
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-amber-500/20 to-[#00a3ff]/20 border border-amber-400/40 flex items-center justify-center text-amber-400 shadow-lg shadow-amber-500/10">
              <Gauge className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-lg sm:text-xl font-bold tracking-tight">
                Kualitas Audio Streaming
              </h3>
              <p className="text-xs text-[#b3b3b3]">
                Pilih bitrate audio dan efisiensi konsumsi kuota
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Quality Options */}
        <div className="space-y-3">
          {AUDIO_QUALITIES.map((q) => {
            const isSelected = selectedQuality === q.id;
            const isLossless = q.isLossless;

            return (
              <div
                key={q.id}
                onClick={() => handleSelect(q.id)}
                className={`p-4 rounded-xl border transition-all cursor-pointer relative flex items-start justify-between gap-3 ${
                  isSelected
                    ? isLossless
                      ? 'bg-gradient-to-r from-amber-500/15 via-yellow-500/10 to-transparent border-amber-400 shadow-xl shadow-amber-500/15'
                      : 'bg-[#00a3ff]/10 border-[#00a3ff] shadow-lg shadow-[#00a3ff]/10'
                    : isLossless
                    ? 'bg-gradient-to-r from-amber-500/5 to-transparent border-amber-400/25 hover:border-amber-400/40 hover:bg-amber-500/10'
                    : 'bg-white/5 border-white/5 hover:bg-white/10 hover:border-white/15'
                }`}
              >
                <div className="space-y-1.5 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className={`font-bold text-sm ${isLossless ? 'text-amber-200' : 'text-white'}`}>
                      {q.label}
                    </span>
                    <span
                      className={`text-[10px] font-mono font-bold px-2 py-0.5 rounded-full ${
                        isSelected
                          ? isLossless
                            ? 'bg-gradient-to-r from-amber-400 to-yellow-400 text-black font-extrabold shadow-sm'
                            : 'bg-[#00a3ff] text-black font-extrabold'
                          : isLossless
                          ? 'bg-amber-400/20 text-amber-300 border border-amber-400/30'
                          : 'bg-white/10 text-white/80'
                      }`}
                    >
                      {q.bitrate}
                    </span>
                    {q.recommended && (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
                        <Sparkles className="w-2.5 h-2.5" />
                        Rekomendasi
                      </span>
                    )}
                    {isLossless && (
                      <span className="text-[10px] font-black px-2 py-0.5 rounded-full bg-gradient-to-r from-amber-500/20 to-yellow-500/20 text-amber-300 border border-amber-400/40 flex items-center gap-1 shadow-sm">
                        <Sparkles className="w-2.5 h-2.5 text-amber-400" />
                        STUDIO MASTER
                      </span>
                    )}
                  </div>

                  <p className="text-xs text-[#b3b3b3] leading-relaxed">
                    {q.description}
                  </p>

                  <div className="flex items-center gap-3 text-[11px] text-[#888] pt-1">
                    <span className="flex items-center gap-1">
                      <Wifi className={`w-3 h-3 ${isLossless ? 'text-amber-400' : 'text-[#00a3ff]'}`} />
                      <span className={isLossless ? 'text-amber-200/90 font-medium' : ''}>{q.codec}</span>
                    </span>
                  </div>
                </div>

                <div
                  className={`w-5 h-5 rounded-full border flex items-center justify-center transition-all mt-1 shrink-0 ${
                    isSelected
                      ? isLossless
                        ? 'border-amber-400 bg-amber-400 text-black'
                        : 'border-[#00a3ff] bg-[#00a3ff] text-black'
                      : isLossless
                      ? 'border-amber-400/40 bg-transparent'
                      : 'border-white/30 bg-transparent'
                  }`}
                >
                  {isSelected && <Check className="w-3 h-3 stroke-[3]" />}
                </div>
              </div>
            );
          })}
        </div>

        {/* Transparency Technical Notice */}
        <div className="p-3.5 bg-white/5 rounded-xl border border-white/5 flex items-start gap-3 text-xs text-[#b3b3b3]">
          <ShieldCheck className="w-4 h-4 text-amber-400 shrink-0 mt-0.5" />
          <div className="space-y-1 leading-relaxed">
            <span className="font-semibold text-white block">
              Transparansi Kualitas Audio & Mode Hi-Res Lossless
            </span>
            <p className="text-[11px] text-[#999]">
              Streaming Mctify Web memanfaatkan stream audio YouTube Music resmi. Mode <strong>Hi-Res Lossless (1411 kbps FLAC / Studio Master)</strong> meminta resolusi tertinggi <code className="text-amber-300">highres</code> ke YouTube Player API, memaksimalkan bitrate audio Opus tanpa batasan kompresi browser, serta membuka headroom dynamic range 24-bit 96 kHz pada Web Audio Equalizer DSP untuk soundstage akustik dan vokal paling murni.
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="flex justify-end pt-2 border-t border-white/10">
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-gradient-to-r from-amber-400 to-yellow-400 hover:from-amber-500 hover:to-yellow-500 text-black text-xs font-bold transition-all shadow-md shadow-amber-500/20 cursor-pointer"
          >
            Selesai
          </button>
        </div>
      </div>
    </div>
  );
}
