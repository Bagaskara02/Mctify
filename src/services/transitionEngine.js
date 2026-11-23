/**
 * McTify Web Audio DSP Transition & Dual-Deck Automix Engine
 *
 * Powers:
 * 1. Beat-accurate bar duration math (1, 2, 4, 8 bars from track BPM in 4/4 time)
 * 2. Harmonic Camelot Wheel compatibility scoring (1A-12B) & Smart Automix presets
 * 3. Mathematical envelope curves for VOLUME (Overlap, Crossfade, Fade, Rise & Drop, Cut),
 *    EQ (None, Bass Swap, Low Cut, Smooth Vocal Blend), and EFFECTS (High-Pass Filter,
 *    Low-Pass Filter, Tempo Echo Fade, Stereo Reverb Tail)
 * 4. Real Web Audio API Dual-Deck DSP Graph (BiquadFilterNodes, DelayNode feedback loop,
 *    algorithmic ConvolverNode impulse response, GainNodes, DynamicsCompressorNode)
 * 5. Waveform peak extraction & multi-tier CORS audio preview resolver
 */

// Curated reference catalog of verified studio BPM & Camelot keys
const VERIFIED_TRACK_BPM_KEY = [
  { match: /one of the girls/i, bpm: 85, key: '4B' },
  { match: /stargirl interlude/i, bpm: 90, key: '5A' },
  { match: /starboy/i, bpm: 93, key: '7A' },
  { match: /i feel it coming/i, bpm: 93, key: '12B' },
  { match: /blinding lights/i, bpm: 171, key: '1A' },
  { match: /save your tears/i, bpm: 118, key: '8B' },
  { match: /die for you/i, bpm: 134, key: '10A' },
  { match: /daisies/i, bpm: 104, key: '8B' },
  { match: /in the end/i, bpm: 105, key: '3A' },
  { match: /numb/i, bpm: 110, key: '9A' },
  { match: /what i've done/i, bpm: 120, key: '6A' },
  { match: /faint/i, bpm: 135, key: '4A' },
  { match: /somewhere i belong/i, bpm: 81, key: '7A' },
  { match: /the emptiness machine/i, bpm: 128, key: '4A' },
  { match: /there for you/i, bpm: 106, key: '6A' },
  { match: /brangkat|muria/i, bpm: 124, key: '8A' },
  { match: /multo/i, bpm: 116, key: '7B' },
  { match: /sanctuary/i, bpm: 84, key: '11B' },
  { match: /best part/i, bpm: 75, key: '9B' },
  { match: /location unknown/i, bpm: 92, key: '5B' },
];

export const TRANSITION_BAR_OPTIONS = [
  { id: '1 bar', label: '1 bar', bars: 1 },
  { id: '2 bars', label: '2 bars', bars: 2 },
  { id: '4 bars', label: '4 bars', bars: 4 },
  { id: '8 bars', label: '8 bars', bars: 8 },
];

export const TRANSITION_VOLUME_OPTIONS = [
  { id: 'overlap', label: 'Overlap', desc: 'Kedua lagu membaur penuh di tengah transisi' },
  { id: 'crossfade', label: 'Crossfade', desc: 'Equal-power fade out & fade in tanpa drop volume' },
  { id: 'fade', label: 'Dip Fade', desc: 'Redup halus di tengah agar vokal tidak bertabrakan' },
  { id: 'rise_drop', label: 'Rise & Drop', desc: 'Build-up intens lalu drop penuh di ketukan baru' },
  { id: 'cut', label: 'Beat Cut', desc: 'Potong presisi tepat di bar intro lagu berikutnya' },
];

export const TRANSITION_EQ_OPTIONS = [
  { id: 'none', label: 'None', desc: 'EQ standar netral di kedua deck' },
  { id: 'bass_swap', label: 'Bass Swap', desc: 'Tukar sub-bass (<180Hz) tepat di titik drop tengah' },
  { id: 'high_pass', label: 'Low Cut Outgoing', desc: 'Potong bass lagu keluar agar kick baru dominan' },
  { id: 'smooth_blend', label: 'Vocal Blend', desc: 'Redam frekuensi tengah (1.2kHz) agar vokal bersih' },
];

export const TRANSITION_EFFECT_OPTIONS = [
  { id: 'high_pass', label: 'High pass filter', desc: 'Sapuan resonansi HPF (30Hz → 2.4kHz) pada outro' },
  { id: 'low_pass', label: 'Low pass filter', desc: 'Sapuan LPF hangat (18kHz → 320Hz) meredam vokal' },
  { id: 'echo_fade', label: 'Echo fade', desc: 'Delay ritmis sinkron BPM pada ekor lagu keluar' },
  { id: 'reverb_tail', label: 'Reverb wash', desc: 'Gema ruang stereo (convolver) mengiringi intro' },
  { id: 'none', label: 'None', desc: 'Transisi murni tanpa efek modulasi tambahan' },
];

/**
 * Clean noisy YouTube/streaming suffixes from track titles before lookup
 */
export function cleanSearchTitle(rawTitle = '') {
  return String(rawTitle || '')
    .replace(/\s*\[[^\]]*\]/g, '')
    .replace(/\s*\((?:official|lyric|audio|video|mv|visualizer|hd|4k|remaster|live)[^)]*\)/gi, '')
    .replace(/\s*-\s*(?:official|lyrics?|audio|video).*$/gi, '')
    .trim();
}

/**
 * Compute realistic BPM and Camelot Key (1A-12B) for any track
 */
