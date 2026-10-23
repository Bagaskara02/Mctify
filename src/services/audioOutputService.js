/**
 * Audio Output Device Manager
 * Allows switching between Speakers, Headphones, Bluetooth Earphones using Web Audio & setSinkId API
 */
class AudioOutputService {
  constructor() {
    this.selectedDeviceId = typeof window !== 'undefined' 
      ? localStorage.getItem('mcmusic_audio_output_id') || 'default'
      : 'default';
    this.devices = [];
    this.subscribers = new Set();
    this.isSupported = typeof navigator !== 'undefined' && 
      !!(navigator.mediaDevices && (navigator.mediaDevices.enumerateDevices || navigator.mediaDevices.selectAudioOutput));

    if (typeof window !== 'undefined' && navigator.mediaDevices) {
      navigator.mediaDevices.addEventListener?.('devicechange', () => {
        this.refreshDevices();
      });
      // Initial fetch
      setTimeout(() => this.refreshDevices(), 500);
    }
  }

  subscribe(callback) {
    this.subscribers.add(callback);
    callback(this.devices, this.selectedDeviceId);
    return () => this.subscribers.delete(callback);
  }

  notify() {
    for (const cb of this.subscribers) {
      try {
        cb(this.devices, this.selectedDeviceId);
      } catch (_) {}
    }
  }

  async refreshDevices() {
    if (!this.isSupported) return [];
    try {
      const allDevices = await navigator.mediaDevices.enumerateDevices();
      const outputDevices = allDevices.filter((d) => d.kind === 'audiooutput');
      this.devices = outputDevices;
      this.notify();
      return outputDevices;
    } catch (e) {
      console.warn('[AudioOutputService] refreshDevices error:', e);
      return [];
    }
  }

  async selectSystemDevice(mediaElement = null, audioContext = null) {
    if (typeof navigator !== 'undefined' && navigator.mediaDevices?.selectAudioOutput) {
      try {
        const device = await navigator.mediaDevices.selectAudioOutput();
        if (device && device.deviceId) {
          await this.setOutputDevice(device.deviceId, mediaElement, audioContext);
          await this.refreshDevices();
          return device;
        }
      } catch (err) {
        if (err.name !== 'AbortError' && err.name !== 'NotAllowedError') {
          console.warn('[AudioOutputService] selectAudioOutput note:', err);
        }
      }
    }
    return null;
  }

  async setOutputDevice(deviceId, mediaElement = null, audioContext = null) {
    this.selectedDeviceId = deviceId || 'default';
    try {
      localStorage.setItem('mcmusic_audio_output_id', this.selectedDeviceId);
    } catch (_) {}

    // Apply to media element if supported
    if (mediaElement && typeof mediaElement.setSinkId === 'function') {
      try {
        await mediaElement.setSinkId(deviceId);
      } catch (err) {
        console.warn('[AudioOutputService] setSinkId mediaElement note:', err);
      }
    }

    // Apply to audio context if supported
    if (audioContext && typeof audioContext.setSinkId === 'function') {
      try {
        await audioContext.setSinkId(deviceId);
      } catch (err) {
        console.warn('[AudioOutputService] setSinkId audioContext note:', err);
      }
    }

    this.notify();
  }

  getDeviceId() {
    return this.selectedDeviceId;
  }
}

export const audioOutputService = new AudioOutputService();
