import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { AUDIO_QUALITIES, audioQualityService } from '../src/services/audioQualityService.js';
import { webAudioEqualizer, DEFAULT_EQ_SETTINGS } from '../src/services/webAudioEqualizer.js';

describe('Web Audio Quality Service Tests', () => {
  it('defines realistic YouTube audio bitrates up to 160 kbps ceiling', () => {
    assert.equal(AUDIO_QUALITIES.length, 3);
    const bitrates = AUDIO_QUALITIES.map(q => q.bitrate);
    assert.deepEqual(bitrates, ['64 kbps', '128 kbps', '160 kbps']);

    const highQuality = AUDIO_QUALITIES.find(q => q.id === 'high');
    assert.ok(highQuality);
    assert.equal(highQuality.recommended, true);
    assert.ok(highQuality.codec.includes('Opus'));
  });

  it('provides reliable fallback when invalid quality ID is provided', () => {
    const fallback = audioQualityService.getQualityDetails('invalid_unknown_id');
    assert.equal(fallback.id, 'high');
    assert.equal(fallback.bitrate, '160 kbps');
  });
});

describe('Web Audio Equalizer Tests', () => {
  it('initializes with 5 bands and studio defaults', () => {
    assert.equal(DEFAULT_EQ_SETTINGS.bands.length, 5);
    assert.equal(DEFAULT_EQ_SETTINGS.selectedPreset, 'Bass Boost');
    assert.equal(typeof DEFAULT_EQ_SETTINGS.bassBoost, 'number');
  });

  it('calculates acoustic loudness multiplier with bounded headroom', () => {
    // Disabled Equalizer should return neutral unity multiplier (1.0)
    const disabledMult = webAudioEqualizer.getLoudnessMultiplier({ isEnabled: false });
    assert.equal(disabledMult, 1.0);

    // Flat Equalizer (0 dB everywhere, 0 bass boost) should return neutral 1.0
    const flatMult = webAudioEqualizer.getLoudnessMultiplier({
      isEnabled: true,
      bands: [0, 0, 0, 0, 0],
      bassBoost: 0,
    });
    assert.ok(Math.abs(flatMult - 1.0) < 0.05);

    // Boosted Equalizer should return > 1.0 but clamped safely within +6 dB (< 2.05)
    const boostedMult = webAudioEqualizer.getLoudnessMultiplier({
      isEnabled: true,
      bands: [12, 8, 4, 2, 2],
      bassBoost: 100,
    });
    assert.ok(boostedMult > 1.0);
    assert.ok(boostedMult <= 2.05, `Boosted mult ${boostedMult} should be <= 2.05 (+6 dB ceiling)`);
  });
});

describe('Web Audio Output Service Tests', () => {
  it('initializes safely and provides default device fallback', async () => {
    const { audioOutputService } = await import('../src/services/audioOutputService.js');
    assert.equal(typeof audioOutputService.getDeviceId(), 'string');
    assert.ok(['default', ''].includes(audioOutputService.getDeviceId()) || typeof audioOutputService.getDeviceId() === 'string');
    
    let receivedDeviceId = null;
    const unsubscribe = audioOutputService.subscribe((devs, deviceId) => {
      receivedDeviceId = deviceId;
    });
    assert.ok(receivedDeviceId !== null);
    unsubscribe();
  });
});