export function computeTrackBpmAndKey(track) {
  if (!track) return { bpm: 90, key: '4B' };

  const existingBpm = Number(track.bpm);
  const existingKey = typeof track.key === 'string' && /^\d{1,2}[AB]$/i.test(track.key.trim())
    ? track.key.trim().toUpperCase()
    : null;

  if (Number.isFinite(existingBpm) && existingBpm >= 50 && existingBpm <= 210 && existingKey) {
    return { bpm: Math.round(existingBpm), key: existingKey };
  }

  const combined = `${track.title || ''} ${track.artist || ''}`.trim();
  for (const entry of VERIFIED_TRACK_BPM_KEY) {
    if (entry.match.test(combined)) {
      return {
        bpm: existingBpm >= 50 && existingBpm <= 210 ? Math.round(existingBpm) : entry.bpm,
        key: existingKey || entry.key,
      };
    }
  }

  const str = `${track.title || ''} ${track.artist || ''} ${track.genre || ''}`.toLowerCase();
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (hash << 5) - hash + str.charCodeAt(i);
    hash |= 0;
  }
  const posHash = Math.abs(hash);

  let baseBpm = 96;
  if (/dance|edm|house|techno|club|electronic|trance|disco/i.test(str)) {
    baseBpm = 122 + (posHash % 10);
  } else if (/hip\s*hop|rap|trap|r&b|soul|interlude/i.test(str)) {
    baseBpm = 82 + (posHash % 16);
  } else if (/rock|metal|punk|band|alternative/i.test(str)) {
    baseBpm = 118 + (posHash % 26);
  } else if (/acoustic|ballad|slow|sad|lofi|piano|chill/i.test(str)) {
    baseBpm = 74 + (posHash % 18);
  } else {
    baseBpm = 90 + (posHash % 32);
  }

  const keyNum = (posHash % 12) + 1;
  const keyLetter = posHash % 2 === 0 ? 'B' : 'A';
  return {
    bpm: existingBpm >= 50 && existingBpm <= 210 ? Math.round(existingBpm) : baseBpm,
    key: existingKey || `${keyNum}${keyLetter}`,
  };
}

/**
 * Evaluate harmonic compatibility on the Camelot Wheel (1A..12B)
 */
export function computeCamelotCompatibility(keyA = '4B', keyB = '4B') {
  const parseKey = (k) => {
    const m = String(k || '4B').trim().toUpperCase().match(/^(\d{1,2})([AB])$/);
    if (!m) return { num: 4, letter: 'B' };
    return { num: Math.max(1, Math.min(12, parseInt(m[1], 10))), letter: m[2] };
  };

  const a = parseKey(keyA);
  const b = parseKey(keyB);
  const rawDiff = Math.abs(a.num - b.num);
  const wheelDist = Math.min(rawDiff, 12 - rawDiff);
  const sameLetter = a.letter === b.letter;

  if (wheelDist === 0 && sameLetter) {
    return { tier: 'perfect', score: 100, label: 'Harmoni Identik (Unison Key)' };
  }
  if (wheelDist === 0 && !sameLetter) {
    return { tier: 'perfect', score: 96, label: 'Harmoni Relatif (Major ⇄ Minor)' };
  }
  if (wheelDist === 1 && sameLetter) {
    return { tier: 'harmonic', score: 92, label: 'Harmoni Quint/Fourth (Camelot ±1)' };
  }
  if ((wheelDist === 1 && !sameLetter) || (wheelDist === 2 && sameLetter)) {
    return { tier: 'energy', score: 80, label: 'Modulasi Energi (Energy Boost)' };
  }
  return { tier: 'contrast', score: 62, label: 'Kontras Nada (Gunakan Filter/Bass Swap)' };
}

/**
 * Compute beat-accurate transition duration in seconds from BPM and bar selection.
 * Handles half-time / double-time folding (e.g. 170 BPM vs 85 BPM).
 */
export function computeBarDurationSec(bpmA = 90, bpmB = 90, barsLabel = '2 bars') {
  const safeA = Number.isFinite(Number(bpmA)) && Number(bpmA) > 0 ? Number(bpmA) : 90;
  let safeB = Number.isFinite(Number(bpmB)) && Number(bpmB) > 0 ? Number(bpmB) : 90;

  // Fold double-time / half-time so 170 BPM & 85 BPM lock to the same beat grid
  let foldedB = safeB;
  if (safeA / safeB >= 1.75) foldedB = safeB * 2;
  else if (safeB / safeA >= 1.75) foldedB = safeB / 2;

  const avgBpm = Math.max(60, Math.min(180, (safeA + foldedB) / 2));

  const customMatch = String(barsLabel || '').match(/custom\s*(\d+(?:\.\d+)?)\s*s/i);
  if (customMatch) {
    const customSec = Math.max(1.5, Math.min(25, parseFloat(customMatch[1])));
    const approxBeats = Math.max(2, Math.round((customSec * avgBpm) / 60));
    return {
      bars: Math.max(1, Math.round(approxBeats / 4)),
      beats: approxBeats,
      durationSec: Number(customSec.toFixed(1)),
      effectiveBpm: Math.round(avgBpm),
      tempoRatio: Number((foldedB / safeA).toFixed(3)),
      deltaBpm: Math.round(Math.abs(safeA - foldedB)),
    };
  }

  const barMatch = String(barsLabel || '2 bars').match(/(\d+)\s*bar/i);
  const bars = barMatch ? Math.max(1, Math.min(16, parseInt(barMatch[1], 10))) : 2;
  const beats = bars * 4; // 4/4 time signature
  const rawSeconds = (beats * 60) / avgBpm;
  const clampedSeconds = Math.max(2.0, Math.min(24.0, rawSeconds));

  return {
    bars,
    beats,
    durationSec: Number(clampedSeconds.toFixed(1)),
    effectiveBpm: Math.round(avgBpm),
    tempoRatio: Number((foldedB / safeA).toFixed(3)),
    deltaBpm: Math.round(Math.abs(safeA - foldedB)),
  };
}

/**
 * Evaluate exact instantaneous DSP parameters at normalized transition progress p in [0, 1].
 */
