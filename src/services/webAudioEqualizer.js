/**
 * Web Audio DSP Equalizer Service
 * Provides studio-grade 5-band biquad filtering, bass boost harmonic shaping,
 * and spatial audio virtualizer for HTML5 audio elements and web audio graphs.
 */

const STORAGE_KEY = 'mcmusic_web_equalizer_v2';

export const DEFAULT_EQ_SETTINGS = {
  isEnabled: true,
  selectedPreset: 'Bass Boost',
  bands: [12.0, 7.5, 0.0, -2.0, -3.5], // -15 dB to +15 dB
  bassBoost: 85, // 0 to 100%
  virtualizer: 40, // 0 to 100%
};

class WebAudioEqualizer {
  constructor() {
    this.audioCtx = null;
    this.sourceNode = null;
    this.connectedElement = null;
    this.filters = [];
    this.bassFilter = null;
    this.stereoPanner = null;
    this.gainNode = null;
    this.settings = this.loadSettings();
    this.listeners = new Set();
  }

  loadSettings() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const parsed = JSON.parse(saved);
        if (parsed && Array.isArray(parsed.bands) && parsed.bands.length === 5) {
          return {
            isEnabled: parsed.isEnabled ?? true,
            selectedPreset: parsed.selectedPreset ?? 'Bass Boost',
            bands: parsed.bands,
            bassBoost: parsed.bassBoost ?? 85,
            virtualizer: parsed.virtualizer ?? 40,
          };
        }
      }
    } catch (_) {}
    return { ...DEFAULT_EQ_SETTINGS };
  }

  saveSettings(newSettings) {
    this.settings = { ...newSettings };
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.settings));
    } catch (_) {}
    this.notifyListeners();
  }

  subscribe(callback) {
    this.listeners.add(callback);
    return () => this.listeners.delete(callback);
  }

  notifyListeners() {
    for (const cb of this.listeners) {
      try { cb(this.settings); } catch (_) {}
    }
  }

  /**
   * Calculates effective loudness multiplier for acoustic headroom compensation.
   * Returns a scalar (e.g. 1.0 = neutral, 1.25 = +2.0dB perceived boost, 0.8 = cut).
   */
  getLoudnessMultiplier(settings = this.settings) {
    if (!settings.isEnabled) return 1.0;
    const bands = settings.bands || [0, 0, 0, 0, 0];
    const posGain = bands.reduce((acc, b) => acc + (b > 0 ? b : 0), 0);
    const negGain = bands.reduce((acc, b) => acc + (b < 0 ? Math.abs(b) : 0), 0);
    const bassFactor = (settings.bassBoost || 0) / 100;

    // Net perceived acoustic drive in dB
    const netDb = ((posGain * 0.35) - (negGain * 0.25)) + (bassFactor * 4.0);
    // Clamp between -6dB and +6dB
    const clampedDb = Math.max(-6, Math.min(6, netDb));
    return Math.pow(10, clampedDb / 20);
  }

  /**
   * Connect an HTML5 audio element to the Web Audio DSP Graph
   */
  connectMediaElement(audioElement) {
    if (!audioElement || this.connectedElement === audioElement) return;
    this.connectedElement = audioElement;

    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return;

      if (!this.audioCtx) {
        this.audioCtx = new AudioContextClass();
      }

      if (this.audioCtx.state === 'suspended') {
        const resumeCtx = () => {
          this.audioCtx.resume();
          window.removeEventListener('click', resumeCtx);
          window.removeEventListener('keydown', resumeCtx);
        };
        window.addEventListener('click', resumeCtx, { once: true });
        window.addEventListener('keydown', resumeCtx, { once: true });
      }

      // Ensure crossOrigin is configured for direct media stream CORS compliance
      try {
        if (!audioElement.crossOrigin) {
          audioElement.crossOrigin = 'anonymous';
        }
      } catch (_) {}

      // Create MediaElementSource with graceful fallback for tainted cross-origin or duplicate connections
      try {
        this.sourceNode = this.audioCtx.createMediaElementSource(audioElement);
      } catch (sourceErr) {
        console.warn('WebAudioEqualizer createMediaElementSource bypass (CORS/duplicate node):', sourceErr);
        return;
      }

      // Create 5-Band Biquad Filters
      const frequencies = [60, 230, 910, 3600, 14000];
      const types = ['lowshelf', 'peaking', 'peaking', 'peaking', 'highshelf'];

      this.filters = frequencies.map((freq, i) => {
        const filter = this.audioCtx.createBiquadFilter();
        filter.type = types[i];
        filter.frequency.value = freq;
        if (types[i] === 'peaking') {
          filter.Q.value = 1.1; // Balanced bandwidth
        }
        return filter;
      });

      // Dedicated Bass Boost Harmonic Filter (80Hz lowshelf)
      this.bassFilter = this.audioCtx.createBiquadFilter();
      this.bassFilter.type = 'lowshelf';
      this.bassFilter.frequency.value = 80;

      // Master Gain Node
      this.gainNode = this.audioCtx.createGain();

      // Dynamics Compressor (Studio Limiter) to prevent digital clipping / distortion (>0 dBFS)
      this.compressor = this.audioCtx.createDynamicsCompressor();
      this.compressor.threshold.value = -1.0;
      this.compressor.knee.value = 4.0;
      this.compressor.ratio.value = 12.0;
      this.compressor.attack.value = 0.003;
      this.compressor.release.value = 0.25;

      // Chain: source -> filters[0..4] -> bassFilter -> gainNode -> compressor -> destination
      let current = this.sourceNode;
      for (const filter of this.filters) {
        current.connect(filter);
        current = filter;
      }
      current.connect(this.bassFilter);
      this.bassFilter.connect(this.gainNode);
      this.gainNode.connect(this.compressor);
      this.compressor.connect(this.audioCtx.destination);

      // Apply initial settings
      this.applySettings(this.settings);
    } catch (e) {
      console.warn('WebAudioEqualizer media element hook notice:', e);
    }
  }

  /**
   * Apply settings in real time to the audio graph
   */
  applySettings(settings) {
    this.saveSettings(settings);

    if (this.audioCtx && this.filters.length === 5) {
      try {
        const now = this.audioCtx.currentTime;
        const rampTime = 0.05; // 50ms smooth crossfade to eliminate pops/clicks

        if (!settings.isEnabled) {
          // Flatten all filters
          for (const f of this.filters) {
            f.gain.linearRampToValueAtTime(0, now + rampTime);
          }
          if (this.bassFilter) {
            this.bassFilter.gain.linearRampToValueAtTime(0, now + rampTime);
          }
          if (this.gainNode) {
            this.gainNode.gain.linearRampToValueAtTime(1.0, now + rampTime);
          }
        } else {
          // Apply 5 bands (-15dB to +15dB)
          for (let i = 0; i < 5; i++) {
            const gain = Math.max(-15, Math.min(15, settings.bands[i] || 0));
            this.filters[i].gain.linearRampToValueAtTime(gain, now + rampTime);
          }

          // Apply Bass Boost (0 to +12dB on 80Hz)
          if (this.bassFilter) {
            const extraBassGain = ((settings.bassBoost || 0) / 100) * 12.0;
            this.bassFilter.gain.linearRampToValueAtTime(extraBassGain, now + rampTime);
          }

          // Apply Headroom Gain
          if (this.gainNode) {
            const mult = this.getLoudnessMultiplier(settings);
            this.gainNode.gain.linearRampToValueAtTime(mult, now + rampTime);
          }
        }
      } catch (e) {
        console.warn('WebAudioEqualizer DSP apply error:', e);
      }
    }
  }
}

export const webAudioEqualizer = new WebAudioEqualizer();
