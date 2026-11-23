import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  applyApiSecurity,
  resetRateLimitForTests,
  isOriginAllowed,
  isValidVideoId,
  isValidYoutubePlaylistId,
  isValidSpotifyPlaylistId,
  isValidChannelId,
  sanitizeQuery,
  isSafeUpstreamHost,
} from '../api/_security.js';
import { sanitizeMediaUrl } from '../src/services/storageService.js';
import { parseTitleAndArtist, toHighResUrl } from '../api/yt/playlist.js';

function createMockReq({ method = 'GET', headers = {}, ip = '203.0.113.10' } = {}) {
  return {
    method,
    headers: { 'x-forwarded-for': ip, ...headers },
    socket: { remoteAddress: ip },
  };
}

function createMockRes() {
  const headers = {};
  let body = '';
  return {
    statusCode: 200,
    headersSent: false,
    headers,
    setHeader(k, v) {
      headers[k.toLowerCase()] = String(v);
    },
    end(chunk = '') {
      if (chunk) body += String(chunk);
      this.headersSent = true;
    },
    getBodyJson() {
      return body ? JSON.parse(body) : null;
    },
  };
}

describe('API Security Helper', () => {
  beforeEach(() => {
    resetRateLimitForTests();
  });

  it('validates CORS origin allowlist strictly', () => {
    assert.equal(isOriginAllowed('https://mctify.vercel.app'), true);
    assert.equal(isOriginAllowed('https://mctify-git-main-demo.vercel.app'), true);
    assert.equal(isOriginAllowed('http://localhost:5173'), true);
    assert.equal(isOriginAllowed('http://127.0.0.1:4173'), true);

    assert.equal(isOriginAllowed('https://evil.com'), false);
    assert.equal(isOriginAllowed('http://mctify.vercel.app'), false);
    assert.equal(isOriginAllowed('https://mctify.vercel.app.evil.com'), false);
    assert.equal(isOriginAllowed(''), false);
    assert.equal(isOriginAllowed(null), false);
  });

  it('validates YouTube, Spotify, and Channel IDs', () => {
    assert.equal(isValidVideoId('dQw4w9WgXcQ'), true);
    assert.equal(isValidVideoId('abc_123-XYZ'), true);
    assert.equal(isValidVideoId('../etc/passwd'), false);
    assert.equal(isValidVideoId('short'), false);

    assert.equal(isValidYoutubePlaylistId('PL1234567890_abc-def'), true);
    assert.equal(isValidYoutubePlaylistId('RDCLAK5uy_n9Fbdw7e6ap'), true);
    assert.equal(isValidYoutubePlaylistId('bad?id=1'), false);

    assert.equal(isValidSpotifyPlaylistId('37i9dQZF1DXcBWIGoYBM5M'), true);
    assert.equal(isValidSpotifyPlaylistId('invalid_under!'), false);

    assert.equal(isValidChannelId('UC_x5XG1OV2P6uZZ5FSM9Ttw'), true);
    assert.equal(isValidChannelId('PL_x5XG1OV2P6uZZ5FSM9Ttw'), false);
  });

  it('sanitizes query text and rejects unsafe upstream hosts (SSRF protection)', () => {
    assert.equal(sanitizeQuery('  hello\x00\x07   world\n\t '), 'hello world');
    assert.equal(sanitizeQuery('a'.repeat(300), 50).length, 50);

    assert.equal(
      isSafeUpstreamHost('https://rr1---sn-4g5ednsd.googlevideo.com/videoplayback?id=1'),
      true
    );
    assert.equal(
      isSafeUpstreamHost('http://rr1---sn-4g5ednsd.googlevideo.com/videoplayback?id=1'),
      false
    );
    assert.equal(isSafeUpstreamHost('https://127.0.0.1/googlevideo.com'), false);
    assert.equal(isSafeUpstreamHost('https://evil.com/.googlevideo.com'), false);
    assert.equal(isSafeUpstreamHost('javascript:alert(1)'), false);
  });

  it('enforces headers, CORS, method, and rate limit in applyApiSecurity', () => {
    // Allows native mobile request without Origin header
    const mobileRes = createMockRes();
    const okMobile = applyApiSecurity(
      createMockReq({ method: 'GET', headers: {} }),
      mobileRes,
      { rateLimit: 2, windowMs: 60000 }
    );
    assert.equal(okMobile, true);
    assert.equal(mobileRes.headers['x-content-type-options'], 'nosniff');
    assert.equal(mobileRes.headers['x-frame-options'], 'DENY');
    assert.equal(mobileRes.headers['access-control-allow-origin'], undefined);

    // Rejects unknown browser Origin with 403
    const evilRes = createMockRes();
    const okEvil = applyApiSecurity(
      createMockReq({ method: 'GET', headers: { origin: 'https://attacker.example' } }),
      evilRes
    );
    assert.equal(okEvil, false);
    assert.equal(evilRes.statusCode, 403);

    // Rejects unsupported method with 405
    const methodRes = createMockRes();
    const okMethod = applyApiSecurity(
      createMockReq({ method: 'POST', headers: {} }),
      methodRes,
      { methods: 'GET, OPTIONS' }
    );
    assert.equal(okMethod, false);
    assert.equal(methodRes.statusCode, 405);

    // Enforces sliding-window rate limit -> 429 on 3rd request for same IP (1st already counted)
    const okSecond = applyApiSecurity(
      createMockReq({ method: 'GET' }),
      createMockRes(),
      { rateLimit: 2, windowMs: 60000 }
    );
    assert.equal(okSecond, true);

    const rateRes = createMockRes();
    const okThird = applyApiSecurity(
      createMockReq({ method: 'GET' }),
      rateRes,
      { rateLimit: 2, windowMs: 60000 }
    );
    assert.equal(okThird, false);
    assert.equal(rateRes.statusCode, 429);
    assert.ok(Number(rateRes.headers['retry-after']) >= 1);
  });
});