export function evaluateTransitionEnvelope(progress, config = {}) {
  const p = Math.max(0, Math.min(1, Number.isFinite(progress) ? progress : 0));
  const volumeMode = config.volume || 'overlap';
  const eqMode = config.eq || 'none';
  const effectMode = config.effect || 'high_pass';
  const bpmA = Number(config.bpmA) || 85;
  const bpmB = Number(config.bpmB) || 90;
  const tempoSync = config.tempoSync !== false;

  // 1. Volume Gain Curves (outGain, inGain in [0, 1])
  let outGain = 1.0;
  let inGain = 0.0;

  if (volumeMode === 'overlap') {
    // Spotify Overlap: Outgoing stays at 100% until 45%, then smooth cosine fade out;
    // Incoming fades in over 0..55% and stays at 100%
    outGain = p <= 0.45 ? 1.0 : Math.cos(((p - 0.45) / 0.55) * (Math.PI / 2));
    inGain = p >= 0.55 ? 1.0 : Math.sin((p / 0.55) * (Math.PI / 2));
  } else if (volumeMode === 'crossfade') {
    // Equal-power crossfade: out^2 + in^2 = 1.0
    outGain = Math.cos(p * (Math.PI / 2));
    inGain = Math.sin(p * (Math.PI / 2));
  } else if (volumeMode === 'fade') {
    // Center-dip fade: avoids vocal collision in the middle
    outGain = Math.pow(1 - p, 1.45);
    inGain = Math.pow(p, 1.45);
  } else if (volumeMode === 'rise_drop') {
    // Build-up until 78%, then sharp drop into Track 2
    if (p < 0.78) {
      outGain = 1.0;
      inGain = 0.35 * (p / 0.78);
    } else if (p < 0.88) {
      const t = (p - 0.78) / 0.10;
      outGain = 1.0 - t;
      inGain = 0.35 + 0.65 * t;
    } else {
      outGain = 0.0;
      inGain = 1.0;
    }
  } else if (volumeMode === 'cut') {
    // DJ Beat Cut at 82% of window
    const cutPoint = 0.82;
    if (p < cutPoint - 0.03) {
      outGain = 1.0;
      inGain = 0.0;
    } else if (p <= cutPoint + 0.03) {
      const t = (p - (cutPoint - 0.03)) / 0.06;
      outGain = 1.0 - t;
      inGain = t;
    } else {
      outGain = 0.0;
      inGain = 1.0;
    }
  } else {
    outGain = Math.cos(p * (Math.PI / 2));
    inGain = Math.sin(p * (Math.PI / 2));
  }

  outGain = Math.max(0, Math.min(1, outGain));
  inGain = Math.max(0, Math.min(1, inGain));

  // 2. EQ Curves (Low-shelf 160Hz & Mid-peaking 1250Hz in dB)
  let outLowDb = 0;
  let inLowDb = 0;
  let outMidDb = 0;
  let inMidDb = 0;

  if (eqMode === 'bass_swap') {
    // Swap sub-bass cleanly around p = 0.50
    if (p < 0.42) {
      outLowDb = 0;
      inLowDb = -16;
    } else if (p <= 0.58) {
      const t = (p - 0.42) / 0.16;
      outLowDb = -18 * t;
      inLowDb = -16 + 17.5 * t;
    } else {
      outLowDb = -18;
      inLowDb = 1.5 * (1 - (p - 0.58) / 0.42);
    }
  } else if (eqMode === 'high_pass' || eqMode === 'low_cut') {
    outLowDb = -18 * Math.pow(p, 0.85);
    inLowDb = -6 * Math.pow(1 - p, 1.5);
  } else if (eqMode === 'smooth_blend' || eqMode === 'vocal_blend') {
    const midBell = Math.sin(p * Math.PI);
    outMidDb = -7.5 * midBell;
    inMidDb = -4.5 * Math.pow(1 - p, 1.3);
    outLowDb = -6 * p;
  }

  // 3. Effects Curves (Filter Sweep, Echo Delay Send, Stereo Reverb Wet)
  let outFilterType = 'allpass';
  let outFilterFreqHz = 20;
  let outFilterQ = 0.707;
  let inFilterType = 'allpass';
  let inFilterFreqHz = 20;
  let echoSend = 0;
  let echoFeedback = 0.25;
  let reverbWet = 0;

  if (effectMode === 'high_pass') {
    outFilterType = 'highpass';
    // Exponential sweep 28 Hz -> 2400 Hz
    outFilterFreqHz = 28 * Math.pow(2400 / 28, Math.pow(p, 1.1));
    outFilterQ = 1.55;
    inFilterType = 'highpass';
    inFilterFreqHz = p < 0.45 ? 240 * Math.pow(20 / 240, p / 0.45) : 20;
  } else if (effectMode === 'low_pass') {
    outFilterType = 'lowpass';
    // Exponential sweep 18000 Hz -> 320 Hz
    outFilterFreqHz = 18000 * Math.pow(320 / 18000, Math.pow(p, 1.05));
    outFilterQ = 1.45;
  } else if (effectMode === 'echo_fade') {
    outFilterType = 'highpass';
    outFilterFreqHz = 30 * Math.pow(620 / 30, p);
    outFilterQ = 1.1;
    echoSend = Math.min(0.68, 0.08 + 0.60 * Math.pow(p, 0.9));
    echoFeedback = Math.min(0.64, 0.25 + 0.39 * p);
  } else if (effectMode === 'reverb_tail') {
    outFilterType = 'lowpass';
    outFilterFreqHz = 16000 * Math.pow(1200 / 16000, Math.pow(p, 1.2));
    outFilterQ = 0.9;
    reverbWet = Math.min(0.75, 0.06 + 0.69 * Math.pow(p, 0.85));
  }

  // 4. Tempo Sync (Beatmatching PlaybackRate Interpolation)
  let foldedB = bpmB;
  if (bpmA / bpmB >= 1.75) foldedB = bpmB * 2;
  else if (bpmB / bpmA >= 1.75) foldedB = bpmB / 2;
  const rawRatio = foldedB / bpmA;
  const canTempoSync = tempoSync && Math.abs(rawRatio - 1) <= 0.14;

  const outPlaybackRate = canTempoSync
    ? Number((1 + (rawRatio - 1) * Math.min(1, p * 1.15)).toFixed(3))
    : 1.0;
  const inPlaybackRate = canTempoSync
    ? Number(((1 / rawRatio) + (1 - 1 / rawRatio) * Math.min(1, p * 1.15)).toFixed(3))
    : 1.0;

  // 5. Effective IFrame Volume Contour (projects EQ/Filter energy onto 0..100 for YouTube IFrame dual decks)
  let outAcousticalFactor = 1.0;
  let inAcousticalFactor = 1.0;
  if (eqMode === 'bass_swap') {
    outAcousticalFactor *= p < 0.5 ? 1.0 : 0.78;
    inAcousticalFactor *= p < 0.5 ? 0.82 : 1.05;
  } else if (eqMode === 'high_pass') {
    outAcousticalFactor *= 1 - 0.22 * p;
  }
  if (effectMode === 'high_pass' || effectMode === 'low_pass') {
    outAcousticalFactor *= 1 - 0.25 * Math.pow(p, 1.2);
  } else if (effectMode === 'echo_fade' || effectMode === 'reverb_tail') {
    // Sustain tail slightly longer for ambient wash
    outAcousticalFactor *= 1 + 0.14 * Math.sin(p * Math.PI);
  }

  const effectiveOutIframeVol = Math.max(0, Math.min(100, Math.round(outGain * outAcousticalFactor * 100)));
  const effectiveInIframeVol = Math.max(0, Math.min(100, Math.round(inGain * inAcousticalFactor * 100)));

  return {
    progress: p,
    outGain,
    inGain,
    outLowDb,
    inLowDb,
    outMidDb,
    inMidDb,
    outFilterType,
    outFilterFreqHz,
    outFilterQ,
    inFilterType,
    inFilterFreqHz,
    echoSend,
    echoFeedback,
    reverbWet,
    outPlaybackRate,
    inPlaybackRate,
    effectiveOutIframeVol,
    effectiveInIframeVol,
  };
}

