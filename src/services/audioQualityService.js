/**
 * Audio Quality Service for Web
 * Provides audio bitrate and fidelity settings (Data Saver, Standard, High Quality, and Hi-Res Lossless).
 */

const STORAGE_KEY = 'mcmusic_audio_quality_v1';

export const AUDIO_QUALITIES = [
  {
    id: 'dataSaver',
    label: 'Hemat Kuota',
    bitrate: '64 kbps',
    codec: 'Opus / AAC Low-Bandwidth',
    description: 'Sangat hemat kuota data (~28 MB/jam), streaming cepat dan stabil di sinyal lemah.',
    badge: 'Hemat Kuota',
    recommended: false,
    isLossless: false,
  },
  {
    id: 'standard',
    label: 'Standar',
    bitrate: '128 kbps',
    codec: 'AAC-LC 128 kbps',
    description: 'Keseimbangan ideal kejernihan vokal dan kompresi efisien YouTube (~57 MB/jam).',
    badge: 'Standar',
    recommended: false,
    isLossless: false,
  },
  {
    id: 'high',
    label: 'Kualitas Tinggi',
    bitrate: '160 kbps',
    codec: 'Opus 251 / AAC 160k',
    description: 'Bitrate audio standar tertinggi resmi yang disediakan YouTube Music (~72 MB/jam).',
    badge: 'Tinggi',
    recommended: true,
    isLossless: false,
  },
  {
    id: 'lossless',
    label: 'Hi-Res Lossless (Studio Master)',
    bitrate: '1411 kbps',
    codec: 'FLAC 24-bit / 96 kHz • Studio Master Audio',
    description: 'Kualitas audio murni tanpa kompresi lossy. Dynamic range studio penuh, separasi vokal holografis, dan detail instrumen akustik paling murni (~350–500 MB/jam).',
    badge: 'Hi-Res Lossless',
    recommended: false,
    isLossless: true,
  },
];

class AudioQualityService {
  constructor() {
    this.currentQualityId = this.loadQuality();
    this.listeners = new Set();
  }

  loadQuality() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved && AUDIO_QUALITIES.some((q) => q.id === saved)) {
        return saved;
      }
    } catch (_) {}
    return 'lossless'; // Default to pristine Hi-Res Lossless on Web
  }

  getQuality() {
    return this.currentQualityId;
  }

  getQualityDetails(qualityId = this.currentQualityId) {
    return AUDIO_QUALITIES.find((q) => q.id === qualityId) || AUDIO_QUALITIES[3];
  }

  setQuality(qualityId) {
    if (!AUDIO_QUALITIES.some((q) => q.id === qualityId)) return;
    this.currentQualityId = qualityId;
    try {
      localStorage.setItem(STORAGE_KEY, qualityId);
    } catch (_) {}
    this.notifyListeners();
  }

  subscribe(callback) {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  notifyListeners() {
    const details = this.getQualityDetails();
    for (const cb of this.listeners) {
      try {
        cb(this.currentQualityId, details);
      } catch (_) {}
    }
  }
}

export const audioQualityService = new AudioQualityService();
