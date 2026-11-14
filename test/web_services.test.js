import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { AUDIO_QUALITIES, audioQualityService } from '../src/services/audioQualityService.js';
import { webAudioEqualizer, DEFAULT_EQ_SETTINGS } from '../src/services/webAudioEqualizer.js';
import { storageService } from '../src/services/storageService.js';
import { buildSpotifyShuffleDeck } from '../src/utils/shuffle.js';
import { scoreLyricCandidate } from '../src/utils/lyricsMatcher.js';
import { 
  parseUrlSyncParams, 
  parseTargetSeconds, 
  generateUrlSyncLink, 
  formatPlaybackSeconds 
} from '../src/utils/urlSync.js';
import { 
  getHighResArtworkUrl, 
  isCleanPopularTrack, 
  cleanTrackTitle, 
  spreadArtists, 
  DEFAULT_ARTWORK,
  musicApi
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

describe('Spotify Web Lyrics Candidate Matcher Tests', () => {
  it('rewards exact artist + duration match and rejects unrelated artist or wrong duration remix', () => {
    const exactScore = scoreLyricCandidate({
      candTitle: 'Yellow',
      candArtist: 'Coldplay',
      candDurationSec: 267,
      targetTitle: 'Yellow',
      targetArtist: 'Coldplay',
      targetDurationSec: 269,
      isSynced: true,
      isSyllable: false,
    });

    const wrongArtistScore = scoreLyricCandidate({
      candTitle: 'Yellow',
      candArtist: 'Unrelated Cover Band',
      candDurationSec: 267,
      targetTitle: 'Yellow',
      targetArtist: 'Coldplay',
      targetDurationSec: 269,
      isSynced: true,
      isSyllable: true,
    });

    const wrongDurationRemixScore = scoreLyricCandidate({
      candTitle: 'Yellow (Slowed + Remix)',
      candArtist: 'Coldplay',
      candDurationSec: 340,
      targetTitle: 'Yellow',
      targetArtist: 'Coldplay',
      targetDurationSec: 269,
      isSynced: true,
      isSyllable: false,
    });

    assert.ok(exactScore >= 1400, `Expected high score for exact match, got ${exactScore}`);
    assert.ok(wrongArtistScore < 0, `Wrong artist must be rejected (< 0), got ${wrongArtistScore}`);
    assert.ok(wrongDurationRemixScore < exactScore, 'Wrong remix duration must score far below studio exact match');
  });
});

describe('Web YouTube Resolver & Embed Fallback Tests', () => {
  it('passes title/artist/exclude params, skips cached blocked IDs, and falls back to search-multi', async () => {
    const origFetch = globalThis.fetch;
    const requestedUrls = [];

    globalThis.fetch = async (url) => {
      const urlStr = String(url);
      requestedUrls.push(urlStr);

      if (urlStr.startsWith('/api/yt/search?')) {
        if (!urlStr.includes('exclude=badVid1')) {
          return {
            ok: true,
            json: async () => ({
              videoId: 'badVid1',
              title: 'Location Unknown',
              artist: 'HONNE',
              duration: 329,
              thumbnail: 'https://i.ytimg.com/vi/badVid1/default.jpg',
            }),
          };
        }
        return { ok: false, status: 404 };
      }

      if (urlStr.startsWith('/api/yt/search-multi?')) {
        return {
          ok: true,
          json: async () => ({
            songs: [
              { videoId: 'badVid1', title: 'Location Unknown', artist: 'HONNE', duration: 329 },
              { videoId: 'goodVid2', title: 'Location Unknown', artist: 'HONNE', duration: 329, artwork: '' },
            ],
          }),
        };
      }

      return { ok: false, status: 404 };
    };

    try {
      const first = await musicApi.resolveYouTubeMatch('Location Unknown ◐', 'HONNE', 329);
      assert.equal(first?.videoId, 'badVid1');
      assert.ok(requestedUrls[0].includes('title=Location%20Unknown'), 'Must pass sanitized title param');
      assert.ok(requestedUrls[0].includes('artist=HONNE'), 'Must pass artist param');

      const recovered = await musicApi.resolveYouTubeMatch('Location Unknown ◐', 'HONNE', 329, ['badVid1']);
      assert.equal(recovered?.videoId, 'goodVid2', 'Must bypass badVid1 cache and recover via search-multi');
      assert.ok(
        requestedUrls.some((u) => u.includes('exclude=badVid1')),
        'Must pass exclude query parameter on recovery lookup'
      );
    } finally {
      globalThis.fetch = origFetch;
    }
  });
});

describe('Web URL Sync & "Dengarkan Bareng" Parameter Tests', () => {
  it('parses target seconds across various format strings (raw seconds, mm:ss, 1m30s)', () => {
    assert.equal(parseTargetSeconds(45), 45);
    assert.equal(parseTargetSeconds('45'), 45);
    assert.equal(parseTargetSeconds('1m30s'), 90);
    assert.equal(parseTargetSeconds('2m'), 120);
    assert.equal(parseTargetSeconds('45s'), 45);
    assert.equal(parseTargetSeconds('01:45'), 105);
    assert.equal(parseTargetSeconds('00:30'), 30);
    assert.equal(parseTargetSeconds('invalid'), 0);
    assert.equal(parseTargetSeconds(null), 0);
  });

  it('parses song, artist, and timestamp parameters from shared query strings', () => {
    const parsed = parseUrlSyncParams('?song=Blinding%20Lights&artist=The%20Weeknd&t=45');
    assert.ok(parsed);
    assert.equal(parsed.song, 'Blinding Lights');
    assert.equal(parsed.artist, 'The Weeknd');
    assert.equal(parsed.targetSeconds, 45);
    assert.equal(parsed.videoId, null);

    const parsedWithTrack = parseUrlSyncParams('?track=Satu%20Bulan&artist=Bernadya&t=1m15s');
    assert.ok(parsedWithTrack);
    assert.equal(parsedWithTrack.song, 'Satu Bulan');
    assert.equal(parsedWithTrack.artist, 'Bernadya');
    assert.equal(parsedWithTrack.targetSeconds, 75);

    const parsedWithVideoId = parseUrlSyncParams('?id=dQw4w9WgXcQ&t=30');
    assert.ok(parsedWithVideoId);
    assert.equal(parsedWithVideoId.videoId, 'dQw4w9WgXcQ');
    assert.equal(parsedWithVideoId.targetSeconds, 30);

    const empty = parseUrlSyncParams('?something_else=123');
    assert.equal(empty, null);

    // Test real-time drift compensation with ts parameter
    const nowSec = Math.floor(Date.now() / 1000);
    const parsedWithTs = parseUrlSyncParams(`?song=Risk%20It%20All&artist=Bruno%20Mars&t=30&ts=${nowSec - 15}`);
    assert.ok(parsedWithTs);
    assert.equal(parsedWithTs.song, 'Risk It All');
    assert.equal(parsedWithTs.baseTargetSeconds, 30);
    assert.ok(parsedWithTs.targetSeconds >= 44 && parsedWithTs.targetSeconds <= 46);
  });

  it('generates shareable Dengarkan Bareng links with exact live timestamps', () => {
    const link = generateUrlSyncLink({
      song: 'Yellow',
      artist: 'Coldplay',
      seconds: 52.8,
      baseUrl: 'https://mctify.vercel.app',
    });
    assert.equal(link, 'https://mctify.vercel.app/?song=Yellow&artist=Coldplay&t=52');

    const formatted = formatPlaybackSeconds(125);
    assert.equal(formatted, '2:05');
  });
});

describe('Web Lyrics Romanizer & "Huruf Biasa" Transliteration Tests', () => {
  it('detects Korean Hangul and Japanese Kana as non-Latin scripts', async () => {
    const { isNonLatin } = await import('../src/utils/romanizer.js');
    assert.equal(isNonLatin('나의 두 눈을 감으면'), true);
    assert.equal(isNonLatin('Stay With Me'), false);
    assert.equal(isNonLatin('さくら (Sakura)'), true);
    assert.equal(isNonLatin('Ed Sheeran - Shape of You'), false);
  });

  it('accurately romanizes Korean Hangul syllables to Latin letters (Revised Romanization)', async () => {
    const { romanizeKorean } = await import('../src/utils/romanizer.js');
    const line1 = romanizeKorean('나의 두 눈을 감으면');
    assert.equal(line1, 'naui du nuneul gameumyeon');

    const line2 = romanizeKorean('떠오르는 그 눈동자');
    assert.equal(line2, 'tteooreuneun geu nundongja');

    const greeting = romanizeKorean('안녕하세요');
    assert.equal(greeting, 'annyeonghaseyo');
  });

  it('accurately romanizes Japanese Hiragana, Katakana, and double consonants to Romaji', async () => {
    const { romanizeJapanese } = await import('../src/utils/romanizer.js');
    assert.equal(romanizeJapanese('ありがとう'), 'arigatou');
    assert.equal(romanizeJapanese('さくら'), 'sakura');
    assert.equal(romanizeJapanese('ちょっとまって'), 'chottomatte');
    assert.equal(romanizeJapanese('ラーメン'), 'raamen');
  });

  it('attaches studio romalrc or algorithmic romanization and generates word timings for karaoke wipe', async () => {
    const { attachRomanizationToLines } = await import('../src/utils/romanizer.js');

    const lines = [
      {
        id: 'l-1',
        time: 14.64,
        endTime: 18.0,
        duration: 3.36,
        text: '나의 두 눈을 감으면',
        words: [
          { id: 'w-1', word: '나의', startTime: 14.64, duration: 0.8 },
          { id: 'w-2', word: '두', startTime: 15.5, duration: 0.4 },
          { id: 'w-3', word: '눈을', startTime: 16.0, duration: 0.6 },
          { id: 'w-4', word: '감으면', startTime: 16.7, duration: 1.0 },
        ],
      },
      {
        id: 'l-2',
        time: 18.46,
        endTime: 22.0,
        duration: 3.54,
        text: '떠오르는 그 눈동자',
        words: [{ id: 'w-5', word: '떠오르는', startTime: 18.46, duration: 1.2 }],
      },
    ];

    const studioRomalrc = `[00:14.640]na ui du nu neul ga meu myeon\n[00:18.460]ddeo o reu neun geu nun dong za`;

    const result = attachRomanizationToLines(lines, studioRomalrc);
    assert.equal(result.length, 2);
    assert.equal(result[0].hasRomanization, true);
    assert.equal(result[0].romanizedText, 'na ui du nu neul ga meu myeon');
    assert.ok(result[0].romanizedWords.length >= 4);
    assert.equal(result[0].romanizedWords[0].word, 'naui');
    assert.ok(result[0].romanizedWords[0].chars.length > 0);

    // Fallback when no romalrc is provided
    const noRomaResult = attachRomanizationToLines(lines, null);
    assert.equal(noRomaResult[0].hasRomanization, true);
    assert.equal(noRomaResult[0].romanizedText, 'naui du nuneul gameumyeon');
  });
});

describe('Web Context-Aware Radio & Vibe Clustered Autoplay Tests', () => {
  it('accurately identifies regional genres and isolates Korean OSTs from Western Pop', async () => {
    const { detectTrackRegion, getSimilarArtists, isCleanPopularTrack } = await import('../src/services/musicApi.js');

    // 1. Korean Drama OST (Kim Tae-ri, Chanyeol)
    const kimTaeriRegion = detectTrackRegion('Kim Taeri, Nam Joo-hyuk, 보나, 최현욱 & Lee Ju-myung', 'With', 'TV Soundtrack', 'Twenty Five Twenty One OST');
    assert.equal(kimTaeriRegion, 'k-ost');

    const chanyeolRegion = detectTrackRegion('CHANYEOL', 'Stay With Me', 'Soundtrack', '도깨비 OST Part 1 Guardian');
    assert.equal(chanyeolRegion, 'k-ost');

    // 2. Korean Pop (NewJeans)
    const newjeansRegion = detectTrackRegion('NewJeans', 'Ditto', 'K-Pop', 'OMG');
    assert.equal(newjeansRegion, 'kpop');

    // 3. Indonesian Indie (Bernadya)
    const bernadyaRegion = detectTrackRegion('Bernadya', 'Satu Bulan', 'Pop', 'Sialnya, Hidup Harus Tetap Berjalan');
    assert.equal(bernadyaRegion, 'indo-indie');

    // 4. Western Pop (Katy Perry - Daisies)
    const daisiesRegion = detectTrackRegion('Katy Perry', 'Daisies', 'Pop', 'Smile');
    assert.equal(daisiesRegion, 'western-pop');

    // 5. Western Rock (Linkin Park)
    const lpRegion = detectTrackRegion('LINKIN PARK', 'Numb', 'Alternative Rock', 'Meteora');
    assert.equal(lpRegion, 'western-rock');

    // Verify peers: Korean OST must NEVER contain Katy Perry or Western rock
    const ostPeers = getSimilarArtists('Kim Taeri', 'TV Soundtrack', [], 'With', 'Twenty Five Twenty One OST');
    assert.ok(ostPeers.length > 0);
    assert.ok(!ostPeers.includes('Katy Perry'));
    assert.ok(!ostPeers.includes('Justin Bieber'));
    assert.ok(!ostPeers.includes('Green Day'));
    assert.ok(ostPeers.some(p => ['Punch', 'Crush', 'Gaho', 'Davichi', 'Heize', 'Paul Kim', 'MeloMance', '10cm', 'Gummy', 'Sam Kim', 'Roy Kim', 'Taeyeon', 'Ailee', 'Yerin Baek', 'Sondia', 'Car, the garden', 'Lee Mu-jin', 'IU'].includes(p)));

    // Verify instrumental rejection in isCleanPopularTrack
    assert.equal(isCleanPopularTrack({ title: 'With (Inst.)', artist: 'Kim Taeri', duration: 250 }), false);
    assert.equal(isCleanPopularTrack({ title: 'Twenty Five Twenty One (Instrumental)', artist: 'Roy Kim', duration: 240 }), false);
    assert.equal(isCleanPopularTrack({ title: 'With', artist: 'Kim Taeri', duration: 250 }), true);
  });
});

describe('Web Korean & Foreign Lyrics Timing Calibration Tests', () => {
  it('sustains natural vocal phrasing across Korean lines instead of rushing through in 1.8s', async () => {
    const { lyricsService } = await import('../src/services/lyricsService.js');

    const rawLrc = `[00:14.64] 나의 두 눈을 감으면\n[00:18.46] 떠오르는 그 눈동자\n[00:22.34] 자꾸 가슴이 시려서`;
    const parsed = lyricsService.parseLrc(rawLrc);

    // parsed contains intro interlude (since 14.64s > 4.2s) plus 3 lyric lines
    assert.equal(parsed.length, 4);
    assert.equal(parsed[0].isInterlude, true);

    // Line 1 gap is 18.46 - 14.64 = 3.82s. Duration must be at least 3.0s, NOT capped to 1.8s!
    const line1 = parsed[1];
    assert.equal(line1.text, '나의 두 눈을 감으면');
    assert.ok(line1.duration >= 3.0, `Duration should be >= 3.0s, got ${line1.duration}`);
    assert.ok(line1.endTime >= 17.6, `EndTime should be >= 17.6s, got ${line1.endTime}`);

    // Verify multi-syllable word '감으면' (3 Hangul blocks) receives more duration than single-block '두'
    const words = line1.words;
    assert.equal(words.length, 4);
    const duWord = words.find(w => w.word === '두');
    const gameumyeonWord = words.find(w => w.word === '감으면');
    assert.ok(duWord && gameumyeonWord);
    assert.ok(gameumyeonWord.duration > duWord.duration * 1.5, 'Multi-syllable word should receive longer phonation');
  });
});
