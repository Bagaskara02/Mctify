import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  computeTrackBpmAndKey,
  computeCamelotCompatibility,
  computeBarDurationSec,
  evaluateTransitionEnvelope,
  computeSmartAutomixPreset,
  buildEnvelopeSvgPaths,
  generateMusicalWaveformBars,
  analyzePcmBeatGrid,
} from '../src/services/transitionEngine.js';

describe('Web Audio DSP Transition & Dual-Deck Automix Engine Tests', () => {
  it('resolves verified studio BPM & Camelot keys and deterministic genre estimates', () => {
    const t1 = computeTrackBpmAndKey({
      title: 'One Of The Girls (with JENNIE, Lily-Rose Depp)',
      artist: 'The Weeknd',
    });
    assert.equal(t1.bpm, 85);
    assert.equal(t1.key, '4B');

    const t2 = computeTrackBpmAndKey({
      title: 'Stargirl Interlude',
      artist: 'The Weeknd, Lana Del Rey',
    });
    assert.equal(t2.bpm, 90);
    assert.equal(t2.key, '5A');

    const custom = computeTrackBpmAndKey({
      title: 'Synth Club Anthem',
      artist: 'DJ Test',
      genre: 'EDM House',
    });
    assert.ok(custom.bpm >= 120 && custom.bpm <= 135);
    assert.match(custom.key, /^\d{1,2}[AB]$/);
  });

  it('scores harmonic Camelot Wheel compatibility accurately', () => {
    assert.equal(computeCamelotCompatibility('4B', '4B').score, 100);
    assert.equal(computeCamelotCompatibility('4B', '4A').score, 96);
    assert.equal(computeCamelotCompatibility('4B', '5B').score, 92);
    assert.equal(computeCamelotCompatibility('1A', '12A').score, 92); // wraps around 1 <-> 12
    assert.ok(computeCamelotCompatibility('4B', '10A').score < 70);
  });

  it('computes beat-accurate bar durations in 4/4 time and folds double/half-time BPMs', () => {
    // 85 BPM & 90 BPM -> avg 87.5 BPM -> 2 bars (8 beats) = 8 * 60 / 87.5 = 5.485s -> 5.5s
    const twoBars = computeBarDurationSec(85, 90, '2 bars');
    assert.equal(twoBars.bars, 2);
    assert.equal(twoBars.beats, 8);
    assert.equal(twoBars.durationSec, 5.5);

    const fourBars = computeBarDurationSec(85, 90, '4 bars');
    assert.equal(fourBars.bars, 4);
    assert.equal(fourBars.beats, 16);
    assert.equal(fourBars.durationSec, 11.0);

    // Double-time folding: 170 BPM vs 85 BPM should fold to 0 deltaBpm and 1.0 tempoRatio
    const folded = computeBarDurationSec(85, 170, '2 bars');
    assert.equal(folded.deltaBpm, 0);
    assert.equal(folded.tempoRatio, 1);
  });

  it('evaluates volume, EQ bass-swap, and filter sweep envelopes accurately across [0, 1]', () => {
    // 1. Overlap mode keeps both tracks high around midpoint (p = 0.45)
    const midOverlap = evaluateTransitionEnvelope(0.45, {
      volume: 'overlap',
      eq: 'bass_swap',
      effect: 'high_pass',
      bpmA: 85,
      bpmB: 90,
    });
    assert.equal(midOverlap.outGain, 1.0);
    assert.ok(midOverlap.inGain > 0.85);

    // 2. Crossfade mode maintains equal-power energy (outGain^2 + inGain^2 == 1)
    for (const p of [0, 0.25, 0.5, 0.75, 1.0]) {
      const cf = evaluateTransitionEnvelope(p, { volume: 'crossfade' });
      const powerSum = cf.outGain * cf.outGain + cf.inGain * cf.inGain;
      assert.ok(Math.abs(powerSum - 1.0) < 1e-6);
    }

    // 3. Bass Swap EQ cuts incoming bass early and swaps outgoing bass out after midpoint
    const earlySwap = evaluateTransitionEnvelope(0.2, { eq: 'bass_swap' });
    const lateSwap = evaluateTransitionEnvelope(0.7, { eq: 'bass_swap' });
    assert.equal(earlySwap.outLowDb, 0);
    assert.equal(earlySwap.inLowDb, -16);
    assert.equal(lateSwap.outLowDb, -18);
    assert.ok(lateSwap.inLowDb >= 0);

    // 4. High-Pass filter sweeps cutoff exponentially from ~28Hz up to 2400Hz
    const hpfStart = evaluateTransitionEnvelope(0, { effect: 'high_pass' });
    const hpfEnd = evaluateTransitionEnvelope(1, { effect: 'high_pass' });
    assert.equal(hpfStart.outFilterType, 'highpass');
    assert.ok(hpfStart.outFilterFreqHz <= 30);
    assert.ok(hpfEnd.outFilterFreqHz >= 2350);
  });

  it('generates Smart Automix presets, SVG envelope paths, and waveform bars', () => {
    const preset = computeSmartAutomixPreset(
      { title: 'One Of The Girls', artist: 'The Weeknd', bpm: 85, key: '4B' },
      { title: 'Stargirl Interlude', artist: 'The Weeknd', bpm: 90, key: '5A' }
    );
    assert.ok(preset.durationSec > 0);
    assert.ok(preset.explanation.length > 20);

    const svg = buildEnvelopeSvgPaths(preset, 200, 72);
    assert.ok(svg.outLinePoints.includes(','));
    assert.ok(svg.inAreaPath.startsWith('M 0,72'));

    const bars = generateMusicalWaveformBars(60, { title: 'Test', bpm: 90 }, true);
    assert.equal(bars.length, 60);
    assert.ok(bars.every((b) => b >= 14 && b <= 94));
  });

  it('detects Intro-Drop onset and real BPM from synthetic PCM kick drum pulses', () => {
    const sampleRate = 22050;
    const durationSec = 8;
    const pcm = new Float32Array(sampleRate * durationSec);
    // 2.0s silent intro, then 120 BPM (0.5s per beat) kick pulses
    const beatInterval = 0.5;
    for (let t = 2.0; t < durationSec; t += beatInterval) {
      const startIdx = Math.floor(t * sampleRate);
      const kickLen = Math.floor(0.08 * sampleRate);
      for (let i = 0; i < kickLen && startIdx + i < pcm.length; i++) {
        const env = Math.exp(-i / (0.02 * sampleRate));
        pcm[startIdx + i] = Math.sin((2 * Math.PI * 65 * i) / sampleRate) * env;
      }
    }

    const analysis = analyzePcmBeatGrid(pcm, sampleRate, false);
    assert.ok(analysis.introDropSec >= 1.8 && analysis.introDropSec <= 2.2, `Expected ~2.0s introDropSec, got ${analysis.introDropSec}`);
    assert.ok(analysis.detectedBpm >= 116 && analysis.detectedBpm <= 124, `Expected ~120 BPM, got ${analysis.detectedBpm}`);
  });
});
