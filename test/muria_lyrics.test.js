import { describe, it } from 'node:test';
import assert from 'node:assert';
import { getLyrics } from '../api/lyrics.js';
import { lyricsService } from '../src/services/lyricsService.js';

describe('Studio Synced Lyrics: Muria - Brangkat Tests', () => {
  it('resolves verified studio synced LRC via /api/lyrics with exact intro interlude and first vocal line', async () => {
    const res = await getLyrics('Brangkat', 'Muria', 215);
    assert.strictEqual(res.synced, true);
    assert.strictEqual(res.source, 'Verified Studio Synced Master');
    assert.ok(res.lines.length >= 70, `Expected at least 70 lines, got ${res.lines.length}`);

    // Check intro interlude (beat intro before vocal starts)
    const intro = res.lines[0];
    assert.strictEqual(intro.isInstrumental, true);
    assert.ok(intro.time <= 1.0, `Intro start should be <= 1.0s, got ${intro.time}`);
    assert.ok(intro.endTime >= 10.0, `Intro end should be >= 10.0s, got ${intro.endTime}`);

    // Check first vocal line starts at ~00:10.7
    const line1 = res.lines[1];
    assert.strictEqual(line1.text, 'Mungkin esok atau lusa');
    assert.strictEqual(line1.time, 10.7);
    assert.ok(line1.endTime > 12.5, `Line 1 end should be > 12.5s, got ${line1.endTime}`);

    // Check second vocal line
    const line2 = res.lines[2];
    assert.strictEqual(line2.text, 'Ku tak lagi di sini');
    assert.strictEqual(line2.time, 13.2);

    // Check verse 1 line
    const verse1 = res.lines.find(l => l.text === "I'm going out from the block");
    assert.ok(verse1, 'Expected verse 1 line to exist');
    assert.strictEqual(verse1.time, 31.8);
  });

  it('matches across various dirty streaming titles (Topic, Lirik, composite, etc.) in client lyricsService', async () => {
    const titles = [
      ['BRANGKAT', 'Muria - Topic'],
      ['Muria - Brangkat', ''],
      ['MURIA - BRANGKAT Lirik', ''],
      ['Brangkat', 'Muria Mardika'],
    ];

    for (const [title, artist] of titles) {
      const res = await lyricsService.fetchLyrics(artist, title, 215);
      assert.ok(res, `Expected lyrics for ${title} - ${artist}`);
      assert.strictEqual(res.synced, true);
      assert.strictEqual(res.lines[1].text, 'Mungkin esok atau lusa');
      assert.strictEqual(res.lines[1].time, 10.7);
    }
  });
});
