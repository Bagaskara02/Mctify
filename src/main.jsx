import { StrictMode, Component } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error('McMusic ErrorBoundary caught crash:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-[#07070a] text-white flex flex-col items-center justify-center p-6 text-center select-none">
          <div className="w-16 h-16 rounded-full bg-[#00a3ff]/10 border border-[#00a3ff]/30 flex items-center justify-center mb-4 text-[#00a3ff] text-2xl font-bold">
            ♪
          </div>
          <h2 className="text-xl font-bold mb-2">McMusic Terkendala Memuat</h2>
          <p className="text-slate-400 text-sm max-w-md mb-6 leading-relaxed">
            {this.state.error?.message || 'Terjadi galat sementara pada data lokal browser. Silakan muat ulang atau pulihkan data cache.'}
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <button
              onClick={() => window.location.reload()}
              className="px-5 py-2.5 rounded-full bg-[#00a3ff] text-black font-bold text-xs hover:bg-[#2eb4ff] transition-all active:scale-95 shadow-lg shadow-[#00a3ff]/20"
            >
              Muat Ulang Halaman
            </button>
            <button
              onClick={() => {
                try {
                  localStorage.removeItem('mcmusic_play_counts_v2');
                  localStorage.removeItem('mcmusic_settings_v2');
                  localStorage.removeItem('mcmusic_web_equalizer_v2');
                } catch (_) {}
                window.location.reload();
              }}
              className="px-5 py-2.5 rounded-full bg-white/10 text-white font-semibold text-xs hover:bg-white/15 transition-all border border-white/20 active:scale-95"
            >
              Pulihkan Cache & Buka
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
)
