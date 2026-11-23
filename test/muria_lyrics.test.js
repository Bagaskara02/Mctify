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
    assert.ok(intro.endTime >= 20.0, `Intro end should be >= 20.0s, got ${intro.endTime}`);

    // Check first vocal line starts at ~00:21.4 (calibrated to vocal onset)
    const line1 = res.lines[1];
    assert.strictEqual(line1.text, 'Mungkin esok atau lusa');
    assert.strictEqual(line1.time, 21.4);
    assert.ok(line1.endTime > 23.0, `Line 1 end should be > 23.0s, got ${line1.endTime}`);

    // Check second vocal line
    const line2 = res.lines[2];
    assert.strictEqual(line2.text, 'Ku tak lagi di sini');
    assert.strictEqual(line2.time, 24.0);

    // Check verse 1 line
    const verse1 = res.lines.find(l => l.text === "I'm going out from the block");
    assert.ok(verse1, 'Expected verse 1 line to exist');
    assert.strictEqual(verse1.time, 42.8);
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
      assert.strictEqual(res.lines[1].time, 21.4);
    }
  });

  it('prevents stopword artist hijack, substring title mismatch, Unicode stripping, and 180/210 placeholder duration rejection', async () => {
    const {
      normalizeLyricText,
      scoreLyricCandidate,
    } = await import('../src/utils/lyricsMatcher.js');
    const { findVerifiedStudioLrc, cleanTrackMetadata } = await import('../api/lyrics.js');

    // 1. Preserves Korean Hangul & Japanese Kana/Kanji in normalizeLyricText
    assert.strictEqual(normalizeLyricText('사랑인가봐 (Love, Maybe)'), '사랑인가봐');
    assert.strictEqual(normalizeLyricText('夜に駆ける [Official]'), '夜に駆ける');

    // 2. Rejects different artist sharing stopword "The" ("The Weeknd" vs "The 1975")
    const stopwordArtistScore = scoreLyricCandidate({
      candTitle: 'One Of The Girls',
      candArtist: 'The 1975',
      candDurationSec: 244,
      targetTitle: 'One Of The Girls',
      targetArtist: 'The Weeknd',
      targetDurationSec: 244,
    });
    assert.ok(stopwordArtistScore < 0, `Expected negative score for wrong "The" artist, got ${stopwordArtistScore}`);

    // 3. Keeps exact title + exact artist match valid even if targetDurationSec was a 180s placeholder
    const placeholderDurScore = scoreLyricCandidate({
      candTitle: 'One Of The Girls',
      candArtist: 'The Weeknd',
      candDurationSec: 244,
      targetTitle: 'One Of The Girls',
      targetArtist: 'The Weeknd',
      targetDurationSec: 180,
      isSynced: true,
    });
    assert.ok(placeholderDurScore >= 700, `Expected exact title+artist match to survive placeholder duration, got ${placeholderDurScore}`);

    // 4. Extracts real artist and title when YouTube channel is a record label
    const cleaned = cleanTrackMetadata('Dewa 19 - Kangen (Official Video)', 'Aquarius Musikindo');
    assert.strictEqual(cleaned.artist, 'Dewa 19');
    assert.strictEqual(cleaned.title, 'Kangen');

    // 5. Does not hijack short unrelated titles in findVerifiedStudioLrc
    assert.strictEqual(findVerifiedStudioLrc('In', 'Some Artist'), null);
    assert.strictEqual(findVerifiedStudioLrc('You', 'Some Artist'), null);
  });
});
