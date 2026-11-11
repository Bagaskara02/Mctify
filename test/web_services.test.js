import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { AUDIO_QUALITIES, audioQualityService } from '../src/services/audioQualityService.js';
import { webAudioEqualizer, DEFAULT_EQ_SETTINGS } from '../src/services/webAudioEqualizer.js';
import { storageService } from '../src/services/storageService.js';
import { buildSpotifyShuffleDeck } from '../src/utils/shuffle.js';
import { 
  getHighResArtworkUrl, 
  isCleanPopularTrack, 
  cleanTrackTitle, 
  spreadArtists, 
  DEFAULT_ARTWORK 
} from '../src/services/musicApi.js';

describe('Web Audio Quality Service Tests', () => {
  it('defines audio bitrates including standard tiers and Hi-Res Lossless', () => {
    assert.equal(AUDIO_QUALITIES.length, 4);
    const bitrates = AUDIO_QUALITIES.map(q => q.bitrate);
    assert.deepEqual(bitrates, ['64 kbps', '128 kbps', '160 kbps', '1411 kbps']);

    const losslessQuality = AUDIO_QUALITIES.find(q => q.id === 'lossless');
    assert.ok(losslessQuality);
    assert.equal(losslessQuality.isLossless, true);
    assert.ok(losslessQuality.codec.includes('FLAC'));
  });

  it('provides reliable fallback when invalid quality ID is provided', () => {
    const fallback = audioQualityService.getQualityDetails('invalid_unknown_id');
    assert.equal(fallback.id, 'lossless');
    assert.equal(fallback.bitrate, '1411 kbps');
  });
});