/**
 * Compute Smart Automix optimal transition preset between outgoing and incoming track
 */
export function computeSmartAutomixPreset(outgoing, incoming) {
  const metaA = computeTrackBpmAndKey(outgoing);
  const metaB = computeTrackBpmAndKey(incoming);
  const compat = computeCamelotCompatibility(metaA.key, metaB.key);
  const barStats2 = computeBarDurationSec(metaA.bpm, metaB.bpm, '2 bars');
  const deltaBpm = barStats2.deltaBpm;

  let bars = '2 bars';
  let volume = 'overlap';
  let eq = 'bass_swap';
  let effect = 'high_pass';
  let tempoSync = deltaBpm <= 12;
  let explanation = '';

  if (deltaBpm <= 4 && compat.score >= 90) {
    bars = '4 bars';
    volume = 'overlap';
    eq = 'bass_swap';
    effect = 'high_pass';
    tempoSync = true;
    explanation = `Harmoni & Tempo Sempurna (${metaA.bpm} → ${metaB.bpm} BPM, ${metaA.key} → ${metaB.key} • ${compat.label}). Menggunakan Overlap 4 Bars (${computeBarDurationSec(metaA.bpm, metaB.bpm, '4 bars').durationSec}s) dengan Bass Swap & High-Pass Filter agar beat menyatu seperti set DJ profesional.`;
  } else if (deltaBpm <= 10) {
    bars = '2 bars';
    volume = compat.score >= 80 ? 'overlap' : 'crossfade';
    eq = compat.score >= 80 ? 'bass_swap' : 'smooth_blend';
    effect = compat.score >= 80 ? 'high_pass' : 'low_pass';
    tempoSync = true;
    explanation = `Beatmatch Halus (${metaA.bpm} → ${metaB.bpm} BPM, selisih ${deltaBpm} BPM • ${compat.label}). Menggunakan ${volume === 'overlap' ? 'Overlap' : 'Crossfade'} 2 Bars (${barStats2.durationSec}s) dengan Tempo Sync aktif & ${effect === 'high_pass' ? 'High-Pass Sweep' : 'Low-Pass Warm Filter'}.`;
  } else if (deltaBpm <= 20) {
    bars = '2 bars';
    volume = 'rise_drop';
    eq = 'high_pass';
    effect = 'echo_fade';
    tempoSync = false;
    explanation = `Transisi Energi Kontras (${metaA.bpm} → ${metaB.bpm} BPM). Menggunakan Rise & Drop 2 Bars (${barStats2.durationSec}s) dengan Low Cut & Tempo Echo Fade agar perpindahan tempo terasa dramatis tanpa tabrakan ketukan.`;
  } else {
    bars = '1 bar';
    volume = 'cut';
    eq = 'high_pass';
    effect = 'reverb_tail';
    tempoSync = false;
    const barStats1 = computeBarDurationSec(metaA.bpm, metaB.bpm, '1 bar');
    explanation = `DJ Drop Cut (${metaA.bpm} vs ${metaB.bpm} BPM, selisih ${deltaBpm} BPM). Menggunakan Beat Cut 1 Bar (${barStats1.durationSec}s) dengan Reverb Wash pada ketukan terakhir agar lagu baru langsung masuk penuh di beat pertama.`;
  }

  const finalBarStats = computeBarDurationSec(metaA.bpm, metaB.bpm, bars);
  return {
    bars,
    durationSec: finalBarStats.durationSec,
    beats: finalBarStats.beats,
    volume,
    eq,
    effect,
    tempoSync,
    outroOffsetSec: 0,
    introOffsetSec: 0,
    bpmA: metaA.bpm,
    bpmB: metaB.bpm,
    keyA: metaA.key,
    keyB: metaB.key,
    deltaBpm,
    compatibility: compat,
    explanation,
  };
}

/**
 * Generate SVG polyline points & area path for waveform envelope visualization
 */
