/**
 * Audio Output Device Manager
 * Allows switching between Speakers, Headphones, Bluetooth Earphones using Web Audio & setSinkId API
 */
class AudioOutputService {
  constructor() {
    this.selectedDeviceId = typeof window !== 'undefined' 
      ? localStorage.getItem('mcmusic_audio_output_id') || 'default'
      : 'default';
    this.selectedDeviceLabel = typeof window !== 'undefined'
      ? localStorage.getItem('mcmusic_audio_output_label') || ''
      : '';
    this.devices = [];
    this.subscribers = new Set();
    this.isSupported = typeof navigator !== 'undefined' && 
      !!(navigator.mediaDevices && (navigator.mediaDevices.enumerateDevices || navigator.mediaDevices.selectAudioOutput));

    if (typeof window !== 'undefined' && navigator.mediaDevices) {
      navigator.mediaDevices.addEventListener?.('devicechange', () => {
        this.refreshDevices();
      });
      // Initial fetch
      setTimeout(() => this.refreshDevices(), 300);
    }
  }

  subscribe(callback) {
    this.subscribers.add(callback);
    callback(this.devices, this.selectedDeviceId, this.selectedDeviceLabel);
    return () => this.subscribers.delete(callback);
  }

  notify() {
    for (const cb of this.subscribers) {
      try {
        cb(this.devices, this.selectedDeviceId, this.selectedDeviceLabel);
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

  /**
   * Request Windows audio device access to reveal real hardware labels
   */
  async requestDeviceAccess(mediaElement = null, audioContext = null) {
    if (!this.isSupported) return false;

    // 1. Try Windows / Chrome native selectAudioOutput first
    if (typeof navigator !== 'undefined' && navigator.mediaDevices?.selectAudioOutput) {
      try {
        const device = await navigator.mediaDevices.selectAudioOutput();
        if (device && device.deviceId) {
          await this.setOutputDevice(device.deviceId, mediaElement, audioContext, device.label);
          await this.refreshDevices();
          return true;
        }
      } catch (err) {
        if (err.name === 'AbortError') return false;
      }
    }

    // 2. Unlock device names by briefly requesting audio permission
    if (typeof navigator !== 'undefined' && navigator.mediaDevices?.getUserMedia) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        // Immediately stop microphone track to keep privacy pristine
        stream.getTracks().forEach((track) => track.stop());
        await this.refreshDevices();
        return true;
      } catch (err) {
        console.warn('[AudioOutputService] getUserMedia permission note:', err);
      }
    }

    return false;
  }

  async selectSystemDevice(mediaElement = null, audioContext = null) {
    if (typeof navigator !== 'undefined' && navigator.mediaDevices?.selectAudioOutput) {
      try {
        const device = await navigator.mediaDevices.selectAudioOutput();
        if (device && device.deviceId) {
          await this.setOutputDevice(device.deviceId, mediaElement, audioContext, device.label);
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

  async setOutputDevice(deviceId, mediaElement = null, audioContext = null, label = '') {
    this.selectedDeviceId = deviceId || 'default';
    if (label) {
      this.selectedDeviceLabel = label;
    } else if (deviceId === 'default') {
      this.selectedDeviceLabel = 'Speakers / Output Default Sistem';
    } else {
      const match = this.devices.find((d) => d.deviceId === deviceId);
      if (match?.label) {
        this.selectedDeviceLabel = match.label;
      }
    }

    try {
      localStorage.setItem('mcmusic_audio_output_id', this.selectedDeviceId);
      localStorage.setItem('mcmusic_audio_output_label', this.selectedDeviceLabel);
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

  getDeviceLabel() {
    return this.selectedDeviceLabel;
  }
}

export const audioOutputService = new AudioOutputService();
