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

const YoutubeIcon = ({ className = "w-4 h-4" }) => (
  <svg className={className} viewBox="0 0 24 24" fill="currentColor">
    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
  </svg>
);

export default function TopNavBar({
  currentView,
  setCurrentView,
  searchQuery,
  setSearchQuery,
  onOpenDownloadApp,
  onCreatePlaylist,
  onOpenImportYouTube,
}) {
  return (
    <header className="h-16 bg-black px-4 sm:px-6 flex items-center justify-between gap-4 select-none z-30">
      {/* Left: Spotify-style Logo */}
      <div 
        onClick={() => setCurrentView('discover')}
        className="flex items-center gap-2 cursor-pointer flex-shrink-0 group"
      >
        <div className="w-9 h-9 rounded-full bg-[#1ed760] flex items-center justify-center shadow-md group-hover:scale-105 transition-transform">
          <Music className="w-5 h-5 text-black stroke-[2.5]" />
        </div>
        <span className="font-bold text-lg tracking-tight text-white hidden sm:inline-block">
          McMusic
        </span>
      </div>

      {/* Center: Home Button + Capsule Search Bar (Spotify Desktop Spec) */}
      <div className="flex items-center gap-2 flex-1 max-w-xl mx-auto">
        {/* Home circular button */}
        <button
          onClick={() => setCurrentView('discover')}
          className={`w-12 h-12 rounded-full flex items-center justify-center transition-all flex-shrink-0 hover:scale-105 active:scale-95 ${
            currentView === 'discover'
              ? 'bg-[#1f1f1f] text-white'
              : 'bg-[#1f1f1f] text-[#b3b3b3] hover:text-white hover:bg-[#282828]'
          }`}
          title="Beranda"
        >
          <Home className="w-5 h-5" />
        </button>

        {/* Search Input Bar */}
        <div className="relative flex-1 group">
          <Search className="w-5 h-5 text-[#b3b3b3] group-hover:text-white transition-colors absolute left-4 top-1/2 -translate-y-1/2 pointer-events-none" />
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
            className="w-full h-12 pl-12 pr-10 rounded-full bg-[#1f1f1f] hover:bg-[#282828] focus:bg-[#282828] border border-transparent focus:border-white text-sm text-white placeholder-[#b3b3b3] focus:outline-none transition-all cursor-text"
          />

          {searchQuery ? (
            <button
              onClick={() => {
                setSearchQuery('');
              }}
              className="absolute right-4 top-1/2 -translate-y-1/2 p-1 text-[#b3b3b3] hover:text-white"
            >
              <X className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={() => setCurrentView('search')}
              className="absolute right-4 top-1/2 -translate-y-1/2 text-[#b3b3b3] hover:text-white"
              title="Jelajahi Semua"
            >
              <Compass className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Right: Quick Actions & Download App */}
      <div className="flex items-center gap-2 sm:gap-3 flex-shrink-0">
        <button
          onClick={onCreatePlaylist}
          className="hidden md:flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-[#242424] hover:bg-[#2e2e2e] text-white text-xs font-bold transition-all active:scale-95"
          title="Buat Playlist Baru"
        >
          <Plus className="w-4 h-4 text-[#1ed760]" />
          <span>Buat</span>
        </button>

        <button
          onClick={onOpenImportYouTube}
          className="hidden sm:flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-[#242424] hover:bg-[#2e2e2e] text-white text-xs font-bold transition-all active:scale-95"
          title="Import Lagu dari YouTube"
        >
          <YoutubeIcon className="w-3.5 h-3.5 fill-[#ff4e4e]" />
          <span>Import YouTube</span>
        </button>

        <button
          onClick={onOpenDownloadApp}
          className="px-4 py-2 rounded-full bg-white hover:bg-[#e8e8e8] text-black text-xs font-bold flex items-center gap-1.5 shadow-sm transition-all hover:scale-105 active:scale-95"
          title="Download Aplikasi Mobile"
        >
          <Download className="w-4 h-4 stroke-[2.5]" />
          <span>Download App</span>
        </button>
      </div>
    </header>
  );
}