describe('Web Media Sanitization & YouTube Playlist Normalization', () => {
  it('blocks XSS vectors in sanitizeMediaUrl while keeping safe HTTPS and raster images', () => {
    assert.equal(sanitizeMediaUrl('javascript:alert(document.cookie)', 'safe'), 'safe');
    assert.equal(sanitizeMediaUrl('data:image/svg+xml;base64,PHN2Zy8+', 'safe'), 'safe');
    assert.equal(sanitizeMediaUrl('data:text/html;base64,PGI+eDwvYj4=', 'safe'), 'safe');
    assert.equal(sanitizeMediaUrl('http://insecure.example.com/art.jpg', 'safe'), 'safe');

    assert.equal(
      sanitizeMediaUrl('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'
    );
    assert.equal(
      sanitizeMediaUrl('data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=='),
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=='
    );
  });

  it('parses YouTube track title & artist without corrupting version suffixes', () => {
    assert.deepEqual(
      parseTitleAndArtist('Linkin Park - Numb', 'YouTube', 'My Mix'),
      { title: 'Numb', artist: 'Linkin Park' }
    );
    assert.deepEqual(
      parseTitleAndArtist('Someone You Loved - Acoustic Version', 'Lewis Capaldi - Topic'),
      { title: 'Someone You Loved - Acoustic Version', artist: 'Lewis Capaldi' }
    );
    assert.deepEqual(
      parseTitleAndArtist('Stay With Me - Remix', 'Miki MatsubaraVEVO'),
      { title: 'Stay With Me - Remix', artist: 'Miki Matsubara' }
    );
  });

  it('normalizes YouTube Music square artwork and reliable ytimg fallbacks', () => {
    assert.equal(
      toHighResUrl('https://lh3.googleusercontent.com/abc123=w120-h120-l90-rj', 'dQw4w9WgXcQ'),
      'https://lh3.googleusercontent.com/abc123=w544-h544-l90-rj'
    );
    assert.equal(
      toHighResUrl('https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/mqdefault.webp?sqp=123', 'dQw4w9WgXcQ'),
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'
    );
    assert.equal(
      toHighResUrl('https://i.ytimg.com/no_thumbnail.jpg', 'dQw4w9WgXcQ'),
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'
    );
  });
});
