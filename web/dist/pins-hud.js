(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const root = document.getElementById('book-pins-hud');
  if (!root) return;
  const COLLAPSE_KEY = 'sanctuary_crafting:pinsHudCollapsed';
  const PINNED_KEY = 'sanctuary_crafting:pinsHudPinned';
  const LS_POS_XY = 'pinnedTrackerPosition'; /* {x, y} viewport left/top — independent of craftTrackerPosition */
  const HUD = () => window.SanctuaryHud;
  const DRAG_THRESHOLD = 6;
  const DEFAULT_POS = { top: 22, right: 22 };
  const EDGE = 8;
  const MIN_VISIBLE = 40;
  const els = {
    list: document.getElementById('ph-list'),
    count: document.getElementById('ph-count'),
    collapse: document.getElementById('ph-collapse'),
    pin: document.getElementById('ph-pin'),
    hide: document.getElementById('ph-hide'),
    summary: document.getElementById('ph-summary'),
    title: root.querySelector('.ph-title'),
    shell: root.querySelector('.ph-shell'),
    header: document.getElementById('ph-header') || root.querySelector('.ph-header'),
  };

  function post(name, data) {
    return fetch(`https://${res}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
  }

  function loadFlag(key, fallback) {
    try {
      const v = localStorage.getItem(key);
      if (v === '1') return true;
      if (v === '0') return false;
    } catch (_) { /* ignore */ }
    return fallback;
  }
  function saveFlag(key, on) {
    try { localStorage.setItem(key, on ? '1' : '0'); } catch (_) { /* ignore */ }
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
  function lsDel(key) {
    try { localStorage.removeItem(key); } catch (_) { /* ignore */ }
  }

  let collapsed = loadFlag(COLLAPSE_KEY, false);
  let pinned = loadFlag(PINNED_KEY, true);
  /* NUI-owned visibility. Unknown → true. Close/hide never unpins / never empties SQL. */
  let pinsVisible = HUD() ? HUD().readPinsVisible() : true;
  let bookOpen = false;
  let lastPins = [];
  let lastCrafts = [];
  let lastMax = 4;
  let lastFeature = true;
  let drag = null;
  let dragMoved = false;

  function pinToneCounts(pins) {
    let ok = 0, almost = 0, blocked = 0;
    (pins || []).forEach((pin) => {
      if (pin.tone === 'ok') ok += 1;
      else if (pin.tone === 'almost') almost += 1;
      else blocked += 1;
    });
    return { ok, almost, blocked };
  }

  function paintSummary() {
    if (!els.summary) return;
    const t = pinToneCounts(lastPins);
    const missing = t.almost + t.blocked;
    const bits = [];
    if (missing) bits.push(missing + (missing > 1 ? ' manquantes' : ' manquante'));
    if (t.ok) bits.push(t.ok + (t.ok > 1 ? ' faisables' : ' faisable'));
    els.summary.textContent = bits.join(' · ');
    els.summary.hidden = !collapsed;
  }

  function applyChrome() {
    root.classList.toggle('is-collapsed', collapsed);
    if (els.title) {
      els.title.textContent = 'CARNET — ÉPINGLES';
    }
    if (els.collapse) {
      els.collapse.setAttribute('aria-pressed', collapsed ? 'true' : 'false');
      els.collapse.title = collapsed ? 'Agrandir' : 'Réduire';
      els.collapse.setAttribute('aria-label', collapsed ? 'Agrandir' : 'Réduire');
      const ico = els.collapse.querySelector('i');
      if (ico) {
        ico.className = collapsed
          ? 'fa-solid fa-expand'
          : 'fa-solid fa-minus';
      }
    }
    if (els.pin) {
      els.pin.classList.toggle('is-on', pinned);
      els.pin.setAttribute('aria-pressed', pinned ? 'true' : 'false');
      els.pin.title = pinned ? 'Widget épinglé' : 'Non épinglé';
      els.pin.setAttribute('aria-label', 'Épingler le widget');
    }
    if (els.hide) {
      els.hide.title = 'Masquer';
      els.hide.setAttribute('aria-label', 'Masquer');
    }
    paintSummary();
  }

  function shouldShow() {
    if (!pinsVisible) return false;
    if (bookOpen) return false;
    if (!lastFeature) return false;
    if (!lastPins.length) return false;
    return true;
  }

  function applyVisibility() {
    const shown = shouldShow();
    root.classList.toggle('is-visible', shown);
    root.classList.toggle('is-hidden', !shown);
    root.setAttribute('aria-hidden', shown ? 'false' : 'true');
  }

  function setPinsVisible(on, opts) {
    pinsVisible = !!on;
    const hud = HUD();
    if (hud && typeof hud.writePinsVisible === 'function') {
      hud.writePinsVisible(pinsVisible, { silent: true, silentPost: true, source: 'pins' });
      hud.refreshPanel && hud.refreshPanel();
    }
    /* Hide: NUI-owned pinsVisible only. Never persist miniHud=false as the only path. */
    if (pinsVisible && !(opts && opts.skipPost)) {
      post('hudSettingsPins', { visible: true });
      post('bookToggleHud', { enabled: true });
    }
    applyVisibility();
  }

  function craftFor(recipeId, crafts) {
    if (!recipeId || !Array.isArray(crafts)) return null;
    return crafts.find((c) => c && c.recipeId === recipeId) || null;
  }

  function progressOf(c) {
    if (!c) return 0;
    const dur = Number(c.duration || c.durationMs) || 0;
    if (dur <= 0) return 0;
    const started = Number(c.startedAt) || 0;
    const now = Date.now();
    if (typeof c.pct === 'number') return Math.max(0, Math.min(1, c.pct));
    if (c.endsAt && started) {
      const t = Number(c.endsAt) - started;
      if (t > 0) return Math.max(0, Math.min(1, (now - started) / t));
    }
    return 0;
  }

  function renderRow(p, craft) {
    const tone = craft ? 'craft' : (p.tone || 'blocked');
    const status = craft ? 'En cours' : (p.status || '');
    const row = document.createElement('div');
    row.className = `ph-row is-${tone}`;
    row.innerHTML = `
      <span class="ph-dot" aria-hidden="true"></span>
      <span class="ph-name"></span>
      <span class="ph-status"></span>
    `;
    row.querySelector('.ph-name').textContent = p.label || (p.kind === 'resource' ? 'Ressource' : 'Recette');
    row.querySelector('.ph-status').textContent = status;
    if (craft) {
      const bar = document.createElement('div');
      bar.className = 'ph-bar';
      bar.innerHTML = '<i></i>';
      const pct = progressOf(craft);
      bar.querySelector('i').style.width = `${Math.round(pct * 100)}%`;
      row.appendChild(bar);
    }
    return row;
  }

  function paintList() {
    const pins = lastPins;
    const crafts = lastCrafts;
    const max = lastMax;
    if (els.count) els.count.textContent = String(pins.length);
    paintSummary();
    if (!els.list) return;
    els.list.innerHTML = '';
    if (!pins.length) return;

    const craftingIds = new Set(crafts.map((c) => c && c.recipeId).filter(Boolean));
    const inProgress = pins.filter((p) => craftingIds.has(p.recipeId));
    const followed = pins.filter((p) => !craftingIds.has(p.recipeId));
    const shown = [];
    inProgress.forEach((p) => { if (shown.length < max) shown.push({ p, craft: craftFor(p.recipeId, crafts) }); });
    followed.forEach((p) => { if (shown.length < max) shown.push({ p, craft: null }); });
    const hiddenN = Math.max(0, pins.length - shown.length);

    const hasCraft = shown.some((x) => x.craft);
    if (hasCraft) {
      const g = document.createElement('div');
      g.className = 'ph-group';
      g.textContent = 'En cours';
      els.list.appendChild(g);
    }
    let followedHeader = false;
    shown.forEach((x) => {
      if (!x.craft && !followedHeader && hasCraft) {
        const g = document.createElement('div');
        g.className = 'ph-group';
        g.textContent = 'Suivis';
        els.list.appendChild(g);
        followedHeader = true;
      }
      els.list.appendChild(renderRow(x.p, x.craft));
    });
    if (hiddenN > 0) {
      const more = document.createElement('div');
      more.className = 'ph-more';
      more.textContent = hiddenN === 1 ? '+1 autre' : ('+' + hiddenN + ' autres');
      els.list.appendChild(more);
    }
    paintSummary();
  }

  function render(payload) {
    if (payload) {
      /* Always keep real pins — Lua no longer sends [] just because HUD hidden. */
      if (Array.isArray(payload.pins)) lastPins = payload.pins;
      if (Array.isArray(payload.crafts)) lastCrafts = payload.crafts;
      if (payload.max != null) lastMax = Math.max(1, Number(payload.max) || 4);
      if (typeof payload.bookOpen === 'boolean') bookOpen = payload.bookOpen;
      if (typeof payload.feature === 'boolean') lastFeature = payload.feature;
    }
    paintList();
    applyVisibility();
  }

  function isFiniteNum(n) {
    return typeof n === 'number' && Number.isFinite(n);
  }

  function widgetSize() {
    const rect = root.getBoundingClientRect();
    const w = rect.width > 1 ? rect.width : 248;
    const headerH = els.header ? els.header.getBoundingClientRect().height : 0;
    const h = rect.height > 1 ? rect.height : (headerH > 1 ? headerH : 48);
    return { w, h };
  }

  function onScreen(x, y, w, h) {
    if (!isFiniteNum(x) || !isFiniteNum(y) || !isFiniteNum(w) || !isFiniteNum(h)) return false;
    const vw = window.innerWidth || 0;
    const vh = window.innerHeight || 0;
    if (vw < 2 || vh < 2) return true;
    if (x + w < MIN_VISIBLE || y + h < MIN_VISIBLE) return false;
    if (x > vw - MIN_VISIBLE || y > vh - MIN_VISIBLE) return false;
    return true;
  }

  function clampXY(x, y) {
    const { w, h } = widgetSize();
    const headerH = (els.header && els.header.getBoundingClientRect().height > 1)
      ? els.header.getBoundingClientRect().height
      : Math.min(h, 48);
    const vw = window.innerWidth || 800;
    const vh = window.innerHeight || 600;
    const maxX = Math.max(EDGE, vw - w - EDGE);
    /* Keep the header on-screen even if the list hangs off the bottom. */
    const maxY = Math.max(EDGE, vh - headerH - EDGE);
    return {
      x: Math.round(Math.max(EDGE, Math.min(maxX, x))),
      y: Math.round(Math.max(EDGE, Math.min(maxY, y))),
    };
  }

  function applyDefault() {
    root.style.top = `${DEFAULT_POS.top}px`;
    root.style.right = `${DEFAULT_POS.right}px`;
    root.style.left = 'auto';
    root.style.bottom = 'auto';
  }

  function applyXY(x, y) {
    const { w, h } = widgetSize();
    if (!onScreen(x, y, w, h)) {
      applyDefault();
      return false;
    }
    const c = clampXY(x, y);
    root.style.left = `${c.x}px`;
    root.style.top = `${c.y}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
    return true;
  }

  function parseXY(raw) {
    if (!raw) return null;
    try {
      const o = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!o || typeof o !== 'object') return null;
      const x = Number(o.x);
      const y = Number(o.y);
      if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
      return { x, y };
    } catch (_) {
      return null;
    }
  }

  function currentXY() {
    const rect = root.getBoundingClientRect();
    if (rect.width > 1) return { x: Math.round(rect.left), y: Math.round(rect.top) };
    const left = parseInt(root.style.left, 10);
    const top = parseInt(root.style.top, 10);
    if (Number.isFinite(left) && Number.isFinite(top)) return { x: left, y: top };
    return null;
  }

  function persistXY(x, y) {
    const { w, h } = widgetSize();
    if (!onScreen(x, y, w, h)) {
      applyDefault();
      lsDel(LS_POS_XY);
      return;
    }
    const c = clampXY(x, y);
    root.style.left = `${c.x}px`;
    root.style.top = `${c.y}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
    lsSet(LS_POS_XY, JSON.stringify({ x: c.x, y: c.y }));
  }

  function restorePosition() {
    const stored = parseXY(lsGet(LS_POS_XY, ''));
    if (stored) {
      if (!applyXY(stored.x, stored.y)) applyDefault();
      return;
    }
    applyDefault();
  }

  function resetPosition() {
    lsDel(LS_POS_XY);
    applyDefault();
  }

  function reclampIfPositioned() {
    const xy = currentXY();
    if (!xy) return;
    const { w, h } = widgetSize();
    if (!onScreen(xy.x, xy.y, w, h)) applyDefault();
    else applyXY(xy.x, xy.y);
  }

  function isHeaderControl(target) {
    if (!target || typeof target.closest !== 'function') return false;
    if (target.closest('#ph-pin, #ph-collapse, #ph-hide')) return true;
    if (target.closest('.ph-btn')) return true;
    if (target.closest('button')) return true;
    return false;
  }

  /* Drag from empty header (not PIN / collapse / hide). Threshold so a click is not a drag.
     PIN never locks drag. Collapsed header stays draggable. */
  function onPointerDown(ev) {
    if (drag) return;
    if (ev.button != null && ev.button !== 0) return;
    if (isHeaderControl(ev.target)) return;
    if (!els.header || !els.header.contains(ev.target)) return;
    const rect = root.getBoundingClientRect();
    drag = {
      ox: ev.clientX - rect.left,
      oy: ev.clientY - rect.top,
      w: rect.width,
      h: rect.height,
      headerH: (els.header.getBoundingClientRect().height) || 48,
      startX: ev.clientX,
      startY: ev.clientY,
      moved: false,
    };
    dragMoved = false;
  }

  function onPointerMove(ev) {
    if (!drag) return;
    const dx = ev.clientX - drag.startX;
    const dy = ev.clientY - drag.startY;
    if (!drag.moved && (dx * dx + dy * dy) >= DRAG_THRESHOLD * DRAG_THRESHOLD) {
      drag.moved = true;
      root.classList.add('is-dragging');
    }
    if (!drag.moved) return;
    dragMoved = true;
    const headerH = drag.headerH || 48;
    const left = Math.max(EDGE, Math.min(window.innerWidth - drag.w - EDGE, ev.clientX - drag.ox));
    const top = Math.max(EDGE, Math.min(window.innerHeight - headerH - EDGE, ev.clientY - drag.oy));
    root.style.left = `${left}px`;
    root.style.top = `${top}px`;
    root.style.right = 'auto';
    root.style.bottom = 'auto';
  }

  function onPointerUp() {
    if (!drag) return;
    const moved = drag.moved;
    drag = null;
    root.classList.remove('is-dragging');
    if (!moved) return;
    dragMoved = true;
    const rect = root.getBoundingClientRect();
    persistXY(Math.round(rect.left), Math.round(rect.top));
  }

  if (els.header) {
    els.header.addEventListener('mousedown', onPointerDown);
    els.header.addEventListener('pointerdown', onPointerDown);
  }
  window.addEventListener('mousemove', onPointerMove);
  window.addEventListener('mouseup', onPointerUp);
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);

  function stopOwn(ev, fn) {
    ev.stopPropagation();
    fn(ev);
  }

  if (els.collapse) {
    els.collapse.addEventListener('click', (ev) => stopOwn(ev, () => {
      collapsed = !collapsed;
      saveFlag(COLLAPSE_KEY, collapsed);
      applyChrome();
      reclampIfPositioned();
    }));
    els.collapse.addEventListener('mousedown', (ev) => ev.stopPropagation());
    els.collapse.addEventListener('pointerdown', (ev) => ev.stopPropagation());
  }
  if (els.pin) {
    els.pin.addEventListener('click', (ev) => stopOwn(ev, () => {
      pinned = !pinned;
      saveFlag(PINNED_KEY, pinned);
      applyChrome();
      /* Pin stays pin — keep visible only. Never locks drag, never hides, never empties SQL. */
    }));
    els.pin.addEventListener('mousedown', (ev) => ev.stopPropagation());
    els.pin.addEventListener('pointerdown', (ev) => ev.stopPropagation());
  }
  if (els.hide) {
    els.hide.addEventListener('click', (ev) => stopOwn(ev, () => {
      /* D: hide → pinsVisible=false ONLY. Never unpin, never empty SQL, never miniHud=false-only. */
      setPinsVisible(false);
    }));
    els.hide.addEventListener('mousedown', (ev) => ev.stopPropagation());
    els.hide.addEventListener('pointerdown', (ev) => ev.stopPropagation());
  }
  if (els.shell) {
    els.shell.addEventListener('click', (ev) => {
      if (!collapsed) return;
      if (dragMoved) { dragMoved = false; return; }
      if (ev.target.closest('#ph-pin, #ph-hide, #ph-collapse, .ph-btn')) return;
      collapsed = false;
      saveFlag(COLLAPSE_KEY, false);
      applyChrome();
      reclampIfPositioned();
    });
  }

  window.addEventListener('resize', () => {
    const xy = currentXY();
    if (!xy) return;
    const { w, h } = widgetSize();
    if (!onScreen(xy.x, xy.y, w, h)) applyDefault();
    else applyXY(xy.x, xy.y);
  });

  window.addEventListener('message', (ev) => {
    const data = ev.data || {};
    if (data.action === 'pinsHud') render(data);
    if (data.action === 'pinsHud:setVisible') {
      setPinsVisible(!!data.visible, { skipPost: true });
    }
    if (data.action === 'bookOpen') {
      bookOpen = true;
      applyVisibility();
    }
    if (data.action === 'bookClose') {
      bookOpen = false;
      applyVisibility();
    }
    if (data.action === 'hud:reset') {
      collapsed = false;
      saveFlag(COLLAPSE_KEY, false);
      applyChrome();
      setPinsVisible(true, { skipPost: true });
      resetPosition();
    }
  });

  window.addEventListener('sanctuary-hud:change', (ev) => {
    const d = (ev && ev.detail) || {};
    if (typeof d.pinsVisible === 'boolean' && d.pinsVisible !== pinsVisible) {
      pinsVisible = d.pinsVisible;
      applyVisibility();
    }
    if (d.reset) {
      collapsed = false;
      saveFlag(COLLAPSE_KEY, false);
      applyChrome();
      pinsVisible = true;
      applyVisibility();
      resetPosition();
    }
  });

  applyChrome();
  applyVisibility();
  restorePosition();

  window.__pinsHud = {
    setVisible: setPinsVisible,
    getVisible: () => pinsVisible,
    applyVisibility,
    resetPosition,
    restorePosition,
    applyDefault,
    clampXY,
    LS_POS_XY,
    /* D: SQL pins live in Lua/server — this widget never sends empty pins on hide. */
  };
})();
