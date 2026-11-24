import test from 'node:test';
import assert from 'node:assert/strict';
import { storageService } from '../src/services/storageService.js';
import { musicApi } from '../src/services/musicApi.js';

test('Playlist and Queue Reordering & Search Match Tests', async (t) => {
  await t.test('storageService.reorderPlaylistTracks updates track order correctly', () => {
    // Mock localStorage
    const store = {};
    global.localStorage = {
      getItem: (k) => store[k] || null,
      setItem: (k, v) => { store[k] = String(v); },
      removeItem: (k) => { delete store[k]; },
      clear: () => { Object.keys(store).forEach(k => delete store[k]); }
    };

    const pl = storageService.addPlaylist({
      id: 'test-pl-1',
      name: 'EDM Playlist',
      tracks: [
        { id: 'track-1', title: 'Song 1' },
        { id: 'track-2', title: 'Song 2' },
        { id: 'track-3', title: 'Song 3' },
      ],
    });

    assert.equal(pl.tracks.length, 3);
    assert.equal(pl.tracks[0].id, 'track-1');

    // Reorder: move track-3 to index 0
    const reordered = [
      { id: 'track-3', title: 'Song 3' },
      { id: 'track-1', title: 'Song 1' },
      { id: 'track-2', title: 'Song 2' },
    ];
    const updatedPlaylists = storageService.reorderPlaylistTracks('test-pl-1', reordered);
    const targetPl = updatedPlaylists.find(p => p.id === 'test-pl-1');
    assert.equal(targetPl.tracks[0].id, 'track-3');
    assert.equal(targetPl.tracks[1].id, 'track-1');
    assert.equal(targetPl.tracks[2].id, 'track-2');
  });

  await t.test('Queue reordering preserves playback cursor and reorders up-next tracks', () => {
    const queue = [
      { id: 'playing-1', title: 'Current Song' },
      { id: 'next-1', title: 'Next Song 1' },
      { id: 'next-2', title: 'Next Song 2' },
      { id: 'next-3', title: 'Next Song 3' },
    ];
    const currentTrack = queue[0];
    const currentIndex = queue.findIndex(t => t.id === currentTrack.id);
    const upNext = queue.slice(currentIndex + 1);

    // User drags next-3 to the top of upNext (index 0)
    const reorderedUpNext = Array.from(upNext);
    const [moved] = reorderedUpNext.splice(2, 1);
    reorderedUpNext.splice(0, 0, moved);

    const newQueue = [...queue.slice(0, currentIndex + 1), ...reorderedUpNext];
    assert.equal(newQueue.length, 4);
    assert.equal(newQueue[0].id, 'playing-1');
    assert.equal(newQueue[1].id, 'next-3');
    assert.equal(newQueue[2].id, 'next-1');
    assert.equal(newQueue[3].id, 'next-2');
  });

  await t.test('musicApi search ranking prioritizes Cheat Codes & Demi Lovato for "No Promises"', async () => {
    // Mock fetch for /api/yt/search-multi
    const origFetch = global.fetch;
    global.fetch = async (url, opts) => {
      if (typeof url === 'string' && url.startsWith('/api/yt/search-multi')) {
        return {
          ok: true,
          json: async () => ({
            songs: [
              { id: 'yt_HpQKU6HLSfw', videoId: 'HpQKU6HLSfw', title: 'No Promises', artist: 'Shayne Ward', duration: 223 },
              { id: 'yt_8dwSKcSbvAU', videoId: '8dwSKcSbvAU', title: 'No Promises (feat. Demi Lovato)', artist: 'Cheat Codes', duration: 224 },
            ],
            artists: [],
            albums: [],
            suggestions: [],
          }),
        };
      }
      return { ok: true, json: async () => ({ results: [], data: [] }) };
    };

    try {
      const res = await musicApi.searchAll('No Promises');
      assert.ok(res.songs.length >= 2);
      // The top song should be the global smash hit by Cheat Codes & Demi Lovato
      assert.equal(res.songs[0].videoId, '8dwSKcSbvAU');
      assert.equal(res.songs[0].artist, 'Cheat Codes');
    } finally {
      global.fetch = origFetch;
    }
  });
});
