import React, { useState } from 'react';
import { 
  X, 
  Link, 
  FileText, 
  Sparkles, 
  Upload, 
  Loader2, 
  CheckCircle2, 
  AlertCircle, 
  Music, 
  Play,
  ListPlus
} from 'lucide-react';
import { playlistImporter } from '../services/playlistImporter';

export default function ImportPlaylistModal({ isOpen, onClose, onPlaylistImported }) {
  const [activeTab, setActiveTab] = useState('spotify'); // 'spotify' | 'text' | 'presets' | 'json'
  const [urlInput, setUrlInput] = useState('');
  const [textInput, setTextInput] = useState('');
  const [playlistTitle, setPlaylistTitle] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [progressInfo, setProgressInfo] = useState(null);
  const [errorMsg, setErrorMsg] = useState(null);
  const [importedResult, setImportedResult] = useState(null);

  if (!isOpen) return null;

  const handleClose = () => {
    setUrlInput('');
    setTextInput('');
    setPlaylistTitle('');
    setErrorMsg(null);
    setImportedResult(null);
    setProgressInfo(null);
    onClose();
  };

  // 1. Import from Spotify Link
  const handleImportSpotify = async (e) => {
    e.preventDefault();
    if (!urlInput.trim()) return;

    setIsLoading(true);
    setErrorMsg(null);
    setImportedResult(null);

    try {
      const playlist = await playlistImporter.importFromSpotify(urlInput, (curr, total, title) => {
        setProgressInfo({ current: curr, total, message: `Mencocokkan lagu penuh: ${title}` });
      });

      setImportedResult(playlist);
    } catch (err) {
      setErrorMsg(err.message || 'Gagal mengimpor playlist Spotify. Pastikan link publik.');
    } finally {
      setIsLoading(false);
      setProgressInfo(null);
    }
  };

  // 2. Import from Plain Text
  const handleImportText = async (e) => {
    e.preventDefault();
    if (!textInput.trim()) return;

    setIsLoading(true);
    setErrorMsg(null);
    setImportedResult(null);

    try {
      const name = playlistTitle.trim() || 'Playlist Kustom';
      const playlist = await playlistImporter.importFromTextList(textInput, name, (curr, total, title) => {
        setProgressInfo({ current: curr, total, message: `Mencocokkan lagu: ${title}` });
      });

      setImportedResult(playlist);
    } catch (err) {
      setErrorMsg(err.message || 'Gagal memproses daftar teks lagu.');
    } finally {
      setIsLoading(false);
      setProgressInfo(null);
    }
  };

  // 3. Import from 1-Click Preset
  const handleImportPreset = async (preset) => {
    setIsLoading(true);
    setErrorMsg(null);
    setImportedResult(null);

    try {
      const playlist = await playlistImporter.loadPreset(preset, (curr, total, title) => {
        setProgressInfo({ current: curr, total, message: `Memuat: ${title}` });
      });

      setImportedResult(playlist);
    } catch (err) {
      setErrorMsg(err.message || 'Gagal memuat preset playlist.');
    } finally {
      setIsLoading(false);
      setProgressInfo(null);
    }
  };

  // 4. Import from Backup JSON
  const handleFileUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsLoading(true);
    setErrorMsg(null);
    setImportedResult(null);

    try {
      const playlist = await playlistImporter.importFromJsonFile(file);
      setImportedResult(playlist);
    } catch (err) {
      setErrorMsg(err.message || 'File JSON tidak valid.');
    } finally {
      setIsLoading(false);
    }
  };

  // Save imported playlist to Library
  const handleSaveToLibrary = () => {
    if (!importedResult) return;
    onPlaylistImported(importedResult);
    handleClose();
  };

  const presets = playlistImporter.getPresetPlaylists();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-black/80 backdrop-blur-md">
      <div className="relative w-full max-w-2xl bg-[#181818] border border-white/10 rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh] text-white">
        {/* Header */}
        <div className="flex items-center justify-between px-5 sm:px-6 py-4 sm:py-5 border-b border-[#282828]">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#00a3ff] flex items-center justify-center shadow-lg shadow-[#00a3ff]/30">
              <ListPlus className="w-5 h-5 text-black stroke-[2.5]" />
            </div>
            <div>
              <h2 className="text-white font-bold text-base sm:text-lg">Import Playlist</h2>
              <p className="text-[#b3b3b3] text-xs">Impor dari Spotify, YouTube Music, Teks, atau Backup</p>
            </div>
          </div>
          <button
            onClick={handleClose}
            className="p-2 rounded-full text-[#b3b3b3] hover:text-white hover:bg-white/10 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="flex border-b border-[#282828] px-4 sm:px-6 bg-[#141414] overflow-x-auto no-scrollbar">
          <button
            onClick={() => { setActiveTab('spotify'); setImportedResult(null); }}
            className={`py-3.5 px-3 sm:px-4 text-xs font-bold border-b-2 whitespace-nowrap transition-all flex items-center gap-2 ${
              activeTab === 'spotify'
                ? 'border-[#00a3ff] text-[#00a3ff]'
                : 'border-transparent text-[#b3b3b3] hover:text-white'
            }`}
          >
            <span className="w-2 h-2 rounded-full bg-[#00a3ff]" />
            Link Spotify
          </button>

          <button
            onClick={() => { setActiveTab('text'); setImportedResult(null); }}
            className={`py-3.5 px-3 sm:px-4 text-xs font-bold border-b-2 whitespace-nowrap transition-all flex items-center gap-2 ${
              activeTab === 'text'
                ? 'border-[#00a3ff] text-[#00a3ff]'
                : 'border-transparent text-[#b3b3b3] hover:text-white'
            }`}
          >
            <FileText className="w-3.5 h-3.5" />
            Paste Daftar Lagu
          </button>

          <button
            onClick={() => { setActiveTab('presets'); setImportedResult(null); }}
            className={`py-3.5 px-3 sm:px-4 text-xs font-bold border-b-2 whitespace-nowrap transition-all flex items-center gap-2 ${
              activeTab === 'presets'
                ? 'border-[#00a3ff] text-[#00a3ff]'
                : 'border-transparent text-[#b3b3b3] hover:text-white'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5 text-amber-400" />
            1-Klik Preset
          </button>

          <button
            onClick={() => { setActiveTab('json'); setImportedResult(null); }}
            className={`py-3.5 px-3 sm:px-4 text-xs font-bold border-b-2 whitespace-nowrap transition-all flex items-center gap-2 ${
              activeTab === 'json'
                ? 'border-[#00a3ff] text-[#00a3ff]'
                : 'border-transparent text-[#b3b3b3] hover:text-white'
            }`}
          >
            <Upload className="w-3.5 h-3.5" />
            Backup JSON
          </button>
        </div>

        {/* Content Body */}
        <div className="p-4 sm:p-6 overflow-y-auto flex-1 space-y-6">
          {/* Error Banner */}
          {errorMsg && (
            <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-sm flex items-start gap-3">
              <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
              <div>
                <p className="font-semibold mb-1">Pemberitahuan</p>
                <p className="text-xs leading-relaxed text-rose-300">{errorMsg}</p>
              </div>
            </div>
          )}

          {/* Progress Loading Bar */}
          {isLoading && (
            <div className="p-5 rounded-xl bg-[#242424] border border-white/5 space-y-3">
              <div className="flex items-center justify-between text-xs">
                <span className="flex items-center gap-2 text-white font-medium">
                  <Loader2 className="w-4 h-4 animate-spin text-[#00a3ff]" />
                  {progressInfo?.message || 'Memproses playlist...'}
                </span>
                {progressInfo?.total && (
                  <span className="text-[#b3b3b3] tabular-nums font-mono">
                    {progressInfo.current} / {progressInfo.total}
                  </span>
                )}
              </div>
              <div className="w-full h-1.5 rounded-full bg-white/10 overflow-hidden">
                <div 
                  className="h-full bg-gradient-to-r from-[#00a3ff] to-[#60c5ff] transition-all duration-300 rounded-full"
                  style={{
                    width: progressInfo?.total 
                      ? `${(progressInfo.current / progressInfo.total) * 100}%` 
                      : '80%',
                  }}
                />
              </div>
            </div>
          )}

          {/* Result Preview (if import succeeded) */}
          {importedResult ? (
            <div className="p-5 rounded-xl bg-[#242424] border border-white/10 space-y-4">
              <div className="flex items-center gap-4">
                <img
                  src={importedResult.cover}
                  alt={importedResult.name}
                  className="w-16 h-16 rounded-lg object-cover shadow-lg bg-[#333]"
                />
                <div>
                  <div className="flex items-center gap-2">
                    <span className="px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-[#00a3ff]/20 text-[#00a3ff] border border-[#00a3ff]/30">
                      Siap Disimpan
                    </span>
                    <span className="text-[#b3b3b3] text-xs">
                      {importedResult.tracks.length} lagu penuh
                    </span>
                  </div>
                  <h3 className="text-white font-bold text-lg mt-1">{importedResult.name}</h3>
                  <p className="text-[#b3b3b3] text-xs">{importedResult.description}</p>
                </div>
              </div>

              {/* Sample of tracks */}
              <div className="max-h-48 overflow-y-auto rounded-lg bg-[#181818] border border-white/5 divide-y divide-white/5">
                {importedResult.tracks.map((t, i) => (
                  <div key={t.id || i} className="flex items-center justify-between px-3 py-2 text-xs">
                    <div className="flex items-center gap-2.5 min-w-0">
                      <span className="text-[#888888] tabular-nums w-4 text-right">{i + 1}</span>
                      <img src={t.artwork} alt="" className="w-7 h-7 rounded object-cover" />
                      <div className="truncate">
                        <span className="text-white font-medium">{t.title}</span>
                        <span className="text-[#b3b3b3] ml-1.5">• {t.artist}</span>
                      </div>
                    </div>
                    <span className="text-[#00a3ff] text-[10px] font-semibold">Lagu Penuh</span>
                  </div>
                ))}
              </div>

              <div className="flex items-center justify-end gap-3 pt-2">
                <button
                  onClick={() => setImportedResult(null)}
                  className="px-4 py-2 rounded-full text-[#b3b3b3] hover:text-white text-xs font-semibold"
                >
                  Batal
                </button>
                <button
                  onClick={handleSaveToLibrary}
                  className="px-6 py-2.5 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] text-black font-bold text-xs shadow-lg shadow-[#00a3ff]/25 flex items-center gap-2 active:scale-95 transition-all"
                >
                  <CheckCircle2 className="w-4 h-4" />
                  Simpan ke Koleksi Saya
                </button>
              </div>
            </div>
          ) : (
            <>
              {/* TAB 1: SPOTIFY LINK */}
              {activeTab === 'spotify' && (
                <form onSubmit={handleImportSpotify} className="space-y-4">
                  <div className="space-y-2">
                    <label className="text-neutral-300 text-xs font-semibold block">
                      URL Playlist Spotify
                    </label>
                    <input
                      type="url"
                      value={urlInput}
                      onChange={(e) => setUrlInput(e.target.value)}
                      placeholder="https://open.spotify.com/playlist/4EK6n0S5FqMXdIsdbSpKaC"
                      className="w-full px-4 py-3 rounded-xl bg-[#242424] border border-white/10 text-white placeholder-neutral-500 text-sm focus:outline-none focus:border-[#00a3ff] transition-colors"
                      disabled={isLoading}
                    />
                    <p className="text-[#b3b3b3] text-xs leading-relaxed">
                      Tempelkan tautan playlist publik Spotify apa saja. Backend kami akan langsung mengekstrak daftar lagu dan mencocokkan setiap lagu ke versi penuh YouTube Music!
                    </p>
                  </div>

                  <div className="pt-2 flex justify-end">
                    <button
                      type="submit"
                      disabled={isLoading || !urlInput.trim()}
                      className="px-6 py-3 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] disabled:opacity-50 text-black font-bold text-xs shadow-lg shadow-[#00a3ff]/25 flex items-center gap-2 active:scale-95 transition-all"
                    >
                      {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Link className="w-4 h-4" />}
                      Ambil & Impor Playlist
                    </button>
                  </div>
                </form>
              )}

              {/* TAB 2: PASTE TEXT TRACKLIST */}
              {activeTab === 'text' && (
                <form onSubmit={handleImportText} className="space-y-4">
                  <div className="space-y-2">
                    <label className="text-neutral-300 text-xs font-semibold block">
                      Nama Playlist
                    </label>
                    <input
                      type="text"
                      value={playlistTitle}
                      onChange={(e) => setPlaylistTitle(e.target.value)}
                      placeholder="Playlist Favoritku"
                      className="w-full px-4 py-2.5 rounded-xl bg-[#242424] border border-white/10 text-white placeholder-neutral-500 text-sm focus:outline-none focus:border-[#00a3ff]"
                    />
                  </div>

                  <div className="space-y-2">
                    <label className="text-neutral-300 text-xs font-semibold block">
                      Daftar Lagu (Satu lagu per baris)
                    </label>
                    <textarea
                      rows={6}
                      value={textInput}
                      onChange={(e) => setTextInput(e.target.value)}
                      placeholder={`Justin Bieber - DAISIES\nRex Orange County - AMAZING\nColdplay - Yellow\nBernadya - Satu Bulan`}
                      className="w-full px-4 py-3 rounded-xl bg-[#242424] border border-white/10 text-white placeholder-neutral-500 text-xs font-mono focus:outline-none focus:border-[#00a3ff] leading-relaxed"
                      disabled={isLoading}
                    />
                  </div>

                  <div className="pt-2 flex justify-end">
                    <button
                      type="submit"
                      disabled={isLoading || !textInput.trim()}
                      className="px-6 py-3 rounded-full bg-[#00a3ff] hover:bg-[#2eb4ff] disabled:opacity-50 text-black font-bold text-xs shadow-lg shadow-[#00a3ff]/25 flex items-center gap-2 active:scale-95 transition-all"
                    >
                      {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <FileText className="w-4 h-4" />}
                      Cocokkan Lagu
                    </button>
                  </div>
                </form>
              )}

              {/* TAB 3: 1-CLICK PRESETS */}
              {activeTab === 'presets' && (
                <div className="space-y-3">
                  <p className="text-[#b3b3b3] text-xs">
                    Pilih preset siap pakai untuk langsung menikmati playlist penuh:
                  </p>
                  <div className="grid grid-cols-1 gap-2.5">
                    {presets.map((preset) => (
                      <div
                        key={preset.id}
                        className="flex items-center justify-between p-3 rounded-xl bg-[#242424] hover:bg-[#2c2c2c] transition-all group"
                      >
                        <div className="flex items-center gap-3 min-w-0">
                          <img
                            src={preset.cover}
                            alt={preset.name}
                            className="w-12 h-12 rounded-lg object-cover"
                          />
                          <div className="min-w-0">
                            <h4 className="text-white font-semibold text-sm group-hover:text-[#00a3ff] transition-colors">
                              {preset.name}
                            </h4>
                            <p className="text-[#b3b3b3] text-xs truncate max-w-sm">
                              {preset.description}
                            </p>
                          </div>
                        </div>

                        <button
                          onClick={() => handleImportPreset(preset)}
                          disabled={isLoading}
                          className="px-4 py-2 rounded-full bg-white/10 hover:bg-[#00a3ff] hover:text-black text-white text-xs font-semibold flex items-center gap-1.5 transition-all active:scale-95"
                        >
                          <Play className="w-3.5 h-3.5 fill-current" />
                          Impor
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* TAB 4: JSON BACKUP */}
              {activeTab === 'json' && (
                <div className="space-y-4">
                  <label className="flex flex-col items-center justify-center p-8 rounded-2xl border-2 border-dashed border-white/20 hover:border-[#00a3ff] bg-[#242424] cursor-pointer transition-colors group">
                    <Upload className="w-10 h-10 text-neutral-500 group-hover:text-[#00a3ff] transition-colors mb-2" />
                    <span className="text-white font-medium text-sm">Upload File Backup Playlist (.json)</span>
                    <input
                      type="file"
                      accept=".json"
                      onChange={handleFileUpload}
                      className="hidden"
                    />
                  </label>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
