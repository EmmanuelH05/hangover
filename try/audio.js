// Three original loops, made live with the Web Audio API. There are no audio
// files and no samples: every sound below is an oscillator or filtered noise.
// Nothing here runs until the visitor presses play.
(() => {
  'use strict';

  const AC = window.AudioContext || window.webkitAudioContext;
  const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);
  const MASTER = 0.65; // modest on purpose: peaks land near -5 dBFS, the average far lower
  const LOOKAHEAD = 0.14; // seconds of notes scheduled ahead of the clock

  // Made up names, the same ones the app's own demo mode uses.
  const TRACKS = [
    { title: 'Midnight Drive', artist: 'Neon Coast', album: 'Afterglow', dur: 214, hue: 0.92, bpm: 104 },
    { title: 'Paper Lanterns', artist: 'Hollow Pines', album: 'Small Hours', dur: 187, hue: 0.08, bpm: 140 },
    { title: 'Slow Tide', artist: 'Marlow', album: 'Low Light', dur: 241, hue: 0.55, bpm: 76, swing: 0.14 },
  ];

  function createEngine(options) {
    let ctx = (options && options.context) || null;
    let out = null;
    let analyser = null;
    let noise = null;
    let curve = null;
    let bus = null;
    let playing = false;
    let index = 0;
    let pausedAt = 0; // where the track is while paused
    let anchorPos = 0; // track position at anchorCtx
    let anchorCtx = 0;
    let stepNo = 0;
    let nextAt = 0;
    let clock = 0;
    let suspendTimer = 0;
    let ended = false;

    const api = { tracks: TRACKS, onEnd: () => {} };

    // ---- graph -----------------------------------------------------------

    function build() {
      const comp = ctx.createDynamicsCompressor();
      comp.threshold.value = -22;
      comp.knee.value = 14;
      comp.ratio.value = 4;
      comp.attack.value = 0.004;
      comp.release.value = 0.2;
      const master = ctx.createGain();
      master.gain.value = MASTER;
      analyser = ctx.createAnalyser();
      analyser.fftSize = 128;
      analyser.smoothingTimeConstant = 0.6;
      analyser.minDecibels = -85;
      analyser.maxDecibels = -25;
      comp.connect(master);
      master.connect(analyser);
      analyser.connect(ctx.destination);
      out = comp;

      noise = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
      const data = noise.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;

      curve = new Float32Array(256);
      for (let i = 0; i < 256; i++) curve[i] = Math.tanh(2.2 * (i / 128 - 1));
    }

    function ensure() {
      if (ctx) {
        if (!out) build();
        return;
      }
      ctx = new AC();
      build();
    }

    // One bus per track and per restart. A skip or a scrub can then cut the old
    // notes at once without touching the new ones.
    function makeBus(i) {
      const dry = ctx.createGain();
      let tail = dry;
      if (i === 2) {
        const lp = ctx.createBiquadFilter();
        lp.type = 'lowpass';
        lp.frequency.value = 4200;
        dry.connect(lp);
        tail = lp;
      }
      tail.connect(out);
      const send = ctx.createGain();
      const delay = ctx.createDelay(1);
      delay.delayTime.value = (60 / TRACKS[i].bpm) * 0.75;
      const feedback = ctx.createGain();
      feedback.gain.value = 0.32;
      const wet = ctx.createGain();
      wet.gain.value = 0.35;
      send.connect(delay);
      delay.connect(feedback);
      feedback.connect(delay);
      delay.connect(wet);
      wet.connect(dry);
      const sat = ctx.createWaveShaper();
      sat.curve = curve;
      sat.oversample = '2x';
      sat.connect(dry);
      return { dry, send, sat };
    }

    function retire(b) {
      if (!b) return;
      const now = ctx.currentTime;
      b.dry.gain.cancelScheduledValues(now);
      b.dry.gain.setValueAtTime(b.dry.gain.value, now);
      b.dry.gain.linearRampToValueAtTime(0, now + 0.05);
      setTimeout(() => {
        try { b.dry.disconnect(); } catch (e) { /* already gone */ }
      }, 400);
    }

    // ---- voices ----------------------------------------------------------

    function tone(t, f, dur, peak, o) {
      o = o || {};
      const osc = ctx.createOscillator();
      osc.type = o.type || 'sine';
      if (o.from) {
        osc.frequency.setValueAtTime(o.from, t);
        osc.frequency.exponentialRampToValueAtTime(f, t + (o.glide || 0.05));
      } else {
        osc.frequency.setValueAtTime(f, t);
      }
      if (o.detune) osc.detune.value = o.detune;
      const a = o.attack || 0.004;
      const hold = o.hold || 0;
      const g = ctx.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(peak, t + a);
      if (hold) g.gain.setValueAtTime(peak, t + a + hold);
      g.gain.exponentialRampToValueAtTime(0.0001, t + a + hold + dur);
      let node = osc;
      if (o.lp) {
        const lp = ctx.createBiquadFilter();
        lp.type = 'lowpass';
        lp.Q.value = o.q || 0.7;
        lp.frequency.setValueAtTime(o.lp, t);
        if (o.lpTo) lp.frequency.exponentialRampToValueAtTime(o.lpTo, t + a + hold + dur);
        osc.connect(lp);
        node = lp;
      }
      node.connect(g);
      g.connect(o.dest || bus.dry);
      if (o.send) g.connect(bus.send);
      osc.start(t);
      osc.stop(t + a + hold + dur + 0.05);
    }

    function hiss(t, dur, peak, type, freq, o) {
      o = o || {};
      const src = ctx.createBufferSource();
      src.buffer = noise;
      const f = ctx.createBiquadFilter();
      f.type = type;
      f.frequency.value = freq;
      f.Q.value = o.q || 0.7;
      const g = ctx.createGain();
      g.gain.setValueAtTime(peak, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      src.connect(f);
      f.connect(g);
      g.connect(bus.dry);
      if (o.send) g.connect(bus.send);
      src.start(t, (t * 7.31) % 1.5);
      src.stop(t + dur + 0.02);
    }

    const kick = (t, g, lo, hi) => tone(t, lo || 46, 0.32, g || 0.85, { from: hi || 160, glide: 0.09 });
    const snare = (t, g) => {
      hiss(t, 0.16, g, 'highpass', 1500);
      tone(t, 185, 0.09, g * 0.5, { type: 'triangle' });
    };
    const clap = (t, g) => {
      [0, 0.011, 0.022].forEach((d) => hiss(t + d, 0.03, g, 'bandpass', 1500, { q: 0.9 }));
      hiss(t + 0.03, 0.22, g * 0.7, 'bandpass', 1300, { q: 0.9, send: true });
    };
    const hat = (t, g, open) => hiss(t, open ? 0.2 : 0.04, g, 'highpass', 7500);
    const pluck = (t, m, g) =>
      tone(t, hz(m), 0.22, g, { type: 'sawtooth', lp: 3200, lpTo: 500, q: 2, send: true });
    const pad = (t, m, dur, g) =>
      [-7, 7].forEach((d) =>
        tone(t, hz(m), dur * 0.6, g, { type: 'sawtooth', detune: d, attack: 0.35, hold: dur * 0.5, lp: 1100 })
      );
    const bell = (t, m, g) => {
      tone(t, hz(m), 0.9, g, { send: true });
      tone(t, hz(m) * 2.76, 0.35, g * 0.25, { send: true });
    };
    const rhodes = (t, m, g) => {
      tone(t, hz(m), 1.3, g, { attack: 0.006, lp: 2600, send: true });
      tone(t, hz(m) * 2, 0.35, g * 0.4, { lp: 3000 });
      tone(t, hz(m) * 4, 0.12, g * 0.12);
    };

    // ---- 1. Midnight Drive: mid tempo synth, A minor ---------------------

    const CH0 = [[57, 60, 64], [57, 60, 65], [55, 60, 64], [55, 59, 62]];
    const BASS0 = [45, 41, 48, 43];
    const ARP0 = [0, 1, 2, 1, 2, 1, 0, 2];
    const HITS0 = [0, 3, 6, 10, 12];

    function step0(s, t, sd) {
      const bar = s >> 4;
      const st = s & 15;
      const c = bar & 3;
      const ch = CH0[c];
      if (st === 0) ch.forEach((m) => pad(t, m, sd * 16, 0.04));
      if (!(st & 1)) {
        const k = (st >> 1) & 7;
        pluck(t, ch[ARP0[k]] + 12 + (k === 7 ? 12 : 0), st % 4 ? 0.07 : 0.1);
      }
      if (((bar >> 2) & 3) === 0) return; // four bars of intro with no drums
      if (HITS0.includes(st)) {
        tone(t, hz(BASS0[c] + (st === 6 ? 12 : 0)), 0.2, 0.2, { type: 'sawtooth', lp: 480, lpTo: 200, q: 3 });
      }
      if (st === 0 || st === 8 || (st === 10 && bar & 1)) kick(t, 0.8);
      if (st === 4 || st === 12) snare(t, 0.26);
      if (!(st & 1)) hat(t, st % 4 ? 0.05 : 0.08, st === 14);
    }

    // ---- 2. Paper Lanterns: 140 BPM trap with an 808, D minor ------------

    const ROOT1 = [38, 38, 34, 36];
    const MEL1 = [
      [[0, 81], [3, 77], [6, 74], [10, 77], [12, 81], [14, 84]],
      [[0, 81], [2, 84], [6, 81], [8, 77], [11, 74], [14, 77]],
      [[0, 82], [3, 77], [6, 74], [10, 77], [12, 82], [14, 86]],
      [[0, 84], [3, 79], [6, 76], [10, 79], [12, 84], [14, 88]],
    ];

    function step1(s, t, sd) {
      const bar = s >> 4;
      const st = s & 15;
      const c = bar & 3;
      const hard = (bar & 7) >= 2; // the first two bars of a phrase are light
      MEL1[c].forEach((n) => { if (n[0] === st) bell(t, n[1], 0.05); });
      // hats on every sixteenth, with a 32nd note roll on step 7 and a triplet on 15
      const hg = st % 4 === 0 ? 0.07 : 0.04;
      hat(t, hg, false);
      if (st === 7) hat(t + sd / 2, 0.035, false);
      if (st === 15 && (bar & 3) === 3) {
        hat(t + sd / 3, 0.04, false);
        hat(t + (2 * sd) / 3, 0.05, false);
      }
      if (!hard) return;
      const root = hz(ROOT1[c]);
      if (st === 0) tone(t, root, 0.7, 0.55, { from: root * 1.6, glide: 0.04, dest: bus.sat });
      if (st === 7) tone(t, root, 0.2, 0.4, { from: root * 1.4, glide: 0.03, dest: bus.sat });
      if (st === 10) tone(t, root * 1.122, 0.45, 0.5, { from: root * 1.8, glide: 0.04, dest: bus.sat });
      if (st === 14 && c === 3) tone(t, root * 1.5, 0.2, 0.35, { dest: bus.sat });
      if (st === 0 || st === 10) kick(t, 0.5, 52, 130);
      if (st === 8) clap(t, 0.3);
    }

    // ---- 3. Slow Tide: slow lo-fi, swung, in C ---------------------------

    const CH2 = [[50, 53, 57, 60], [50, 53, 55, 59], [52, 55, 59, 64], [55, 57, 60, 64]];
    const BASS2 = [38, 43, 48, 45];
    const SCALE2 = [72, 74, 76, 79, 81, 84];

    function step2(s, t, sd) {
      const bar = s >> 4;
      const st = s & 15;
      const c = bar & 3;
      const ch = CH2[c];
      if (st === 0) ch.forEach((m, k) => rhodes(t + k * 0.012, m, 0.05));
      if (st === 6) ch.slice(1).forEach((m, k) => rhodes(t + k * 0.01, m, 0.03));
      if (st === 10 && (bar & 1)) ch.slice(1).forEach((m, k) => rhodes(t + k * 0.01, m, 0.03));
      if ((st === 3 || st === 11 || st === 14) && (bar * 3 + st) % 7 < 3) {
        rhodes(t, SCALE2[(bar * 5 + st * 3) % 6], 0.035);
      }
      if (st === 0) tone(t, hz(BASS2[c]), 0.9, 0.34, { lp: 400 });
      if (st === 10) tone(t, hz(BASS2[c]), 0.4, 0.25, { lp: 400 });
      if (st === 0 || st === 9) kick(t, st ? 0.5 : 0.7, 44, 110);
      if (st === 4 || st === 12) hiss(t, 0.13, 0.22, 'bandpass', 2400, { q: 0.6 });
      if (!(st & 1)) hat(t, st % 4 ? 0.02 : 0.035, false);
      if (Math.random() < 0.12) hiss(t + Math.random() * sd, 0.008, 0.05, 'highpass', 3000);
    }

    const STEPS = [step0, step1, step2];

    // ---- scheduler -------------------------------------------------------

    function pump(until) {
      const tr = TRACKS[index];
      const sd = 60 / tr.bpm / 4;
      while (nextAt < until) {
        const swing = tr.swing && stepNo & 1 ? tr.swing * sd : 0;
        STEPS[index](stepNo, nextAt + swing, sd);
        stepNo++;
        nextAt += sd;
      }
    }

    function begin(i, pos) {
      retire(bus);
      index = i;
      bus = makeBus(i);
      const sd = 60 / TRACKS[i].bpm / 4;
      stepNo = Math.floor(pos / sd);
      anchorPos = stepNo * sd;
      anchorCtx = ctx.currentTime + 0.06;
      nextAt = anchorCtx;
      ended = false;
    }

    function position() {
      if (!playing) return pausedAt;
      const p = anchorPos + Math.max(0, ctx.currentTime - anchorCtx);
      return Math.min(TRACKS[index].dur, p);
    }

    function startClock() {
      stopClock();
      clock = setInterval(() => {
        pump(ctx.currentTime + LOOKAHEAD);
        if (!ended && position() >= TRACKS[index].dur - 0.02) {
          ended = true;
          api.onEnd();
        }
      }, 25);
    }

    function stopClock() {
      clearInterval(clock);
      clock = 0;
    }

    // ---- public ----------------------------------------------------------

    api.play = () => {
      ensure();
      clearTimeout(suspendTimer);
      if (ctx.resume) ctx.resume();
      if (pausedAt >= TRACKS[index].dur - 0.05) pausedAt = 0;
      begin(index, pausedAt);
      playing = true;
      startClock();
    };

    api.pause = () => {
      if (!playing) return;
      pausedAt = position();
      playing = false;
      stopClock();
      retire(bus);
      bus = null;
      suspendTimer = setTimeout(() => { if (ctx.suspend) ctx.suspend(); }, 120);
    };

    // Move to a track and a time. While playing, the notes restart there.
    api.select = (i, pos) => {
      index = i;
      pausedAt = Math.max(0, Math.min(TRACKS[i].dur, pos || 0));
      if (playing) begin(i, pausedAt);
    };

    api.position = position;
    api.isPlaying = () => playing;
    api.index = () => index;
    api.analyser = () => analyser;

    // For tests: schedule a stretch of a track on an offline context.
    api.renderTo = (i, seconds) => {
      ensure();
      pausedAt = 0;
      begin(i, 0);
      pump(seconds);
      return ctx.startRendering();
    };

    return api;
  }

  window.HangoverTry = window.HangoverTry || {};
  window.HangoverTry.createEngine = createEngine;
  window.HangoverTry.tracks = TRACKS;
})();
