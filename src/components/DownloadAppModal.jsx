import React from 'react';
import { X, Smartphone, Download, Sparkles, CheckCircle2, Terminal, Music } from 'lucide-react';

export default function DownloadAppModal({ isOpen, onClose }) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200 select-none">
      <div 
        className="w-full max-w-lg bg-[#181818] border border-white/10 rounded-2xl p-6 sm:p-8 shadow-2xl relative space-y-6 text-white"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute top-5 right-5 p-2 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Modal Header */}
        <div className="flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-[#00a3ff] flex items-center justify-center shadow-lg shadow-[#00a3ff]/30 flex-shrink-0">
            <Music className="w-7 h-7 text-black stroke-[2.5]" />
          </div>
          <div>
            <h3 className="text-xl sm:text-2xl font-black text-white tracking-tight">
              McMusic Mobile
            </h3>
            <p className="text-xs sm:text-sm text-[#00a3ff] font-semibold mt-0.5 flex items-center gap-1">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Aplikasi Native Flutter (Android, iOS & Desktop)</span>
            </p>
          </div>
        </div>

        {/* Features Checklist */}
        <div className="space-y-2.5 bg-white/5 p-4 rounded-xl border border-white/5 text-xs sm:text-sm text-[#b3b3b3]">
          <div className="flex items-center gap-2 text-white">
            <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
            <span>UI & UX 100% Persis Spotify dengan aksen Electric Azure</span>
          </div>
          <div className="flex items-center gap-2 text-white">
            <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
            <span>Pemutaran lagu lengkap tanpa batas & background playback</span>
          </div>
          <div className="flex items-center gap-2 text-white">
            <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
            <span>Pencarian artis, lagu global & Indonesia di seluruh katalog</span>
          </div>
          <div className="flex items-center gap-2 text-white">
            <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
            <span>Lirik sinkronisasi real-time & radio rekomendasi cerdas</span>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="space-y-3 pt-2">
          <div className="p-3 bg-[#0d223f] border border-[#00a3ff]/30 rounded-xl flex items-center justify-between">
            <div>
              <p className="text-xs font-bold text-white">Source Code Flutter Project</p>
              <p className="text-[11px] text-[#00a3ff]">Tersedia langsung di folder proyek: <code className="bg-black/40 px-1 py-0.5 rounded text-white">mcmusic_flutter/</code></p>
            </div>
            <span className="px-2.5 py-1 rounded-full bg-[#00a3ff]/20 text-[#00a3ff] text-[10px] font-bold">
              Siap Run
            </span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pt-2">
            <a
              href="/downloads/McMusic.apk"
              download="McMusic.apk"
              className="py-3 px-4 rounded-xl bg-[#00a3ff] hover:bg-[#2eb4ff] text-black font-black text-xs sm:text-sm flex items-center justify-center gap-2 shadow-lg shadow-[#00a3ff]/20 active:scale-95 transition-all cursor-pointer no-underline text-center"
            >
              <Smartphone className="w-4 h-4 stroke-[2.5]" />
              <span>Download APK Universal</span>
            </a>
            <a
              href="/downloads/McMusic-arm64.apk"
              download="McMusic-arm64.apk"
              className="py-3 px-4 rounded-xl bg-[#00a3ff]/20 hover:bg-[#00a3ff]/30 text-[#00a3ff] border border-[#00a3ff]/40 font-black text-xs sm:text-sm flex items-center justify-center gap-2 active:scale-95 transition-all cursor-pointer no-underline text-center"
            >
              <Smartphone className="w-4 h-4 stroke-[2.5]" />
              <span>Download ARM64 (19MB)</span>
            </a>
          </div>
          <div className="text-center pt-1">
            <a
              href="/downloads"
              className="text-xs text-[#00a3ff] hover:underline inline-flex items-center gap-1 font-semibold"
            >
              <span>Buka Halaman Download Center Lengkap</span>
              <span>→</span>
            </a>
          </div>
          <button
            onClick={onClose}
            className="w-full py-2.5 rounded-full text-xs text-[#b3b3b3] hover:text-white transition-colors"
          >
            Tutup
          </button>
        </div>
      </div>
    </div>
  );
}
