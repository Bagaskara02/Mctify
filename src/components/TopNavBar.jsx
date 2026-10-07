import { 
  Home, 
  Search, 
  Plus, 
  Download, 
  Compass, 
  Bell, 
  X,
  Sparkles,
  Music
} from 'lucide-react';

export default function TopNavBar({
  currentView,
  setCurrentView,
  searchQuery,
  setSearchQuery,
  onOpenDownloadApp,
  onCreatePlaylist,
}) {
  return (
    <header className="h-16 bg-black px-4 sm:px-6 flex items-center justify-between gap-4 border-b border-white/[0.04] select-none z-30">
      {/* Left: Spotify-style Logo */}
      <div 
        onClick={() => setCurrentView('discover')}
        className="flex items-center gap-2 cursor-pointer flex-shrink-0 group"
      >
        <div className="w-9 h-9 rounded-full bg-[#00a3ff] flex items-center justify-center shadow-lg shadow-[#00a3ff]/30 group-hover:scale-105 transition-transform">
          <Music className="w-5 h-5 text-black stroke-[2.5]" />
        </div>
        <span className="font-black text-lg tracking-tight text-white hidden sm:inline-block">
          McMusic
        </span>
      </div>

      {/* Center: Home Button + Search Input Pill (Spotify Desktop Spec) */}
      <div className="flex items-center gap-2 flex-1 max-w-xl mx-auto">
        {/* Home circular button */}
        <button
          onClick={() => setCurrentView('discover')}
          className={`w-11 h-11 rounded-full flex items-center justify-center transition-all flex-shrink-0 ${
            currentView === 'discover'
              ? 'bg-[#242424] text-white'
              : 'bg-[#1f1f1f] text-[#b3b3b3] hover:text-white hover:bg-[#282828]'
          }`}
          title="Beranda"
        >
          <Home className="w-5 h-5" />
        </button>

        {/* Search Input Bar */}
        <div className="relative flex-1">
          <Search className="w-5 h-5 text-[#b3b3b3] absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            type="text"
            value={searchQuery || ''}
            onFocus={() => {
              if (currentView !== 'search') setCurrentView('search');
            }}
            onClick={() => {
              if (currentView !== 'search') setCurrentView('search');
            }}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              if (currentView !== 'search') setCurrentView('search');
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && currentView !== 'search') {
                setCurrentView('search');
              }
            }}
            placeholder="Apa yang ingin kamu putar?"
            className="w-full pl-11 pr-10 py-2.5 rounded-full bg-[#242424] hover:bg-[#2a2a2a] border border-transparent focus:border-white text-sm text-white placeholder-[#b3b3b3] focus:outline-none transition-all shadow-inner cursor-text"
          />

          {searchQuery ? (
            <button
              onClick={() => {
                setSearchQuery('');
              }}
              className="absolute right-3.5 top-1/2 -translate-y-1/2 p-1 text-[#b3b3b3] hover:text-white"
            >
              <X className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={() => setCurrentView('search')}
              className="absolute right-3.5 top-1/2 -translate-y-1/2 text-[#b3b3b3] hover:text-white"
              title="Jelajahi Semua"
            >
              <Compass className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Right: Quick Actions & Profile */}
      <div className="flex items-center gap-2 sm:gap-3 flex-shrink-0">
        <button
          onClick={onCreatePlaylist}
          className="hidden md:flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-[#242424] hover:bg-[#2e2e2e] text-white text-xs font-bold transition-all active:scale-95 border border-white/5"
          title="Buat Playlist Baru"
        >
          <Plus className="w-4 h-4 text-[#00a3ff]" />
          <span>Buat</span>
        </button>

        <button
          onClick={onOpenDownloadApp}
          className="px-4 py-1.5 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black text-xs font-black flex items-center gap-1.5 shadow-md shadow-[#00a3ff]/20 transition-all hover:scale-105 active:scale-95"
          title="Download Aplikasi Flutter Mobile"
        >
          <Download className="w-4 h-4 stroke-[2.5]" />
          <span>Download App</span>
        </button>
      </div>
    </header>
  );
}
