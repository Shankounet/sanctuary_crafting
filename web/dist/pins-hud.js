(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const root = document.getElementById('book-pins-hud');
  if (!root) return;
  const COLLAPSE_KEY = 'sanctuary_crafting:pinsHudCollapsed';
  const PINNED_KEY = 'sanctuary_crafting:pinsHudPinned';
  const HUD = () => window.SanctuaryHud;
  const els = {
    list: document.getElementById('ph-list'),
    count: document.getElementById('ph-count'),
    collapse: document.getElementById('ph-collapse'),
    pin: document.getElementById('ph-pin'),
    hide: document.getElementById('ph-hide'),
    summary: document.getElementById('ph-summary'),
    title: root.querySelector('.ph-title'),
    shell: root.querySelector('.ph-shell'),
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

  let collapsed = loadFlag(COLLAPSE_KEY, false);
  let pinned = loadFlag(PINNED_KEY, true);
  /* NUI-owned visibility. Unknown → true. Close/hide never unpins / never empties SQL. */
  let pinsVisible = HUD() ? HUD().readPinsVisible() : true;
  let bookOpen = false;
  let lastPins = [];
  let lastCrafts = [];
  let lastMax = 4;
  let lastFeature = true;

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

  if (els.collapse) {
    els.collapse.addEventListener('click', (ev) => {
      ev.stopPropagation();
      collapsed = !collapsed;
      saveFlag(COLLAPSE_KEY, collapsed);
      applyChrome();
    });
  }
  if (els.pin) {
    els.pin.addEventListener('click', (ev) => {
      ev.stopPropagation();
      pinned = !pinned;
      saveFlag(PINNED_KEY, pinned);
      applyChrome();
      /* Pin stays pin — does not hide, does not empty SQL. */
    });
  }
  if (els.hide) {
    els.hide.addEventListener('click', (ev) => {
      ev.stopPropagation();
      /* D: hide → pinsVisible=false ONLY. Never unpin, never empty SQL, never miniHud=false-only. */
      setPinsVisible(false);
    });
  }
  if (els.shell) {
    els.shell.addEventListener('click', (ev) => {
      if (!collapsed) return;
      if (ev.target.closest('#ph-pin, #ph-hide, #ph-collapse')) return;
      collapsed = false;
      saveFlag(COLLAPSE_KEY, false);
      applyChrome();
    });
  }

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
    }
  });

  applyChrome();
  applyVisibility();

  window.__pinsHud = {
    setVisible: setPinsVisible,
    getVisible: () => pinsVisible,
    applyVisibility,
    /* D: SQL pins live in Lua/server — this widget never sends empty pins on hide. */
  };
})();
