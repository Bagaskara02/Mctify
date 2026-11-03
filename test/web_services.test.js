import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { AUDIO_QUALITIES, audioQualityService } from '../src/services/audioQualityService.js';
import { webAudioEqualizer, DEFAULT_EQ_SETTINGS } from '../src/services/webAudioEqualizer.js';
import { getHighResArtworkUrl, isCleanPopularTrack, DEFAULT_ARTWORK } from '../src/services/musicApi.js';

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

describe('Music API Artwork & Filter Tests', () => {
  it('transforms low-res album art to high-res versions', () => {
    // Google User Content
    const googleLow = 'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj';
    assert.equal(getHighResArtworkUrl(googleLow), 'https://lh3.googleusercontent.com/abc=w800-h800-l90-rj');

    // YouTube Thumbnail
    const ytLow = 'https://i.ytimg.com/vi/123/default.jpg?sqp=abc';
    assert.equal(getHighResArtworkUrl(ytLow), 'https://i.ytimg.com/vi/123/hq720.jpg');

    // Apple / iTunes
    const appleLow = 'https://is1-ssl.mzstatic.com/image/thumb/123/100x100bb.jpg';
    assert.equal(getHighResArtworkUrl(appleLow), 'https://is1-ssl.mzstatic.com/image/thumb/123/1000x1000bb.jpg');

    // Fallback on null/empty
    assert.equal(getHighResArtworkUrl(null), DEFAULT_ARTWORK);
    assert.equal(getHighResArtworkUrl(''), DEFAULT_ARTWORK);
  });

  it('filters out non-radio tracks, covers, and karaoke versions', () => {
    // Legitimate track
    const goodTrack = { title: 'Yellow', artist: 'Coldplay', duration: 269 };
    assert.equal(isCleanPopularTrack(goodTrack), true);

    // Banned keywords
    assert.equal(isCleanPopularTrack({ title: 'Yellow (Karaoke Version)', artist: 'Coldplay', duration: 269 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow - Guitar Tutorial', artist: 'Someone', duration: 269 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow (Cover by John)', artist: 'John', duration: 200 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow (Sped Up)', artist: 'Coldplay', duration: 180 }), false);

    // Duration boundaries (< 75s or > 450s)
    assert.equal(isCleanPopularTrack({ title: 'Yellow', artist: 'Coldplay', duration: 30 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow', artist: 'Coldplay', duration: 600 }), false);

    // Incomplete data
    assert.equal(isCleanPopularTrack(null), false);
    assert.equal(isCleanPopularTrack({ title: '' }), false);
  });
});