export function buildEnvelopeSvgPaths(config = {}, width = 360, height = 76) {
  const steps = 32;
  const outPoints = [];
  const inPoints = [];

  for (let i = 0; i <= steps; i++) {
    const p = i / steps;
    const env = evaluateTransitionEnvelope(p, config);
    const x = Number((p * width).toFixed(1));
    // Top canvas: y=8 is 100% gain, y=height-6 is 0% gain
    const outY = Number((height - 6 - env.outGain * (height - 14)).toFixed(1));
    // Bottom canvas: y=8 is 100% gain, y=height-6 is 0% gain
    const inY = Number((height - 6 - env.inGain * (height - 14)).toFixed(1));
    outPoints.push([x, outY]);
    inPoints.push([x, inY]);
  }

  const toLine = (pts) => pts.map(([x, y]) => `${x},${y}`).join(' ');
  const toArea = (pts) =>
    `M 0,${height} L ` +
    pts.map(([x, y]) => `${x},${y}`).join(' L ') +
    ` L ${width},${height} Z`;

  return {
    outLinePoints: toLine(outPoints),
    outAreaPath: toArea(outPoints),
    inLinePoints: toLine(inPoints),
    inAreaPath: toArea(inPoints),
  };
}

// In-memory cache for resolved preview URLs and extracted waveform peaks
const previewAudioCache = new Map();
const waveformPeaksCache = new Map();

/**
 * Multi-tier audio stream resolver for transition preview
 * Returns { url, sourceType: 'direct' | 'itunes' | 'yt_proxy' } or null
 */
export async function resolveTransitionTrackAudio(track) {
  if (!track) return null;

  if (
    typeof track.audioUrl === 'string' &&
    track.audioUrl.startsWith('https://') &&
    !track.audioUrl.includes('googlevideo.com')
  ) {
    return { url: track.audioUrl, sourceType: 'direct', isPreview30s: true };
  }

  const cacheKey = `${track.id || ''}:::${track.videoId || ''}:::${track.title || ''}:::${track.artist || ''}`;
  if (previewAudioCache.has(cacheKey)) {
    return previewAudioCache.get(cacheKey);
  }

  const cleanTitle = cleanSearchTitle(track.title || '');
  const cleanArtist = String(track.artist || '')
    .split(',')[0]
    .replace(/\s*-\s*Topic$/i, '')
    .trim();

  // Tier 1: iTunes high-availability CORS AAC preview (supports Web Audio API BiquadFilter/Convolver directly!)
  if (cleanTitle && typeof fetch === 'function') {
    try {
      const q = `${cleanTitle} ${cleanArtist}`.trim();
      const res = await fetch(
        `https://itunes.apple.com/search?term=${encodeURIComponent(q)}&entity=song&limit=6`
      );
      if (res.ok) {
        const data = await res.json();
        const results = Array.isArray(data?.results) ? data.results : [];
        const titleLower = cleanTitle.toLowerCase();
        const artistLower = cleanArtist.toLowerCase();

        let best = null;
        let bestScore = -1;
        for (const item of results) {
          if (!item?.previewUrl) continue;
          const rTitle = String(item.trackName || '').toLowerCase();
          const rArtist = String(item.artistName || '').toLowerCase();
          let score = 0;
          if (rTitle === titleLower) score += 60;
          else if (rTitle.includes(titleLower) || titleLower.includes(rTitle)) score += 38;
          if (artistLower && (rArtist.includes(artistLower) || artistLower.includes(rArtist))) {
            score += 45;
          }
          if (score > bestScore) {
            bestScore = score;
            best = item.previewUrl;
          }
        }

        if (best) {
          const resolved = { url: best, sourceType: 'itunes', isPreview30s: true };
          previewAudioCache.set(cacheKey, resolved);
          return resolved;
        }
      }
    } catch (_) {}
  }

  // Tier 2: Local/Vercel same-origin YouTube Audio Stream Proxy (/api/yt/stream)
  if (track.videoId && /^[a-zA-Z0-9_-]{11}$/.test(track.videoId.trim())) {
    const proxyUrl = `/api/yt/stream?videoId=${encodeURIComponent(track.videoId.trim())}`;
    const resolved = { url: proxyUrl, sourceType: 'yt_proxy', isPreview30s: false };
    previewAudioCache.set(cacheKey, resolved);
    return resolved;
  }

  return null;
}

/**
 * Generate deterministic musical structure waveform bars (fallback or initial render before buffer decode)
 */
export function generateMusicalWaveformBars(count = 60, track = null, isOutro = false) {
  const meta = computeTrackBpmAndKey(track);
  const str = `${track?.id || ''}:${track?.title || ''}:${meta.bpm}:${meta.key}`;
  let seed = meta.bpm * 17;
  for (let i = 0; i < str.length; i++) {
    seed = (seed * 31 + str.charCodeAt(i)) % 10007;
  }

  const bars = [];
  for (let i = 0; i < count; i++) {
    const x = i / Math.max(1, count - 1);
    // 4-beat rhythmic pulse + phrase contour
    const beatPulse = Math.abs(Math.sin((i * Math.PI) / 2)) * 0.28;
    const phraseWave =
      Math.sin((i + seed * 0.13) * 0.65) * 0.25 +
      Math.cos((i * 1.9 + seed * 0.07)) * 0.22 +
      0.52;
    const sectionEnvelope = isOutro
      ? (x < 0.55 ? 0.92 : 0.92 - 0.52 * ((x - 0.55) / 0.45))
      : (x < 0.45 ? 0.40 + 0.52 * (x / 0.45) : 0.92);
    const height = Math.round(Math.max(14, Math.min(94, (phraseWave + beatPulse) * 92 * sectionEnvelope)));
    bars.push(height);
  }
  return bars;
}

/**
 * Decode real audio segment and extract normalized bar heights (14..94) + energy cue point
 */
