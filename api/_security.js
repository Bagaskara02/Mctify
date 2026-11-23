/**
 * Shared Vercel Serverless API Security & Validation Utilities
 * - Strict CORS origin allowlist (allows native mobile clients without Origin header)
 * - Security response headers
 * - Sliding-window in-memory rate limiting per client IP
 * - Input validators and safe error responders
 */

export const ALLOWED_ORIGIN_PATTERNS = [
  /^https:\/\/mctify\.vercel\.app$/i,
  /^https:\/\/mctify-[a-z0-9-]+\.vercel\.app$/i,
  /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/i,
];

const rateLimitStore = new Map();
const MAX_TRACKED_IPS = 2000;

export function isOriginAllowed(origin) {
  if (!origin || typeof origin !== 'string') return false;
  return ALLOWED_ORIGIN_PATTERNS.some((pattern) => pattern.test(origin.trim()));
}

function getClientIp(req) {
  const xff = req.headers?.['x-forwarded-for'] || req.headers?.['X-Forwarded-For'];
  if (typeof xff === 'string' && xff.trim()) {
    return xff.split(',')[0].trim();
  }
  const realIp = req.headers?.['x-real-ip'];
  if (typeof realIp === 'string' && realIp.trim()) {
    return realIp.trim();
  }
  return req.socket?.remoteAddress || 'unknown';
}

function checkRateLimit(ip, limit, windowMs) {
  const now = Date.now();
  const windowStart = now - windowMs;

  if (rateLimitStore.size > MAX_TRACKED_IPS) {
    for (const [k, timestamps] of rateLimitStore.entries()) {
      const fresh = timestamps.filter((t) => t > windowStart);
      if (fresh.length === 0) {
        rateLimitStore.delete(k);
      } else {
        rateLimitStore.set(k, fresh);
      }
    }
    if (rateLimitStore.size > MAX_TRACKED_IPS) {
      rateLimitStore.clear();
    }
  }

  const timestamps = (rateLimitStore.get(ip) || []).filter((t) => t > windowStart);
  if (timestamps.length >= limit) {
    rateLimitStore.set(ip, timestamps);
    return false;
  }

  timestamps.push(now);
  rateLimitStore.set(ip, timestamps);
  return true;
}

export function resetRateLimitForTests() {
  rateLimitStore.clear();
}

export function applyApiSecurity(
  req,
  res,
  {
    methods = 'GET, OPTIONS',
    allowHeaders = 'Content-Type',
    rateLimit = 120,
    windowMs = 60000,
    skipRateLimit = false,
  } = {}
) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');

  const origin = req.headers?.origin;
  if (origin) {
    if (!isOriginAllowed(origin)) {
      res.statusCode = 403;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ error: 'Origin not allowed' }));
      return false;
    }
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }

  res.setHeader('Access-Control-Allow-Methods', methods);
  res.setHeader('Access-Control-Allow-Headers', allowHeaders);

  const method = (req.method || 'GET').toUpperCase();
  if (method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return false;
  }

  const allowedMethods = methods
    .split(',')
    .map((m) => m.trim().toUpperCase())
    .filter(Boolean);
  if (!allowedMethods.includes(method)) {
    res.statusCode = 405;
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ error: 'Method not allowed' }));
    return false;
  }

  if (!skipRateLimit && rateLimit > 0) {
    const ip = getClientIp(req);
    if (!checkRateLimit(ip, rateLimit, windowMs)) {
      res.statusCode = 429;
      res.setHeader('Retry-After', String(Math.ceil(windowMs / 1000)));
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ error: 'Too many requests, please try again later' }));
      return false;
    }
  }

  return true;
}

export function isValidVideoId(id) {
  return typeof id === 'string' && /^[a-zA-Z0-9_-]{11}$/.test(id.trim());
}

export function isValidYoutubePlaylistId(id) {
  return typeof id === 'string' && /^[a-zA-Z0-9_-]{10,120}$/.test(id.trim());
}

export function isValidSpotifyPlaylistId(id) {
  return typeof id === 'string' && /^[a-zA-Z0-9]{10,40}$/.test(id.trim());
}

export function isValidChannelId(id) {
  return typeof id === 'string' && /^UC[a-zA-Z0-9_-]{18,32}$/.test(id.trim());
}

export function sanitizeQuery(value, maxLen = 200) {
  if (typeof value !== 'string') return '';
  return value
    .replace(/[\x00-\x1f\x7f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLen);
}

export function isSafeUpstreamHost(urlStr, allowedHostSuffixes = ['.googlevideo.com']) {
  if (typeof urlStr !== 'string' || !urlStr.trim()) return false;
  try {
    const parsed = new URL(urlStr);
    if (parsed.protocol !== 'https:') return false;
    const host = parsed.hostname.toLowerCase();
    return allowedHostSuffixes.some((suffix) => {
      const cleanSuffix = suffix.toLowerCase();
      return host === cleanSuffix.replace(/^\./, '') || host.endsWith(cleanSuffix);
    });
  } catch {
    return false;
  }
}

export function sendSafeError(res, statusCode, publicMessage, internalError) {
  if (internalError) {
    console.error(`[API Error ${statusCode}] ${publicMessage}:`, internalError?.message || internalError);
  }
  if (!res.headersSent) {
    res.statusCode = statusCode;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(JSON.stringify({ error: publicMessage }));
  } else {
    try {
      res.end();
    } catch {}
  }
}
