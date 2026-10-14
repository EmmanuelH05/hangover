// The "Try it" notch: a small copy of Hangover drawn on the page, with sample
// content. Plain DOM, no libraries. The music engine is in audio.js.
(() => {
  'use strict';

  const root = document.getElementById('try-root');
  const lib = window.HangoverTry;
  if (!root || !lib) return;

  const reducedQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const hoverQuery = window.matchMedia('(hover: hover) and (pointer: fine)');
  const tracks = lib.tracks;
  const engine = lib.createEngine();

  // ---- small helpers ------------------------------------------------------

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const pad2 = (n) => String(n).padStart(2, '0');
  const clock = (sec) => Math.floor(sec / 60) + ':' + pad2(Math.floor(sec % 60));
  const hour12 = (d) => d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });

  // Filled icons and stroked icons, on a 24 point grid.
  const FILL = {
    play: '<path d="M8 5.2v13.6a.6.6 0 0 0 .9.5l11-6.8a.6.6 0 0 0 0-1L8.9 4.7a.6.6 0 0 0-.9.5z"/>',
    pause: '<rect x="6.5" y="5" width="4" height="14" rx="1.2"/><rect x="13.5" y="5" width="4" height="14" rx="1.2"/>',
    prev: '<path d="M11 6.4v11.2L3.5 12zM20.5 6.4v11.2L13 12z"/>',
    next: '<path d="M13 6.4v11.2L20.5 12zM3.5 6.4v11.2L11 12z"/>',
    video: '<path d="M3 7.5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zM16.5 10.5l4.5-3v9l-4.5-3z"/>',
    arrow: '<path d="M3.5 11.5L20.5 3.5 12.5 20.5l-2-7.5z"/>',
    battery: '<path d="M3 9a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2zm17 1.5h1v3h-1z" opacity=".9"/>',
  };
  const STROKE = {
    left: '<path d="M14.5 5.5L8 12l6.5 6.5"/>',
    right: '<path d="M9.5 5.5L16 12l-6.5 6.5"/>',
    down: '<path d="M5.5 9.5L12 16l6.5-6.5"/>',
    up: '<path d="M5.5 14.5L12 8l6.5 6.5"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
    list: '<path d="M4 6.5h1M9 6.5h11M4 12h1M9 12h11M4 17.5h1M9 17.5h11"/>',
    note: '<rect x="4" y="4.5" width="16" height="15" rx="3"/><path d="M8 9.5h8M8 14h5"/>',
    timer: '<circle cx="12" cy="13.5" r="7"/><path d="M12 9.5v4l2.5 1.5M9.5 3.5h5"/>',
    cal: '<rect x="4" y="5" width="16" height="15" rx="3"/><path d="M4 10h16M8.5 3.5v3M15.5 3.5v3"/>',
  };
  const fill = (n, s) => '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false">' + FILL[n] + '</svg>';
  const line = (n, s) => '<svg width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + STROKE[n] + '</svg>';

  // Weather pictures on a 32 point grid.
  const CLOUD = '<path d="M9 24a5 5 0 0 1-.6-9.96A7 7 0 0 1 21.6 13.2 5.4 5.4 0 0 1 22 24z" fill="#f2f2f7"/>';
  const RAYS = (cx, cy, r1, r2) => [0, 45, 90, 135, 180, 225, 270, 315].map((a) => {
    const t = (a * Math.PI) / 180;
    return 'M' + (cx + Math.cos(t) * r1).toFixed(1) + ' ' + (cy + Math.sin(t) * r1).toFixed(1) + 'L' + (cx + Math.cos(t) * r2).toFixed(1) + ' ' + (cy + Math.sin(t) * r2).toFixed(1);
  }).join('');
  const SKY = {
    sun: '<circle cx="16" cy="16" r="6" fill="#ffd60a"/><path d="' + RAYS(16, 16, 9.5, 13) + '" stroke="#ffd60a" stroke-width="2.2" stroke-linecap="round"/>',
    part: '<circle cx="12" cy="12" r="5" fill="#ffd60a"/><path d="' + RAYS(12, 12, 7.8, 10.6) + '" stroke="#ffd60a" stroke-width="2" stroke-linecap="round"/><g transform="translate(5 4) scale(.82)">' + CLOUD + '</g>',
    cloud: '<g transform="translate(0 1)">' + CLOUD + '</g>',
    rain: '<g transform="translate(0 -3)">' + CLOUD + '</g><path d="M11 24.5l-1 3M16.5 24.5l-1 3M22 24.5l-1 3" stroke="#64b5ff" stroke-width="2" stroke-linecap="round"/>',
  };
  const sky = (kind, s) => '<svg width="' + s + '" height="' + s + '" viewBox="0 0 32 32" aria-hidden="true" focusable="false">' + SKY[kind] + '</svg>';

  // ---- sample content -------------------------------------------------------

  const COLORS = { work: '#0a84ff', personal: '#30d158', school: '#bf5af2' };

  const ACCENTS = [
    { name: 'Purple', hex: '#db34f2' },
    { name: 'Blue', hex: '#0091ff' },
    { name: 'Pink', hex: '#ff375f' },
    { name: 'Red', hex: '#ff4245' },
    { name: 'Orange', hex: '#ff9230' },
    { name: 'Yellow', hex: '#ffd600' },
    { name: 'Green', hex: '#30d158' },
    { name: 'Graphite', hex: '#98989d' },
  ];

  const hsb = (h, s, v) => {
    const i = Math.floor(h * 6);
    const f = h * 6 - i;
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);
    const rgb = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6];
    return 'rgb(' + rgb.map((x) => Math.round(x * 255)).join(',') + ')';
  };
  // The app's drawn cover: a gradient with a pale disc in the middle.
  const coverOf = (hue) =>
    'radial-gradient(circle at 50% 50%, rgba(255,255,255,.2) 0 20%, transparent 20.5%), linear-gradient(135deg, ' +
    hsb(hue, 0.62, 1) + ', ' + hsb((hue + 0.12) % 1, 0.85, 0.62) + ')';

  const startedAt = new Date();
  const dayStart = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
  const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

  // Today's three are set from the moment the page loads, which gives the
  // notch one coming up at any hour. They always sit on today's cell, even
  // when a late visitor's clock times run past midnight. The next few are on
  // the days after.
  function makeEvents() {
    const now = startedAt.getTime();
    const quarter = (ms) => Math.ceil(ms / 9e5) * 9e5;
    const today = [
      { title: 'Standup', cal: 'work', link: true, at: now + 20 * 60e3 },
      { title: 'Design review', cal: 'work', at: quarter(now + 2 * 36e5) },
      { title: 'Gym', cal: 'personal', at: quarter(now + 5 * 36e5) },
    ].map((e) => ({ ...e, day: 0, at: new Date(e.at) }));
    const on = (days, h, m) => { const d = addDays(dayStart(startedAt), days); d.setHours(h, m, 0, 0); return d; };
    return today.concat([
      { title: 'Office hours', cal: 'school', day: 1, at: on(1, 10, 0) },
      { title: 'Dentist', cal: 'personal', day: 2, at: on(2, 9, 30) },
      { title: 'Midterm review', cal: 'school', day: 3, at: on(3, 16, 0) },
      { title: 'Dinner with family', cal: 'personal', day: 4, at: on(4, 18, 30) },
    ]);
  }
  const events = makeEvents();

  const todos = ['Finish problem set 3', 'Email the TA', 'Review the pull request', 'Book flights', 'Renew library books', 'Plan the weekend']
    .map((title, i) => ({ id: i, title, done: false }));
  let nextTodoId = todos.length;

  const noteLines = [[300, 'Try the new cache key'], [230, 'Ask about the midterm room'], [150, 'Idea: widget presets'], [70, 'Send the slides tonight'], [25, 'Read chapter 6']];
  const notes = noteLines.map(([minutes, text]) => ({ at: new Date(startedAt.getTime() - minutes * 60e3), text }));

  // The app's demo week: mild, a little rain on day six. Fahrenheit.
  const WX = {
    place: 'Sample city',
    now: 72,
    feels: 72,
    text: { 0: 'Clear', 1: 'Mostly clear', 2: 'Partly cloudy', 3: 'Cloudy', 61: 'Light rain' },
    kind: { 0: 'sun', 1: 'sun', 2: 'part', 3: 'cloud', 61: 'rain' },
    hi: [75, 77, 81, 79, 73, 72, 75],
    lo: [59, 61, 63, 63, 59, 57, 59],
    code: [1, 1, 2, 0, 3, 61, 2],
    rain: [0, 0, 5, 0, 20, 60, 10],
  };

  // ---- the screen -----------------------------------------------------------

  const dockColors = [['#7cc4ff', '#2f7bea'], ['#ffb86b', '#f2672f'], ['#9be89b', '#2e9e5b'], ['#f6a5d6', '#c0449a'], ['#c9b8ff', '#6a50d8'], ['#e6e6ea', '#8d8f99']];
  const swatches = ACCENTS.map((a, i) =>
    '<button type="button" role="radio" aria-checked="' + (i === 0) + '" aria-label="' + a.name + '" data-hex="' + a.hex + '" tabindex="' + (i === 0 ? 0 : -1) + '" style="--c:' + a.hex + '"></button>').join('');

  root.innerHTML = [
    '<div class="try-stage" id="try-stage"><div class="try-screen" id="try-screen">',
    '<div class="try-wall"></div>',
    '<div class="try-menubar" aria-hidden="true"><div><b>Files</b><span>Edit</span><span>View</span></div><div class="mb-r">' + fill('battery', 20) + '<span id="try-time"></span></div></div>',
    '<p class="try-hint" id="try-hint" aria-hidden="true"></p>',
    '<div class="try-dock" aria-hidden="true">' + dockColors.map((c) => '<i style="--a:' + c[0] + ';--b:' + c[1] + '"></i>').join('') + '</div>',
    '<div class="try-island" id="try-island" data-state="closed" data-ears="none"><div class="try-shape"></div><div class="try-clip">',
    '<span class="try-ear is-left" aria-hidden="true"><span class="art" id="ear-art"></span></span>',
    '<span class="try-ear is-right" aria-hidden="true"><span class="try-bars" id="ear-bars"><i></i><i></i><i></i><i></i></span><span class="try-eartime" id="ear-time"></span></span>',
    '<button type="button" class="try-notch" id="try-notch" aria-expanded="false" aria-controls="try-nook"></button>',

    '<div class="try-panel try-nook" id="try-nook" role="region" aria-label="Hangover, with sample content" inert>',
    '<button type="button" class="try-close" id="try-close" aria-label="Close">' + line('close', 12) + '</button>',
    '<div class="try-grid">',

    // music
    '<div class="tcard tmusic wide" role="group" aria-label="Music">',
    '<div class="art" id="m-art"></div>',
    '<div class="m-mid"><div class="m-title" id="m-title"></div><div class="m-sub" id="m-sub"></div>',
    '<div class="m-seek"><input type="range" class="try-range" id="m-seek" min="0" max="100" step="1" value="0" aria-label="Song position" aria-valuetext="0:00 of 0:00">',
    '<div class="m-times" aria-hidden="true"><span id="m-el">0:00</span><span id="m-tot">0:00</span></div></div></div>',
    '<div class="m-ctl"><button type="button" class="tbtn" id="m-prev" aria-label="Previous song">' + fill('prev', 18) + '</button>',
    '<button type="button" class="tbtn big" id="m-play" aria-label="Play">' + fill('play', 22) + '</button>',
    '<button type="button" class="tbtn" id="m-next" aria-label="Next song">' + fill('next', 18) + '</button></div>',
    '</div>',

    // calendar
    '<div class="tcard tcal wide" role="group" aria-label="Calendar">',
    '<div class="thd">' + line('cal', 12) + '<span id="cal-month"></span>',
    '<span class="cal-nav"><button type="button" id="cal-prev" aria-label="Previous week">' + line('left', 12) + '</button>',
    '<button type="button" id="cal-today" aria-label="Go to today">Today</button>',
    '<button type="button" id="cal-next" aria-label="Next week">' + line('right', 12) + '</button></span></div>',
    '<div class="tweek" id="cal-week" role="group" aria-label="Week"></div>',
    '<div class="cal-events" id="cal-events"></div>',
    '</div>',

    // to-dos
    '<div class="tcard" role="group" aria-label="To-dos">',
    '<div class="thd">' + line('list', 12) + 'To-do<span class="tr" id="td-count"></span></div>',
    '<input type="text" class="tinput" id="td-input" placeholder="Add a reminder" aria-label="Add a to-do, then press Return" maxlength="80" autocomplete="off" autocapitalize="sentences" enterkeyhint="done">',
    '<ul class="tlist" id="td-list"></ul>',
    '</div>',

    // notes
    '<div class="tcard" role="group" aria-label="Quick notes">',
    '<div class="thd">' + line('note', 12) + 'Notes<span class="tr">Quick Notes.md</span></div>',
    '<input type="text" class="tinput" id="nt-input" placeholder="Jot something, return to save" aria-label="Add a note, then press Return" maxlength="120" autocomplete="off" autocapitalize="sentences" enterkeyhint="done">',
    '<ul class="tlist" id="nt-list"></ul>',
    '</div>',

    // timer
    '<div class="tcard ttimer" role="group" aria-label="Focus timer">',
    '<div class="thd">' + line('timer', 12) + 'Focus timer<span class="tr">60x demo</span></div>',
    '<div class="tt-time" id="tm-time" role="timer" aria-live="off">25:00</div>',
    '<div class="tt-bar" aria-hidden="true"><i id="tm-bar"></i></div>',
    '<div class="tt-chips" id="tm-chips" role="group" aria-label="Length in minutes"><button type="button" class="tchip" data-min="15" aria-pressed="false">15</button><button type="button" class="tchip" data-min="25" aria-pressed="true">25</button><button type="button" class="tchip" data-min="50" aria-pressed="false">50</button></div>',
    '<div class="tt-act"><button type="button" class="tpill go" id="tm-go">Start</button><button type="button" class="tpill" id="tm-reset" aria-label="Reset the timer">Reset</button></div>',
    '</div>',

    // weather
    '<div class="tcard twx" id="wx" role="group" aria-label="Weather">',
    '<div class="thd">' + fill('arrow', 11) + '<span id="wx-place"></span><span class="seg"><button type="button" id="wx-today" aria-pressed="true">Today</button><button type="button" id="wx-week" aria-pressed="false">7 day</button></span></div>',
    '<div id="wx-body"></div>',
    '</div>',

    '</div></div>', // grid, nook

    // the agent request
    '<div class="try-panel try-req" id="try-req" role="alertdialog" aria-labelledby="req-title" aria-describedby="req-cmd" data-step="ask" inert>',
    '<div class="req-head"><span class="req-dot"></span><b id="req-title">Claude Code</b><span>wants to run</span></div>',
    '<div class="req-code" id="req-cmd">bun test</div>',
    '<div class="req-act"><button type="button" id="req-deny">Deny</button><button type="button" class="allow" id="req-allow">Allow</button></div>',
    '<div class="req-done" id="req-done" role="status"><span class="ok" id="req-ok"></span><span id="req-text"></span></div>',
    '</div>',

    '</div></div></div></div>', // clip, island, screen, stage

    '<div class="try-controls">',
    '<button type="button" class="tbtn-agent" id="try-agent">Send a sample agent request</button>',
    '<div class="try-swatches"><span id="sw-label">Accent</span><div role="radiogroup" aria-labelledby="sw-label" id="try-swatches">' + swatches + '</div></div>',
    '</div>',
    '<div class="try-sr" id="try-live" aria-live="polite"></div>',
  ].join('');

  const $ = (id) => document.getElementById(id);
  const stage = $('try-stage');
  const screen = $('try-screen');
  const island = $('try-island');
  const notch = $('try-notch');
  const nook = $('try-nook');
  const req = $('try-req');
  const hint = $('try-hint');
  const live = $('try-live');
  const agentBtn = $('try-agent');

  const announce = (text) => {
    live.textContent = '';
    window.setTimeout(() => { live.textContent = text; }, 30);
  };

  // ---- scaling --------------------------------------------------------------

  const DESIGN_WIDTH = 520;
  const fit = () => {
    screen.style.setProperty('--s', (stage.clientWidth / DESIGN_WIDTH).toFixed(4));
    screen.classList.add('is-ready');
  };
  new ResizeObserver(fit).observe(stage);
  fit();

  const tickClock = () => { $('try-time').textContent = hour12(new Date()); };
  tickClock();
  window.setInterval(tickClock, 30000);

  hint.textContent = hoverQuery.matches ? 'Point at the notch' : 'Tap the notch';
  // On a touch screen the keyboard has its own return key, and a short hint fits at the larger type.
  if (!hoverQuery.matches) $('nt-input').placeholder = 'Jot something';

  // ---- the island: states and size -------------------------------------------

  const CLOSED_W = 168;
  const EARS_W = 288;
  const NOTCH_H = 32;
  const NOOK_W = 456;
  const REQ_W = 380;

  let state = 'closed'; // closed, open or request
  let openedBy = 'hover'; // hover, touch or key
  let hovered = false;
  let seeking = false;
  let lastPointer = 'mouse';
  let openTimer = 0;
  let closeTimer = 0;
  let ears = 'none';

  function size() {
    let w = ears === 'none' ? CLOSED_W : EARS_W;
    let h = NOTCH_H;
    if (state === 'open') { w = NOOK_W; h = nook.offsetHeight; }
    if (state === 'request') { w = REQ_W; h = req.offsetHeight; }
    island.style.setProperty('--w', w + 'px');
    island.style.setProperty('--h', h + 'px');
  }

  function setState(next) {
    state = next;
    island.dataset.state = next;
    nook.inert = next !== 'open';
    req.inert = next !== 'request';
    notch.setAttribute('aria-expanded', String(next === 'open'));
    hint.classList.toggle('is-hidden', next !== 'closed');
    size();
    labelNotch();
  }

  function labelNotch() {
    let text = state === 'open' ? 'Close the Hangover notch' : 'Open the Hangover notch';
    if (engine.isPlaying() && state !== 'open') text += ', playing ' + tracks[engine.index()].title;
    notch.setAttribute('aria-label', text);
  }

  function setEars() {
    const next = engine.isPlaying() ? 'music' : timer.running ? 'timer' : 'none';
    if (next === ears) return;
    ears = next;
    island.dataset.ears = next;
    if (state === 'closed') size();
    labelNotch();
  }

  const nookObserver = new ResizeObserver(() => { if (state === 'open') size(); });
  nookObserver.observe(nook);
  const reqObserver = new ResizeObserver(() => { if (state === 'request') size(); });
  reqObserver.observe(req);

  // A half-typed line keeps the notch open, as it does in the app.
  const isBusy = () => {
    const a = document.activeElement;
    const typing = a && island.contains(a) && a.matches('input[type="text"]') && a.value.trim() !== '';
    return typing || seeking;
  };

  function openNook(by) {
    if (state !== 'closed') return;
    openedBy = by;
    setState('open');
  }

  function closeNook(returnFocus) {
    window.clearTimeout(openTimer);
    window.clearTimeout(closeTimer);
    if (state !== 'open') return;
    const hadFocus = island.contains(document.activeElement);
    setState('closed');
    if (returnFocus || hadFocus) notch.focus({ preventScroll: true });
  }

  function settle() {
    window.clearTimeout(closeTimer);
    closeTimer = window.setTimeout(() => {
      if (state === 'open' && openedBy === 'hover' && !hovered && !isBusy()) closeNook(false);
    }, 300);
  }

  island.addEventListener('pointerenter', (e) => {
    if (e.pointerType === 'touch') return;
    hovered = true;
    window.clearTimeout(closeTimer);
    if (state === 'closed') {
      window.clearTimeout(openTimer);
      openTimer = window.setTimeout(() => openNook('hover'), 150);
    }
  });
  island.addEventListener('pointerleave', (e) => {
    if (e.pointerType === 'touch') return;
    hovered = false;
    window.clearTimeout(openTimer);
    if (state === 'open') settle();
  });
  notch.addEventListener('pointerdown', (e) => { lastPointer = e.pointerType; });
  notch.addEventListener('click', (e) => {
    if (state === 'request') return;
    const byKey = e.detail === 0;
    if (state === 'closed') {
      openNook(byKey ? 'key' : lastPointer === 'mouse' ? 'hover' : 'touch');
    } else if (byKey || lastPointer !== 'mouse') {
      closeNook(true);
    }
  });
  $('try-close').addEventListener('click', () => closeNook(true));
  island.addEventListener('focusout', (e) => {
    if (state !== 'open' || openedBy !== 'key' || island.contains(e.relatedTarget)) return;
    window.setTimeout(() => { if (state === 'open' && !island.contains(document.activeElement)) closeNook(false); }, 0);
  });
  // A tap outside closes it. A touch that turns into a scroll does not.
  let outside = null;
  document.addEventListener('pointerdown', (e) => {
    outside = state === 'open' && !island.contains(e.target) ? { x: e.clientX, y: e.clientY } : null;
  });
  document.addEventListener('pointerup', (e) => {
    if (outside && state === 'open' && Math.hypot(e.clientX - outside.x, e.clientY - outside.y) < 10) closeNook(false);
    outside = null;
  });
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (state === 'request') { answer(false); return; }
    if (state !== 'open') return;
    const a = document.activeElement;
    if (a && a.matches && a.matches('input[type="text"]') && a.value) { a.value = ''; return; }
    closeNook(island.contains(a));
  });
  // The scrubber's change event fires after pointerup. The flag drops a beat later.
  document.addEventListener('pointerup', () => {
    if (!seeking) return;
    window.setTimeout(() => { seeking = false; renderTime(true); settle(); }, 0);
  });
  island.addEventListener('focusout', () => { if (state === 'open') settle(); });

  // ---- music ----------------------------------------------------------------

  const seek = $('m-seek');
  const playBtn = $('m-play');
  const bars = Array.from($('ear-bars').children);
  let lastSecond = -1;

  function renderTrack() {
    const i = engine.index();
    const t = tracks[i];
    $('m-title').textContent = t.title;
    $('m-sub').textContent = t.artist + ' · ' + t.album;
    $('m-art').style.background = coverOf(t.hue);
    $('ear-art').style.background = coverOf(t.hue);
    seek.max = String(t.dur);
    $('m-tot').textContent = clock(t.dur);
    renderTime(true);
    labelNotch();
  }

  function renderTime(force) {
    const pos = engine.position();
    const sec = Math.floor(pos);
    if (!force && sec === lastSecond) return;
    lastSecond = sec;
    const dur = tracks[engine.index()].dur;
    if (!seeking) seek.value = String(sec);
    seek.style.setProperty('--p', ((seeking ? Number(seek.value) : sec) / dur * 100).toFixed(2) + '%');
    $('m-el').textContent = clock(seeking ? Number(seek.value) : sec);
    seek.setAttribute('aria-valuetext', clock(seeking ? Number(seek.value) : sec) + ' of ' + clock(dur));
  }

  function renderPlayState() {
    const on = engine.isPlaying();
    playBtn.innerHTML = fill(on ? 'pause' : 'play', 22);
    playBtn.setAttribute('aria-label', on ? 'Pause' : 'Play');
    setEars();
    stillBars();
    if (on) startFrames();
  }

  // The app's bars when Reduce Motion is on: playing bars at fixed, uneven heights.
  function stillBars() {
    const on = engine.isPlaying();
    const reduced = reducedQuery.matches;
    bars.forEach((b, i) => {
      if (!on) b.style.transform = 'scaleY(0.25)';
      else if (reduced) b.style.transform = 'scaleY(' + (0.35 + 0.65 * Math.abs(Math.sin(1.1 + i * 1.3))).toFixed(2) + ')';
    });
  }

  function play() {
    engine.play();
    renderPlayState();
    announce('Playing ' + tracks[engine.index()].title + ' by ' + tracks[engine.index()].artist);
  }

  function pause() {
    engine.pause();
    renderPlayState();
  }

  function go(step) {
    const next = (engine.index() + step + tracks.length) % tracks.length;
    engine.select(next, 0);
    renderTrack();
    if (engine.isPlaying()) announce('Playing ' + tracks[next].title + ' by ' + tracks[next].artist);
  }

  playBtn.addEventListener('click', () => (engine.isPlaying() ? pause() : play()));
  $('m-next').addEventListener('click', () => go(1));
  $('m-prev').addEventListener('click', () => {
    // Like a real player: a few seconds in, back starts the song again.
    if (engine.position() > 3) { engine.select(engine.index(), 0); renderTime(true); } else go(-1);
  });
  seek.addEventListener('pointerdown', () => { seeking = true; });
  seek.addEventListener('input', () => { seeking = true; renderTime(true); });
  seek.addEventListener('change', () => {
    engine.select(engine.index(), Number(seek.value));
    seeking = false;
    renderTime(true);
  });
  engine.onEnd = () => { go(1); };

  // Bars follow the AnalyserNode while a song plays and the page is on screen.
  let frameId = 0;
  let onScreen = true;
  const freq = new Uint8Array(64);
  // Bins to read and the quiet and loud ends of each, in the analyser's 0 to 255,
  // measured on the three loops, which gives every bar its whole range.
  const BANDS = [[0, 1, 110, 250], [2, 3, 60, 200], [4, 7, 20, 150], [8, 16, 0, 100]];
  function frame() {
    frameId = 0;
    if (!engine.isPlaying()) return;
    renderTime(false);
    const analyser = engine.analyser();
    if (analyser && onScreen && !reducedQuery.matches && state === 'closed') {
      analyser.getByteFrequencyData(freq);
      BANDS.forEach(([from, to, quiet, loud], i) => {
        let sum = 0;
        for (let k = from; k <= to; k++) sum += freq[k];
        const level = clamp((sum / (to - from + 1) - quiet) / (loud - quiet), 0, 1);
        bars[i].style.transform = 'scaleY(' + (0.22 + 0.78 * level).toFixed(3) + ')';
      });
    }
    frameId = requestAnimationFrame(frame);
  }
  function startFrames() { if (!frameId) frameId = requestAnimationFrame(frame); }
  new IntersectionObserver((entries) => { onScreen = entries[0].isIntersecting; }).observe(stage);

  // Nothing keeps playing in a hidden tab.
  document.addEventListener('visibilitychange', () => { if (document.hidden && engine.isPlaying()) pause(); });

  // ---- calendar ---------------------------------------------------------------

  const todayStart = dayStart(startedAt);
  let weekStart = addDays(todayStart, -todayStart.getDay());
  let selected = todayStart;
  let expanded = false;

  const offsetOf = (d) => Math.round((dayStart(d) - todayStart) / 864e5);
  const eventsOn = (d) => events.filter((e) => e.day === offsetOf(d)).sort((a, b) => a.at - b.at);

  function whenLabel(e) {
    const mins = Math.round((e.at.getTime() - Date.now()) / 60000);
    if (e.link && mins > 0 && mins <= 60) return fill('video', 12) + 'in ' + mins + ' min';
    return hour12(e.at);
  }

  function renderCalendar() {
    const mid = addDays(weekStart, 3);
    $('cal-month').textContent = mid.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
    $('cal-week').innerHTML = Array.from({ length: 7 }, (_, i) => {
      const d = addDays(weekStart, i);
      const cals = [...new Set(eventsOn(d).map((e) => e.cal))];
      const label = d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' }) + (sameDay(d, todayStart) ? ', today' : '') + (cals.length ? ', ' + eventsOn(d).length + ' events' : '');
      return '<button type="button" class="tday' + (sameDay(d, todayStart) ? ' is-today' : '') + '" aria-pressed="' + sameDay(d, selected) + '" aria-label="' + label + '" tabindex="' + (sameDay(d, selected) ? 0 : -1) + '" data-day="' + i + '">' +
        '<span class="wd">' + d.toLocaleDateString('en-US', { weekday: 'short' }) + '</span><span class="n">' + d.getDate() + '</span>' +
        '<span class="dots">' + cals.map((c) => '<i style="background:' + COLORS[c] + '"></i>').join('') + '</span></button>';
    }).join('');
    const list = eventsOn(selected);
    const shown = expanded ? list : list.slice(0, 1);
    let html = shown.map((e) => '<div class="ev"><span class="dot" style="background:' + COLORS[e.cal] + '"></span><span class="t">' + esc(e.title) + '</span><span class="when">' + whenLabel(e) + '</span></div>').join('');
    if (list.length === 0) html = '<div class="cal-none">Nothing planned</div>';
    if (list.length > 1) {
      html += '<button type="button" class="cal-more" id="cal-more" aria-expanded="' + expanded + '">' +
        (expanded ? 'Show less' + line('up', 10) : '+' + (list.length - 1) + ' more' + line('down', 10)) + '</button>';
    }
    $('cal-events').innerHTML = html;
  }

  $('cal-week').addEventListener('click', (e) => {
    const b = e.target.closest('.tday');
    if (!b) return;
    selected = addDays(weekStart, Number(b.dataset.day));
    expanded = false;
    renderCalendar();
    $('cal-week').querySelector('[aria-pressed="true"]').focus({ preventScroll: true });
  });
  // One tab stop for the week. The arrow keys move through its days.
  $('cal-week').addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    e.preventDefault();
    const at = Math.round((selected - weekStart) / 864e5) + (e.key === 'ArrowLeft' ? -1 : 1);
    selected = addDays(weekStart, clamp(at, 0, 6));
    expanded = false;
    renderCalendar();
    $('cal-week').querySelector('[aria-pressed="true"]').focus({ preventScroll: true });
  });
  $('cal-events').addEventListener('click', (e) => {
    if (!e.target.closest('#cal-more')) return;
    expanded = !expanded;
    renderCalendar();
    const more = $('cal-more');
    if (more) more.focus({ preventScroll: true });
  });
  const shiftWeek = (days) => {
    weekStart = addDays(weekStart, days);
    selected = addDays(selected, days);
    expanded = false;
    renderCalendar();
  };
  $('cal-prev').addEventListener('click', () => shiftWeek(-7));
  $('cal-next').addEventListener('click', () => shiftWeek(7));
  $('cal-today').addEventListener('click', () => {
    weekStart = addDays(todayStart, -todayStart.getDay());
    selected = todayStart;
    expanded = false;
    renderCalendar();
  });
  window.setInterval(() => { if (state === 'open') renderCalendar(); }, 30000);

  // ---- to-dos -----------------------------------------------------------------

  const tdList = $('td-list');
  const todoRow = (t, isNew) =>
    '<li' + (isNew ? ' class="is-new"' : '') + '><button type="button" class="trow" role="checkbox" aria-checked="' + t.done + '" data-id="' + t.id + '">' +
    '<span class="ring">' + line('check', 10) + '</span><span class="tt">' + esc(t.title) + '</span></button></li>';
  const renderTodoCount = () => { $('td-count').textContent = todos.filter((t) => !t.done).length + ' left'; };
  tdList.innerHTML = todos.map((t) => todoRow(t, false)).join('');
  renderTodoCount();

  tdList.addEventListener('click', (e) => {
    const b = e.target.closest('.trow');
    if (!b) return;
    const t = todos.find((x) => x.id === Number(b.dataset.id));
    t.done = !t.done;
    b.setAttribute('aria-checked', String(t.done));
    renderTodoCount();
    announce(t.title + (t.done ? ', done' : ', not done'));
  });
  $('td-input').addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const title = e.target.value.trim();
    if (!title) return;
    const t = { id: nextTodoId++, title, done: false };
    todos.unshift(t);
    tdList.insertAdjacentHTML('afterbegin', todoRow(t, true));
    tdList.scrollTop = 0;
    e.target.value = '';
    renderTodoCount();
    announce('Added ' + title);
  });

  // ---- notes ------------------------------------------------------------------

  const ntList = $('nt-list');
  const noteRow = (n, isNew) => '<li class="nrow' + (isNew ? ' is-new' : '') + '"><time>' + hour12(n.at) + '</time><span>' + esc(n.text) + '</span></li>';
  ntList.innerHTML = notes.slice().reverse().map((n) => noteRow(n, false)).join('');
  $('nt-input').addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const text = e.target.value.trim();
    if (!text) return;
    const n = { at: new Date(), text };
    notes.push(n);
    ntList.insertAdjacentHTML('afterbegin', noteRow(n, true));
    ntList.scrollTop = 0;
    e.target.value = '';
    announce('Saved note: ' + text);
  });

  // ---- focus timer ------------------------------------------------------------

  const SPEED = 60; // one real second counts as one minute
  const TICK = 250;
  const timer = { total: 25 * 60, left: 25 * 60, running: false, id: 0 };

  function renderTimer() {
    const shown = Math.max(0, Math.round(timer.left));
    const text = pad2(Math.floor(shown / 60)) + ':' + pad2(shown % 60);
    $('tm-time').textContent = text;
    $('ear-time').textContent = text;
    $('tm-bar').style.setProperty('--f', (timer.left / timer.total).toFixed(4));
    $('tm-go').textContent = timer.running ? 'Pause' : timer.left < timer.total && timer.left > 0 ? 'Resume' : 'Start';
    $('tm-chips').querySelectorAll('.tchip').forEach((c) => {
      c.setAttribute('aria-pressed', String(Number(c.dataset.min) * 60 === timer.total));
      c.disabled = timer.running;
    });
  }
  function stopTimer() {
    window.clearInterval(timer.id);
    timer.running = false;
  }
  function tickTimer() {
    timer.left = Math.max(0, timer.left - (SPEED * TICK) / 1000);
    if (timer.left <= 0) {
      stopTimer();
      announce('Timer done');
    }
    renderTimer();
    setEars();
  }
  $('tm-go').addEventListener('click', () => {
    if (timer.running) { stopTimer(); } else {
      if (timer.left <= 0) timer.left = timer.total;
      timer.running = true;
      timer.id = window.setInterval(tickTimer, TICK);
    }
    renderTimer();
    setEars();
  });
  $('tm-reset').addEventListener('click', () => {
    stopTimer();
    timer.left = timer.total;
    renderTimer();
    setEars();
  });
  $('tm-chips').addEventListener('click', (e) => {
    const c = e.target.closest('.tchip');
    if (!c || timer.running) return;
    timer.total = Number(c.dataset.min) * 60;
    timer.left = timer.total;
    renderTimer();
  });
  renderTimer();

  // ---- weather ----------------------------------------------------------------

  let wxView = 'today';
  const dayName = (i) => (i === 0 ? 'Today' : addDays(todayStart, i).toLocaleDateString('en-US', { weekday: 'short' }));
  const curve = (h) => 19.5 + 5.5 * Math.sin(((h - 9) / 24) * 2 * Math.PI);

  function renderWeather() {
    $('wx-place').textContent = WX.place;
    $('wx-today').setAttribute('aria-pressed', String(wxView === 'today'));
    $('wx-week').setAttribute('aria-pressed', String(wxView === 'week'));
    const h0 = startedAt.getHours();
    if (wxView === 'today') {
      const hours = [0, 1, 2, 3].map((k) => {
        const h = (h0 + k) % 24;
        const temp = Math.round(WX.now + 1.8 * (curve(h) - curve(h0)));
        const label = k === 0 ? 'Now' : new Date(2000, 0, 1, h).toLocaleTimeString('en-US', { hour: 'numeric' });
        return '<span>' + label + sky(k === 2 ? 'part' : 'sun', 18) + '<b>' + temp + '°</b></span>';
      }).join('');
      $('wx-body').innerHTML =
        '<div class="wx-now">' + sky('sun', 34) + '<span class="big">' + WX.now + '°</span><span class="what"><b>' + WX.text[1] + '</b>Feels like ' + WX.feels + '°<br>H ' + WX.hi[0] + '° · L ' + WX.lo[0] + '°</span></div>' +
        '<div class="wx-hours">' + hours + '</div>';
    } else {
      $('wx-body').innerHTML = '<div class="wx-days">' + WX.code.map((c, i) =>
        '<div class="wx-day"><span class="d">' + dayName(i) + '</span>' + sky(WX.kind[c], 16) +
        '<span class="lo">' + WX.lo[i] + '°</span><span class="hi">' + WX.hi[i] + '°</span>' +
        '<span class="pc">' + (WX.rain[i] >= 20 ? WX.rain[i] + '%' : '') + '</span></div>').join('') + '</div>';
    }
  }
  const setWx = (view) => { wxView = view; renderWeather(); };
  $('wx-today').addEventListener('click', (e) => { e.stopPropagation(); setWx('today'); });
  $('wx-week').addEventListener('click', (e) => { e.stopPropagation(); setWx('week'); });
  $('wx').addEventListener('click', () => setWx(wxView === 'today' ? 'week' : 'today'));
  renderWeather();

  // ---- the agent request --------------------------------------------------------

  let requestTimer = 0;
  function sendRequest() {
    if (state === 'request') return;
    window.clearTimeout(openTimer);
    window.clearTimeout(closeTimer);
    req.dataset.step = 'ask';
    setState('request');
    $('req-allow').focus({ preventScroll: true });
    announce('Claude Code wants to run bun test. Allow or deny.');
  }
  function answer(allowed) {
    if (state !== 'request' || req.dataset.step !== 'ask') return;
    req.dataset.step = 'done';
    const ok = $('req-ok');
    ok.className = allowed ? 'ok' : 'ok no';
    ok.innerHTML = line(allowed ? 'check' : 'close', 11);
    $('req-text').textContent = allowed ? 'Claude Code ran bun test. 24 tests passed.' : 'Denied. Claude Code did not run bun test.';
    announce($('req-text').textContent);
    size();
    window.clearTimeout(requestTimer);
    requestTimer = window.setTimeout(() => {
      if (state !== 'request') return;
      setState('closed');
      agentBtn.focus({ preventScroll: true });
    }, 3200);
  }
  agentBtn.addEventListener('click', sendRequest);
  $('req-allow').addEventListener('click', () => answer(true));
  $('req-deny').addEventListener('click', () => answer(false));

  // ---- accent -----------------------------------------------------------------

  const group = $('try-swatches');
  const radios = Array.from(group.querySelectorAll('button'));
  function pickAccent(button) {
    radios.forEach((b) => { b.setAttribute('aria-checked', String(b === button)); b.tabIndex = b === button ? 0 : -1; });
    screen.style.setProperty('--accent', button.dataset.hex);
  }
  group.addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) pickAccent(b); });
  group.addEventListener('keydown', (e) => {
    const k = e.key;
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(k)) return;
    e.preventDefault();
    const i = radios.indexOf(document.activeElement);
    const next = radios[(i + (k === 'ArrowLeft' || k === 'ArrowUp' ? -1 : 1) + radios.length) % radios.length];
    next.focus();
    pickAccent(next);
  });

  // ---- start --------------------------------------------------------------------

  renderTrack();
  renderCalendar();
  renderPlayState();
  setState('closed');
  reducedQuery.addEventListener('change', stillBars);
})();