export async function extractAudioWaveformData(audioUrl, barCount = 60, isOutro = false) {
  if (!audioUrl || typeof window === 'undefined') return null;
  const cacheKey = `${audioUrl}:::${barCount}:::${isOutro ? 'out' : 'in'}`;
  if (waveformPeaksCache.has(cacheKey)) {
    return waveformPeaksCache.get(cacheKey);
  }

  try {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return null;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 4500);
    const res = await fetch(audioUrl, { signal: controller.signal });
    clearTimeout(timer);
    if (!res.ok) return null;

    const buf = await res.arrayBuffer();
    if (!buf || buf.byteLength < 1024) return null;

    const tempCtx = new AudioCtx();
    let audioBuffer = null;
    try {
      audioBuffer = await tempCtx.decodeAudioData(buf.slice(0));
    } finally {
      try { await tempCtx.close(); } catch (_) {}
    }
    if (!audioBuffer) return null;

    const channel = audioBuffer.getChannelData(0);
    const totalSamples = channel.length;
    const sampleRate = audioBuffer.sampleRate || 44100;
    const totalDur = audioBuffer.duration || totalSamples / sampleRate;

    // Focus on the last 16s for outro or first 16s for intro (or full 30s preview window)
    const windowSec = Math.min(totalDur, 16);
    const startSec = isOutro ? Math.max(0, totalDur - windowSec) : 0;
    const startSample = Math.floor(startSec * sampleRate);
    const endSample = Math.min(totalSamples, startSample + Math.floor(windowSec * sampleRate));
    const span = Math.max(barCount, endSample - startSample);
    const samplesPerBar = Math.max(1, Math.floor(span / barCount));

    const rawRms = [];
    let maxRms = 0.001;
    for (let b = 0; b < barCount; b++) {
      const s0 = startSample + b * samplesPerBar;
      const s1 = Math.min(endSample, s0 + samplesPerBar);
      const step = Math.max(1, Math.floor((s1 - s0) / 64));
      let sumSq = 0;
      let count = 0;
      for (let idx = s0; idx < s1; idx += step) {
        const v = channel[idx];
        sumSq += v * v;
        count++;
      }
      const rms = count > 0 ? Math.sqrt(sumSq / count) : 0;
      rawRms.push(rms);
      if (rms > maxRms) maxRms = rms;
    }

    const bars = rawRms.map((r) => {
      const norm = Math.pow(r / maxRms, 0.75);
      return Math.round(Math.max(14, Math.min(94, 14 + norm * 80)));
    });

    // Detect first crisp beat onset in intro or optimal transition start in outro
    let suggestedCueSec = isOutro ? Math.max(0, totalDur - 11) : 0.2;
    if (!isOutro) {
      const onsetIdx = rawRms.findIndex((r) => r >= maxRms * 0.32);
      if (onsetIdx > 0) {
        suggestedCueSec = Number(((onsetIdx / barCount) * windowSec).toFixed(2));
      }
    }

    const result = { bars, durationSec: totalDur, suggestedCueSec };
    waveformPeaksCache.set(cacheKey, result);
    return result;
  } catch (_) {
    return null;
  }
}

/**
 * Create a lush stereo impulse response buffer for the Reverb Tail ConvolverNode
 */
function createStereoReverbImpulse(ctx, durationSec = 2.2, decay = 2.6) {
  const rate = ctx.sampleRate || 44100;
  const length = Math.floor(rate * durationSec);
  const impulse = ctx.createBuffer(2, length, rate);
  const left = impulse.getChannelData(0);
  const right = impulse.getChannelData(1);

  for (let i = 0; i < length; i++) {
    const n = i / length;
    const env = Math.pow(1 - n, decay);
    left[i] = (Math.random() * 2 - 1) * env * 0.55;
    right[i] = (Math.random() * 2 - 1) * env * 0.55;
  }
  return impulse;
}

/**
 * Real Web Audio API Dual-Deck Transition Audition Mixer
 * Connects two HTML5 Audio elements (and/or synced YouTube fallback decks)
 * with live BiquadFilter EQ, HPF/LPF resonant filter sweeps, tempo-synced echo delay,
 * stereo convolver reverb, and dynamic volume envelopes.
 */
export class TransitionAuditionMixer {
  constructor() {
    this.ctx = null;
    this.elOut = null;
    this.elIn = null;
    this.deckOut = null;
    this.deckIn = null;
    this.masterLimiter = null;
    this.animFrame = null;
    this.isRunning = false;
    this.config = {};
    this.progress = 0;
    this.startWallTime = 0;
    this.outStartCueSec = 18;
    this.inStartCueSec = 0;
    this.leadInSec = 1.6; // Play 1.6s of outgoing track solo before overlap begins
    this.leadOutSec = 1.6; // Play 1.6s of incoming track solo after overlap completes
    this.onProgress = null;
    this.onStop = null;
  }

  _buildDeckGraph(ctx, audioEl, bpm = 90) {
    const lowFilter = ctx.createBiquadFilter();
    lowFilter.type = 'lowshelf';
    lowFilter.frequency.value = 165;
    lowFilter.gain.value = 0;

    const midFilter = ctx.createBiquadFilter();
    midFilter.type = 'peaking';
    midFilter.frequency.value = 1250;
    midFilter.Q.value = 1.1;
    midFilter.gain.value = 0;

    const sweepFilter = ctx.createBiquadFilter();
    sweepFilter.type = 'allpass';
    sweepFilter.frequency.value = 20;
    sweepFilter.Q.value = 0.707;

    // Echo delay send loop
    const delayNode = ctx.createDelay(2.0);
    const beatSec = Math.max(0.18, Math.min(0.85, 60 / Math.max(60, bpm) / 2));
    delayNode.delayTime.value = beatSec;

    const feedbackGain = ctx.createGain();
    feedbackGain.gain.value = 0.28;

    const echoFilter = ctx.createBiquadFilter();
    echoFilter.type = 'highpass';
    echoFilter.frequency.value = 340;

    const echoSendGain = ctx.createGain();
    echoSendGain.gain.value = 0;

    delayNode.connect(echoFilter);
    echoFilter.connect(feedbackGain);
    feedbackGain.connect(delayNode);

    // Reverb convolver send
    const convolver = ctx.createConvolver();
    convolver.buffer = createStereoReverbImpulse(ctx, 2.0, 2.4);
    const reverbSendGain = ctx.createGain();
    reverbSendGain.gain.value = 0;

    const envelopeGain = ctx.createGain();
    envelopeGain.gain.value = 1.0;

    // Connect main chain
    lowFilter.connect(midFilter);
    midFilter.connect(sweepFilter);
    sweepFilter.connect(envelopeGain);

    // Connect parallel Echo & Reverb sends into envelopeGain
    sweepFilter.connect(echoSendGain);
    echoSendGain.connect(delayNode);
    delayNode.connect(envelopeGain);

    sweepFilter.connect(reverbSendGain);
    reverbSendGain.connect(convolver);
    convolver.connect(envelopeGain);

    envelopeGain.connect(this.masterLimiter);

    let webAudioConnected = false;
    try {
      const source = ctx.createMediaElementSource(audioEl);
      source.connect(lowFilter);
      webAudioConnected = true;
    } catch (_) {
      webAudioConnected = false;
    }

    return {
      audioEl,
      lowFilter,
      midFilter,
      sweepFilter,
      delayNode,
      feedbackGain,
      echoSendGain,
      reverbSendGain,
      envelopeGain,
      webAudioConnected,
    };
  }

