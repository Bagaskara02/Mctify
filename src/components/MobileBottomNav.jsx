import React from 'react';
import { Home, Search, Library, PlusCircle } from 'lucide-react';

export default function MobileBottomNav({
  currentView,
  setCurrentView,
  selectedPlaylistId,
  setSelectedPlaylistId,
  onOpenImportModal,
}) {
  return (
    <nav className="md:hidden fixed bottom-0 left-0 right-0 h-14 bg-black/95 backdrop-blur-xl border-t border-white/10 flex items-center justify-around z-40 px-2 select-none">
      {/* Home / Beranda */}
      <button
        onClick={() => {
          setCurrentView('discover');
          setSelectedPlaylistId(null);
        }}
        className={`flex flex-col items-center justify-center flex-1 py-1 transition-colors ${
          currentView === 'discover' && !selectedPlaylistId
            ? 'text-[#00a3ff]'
            : 'text-[#b3b3b3] hover:text-white'
        }`}
      >
        <Home className="w-5 h-5" />
        <span className="text-[10px] font-semibold mt-1">Beranda</span>
      </button>

      {/* Search / Cari */}
      <button
        onClick={() => {
          setCurrentView('search');
          setSelectedPlaylistId(null);
        }}
        className={`flex flex-col items-center justify-center flex-1 py-1 transition-colors ${
          currentView === 'search' && !selectedPlaylistId
            ? 'text-[#00a3ff]'
            : 'text-[#b3b3b3] hover:text-white'
        }`}
      >
        <Search className="w-5 h-5" />
        <span className="text-[10px] font-semibold mt-1">Cari</span>
      </button>

      {/* Library / Koleksi Kamu */}
      <button
        onClick={() => {
          setCurrentView('liked');
          setSelectedPlaylistId(null);
        }}
        className={`flex flex-col items-center justify-center flex-1 py-1 transition-colors ${
          currentView === 'liked' || selectedPlaylistId
            ? 'text-[#00a3ff]'
            : 'text-[#b3b3b3] hover:text-white'
        }`}
      >
        <Library className="w-5 h-5" />
        <span className="text-[10px] font-semibold mt-1">Koleksi</span>
      </button>

      {/* Import Playlist Modal Trigger */}
      <button
        onClick={onOpenImportModal}
        className="flex flex-col items-center justify-center flex-1 py-1 text-[#b3b3b3] hover:text-[#00a3ff] transition-colors"
      >
        <PlusCircle className="w-5 h-5 text-[#00a3ff]" />
        <span className="text-[10px] font-semibold mt-1">Import</span>
      </button>
    </nav>
  );
}