describe('Web Audio Equalizer Tests', () => {
  it('initializes with 5 bands and studio defaults', () => {
    assert.equal(DEFAULT_EQ_SETTINGS.bands.length, 5);
    assert.equal(DEFAULT_EQ_SETTINGS.selectedPreset, 'Bass Boost');
    assert.equal(typeof DEFAULT_EQ_SETTINGS.bassBoost, 'number');
  });

  it('calculates acoustic loudness multiplier with bounded headroom', () => {
    const disabledMult = webAudioEqualizer.getLoudnessMultiplier({ isEnabled: false });
    assert.equal(disabledMult, 1.0);

    const flatMult = webAudioEqualizer.getLoudnessMultiplier({
      isEnabled: true,
      bands: [0, 0, 0, 0, 0],
      bassBoost: 0,
    });
    assert.ok(Math.abs(flatMult - 1.0) < 0.05);

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
    const googleLow = 'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj';
    assert.equal(getHighResArtworkUrl(googleLow), 'https://lh3.googleusercontent.com/abc=w800-h800-l90-rj');

    const ytLow = 'https://i.ytimg.com/vi/123/default.jpg?sqp=abc';
    assert.equal(getHighResArtworkUrl(ytLow), 'https://i.ytimg.com/vi/123/hq720.jpg');

    const appleLow = 'https://is1-ssl.mzstatic.com/image/thumb/123/100x100bb.jpg';
    assert.equal(getHighResArtworkUrl(appleLow), 'https://is1-ssl.mzstatic.com/image/thumb/123/1000x1000bb.jpg');

    assert.equal(getHighResArtworkUrl(null), DEFAULT_ARTWORK);
    assert.equal(getHighResArtworkUrl(''), DEFAULT_ARTWORK);
  });

  it('filters out non-radio tracks, covers, and karaoke versions', () => {
    const goodTrack = { title: 'Yellow', artist: 'Coldplay', duration: 269 };
    assert.equal(isCleanPopularTrack(goodTrack), true);

    assert.equal(isCleanPopularTrack({ title: 'Yellow (Karaoke Version)', artist: 'Coldplay', duration: 269 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow - Guitar Tutorial', artist: 'Someone', duration: 269 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow (Cover by John)', artist: 'John', duration: 200 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow (Sped Up)', artist: 'Coldplay', duration: 180 }), false);

    assert.equal(isCleanPopularTrack({ title: 'Yellow', artist: 'Coldplay', duration: 30 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Yellow', artist: 'Coldplay', duration: 600 }), false);

    assert.equal(isCleanPopularTrack(null), false);
    assert.equal(isCleanPopularTrack({ title: '' }), false);
  });
});

describe('Yugen Inspirations: Title Cleaning & Artist Spreading Tests', () => {
  it('cleans noisy YouTube video metadata, videoIds, and bracket noise', () => {
    // 11-char videoId bracket
    assert.equal(cleanTrackTitle('Midsummer Madness [dQw4w9WgXcQ]'), 'Midsummer Madness');

    // Video noise in brackets
    assert.equal(cleanTrackTitle('Die With A Smile (Official Music Video)'), 'Die With A Smile');
    assert.equal(cleanTrackTitle('Golden Hour [Visualizer]'), 'Golden Hour');
    assert.equal(cleanTrackTitle('Fix You (Live 4K Remastered)'), 'Fix You');

    // Suffix noise
    assert.equal(cleanTrackTitle('Sialan - Official Video'), 'Sialan');

    // Legitimate song title brackets preserved
    assert.equal(cleanTrackTitle('Telepatía (feat. Kali Uchis)'), 'Telepatía (feat. Kali Uchis)');

    // Outer quotes stripped
    assert.equal(cleanTrackTitle('"Glimpse of Us"'), 'Glimpse of Us');
    assert.equal(cleanTrackTitle('“Komang”'), 'Komang');
  });

  it('spreads tracks across unique artists in balanced round-robin cycles', () => {
    const tracks = [
      { id: '1', title: 'Slow Dancing', artist: 'Joji' },
      { id: '2', title: 'Glimpse of Us', artist: 'Joji' },
      { id: '3', title: 'Sanctuary', artist: 'Joji' },
      { id: '4', title: 'LIMBO', artist: 'Keshi' },
      { id: '5', title: 'Gesk', artist: 'Keshi' },
      { id: '6', title: 'Lowkey', artist: 'NIKI' },
      { id: '7', title: 'Every Summertime', artist: 'NIKI' },
    ];

    const spread = spreadArtists(tracks, 2);
    assert.ok(spread.length <= 6); // Max 2 per artist = 2 * 3 = 6

    // The first 3 tracks must be from 3 different artists!
    const first3Artists = spread.slice(0, 3).map(t => t.artist.toLowerCase());
    const uniqueFirst3 = new Set(first3Artists);
    assert.equal(uniqueFirst3.size, 3, 'First round must contain one track per unique artist');
  });
});

describe('Spotify Search History Persistence Tests', () => {
  it('adds, deduplicates, removes, and clears recent search queries', () => {
    const store = new Map();
    globalThis.localStorage = {
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => store.set(k, String(v)),
      removeItem: (k) => store.delete(k),
    };

    storageService.clearRecentSearches();
    assert.deepEqual(storageService.getRecentSearches(), []);

    storageService.addRecentSearch({ query: 'Tulus', title: 'Tulus', subtitle: 'Artis', type: 'artist' });
    storageService.addRecentSearch({ query: 'Hati-Hati di Jalan', title: 'Hati-Hati di Jalan', subtitle: 'Lagu • Tulus', type: 'track' });
    storageService.addRecentSearch({ query: 'Tulus', title: 'Tulus', subtitle: 'Artis', type: 'artist' });

    const list = storageService.getRecentSearches();
    assert.equal(list.length, 2, 'Should deduplicate identical search entries');
    assert.equal(list[0].title, 'Tulus', 'Most recent entry should move to top');

    storageService.removeRecentSearch('Tulus', 'artist');
    assert.equal(storageService.getRecentSearches().length, 1);

    storageService.clearRecentSearches();
    assert.deepEqual(storageService.getRecentSearches(), []);
  });
});

describe('Spotify Balanced Fisher-Yates Shuffle Deck Tests', () => {
  it('plays every song once without repeats, keeps anchor at index 0, and spreads artists', () => {
    const playlist = [
      { id: '1', title: 'Track A1', artist: 'Tulus' },
      { id: '2', title: 'Track A2', artist: 'Tulus' },
      { id: '3', title: 'Track B1', artist: 'NIKI' },
      { id: '4', title: 'Track B2', artist: 'NIKI' },
      { id: '5', title: 'Track C1', artist: 'Coldplay' },
      { id: '6', title: 'Track C2', artist: 'Coldplay' },
      { id: '7', title: 'Track D1', artist: 'Bernadya' },
    ];

    const anchor = playlist[0];
    const deck = buildSpotifyShuffleDeck(playlist, anchor);

    assert.equal(deck.length, playlist.length, 'Shuffled deck must contain every track once');
    assert.equal(deck[0].id, anchor.id, 'Anchor track must remain at index 0');

    const uniqueIds = new Set(deck.map((t) => t.id));
    assert.equal(uniqueIds.size, playlist.length, 'No duplicate or skipped tracks in deck');

    for (let i = 1; i < deck.length; i++) {
      assert.notEqual(
        deck[i].artist.toLowerCase(),
        deck[i - 1].artist.toLowerCase(),
        `Expected adjacent tracks ${i - 1} and ${i} not to share the same artist when avoidable`
      );
    }
  });
});