  async start({
    outUrl,
    inUrl,
    config,
    outDurationEstimate = 30,
    onProgress,
    onStop,
    onYtPreviewTick,
  }) {
    this.stop();
    this.config = { ...config };
    this.onProgress = onProgress;
    this.onStop = onStop;
    this.onYtPreviewTick = onYtPreviewTick;
    this.isRunning = true;

    const AudioCtx = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext);
    if (AudioCtx) {
      this.ctx = new AudioCtx();
      if (this.ctx.state === 'suspended') {
        try { await this.ctx.resume(); } catch (_) {}
      }
      this.masterLimiter = this.ctx.createDynamicsCompressor();
      this.masterLimiter.threshold.value = -1.2;
      this.masterLimiter.knee.value = 4.0;
      this.masterLimiter.ratio.value = 10.0;
      this.masterLimiter.attack.value = 0.003;
      this.masterLimiter.release.value = 0.2;
      this.masterLimiter.connect(this.ctx.destination);
    }

    const overlapSec = Math.max(2.0, Number(this.config.durationSec) || 5.5);
    const outroOffset = Number(this.config.outroOffsetSec) || 0;
    const introOffset = Math.max(0, Number(this.config.introOffsetSec) || 0);

    // Prepare Outgoing Audio Element
    if (outUrl && typeof Audio !== 'undefined') {
      this.elOut = new Audio();
      this.elOut.crossOrigin = 'anonymous';
      this.elOut.preload = 'auto';
      this.elOut.src = outUrl;
      if (this.ctx) {
        this.deckOut = this._buildDeckGraph(this.ctx, this.elOut, this.config.bpmA || 85);
      }
    }

    // Prepare Incoming Audio Element
    if (inUrl && typeof Audio !== 'undefined') {
      this.elIn = new Audio();
      this.elIn.crossOrigin = 'anonymous';
      this.elIn.preload = 'auto';
      this.elIn.src = inUrl;
      if (this.ctx) {
        this.deckIn = this._buildDeckGraph(this.ctx, this.elIn, this.config.bpmB || 90);
      }
    }

    // Wait briefly for metadata so currentTime seeks accurately
    await Promise.all([
      this._waitMetadata(this.elOut),
      this._waitMetadata(this.elIn),
    ]);

    if (!this.isRunning) return;

    const actualOutDur = (this.elOut && Number.isFinite(this.elOut.duration) && this.elOut.duration > 5)
      ? this.elOut.duration
      : outDurationEstimate;
    const totalAuditionSec = this.leadInSec + overlapSec + this.leadOutSec;

    this.outStartCueSec = Math.max(
      0,
      Math.min(actualOutDur - 2, actualOutDur - (this.leadInSec + overlapSec) + outroOffset)
    );
    this.inStartCueSec = Math.max(0, introOffset);

    if (this.elOut) {
      try {
        this.elOut.currentTime = this.outStartCueSec;
        await this.elOut.play();
      } catch (_) {}
    }

    this.startWallTime = performance.now();
    this._inStarted = false;

    const tick = () => {
      if (!this.isRunning) return;

      const curOverlapSec = Math.max(2.0, Number(this.config.durationSec) || 5.5);
      const totalWindowSec = this.leadInSec + curOverlapSec + this.leadOutSec;
      const elapsedSec = (performance.now() - this.startWallTime) / 1000;
      const overallProgress = Math.max(0, Math.min(1, elapsedSec / totalWindowSec));

      // Overlap progress p in [0, 1] during the middle overlap window
      let overlapProgress = 0;
      let phase = 'lead_in';
      if (elapsedSec < this.leadInSec) {
        overlapProgress = 0;
        phase = 'lead_in';
      } else if (elapsedSec <= this.leadInSec + curOverlapSec) {
        overlapProgress = (elapsedSec - this.leadInSec) / curOverlapSec;
        phase = 'overlap';
      } else {
        overlapProgress = 1;
        phase = 'lead_out';
      }

      // Start incoming deck as soon as we enter the overlap window
      if (!this._inStarted && elapsedSec >= this.leadInSec) {
        this._inStarted = true;
        if (this.elIn) {
          try {
            this.elIn.currentTime = this.inStartCueSec;
            this.elIn.play().catch(() => {});
          } catch (_) {}
        }
      }

      const env = evaluateTransitionEnvelope(overlapProgress, this.config);
      if (phase === 'lead_in') {
        env.outGain = 1.0;
        env.inGain = 0.0;
        env.effectiveOutIframeVol = 100;
        env.effectiveInIframeVol = 0;
      } else if (phase === 'lead_out') {
        env.outGain = 0.0;
        env.inGain = 1.0;
        env.effectiveOutIframeVol = 0;
        env.effectiveInIframeVol = 100;
        if (this.elOut && !this.elOut.paused) {
          try { this.elOut.pause(); } catch (_) {}
        }
      }

      this._applyEnvelopeToDecks(env, phase);
      this.progress = overallProgress;

      this.onProgress?.({
        overallProgress,
        overlapProgress,
        phase,
        elapsedSec,
        totalWindowSec,
        envelope: env,
      });

      this.onYtPreviewTick?.({
        overallProgress,
        overlapProgress,
        phase,
        envelope: env,
      });

      if (overallProgress < 1.0) {
        this.animFrame = requestAnimationFrame(tick);
      } else {
        this.stop();
      }
    };

