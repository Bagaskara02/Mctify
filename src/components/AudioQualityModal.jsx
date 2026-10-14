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
            <div className="w-10 h-10 rounded-xl bg-[#00a3ff]/20 border border-[#00a3ff]/40 flex items-center justify-center text-[#00a3ff] shadow-lg shadow-[#00a3ff]/20">
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
            return (
              <div
                key={q.id}
                onClick={() => handleSelect(q.id)}
                className={`p-4 rounded-xl border transition-all cursor-pointer relative flex items-start justify-between gap-3 ${
                  isSelected
                    ? 'bg-[#00a3ff]/10 border-[#00a3ff] shadow-lg shadow-[#00a3ff]/10'
                    : 'bg-white/5 border-white/5 hover:bg-white/10 hover:border-white/15'
                }`}
              >
                <div className="space-y-1.5 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-white">{q.label}</span>
                    <span
                      className={`text-[10px] font-mono font-bold px-2 py-0.5 rounded-full ${
                        isSelected
                          ? 'bg-[#00a3ff] text-black font-extrabold'
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
                  </div>

                  <p className="text-xs text-[#b3b3b3] leading-relaxed">
                    {q.description}
                  </p>

                  <div className="flex items-center gap-3 text-[11px] text-[#888] pt-1">
                    <span className="flex items-center gap-1">
                      <Wifi className="w-3 h-3 text-[#00a3ff]" />
                      {q.codec}
                    </span>
                  </div>
                </div>

                <div
                  className={`w-5 h-5 rounded-full border flex items-center justify-center transition-all mt-1 ${
                    isSelected
                      ? 'border-[#00a3ff] bg-[#00a3ff] text-black'
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
          <ShieldCheck className="w-4 h-4 text-[#00a3ff] shrink-0 mt-0.5" />
          <div className="space-y-1 leading-relaxed">
            <span className="font-semibold text-white block">
              Transparansi Kualitas Audio (Bebas Bitrate Semu)
            </span>
            <p className="text-[11px] text-[#999]">
              Streaming Mctify bersumber langsung dari YouTube Music API dengan batas maksimal resmi ~160 kbps (Opus itag 251 / AAC 128-160k). Kami menyajikan bitrate jujur tanpa trik upscaling 320 kbps palsu untuk mempertahankan respon audio paling murni.
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="flex justify-end pt-2 border-t border-white/10">
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-[#00a3ff] hover:bg-[#0088cc] text-black text-xs font-bold transition-all shadow-md shadow-[#00a3ff]/20 cursor-pointer"
          >
            Selesai
          </button>
        </div>
      </div>
    </div>
  );
}
