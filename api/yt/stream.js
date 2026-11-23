import { Innertube } from 'youtubei.js';
import {
  applyApiSecurity,
  isValidVideoId,
  isSafeUpstreamHost,
  sendSafeError,
} from '../_security.js';

let ytPromise = null;
async function getYT() {
  if (!ytPromise) {
    ytPromise = Innertube.create();
  }
  return ytPromise;
}

export default async function handler(req, res) {
  if (
    !applyApiSecurity(req, res, {
      methods: 'GET, HEAD, OPTIONS',
      allowHeaders: 'Range, Content-Type',
      rateLimit: 60,
    })
  ) {
    return;
  }

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    const id = (url.searchParams.get('id') || req.query?.id || '').trim();

    if (!isValidVideoId(id)) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Invalid or missing YouTube video ID' }));
    }

    const yt = await getYT();
    const info = await yt.music.getInfo(id).catch(() => yt.getInfo(id));
    const format = info.chooseFormat({ type: 'audio', quality: 'best' });

    if (!format) {
      res.statusCode = 404;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Audio format not found' }));
    }

    const streamUrl = await format.decipher(yt.session.player);

    if (!streamUrl || !isSafeUpstreamHost(streamUrl, ['.googlevideo.com'])) {
      res.statusCode = 502;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Upstream stream source rejected' }));
    }

    const forwardHeaders = {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    };

    const rawRange = req.headers.range;
    if (typeof rawRange === 'string' && /^bytes=\d*-\d*$/.test(rawRange.trim())) {
      forwardHeaders['Range'] = rawRange.trim();
    }

    const streamRes = await fetch(streamUrl, { headers: forwardHeaders });

    res.statusCode = streamRes.status;
    res.setHeader('Content-Type', streamRes.headers.get('content-type') || 'audio/mp4');
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('Cache-Control', 'public, max-age=3600');

    if (streamRes.headers.get('content-range')) {
      res.setHeader('Content-Range', streamRes.headers.get('content-range'));
    }
    if (streamRes.headers.get('content-length')) {
      res.setHeader('Content-Length', streamRes.headers.get('content-length'));
    }

    if (req.method === 'HEAD') {
      return res.end();
    }

    const reader = streamRes.body.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      res.write(value);
    }
    return res.end();
  } catch (e) {
    return sendSafeError(res, 500, 'Gagal memuat stream audio', e);
  }
}