    this.animFrame = requestAnimationFrame(tick);
  }

  _waitMetadata(audioEl) {
    if (!audioEl) return Promise.resolve();
    if (audioEl.readyState >= 1) return Promise.resolve();
    return new Promise((resolve) => {
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        audioEl.removeEventListener('loadedmetadata', finish);
        audioEl.removeEventListener('error', finish);
        resolve();
      };
      audioEl.addEventListener('loadedmetadata', finish, { once: true });
      audioEl.addEventListener('error', finish, { once: true });
      setTimeout(finish, 1800);
    });
  }

  _applyEnvelopeToDecks(env, phase) {
    const now = this.ctx ? this.ctx.currentTime : 0;

    // Outgoing deck
    if (this.deckOut && this.deckOut.webAudioConnected && this.ctx) {
      const d = this.deckOut;
      this.elOut.volume = 1.0;
      d.envelopeGain.gain.setTargetAtTime(env.outGain, now, 0.025);
      d.lowFilter.gain.setTargetAtTime(env.outLowDb, now, 0.03);
      d.midFilter.gain.setTargetAtTime(env.outMidDb, now, 0.03);

      if (d.sweepFilter.type !== env.outFilterType) {
        d.sweepFilter.type = env.outFilterType;
      }
      d.sweepFilter.frequency.setTargetAtTime(
        Math.max(20, Math.min(20000, env.outFilterFreqHz)),
        now,
        0.03
      );
      d.sweepFilter.Q.setTargetAtTime(env.outFilterQ, now, 0.03);
      d.echoSendGain.gain.setTargetAtTime(phase === 'overlap' ? env.echoSend : 0, now, 0.03);
      d.feedbackGain.gain.setTargetAtTime(env.echoFeedback, now, 0.03);
      d.reverbSendGain.gain.setTargetAtTime(phase === 'overlap' ? env.reverbWet : 0, now, 0.03);
    } else if (this.elOut) {
      this.elOut.volume = Math.max(0, Math.min(1, env.effectiveOutIframeVol / 100));
    }

    if (this.elOut && Number.isFinite(env.outPlaybackRate)) {
      try {
        this.elOut.playbackRate = env.outPlaybackRate;
      } catch (_) {}
    }

    // Incoming deck
    if (this.deckIn && this.deckIn.webAudioConnected && this.ctx) {
      const d = this.deckIn;
      this.elIn.volume = 1.0;
      d.envelopeGain.gain.setTargetAtTime(env.inGain, now, 0.025);
      d.lowFilter.gain.setTargetAtTime(env.inLowDb, now, 0.03);
      d.midFilter.gain.setTargetAtTime(env.inMidDb, now, 0.03);
      if (d.sweepFilter.type !== env.inFilterType) {
        d.sweepFilter.type = env.inFilterType;
      }
      d.sweepFilter.frequency.setTargetAtTime(
        Math.max(20, Math.min(20000, env.inFilterFreqHz)),
        now,
        0.03
      );
    } else if (this.elIn) {
      this.elIn.volume = Math.max(0, Math.min(1, env.effectiveInIframeVol / 100));
    }

    if (this.elIn && Number.isFinite(env.inPlaybackRate)) {
      try {
        this.elIn.playbackRate = env.inPlaybackRate;
      } catch (_) {}
    }
  }

  /**
   * Live update of Volume / EQ / Effects / Bars while audition is actively playing
   */
  updateConfig(newConfig) {
    this.config = { ...this.config, ...newConfig };
  }

  /**
   * Interactive waveform scrubbing: jump to normalized overallProgress in [0, 1]
   */
  seek(overallProgress) {
    if (!this.isRunning) return;
    const p = Math.max(0, Math.min(0.99, overallProgress));
    const curOverlapSec = Math.max(2.0, Number(this.config.durationSec) || 5.5);
    const totalWindowSec = this.leadInSec + curOverlapSec + this.leadOutSec;
    const targetElapsed = p * totalWindowSec;

    this.startWallTime = performance.now() - targetElapsed * 1000;

    if (this.elOut) {
      try {
        if (targetElapsed < this.leadInSec + curOverlapSec) {
          this.elOut.currentTime = Math.max(0, this.outStartCueSec + targetElapsed);
          if (this.elOut.paused) this.elOut.play().catch(() => {});
        } else {
          this.elOut.pause();
        }
      } catch (_) {}
    }

    if (this.elIn) {
      try {
        if (targetElapsed >= this.leadInSec) {
          this._inStarted = true;
          this.elIn.currentTime = Math.max(0, this.inStartCueSec + (targetElapsed - this.leadInSec));
          if (this.elIn.paused) this.elIn.play().catch(() => {});
        } else {
          this._inStarted = false;
          this.elIn.pause();
          this.elIn.currentTime = this.inStartCueSec;
        }
      } catch (_) {}
    }
  }

  stop() {
    const wasRunning = this.isRunning;
    this.isRunning = false;
    if (this.animFrame) {
      cancelAnimationFrame(this.animFrame);
      this.animFrame = null;
    }
    if (this.elOut) {
      try {
        this.elOut.pause();
        this.elOut.src = '';
      } catch (_) {}
      this.elOut = null;
    }
    if (this.elIn) {
      try {
        this.elIn.pause();
        this.elIn.src = '';
      } catch (_) {}
      this.elIn = null;
    }
    this.deckOut = null;
    this.deckIn = null;
    if (this.ctx && this.ctx.state !== 'closed') {
      try { this.ctx.close(); } catch (_) {}
    }
    this.ctx = null;
    this.masterLimiter = null;
    if (wasRunning) {
      this.onStop?.();
    }
  }
}
