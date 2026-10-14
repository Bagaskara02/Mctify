/**
 * Audio Quality Service for Web
 * Provides transparent audio bitrate settings matching Flutter (Data Saver, Standard, High Quality).
 * Transparently reflects YouTube Music audio stream limits (~160 kbps Opus ceiling).
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
  },
  {
    id: 'standard',
    label: 'Standar',
    bitrate: '128 kbps',
    codec: 'AAC-LC 128 kbps',
    description: 'Keseimbangan ideal kejernihan vokal dan kompresi efisien YouTube (~57 MB/jam).',
    badge: 'Standar',
    recommended: false,
  },
  {
    id: 'high',
    label: 'Kualitas Tinggi (Maksimal)',
    bitrate: '160 kbps',
    codec: 'Opus 251 / AAC 160k',
    description: 'Bitrate audio tertinggi resmi yang disediakan server YouTube Music tanpa upscaling palsu.',
    badge: 'Maksimal YouTube',
    recommended: true,
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
    return 'high';
  }

  getQuality() {
    return this.currentQualityId;
  }

  getQualityDetails(qualityId = this.currentQualityId) {
    return AUDIO_QUALITIES.find((q) => q.id === qualityId) || AUDIO_QUALITIES[2];
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
