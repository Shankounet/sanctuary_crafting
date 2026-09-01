(() => {
  const resName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const IMG_BASE = 'nui://ox_inventory/web/images/';
  const LS_PIN = 'sc_tracker_pin';
  const LS_MODE = 'sc_tracker_mode';
  const LS_POS = 'sc_tracker_pos';
  const MODES = ['normal', 'compact', 'minimal'];

  const root = document.getElementById('craft-tracker');
  if (!root) return;

  const els = {
    list: root.querySelector('#ct-list'),
    count: root.querySelector('#ct-count'),
    pin: root.querySelector('#ct-pin'),
    mode: root.querySelector('#ct-mode'),
    reset: root.querySelector('#ct-reset'),
    header: root.querySelector('#ct-header'),
    minimal: root.querySelector('#ct-minimal'),
    minimalCount: root.querySelector('#ct-minimal-count'),
  };

  let config = {
    enabled: true,
    defaultPosition: { top: 24, right: 24 },
    defaultMode: 'normal',
    autoShowOnStart: true,
    hideWithMenuIfUnpinned: true,
    persistPin: true,
    persistMode: true,
    persistPosition: true,
    allowDrag: true,
    completedLingerMs: 4500,
    autoRemoveCompleted: true,
    tickMs: 250,
    phases: {
      medical: ['Préparation', 'Assemblage', 'Stérilisation', 'Finalisation'],
      mechanical: ['Découpe', 'Assemblage', 'Calibrage', 'Finition'],
      cooking: ['Préparation', 'Cuisson', 'Conditionnement'],
      default: ['Préparation', 'Assemblage', 'Finition'],
    },
    sounds: { Enabled: true, OnStart: true, OnComplete: true, OnError: true },
    uiSounds: { Enabled: true, Volume: 0.35, Files: {} },
  };

  const jobs = new Map(); // craftId -> entry (+ local timing)
  let menuOpen = false;
  let pinned = false;
  let mode = 'normal';
  let tickTimer = null;
  let audioCtx = null;
  let completing = new Set();
  let drag = null;

  function post(name, data) {
    return fetch(`https://${resName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({ ok: false }));
  }

  function lsGet(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      return v == null ? fallback : v;
    } catch (_) {
      return fallback;
    }
  }

  function lsSet(key, value) {
    try { localStorage.setItem(key, value); } catch (_) { /* ignore */ }
  }

  function mergeConfig(cfg) {
    if (!cfg || typeof cfg !== 'object') return;
    config = { ...config, ...cfg };
    if (cfg.phases) config.phases = { ...config.phases, ...cfg.phases };
    if (cfg.sounds) config.sounds = { ...config.sounds, ...cfg.sounds };
    if (cfg.uiSounds) config.uiSounds = { ...config.uiSounds, ...cfg.uiSounds };
  }

  function itemImageUrl(item) {
    if (!item) return '';
    return `${IMG_BASE}${encodeURIComponent(String(item))}.png`;
  }

  function bindItemImg(img, item, fallbackEl) {
    if (!img) return;
    const url = itemImageUrl(item);
    img.classList.remove('is-fallback');
    if (fallbackEl) fallbackEl.style.display = '';
    if (!url) {
      img.classList.add('is-fallback');
      img.removeAttribute('src');
      return;
    }
    img.onload = () => {
      if (fallbackEl) fallbackEl.style.display = 'none';
      img.classList.remove('is-fallback');
    };
    img.onerror = () => {
      img.classList.add('is-fallback');
      if (fallbackEl) fallbackEl.style.display = '';
    };
    img.src = url;
    img.alt = item || '';
  }

  function ensureAudio() {
    if (audioCtx) return audioCtx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    audioCtx = new AC();
    return audioCtx;
  }

  function beep(kind) {
    const snd = config.sounds || {};
    const ui = config.uiSounds || {};
    if (snd.Enabled === false || ui.Enabled === false) return;
    if (kind === 'start' && snd.OnStart === false) return;
    if (kind === 'complete' && snd.OnComplete === false) return;
    if (kind === 'error' && snd.OnError === false) return;

    const files = ui.Files || {};
    const map = { start: 'click', complete: 'success', error: 'error', click: 'click' };
    const fileKey = map[kind] || 'click';
    const path = files[fileKey];
    if (path) {
      try {
        const a = new Audio(path);
        a.volume = typeof ui.Volume === 'number' ? ui.Volume : 0.35;
        a.play().catch(() => { /* ignore */ });
        return;
      } catch (_) { /* fall through */ }
    }
    try {
      const ctx = ensureAudio();
      if (!ctx) return;
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = 'square';
      const freq = kind === 'error' ? 180 : (kind === 'complete' ? 520 : 340);
      o.frequency.value = freq;
      g.gain.value = 0.03;
      o.connect(g); g.connect(ctx.destination);
      o.start();
      o.stop(ctx.currentTime + 0.07);
    } catch (_) { /* ignore */ }
  }

  function applyMode(next) {
    mode = MODES.includes(next) ? next : 'normal';
    root.classList.remove('mode-normal', 'mode-compact', 'mode-minimal');
    root.classList.add(`mode-${mode}`);
    if (config.persistMode !== false) lsSet(LS_MODE, mode);
    post('trackerMode', { mode });
  }

  function applyPin(next) {
    pinned = !!next;
    if (els.pin) els.pin.classList.toggle('is-on', pinned);
    if (els.pin) els.pin.setAttribute('aria-pressed', pinned ? 'true' : 'false');
    if (config.persistPin !== false) lsSet(LS_PIN, pinned ? '1' : '0');
    post('trackerPin', { pinned });
    updateVisibility();
  }

  function applyPosition(pos) {
    if (!pos) return;
    if (pos.top != null) {
      root.style.top = `${pos.top}px`;
      root.style.bottom = 'auto';
    }
    if (pos.right != null) {
      root.style.right = `${pos.right}px`;
      root.style.left = 'auto';
    }
    if (pos.left != null) {
      root.style.left = `${pos.left}px`;
      root.style.right = 'auto';
    }
    if (pos.bottom != null) {
      root.style.bottom = `${pos.bottom}px`;
      root.style.top = 'auto';
    }
  }

  function savePositionFromStyle() {
    const top = parseInt(root.style.top || config.defaultPosition.top || 24, 10);
    const right = parseInt(root.style.right || config.defaultPosition.right || 24, 10);
    const payload = { top, right };
    if (config.persistPosition !== false) lsSet(LS_POS, JSON.stringify(payload));
    post('trackerPosition', payload);
  }

  function activeJobCount() {
    let n = 0;
    jobs.forEach((j) => {
      if (j.status === 'active' || j.status === 'queued' || j.status === 'paused' || j.status === 'done') n += 1;
    });
    return n;
  }

  function updateVisibility() {
    const hasJobs = jobs.size > 0;
    const hideUnpinned = config.hideWithMenuIfUnpinned !== false;
    let visible = config.enabled !== false && hasJobs;

    if (visible && !menuOpen && !pinned && hideUnpinned) {
      // Hide panel but keep jobs / tick running for complete callbacks
      root.classList.add('hidden-panel');
      root.classList.add('is-visible');
      return;
    }

    root.classList.remove('hidden-panel');
    if (!visible && menuOpen && config.autoShowOnStart && pinned) visible = true;
    if (visible) root.classList.add('is-visible');
    else root.classList.remove('is-visible');
  }

  function phaseLabel(entry, progress) {
    if (entry.stepLabel && (entry.totalSteps > 1 || entry.status === 'queued' || entry.status === 'done' || entry.status === 'error')) {
      return entry.stepLabel;
    }
    if (entry.status === 'done') return 'FABRICATION TERMINÉE';
    if (entry.status === 'error') return 'Erreur';
    if (entry.status === 'queued') return entry.stepLabel || 'En file';
    const family = entry.phaseFamily || 'default';
    const phases = (config.phases && (config.phases[family] || config.phases.default)) || ['Préparation', 'Assemblage', 'Finition'];
    const p = Math.max(0, Math.min(0.999, progress || 0));
    const idx = Math.min(phases.length - 1, Math.floor(p * phases.length));
    return phases[idx] || entry.stepLabel || 'Fabrication';
  }

  function formatRemain(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${String(r).padStart(2, '0')}`;
  }

  function computeProgress(entry) {
    if (entry.status === 'done') return { pct: 1, remain: 0 };
    if (entry.status === 'error' || entry.status === 'cancelled') return { pct: 1, remain: 0 };

    const duration = Math.max(1, Number(entry.duration) || 1);
    let remain;
    let elapsed;

    if (entry.useWallClock && entry.endsAt) {
      remain = entry.endsAt - Date.now();
      elapsed = duration - remain;
    } else if (entry._localEndsAt) {
      remain = entry._localEndsAt - Date.now();
      elapsed = duration - remain;
    } else {
      elapsed = Date.now() - (entry._localStart || Date.now());
      remain = duration - elapsed;
    }

    const pct = Math.max(0, Math.min(1, elapsed / duration));
    return { pct, remain: Math.max(0, remain) };
  }

  function anchorTiming(entry) {
    const duration = Math.max(0, Number(entry.duration) || 0);
    if (entry.useWallClock && entry.endsAt) {
      entry._localEndsAt = entry.endsAt;
      entry._localStart = entry.endsAt - duration;
      return;
    }
    // Sync from client GetGameTimer via clientTimer snapshot
    if (entry.clientTimer != null && entry.endsAt != null && entry.startedAt != null) {
      const elapsedGame = Math.max(0, entry.clientTimer - entry.startedAt);
      entry._localStart = Date.now() - elapsedGame;
      entry._localEndsAt = entry._localStart + duration;
      return;
    }
    entry._localStart = Date.now();
    entry._localEndsAt = Date.now() + duration;
  }

  function upsertJob(raw) {
    if (!raw || !raw.craftId) return;
    const prev = jobs.get(raw.craftId) || {};
    const entry = { ...prev, ...raw };
    const timingChanged =
      raw.startedAt !== prev.startedAt
      || raw.endsAt !== prev.endsAt
      || raw.duration !== prev.duration
      || raw.status !== prev.status
      || raw.stepIndex !== prev.stepIndex;

    if (timingChanged || !prev._localEndsAt) {
      anchorTiming(entry);
    }

    const isNew = !jobs.has(raw.craftId);
    jobs.set(raw.craftId, entry);
    render();
    updateVisibility();
    ensureTick();

    if (isNew && (entry.status === 'active' || entry.status === 'queued')) {
      beep('start');
    }
    if (entry.status === 'done' && prev.status !== 'done') {
      beep('complete');
      scheduleAutoRemove(entry.craftId);
    }
    if (entry.status === 'error' && prev.status !== 'error') {
      beep('error');
      scheduleAutoRemove(entry.craftId);
    }
  }

  function scheduleAutoRemove(id) {
    if (config.autoRemoveCompleted === false) return;
    const wait = config.completedLingerMs || 4500;
    setTimeout(() => {
      const j = jobs.get(id);
      if (j && (j.status === 'done' || j.status === 'error' || j.status === 'cancelled')) {
        jobs.delete(id);
        render();
        updateVisibility();
        post('trackerDismiss', { craftId: id });
      }
    }, wait);
  }

  function removeJob(id) {
    if (!id) return;
    jobs.delete(id);
    completing.delete(id);
    render();
    updateVisibility();
  }

  function renderJob(entry) {
    const { pct, remain } = computeProgress(entry);
    const phase = phaseLabel(entry, pct);
    const pctTxt = `${Math.round(pct * 100)}%`;
    const statusClass = `is-${entry.status || 'active'}`;
    const el = document.createElement('article');
    el.className = `ct-job ${statusClass}`;
    el.dataset.craftId = entry.craftId;
    el.innerHTML = `
      <div class="ct-thumb">
        <img alt="" />
        <span class="ct-thumb-fallback" aria-hidden="true"><i class="fa-solid fa-hammer"></i></span>
      </div>
      <div class="ct-body">
        <div class="ct-row1">
          <div class="ct-label"></div>
          <div class="ct-batch"></div>
        </div>
        <div class="ct-phase"></div>
        <div class="ct-bar"><div class="ct-fill"></div></div>
        <div class="ct-meta">
          <span class="ct-time"></span>
          <span class="ct-pct"></span>
        </div>
      </div>
      <button type="button" class="ct-dismiss" title="Retirer" aria-label="Retirer">
        <i class="fa-solid fa-xmark"></i>
      </button>
    `;
    el.querySelector('.ct-label').textContent = entry.label || entry.recipeId || 'Production';
    el.querySelector('.ct-batch').textContent = `×${entry.count || entry.batch || 1}`;
    el.querySelector('.ct-phase').textContent = phase;
    el.querySelector('.ct-fill').style.width = `${Math.round(pct * 100)}%`;
    el.querySelector('.ct-time').textContent =
      entry.status === 'done' ? 'Terminé'
        : entry.status === 'error' ? 'Échec'
          : entry.status === 'queued' ? `File · ${formatRemain(remain)}`
            : formatRemain(remain);
    el.querySelector('.ct-pct').textContent = pctTxt;
    bindItemImg(el.querySelector('img'), entry.item || entry.recipeId, el.querySelector('.ct-thumb-fallback'));

    el.addEventListener('click', (ev) => {
      if (ev.target.closest('.ct-dismiss')) return;
      post('trackerClick', { craftId: entry.craftId, benchKey: entry.benchKey });
    });
    el.querySelector('.ct-dismiss').addEventListener('click', (ev) => {
      ev.stopPropagation();
      jobs.delete(entry.craftId);
      render();
      updateVisibility();
      post('trackerDismiss', { craftId: entry.craftId });
    });
    return el;
  }

  function render() {
    if (!els.list) return;
    els.list.innerHTML = '';
    const arr = Array.from(jobs.values()).sort((a, b) => (a.startedAt || 0) - (b.startedAt || 0));
    if (els.count) els.count.textContent = String(arr.filter((j) => j.status !== 'done' && j.status !== 'error').length || arr.length);
    if (els.minimalCount) els.minimalCount.textContent = String(activeJobCount());

    if (!arr.length) {
      const empty = document.createElement('div');
      empty.className = 'ct-empty';
      empty.textContent = 'Aucune production';
      els.list.appendChild(empty);
      return;
    }
    arr.forEach((j) => els.list.appendChild(renderJob(j)));
  }

  function tickVisual() {
    jobs.forEach((entry) => {
      if (entry.status !== 'active' && entry.status !== 'queued' && entry.status !== 'paused') return;
      const { pct, remain } = computeProgress(entry);
      const node = els.list && Array.from(els.list.querySelectorAll('.ct-job')).find((n) => n.dataset.craftId === entry.craftId);
      if (node) {
        const fill = node.querySelector('.ct-fill');
        const time = node.querySelector('.ct-time');
        const pctEl = node.querySelector('.ct-pct');
        const phase = node.querySelector('.ct-phase');
        if (fill) fill.style.width = `${Math.round(pct * 100)}%`;
        if (pctEl) pctEl.textContent = `${Math.round(pct * 100)}%`;
        if (time) {
          time.textContent = entry.status === 'queued'
            ? `File · ${formatRemain(remain)}`
            : formatRemain(remain);
        }
        if (phase) phase.textContent = phaseLabel(entry, pct);
      }
      if (remain <= 0 && !completing.has(entry.craftId)) {
        completing.add(entry.craftId);
        post('trackerComplete', { craftId: entry.craftId }).then((r) => {
          // Client upserts done/advanced/error; if no follow-up, mark done locally
          const cur = jobs.get(entry.craftId);
          if (!cur) return;
          if (r && r.ok && r.advanced) {
            completing.delete(entry.craftId);
            return;
          }
          if (r && r.ok) {
            // wait for client upsert; fallback:
            setTimeout(() => {
              const still = jobs.get(entry.craftId);
              if (still && still.status === 'active') {
                still.status = 'done';
                still.stepLabel = 'FABRICATION TERMINÉE';
                jobs.set(entry.craftId, still);
                render();
                scheduleAutoRemove(entry.craftId);
              }
              completing.delete(entry.craftId);
            }, 400);
            return;
          }
          if (r && r.reason === 'queue_not_ready') {
            completing.delete(entry.craftId);
            return;
          }
          // soft already-done
          if (r && r.already) {
            cur.status = 'done';
            cur.stepLabel = 'FABRICATION TERMINÉE';
            jobs.set(entry.craftId, cur);
            render();
            scheduleAutoRemove(entry.craftId);
            completing.delete(entry.craftId);
            return;
          }
          cur.status = 'error';
          cur.stepLabel = 'Erreur';
          jobs.set(entry.craftId, cur);
          render();
          scheduleAutoRemove(entry.craftId);
          completing.delete(entry.craftId);
        });
      }
    });
  }

  function ensureTick() {
    if (tickTimer) return;
    const ms = Math.max(100, Number(config.tickMs) || 250);
    tickTimer = setInterval(() => {
      if (jobs.size === 0) {
        clearInterval(tickTimer);
        tickTimer = null;
        return;
      }
      tickVisual();
    }, ms);
  }

  function syncAll(payload) {
    if (payload && payload.config) mergeConfig(payload.config);
    if (typeof payload.menuOpen === 'boolean') menuOpen = payload.menuOpen;
    if (Array.isArray(payload.jobs)) {
      const seen = new Set();
      payload.jobs.forEach((j) => {
        if (!j || !j.craftId) return;
        seen.add(j.craftId);
        upsertJob(j);
      });
      Array.from(jobs.keys()).forEach((id) => {
        if (!seen.has(id)) jobs.delete(id);
      });
      render();
      updateVisibility();
      ensureTick();
    } else {
      updateVisibility();
    }
  }

  // Drag
  function onPointerDown(ev) {
    if (config.allowDrag === false) return;
    if (ev.target.closest('button')) return;
    const rect = root.getBoundingClientRect();
    drag = {
      ox: ev.clientX - rect.left,
      oy: ev.clientY - rect.top,
      w: rect.width,
      h: rect.height,
    };
    ev.preventDefault();
  }

  function onPointerMove(ev) {
    if (!drag) return;
    const left = Math.max(8, Math.min(window.innerWidth - drag.w - 8, ev.clientX - drag.ox));
    const top = Math.max(8, Math.min(window.innerHeight - drag.h - 8, ev.clientY - drag.oy));
    root.style.left = `${left}px`;
    root.style.top = `${top}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
  }

  function onPointerUp() {
    if (!drag) return;
    drag = null;
    const rect = root.getBoundingClientRect();
    const top = Math.round(rect.top);
    const right = Math.round(window.innerWidth - rect.right);
    root.style.top = `${top}px`;
    root.style.right = `${right}px`;
    root.style.left = 'auto';
    const payload = { top, right };
    if (config.persistPosition !== false) lsSet(LS_POS, JSON.stringify(payload));
    post('trackerPosition', payload);
  }

  if (els.header) {
    els.header.addEventListener('mousedown', onPointerDown);
  }
  window.addEventListener('mousemove', onPointerMove);
  window.addEventListener('mouseup', onPointerUp);

  if (els.pin) {
    els.pin.addEventListener('click', () => applyPin(!pinned));
  }
  if (els.mode) {
    els.mode.addEventListener('click', () => {
      const idx = MODES.indexOf(mode);
      applyMode(MODES[(idx + 1) % MODES.length]);
    });
  }
  if (els.reset) {
    els.reset.addEventListener('click', () => {
      const pos = config.defaultPosition || { top: 24, right: 24 };
      root.style.top = `${pos.top}px`;
      root.style.right = `${pos.right}px`;
      root.style.left = 'auto';
      root.style.bottom = 'auto';
      try { localStorage.removeItem(LS_POS); } catch (_) { /* ignore */ }
      post('trackerResetPosition', {});
    });
  }

  // Restore prefs
  pinned = lsGet(LS_PIN, '0') === '1';
  if (els.pin) {
    els.pin.classList.toggle('is-on', pinned);
    els.pin.setAttribute('aria-pressed', pinned ? 'true' : 'false');
  }
  applyMode(lsGet(LS_MODE, config.defaultMode || 'normal'));
  try {
    const rawPos = lsGet(LS_POS, '');
    if (rawPos) applyPosition(JSON.parse(rawPos));
    else applyPosition(config.defaultPosition);
  } catch (_) {
    applyPosition(config.defaultPosition);
  }

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    const action = msg.action;
    if (!action || typeof action !== 'string') return;

    if (action === 'tracker:sync') {
      syncAll(msg);
      return;
    }
    if (action === 'tracker:upsert') {
      if (msg.config) mergeConfig(msg.config);
      if (typeof msg.menuOpen === 'boolean') menuOpen = msg.menuOpen;
      upsertJob(msg.entry);
      return;
    }
    if (action === 'tracker:remove') {
      removeJob(msg.craftId);
      return;
    }
    if (action === 'tracker:setVisible') {
      if (msg.resetPosition) applyPosition(msg.resetPosition);
      if (typeof msg.visible === 'boolean') {
        root.classList.toggle('is-visible', msg.visible);
        if (msg.visible) root.classList.remove('hidden-panel');
      } else {
        updateVisibility();
      }
      return;
    }
    if (action === 'tracker:menuState') {
      if (msg.config) mergeConfig(msg.config);
      menuOpen = !!msg.menuOpen;
      if (Array.isArray(msg.jobs)) {
        msg.jobs.forEach((j) => upsertJob(j));
      }
      updateVisibility();
      return;
    }
  });

  // Expose tiny debug hook
  window.__craftTracker = {
    jobs,
    render,
    updateVisibility,
  };
})();
