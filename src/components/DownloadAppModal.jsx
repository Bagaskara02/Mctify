import React, { useState } from 'react';
import { 
  X, 
  Smartphone, 
  Download, 
  Sparkles, 
  CheckCircle2, 
  Music, 
  Apple, 
  Share, 
  PlusSquare, 
  Laptop, 
  HelpCircle,
  ExternalLink
} from 'lucide-react';

export default function DownloadAppModal({ isOpen, onClose }) {
  const isApple = typeof navigator !== 'undefined' && /iPhone|iPad|iPod|Macintosh/.test(navigator.userAgent || '');
  const [activeTab, setActiveTab] = useState(isApple ? 'ios' : 'android');

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200 select-none overflow-y-auto">
      <div 
        className="w-full max-w-lg bg-[#181818] border border-white/10 rounded-2xl p-5 sm:p-7 shadow-2xl relative space-y-5 text-white max-h-[90vh] overflow-y-auto no-scrollbar"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute top-5 right-5 p-2 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
          title="Tutup"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Modal Header */}
        <div className="flex items-center gap-3.5">
          <div className="w-12 h-12 sm:w-14 sm:h-14 rounded-2xl bg-[#00a3ff] flex items-center justify-center shadow-lg shadow-[#00a3ff]/30 flex-shrink-0">
            <Music className="w-6 h-6 sm:w-7 sm:h-7 text-black stroke-[2.5]" />
          </div>
          <div>
            <h3 className="text-xl sm:text-2xl font-black text-white tracking-tight">
              Unduh McTify Mobile
            </h3>
            <p className="text-xs sm:text-sm text-[#00a3ff] font-semibold mt-0.5 flex items-center gap-1">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Aplikasi Musik Bebas Iklan (Android &amp; iOS)</span>
            </p>
          </div>
        </div>

        {/* Platform Switcher Tabs */}
        <div className="flex p-1 bg-white/5 rounded-xl border border-white/10">
          <button
            onClick={() => setActiveTab('android')}
            className={`flex-1 py-2 px-3 rounded-lg text-xs sm:text-sm font-bold flex items-center justify-center gap-2 transition-all ${
              activeTab === 'android'
                ? 'bg-[#00a3ff] text-black shadow-md'
                : 'text-[#b3b3b3] hover:text-white'
            }`}
          >
            <Smartphone className="w-4 h-4 stroke-[2.5]" />
            <span>Android (APK)</span>
          </button>
          <button
            onClick={() => setActiveTab('ios')}
            className={`flex-1 py-2 px-3 rounded-lg text-xs sm:text-sm font-bold flex items-center justify-center gap-2 transition-all ${
              activeTab === 'ios'
                ? 'bg-white text-black shadow-md'
                : 'text-[#b3b3b3] hover:text-white'
            }`}
          >
            <Apple className="w-4 h-4 fill-current" />
            <span>iPhone / iPad (iOS)</span>
          </button>
        </div>

        {/* Tab 1: ANDROID */}
        {activeTab === 'android' && (
          <div className="space-y-4 animate-in fade-in duration-150">
            {/* Features Checklist */}
            <div className="space-y-2 bg-white/5 p-3.5 rounded-xl border border-white/5 text-xs text-[#b3b3b3]">
              <div className="flex items-center gap-2 text-white">
                <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
                <span>Format APK langsung pasang di semua smartphone Android</span>
              </div>
              <div className="flex items-center gap-2 text-white">
                <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
                <span>Pemutaran latar belakang (Background Playback) &amp; MiniPlayer rapat</span>
              </div>
              <div className="flex items-center gap-2 text-white">
                <CheckCircle2 className="w-4 h-4 text-[#00a3ff] flex-shrink-0" />
                <span>Lirik karaoke bersinkronisasi &amp; radio rekomendasi pintar</span>
              </div>
            </div>

            {/* Android Download Button */}
            <a
              href="/downloads/McMusic-arm64.apk"
              download="McTify-v1.4.17-arm64.apk"
              className="w-full py-3.5 px-4 rounded-xl bg-[#00a3ff] hover:bg-[#2eb4ff] text-black font-black text-xs sm:text-sm flex items-center justify-center gap-2 shadow-lg shadow-[#00a3ff]/20 active:scale-95 transition-all cursor-pointer no-underline text-center"
            >
              <Smartphone className="w-4 h-4 stroke-[2.5]" />
              <span>Download McTify Android APK (v1.4.17)</span>
            </a>

            {/* Quick Android Steps */}
            <div className="bg-[#0f172a] border border-[#00a3ff]/20 rounded-xl p-3 text-[11px] sm:text-xs text-[#94a3b8] space-y-1">
              <p className="font-bold text-white flex items-center gap-1.5">
                <HelpCircle className="w-3.5 h-3.5 text-[#00a3ff]" />
                <span>Cara Pasang di Android:</span>
              </p>
              <ol className="list-decimal pl-4 space-y-0.5">
                <li>Klik tombol <strong>Download McTify Android APK</strong> di atas.</li>
                <li>Setelah selesai, buka file dari notifikasi atau folder Download.</li>
                <li>Pilih <strong>Pasang / Perbarui</strong> (izinkan instalasi aplikasi dari browser jika diminta).</li>
              </ol>
            </div>
          </div>
        )}

        {/* Tab 2: IPHONE / IPAD (iOS) */}
        {activeTab === 'ios' && (
          <div className="space-y-4 animate-in fade-in duration-150">
            {/* iOS Method 1: Safari PWA (Most recommended) */}
            <div className="bg-gradient-to-b from-[#182638] to-[#121c2b] border border-[#00a3ff]/40 rounded-xl p-4 space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-black uppercase tracking-wider text-[#00a3ff] bg-[#00a3ff]/15 px-2 py-0.5 rounded-md">
                  Metode 1 • Paling Mudah &amp; Cepat
                </span>
                <span className="text-[10px] font-bold text-emerald-400">
                  Tanpa PC • Permanen
                </span>
              </div>
              <h4 className="font-black text-sm sm:text-base text-white">
                Pasang ke Layar Utama (Add to Home Screen)
              </h4>
              <p className="text-xs text-[#cbd5e1] leading-relaxed">
                Di iPhone, Anda bisa memasang McTify langsung tanpa perlu komputer dan tanpa repot sideload:
              </p>
              <div className="space-y-2 text-xs text-[#e2e8f0] bg-black/40 p-3 rounded-lg border border-white/5">
                <div className="flex items-start gap-2">
                  <span className="w-5 h-5 rounded-full bg-[#00a3ff]/20 text-[#00a3ff] font-black flex items-center justify-center flex-shrink-0 text-[11px]">1</span>
                  <span>Buka website <strong>mctify.vercel.app</strong> menggunakan browser <strong>Safari</strong> di iPhone Anda.</span>
                </div>
                <div className="flex items-start gap-2">
                  <span className="w-5 h-5 rounded-full bg-[#00a3ff]/20 text-[#00a3ff] font-black flex items-center justify-center flex-shrink-0 text-[11px]">2</span>
                  <span className="flex items-center gap-1 flex-wrap">
                    Ketuk tombol <strong>Share</strong> (ikon kotak dengan panah ke atas <Share className="w-3.5 h-3.5 inline text-[#00a3ff]" /> di bilah bawah Safari).
                  </span>
                </div>
                <div className="flex items-start gap-2">
                  <span className="w-5 h-5 rounded-full bg-[#00a3ff]/20 text-[#00a3ff] font-black flex items-center justify-center flex-shrink-0 text-[11px]">3</span>
                  <span className="flex items-center gap-1 flex-wrap">
                    Gulir ke bawah, lalu pilih menu <strong>"Tambah ke Layar Utama"</strong> (atau <em>Add to Home Screen</em> <PlusSquare className="w-3.5 h-3.5 inline text-[#00a3ff]" />).
                  </span>
                </div>
                <div className="flex items-start gap-2">
                  <span className="w-5 h-5 rounded-full bg-[#00a3ff]/20 text-[#00a3ff] font-black flex items-center justify-center flex-shrink-0 text-[11px]">4</span>
                  <span>Tekan tombol <strong>"Tambah" (Add)</strong> di pojok kanan atas.</span>
                </div>
              </div>
              <p className="text-[11px] text-emerald-400 font-medium">
                Selesai! Ikon McTify akan langsung muncul di Layar Utama iPhone Anda dan berjalan secara penuh (Full Screen) persis seperti aplikasi App Store resmi.
              </p>
            </div>

            {/* iOS Method 2: Sideload IPA Package */}
            <div className="bg-white/5 border border-white/10 rounded-xl p-4 space-y-2.5">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-bold uppercase tracking-wider text-white/60">
                  Metode 2 • Sideload .IPA (Flutter Native)
                </span>
                <span className="text-[10px] text-amber-300 font-semibold">
                  Perlu PC / AltStore
                </span>
              </div>
              <p className="text-xs text-[#94a3b8] leading-relaxed">
                Jika Anda ingin memasang aplikasi native murni dari file paket <code>.ipa</code>:
              </p>
              <a
                href="/downloads/McTify-v1.4.17.ipa"
                download="McTify-v1.4.17.ipa"
                className="w-full py-2.5 px-3 rounded-lg bg-emerald-500/20 hover:bg-emerald-500/30 border border-emerald-500/30 text-emerald-300 font-bold text-xs flex items-center justify-center gap-2 transition-all active:scale-95 no-underline"
              >
                <Download className="w-3.5 h-3.5 text-emerald-300" />
                <span>Download Paket McTify-v1.4.17.ipa</span>
              </a>
              <div className="text-[11px] text-[#94a3b8] space-y-1 bg-black/30 p-2.5 rounded-lg">
                <p className="font-semibold text-white flex items-center gap-1">
                  <Laptop className="w-3.5 h-3.5 text-white/70" />
                  <span>Cara Pasang File .IPA ke iPhone:</span>
                </p>
                <p>Apple tidak mengizinkan file .ipa langsung di-klik dari browser iPhone. Anda perlu alat bantu sideload seperti <strong>Sideloadly</strong> (di PC/Mac sambung kabel ke iPhone) atau <strong>AltStore / Scarlet</strong>.</p>
              </div>
            </div>
          </div>
        )}

        {/* Links to Download Center & GitHub */}
        <div className="pt-2 border-t border-white/10 flex items-center justify-between text-xs text-[#b3b3b3]">
          <a
            href="/downloads"
            className="text-[#00a3ff] hover:underline inline-flex items-center gap-1 font-semibold"
          >
            <span>Buka Halaman Download Center Lengkap</span>
            <span>→</span>
          </a>
          <a
            href="https://github.com/Bagaskara02/Mctify/releases/tag/v1.4.17"
            target="_blank"
            rel="noopener noreferrer"
            className="text-[#b3b3b3] hover:text-white inline-flex items-center gap-1 text-[11px]"
          >
            <span>GitHub Releases</span>
            <ExternalLink className="w-3 h-3" />
          </a>
        </div>

        {/* Close Modal Button */}
        <button
          onClick={onClose}
          className="w-full py-2.5 rounded-full text-xs text-[#b3b3b3] hover:text-white bg-white/5 hover:bg-white/10 transition-colors font-medium"
        >
          Tutup
        </button>
      </div>
    </div>
  );
}
