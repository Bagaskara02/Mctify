import { Innertube, Platform } from 'youtubei.js';

Platform.shim.eval = (script) => {
  const code = typeof script === 'string' ? script : script?.output;
  return new Function(code + '\nreturn exportedVars;')();
};

let ytPromise = null;
async function getYT() {
  if (!ytPromise) {
    ytPromise = Innertube.create();
  }
  return ytPromise;
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Range, Content-Type');

  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    return res.end();
  }

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    const id = url.searchParams.get('id') || req.query?.id;

    if (!id) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing video id' }));
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

    if (!streamUrl) {
      res.statusCode = 500;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Failed to decipher stream' }));
    }

    const forwardHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    };

    if (req.headers.range) {
      forwardHeaders['Range'] = req.headers.range;
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
    console.error('API /api/yt/stream error:', e);
    if (!res.headersSent) {
      res.statusCode = 500;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: e.message }));
    }
    return res.end();
  }
}
