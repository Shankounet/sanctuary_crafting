(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const root = document.getElementById('book-pins-hud');
  if (!root) return;
  const COLLAPSE_KEY = 'sanctuary_crafting:pinsHudCollapsed';
  const PINNED_KEY = 'sanctuary_crafting:pinsHudPinned';
  const els = {
    list: document.getElementById('ph-list'),
    count: document.getElementById('ph-count'),
    collapse: document.getElementById('ph-collapse'),
    pin: document.getElementById('ph-pin'),
    hide: document.getElementById('ph-hide'),
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

  function applyChrome() {
    root.classList.toggle('is-collapsed', collapsed);
    if (els.collapse) {
      els.collapse.setAttribute('aria-pressed', collapsed ? 'true' : 'false');
      els.collapse.title = collapsed ? 'Déplier' : 'Réduire';
    }
    if (els.pin) {
      els.pin.classList.toggle('is-on', pinned);
      els.pin.setAttribute('aria-pressed', pinned ? 'true' : 'false');
    }
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
    /* startedAt from client GetGameTimer is not Date.now — prefer pct if sent */
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
    row.querySelector('.ph-name').textContent = p.label || p.recipeId || 'Recette';
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

  function render(payload) {
    const pins = (payload && payload.pins) || [];
    const crafts = (payload && payload.crafts) || [];
    const max = Math.max(1, Number((payload && payload.max) || 4));
    const visible = payload && payload.visible !== false && pins.length > 0;
    root.classList.toggle('is-visible', !!visible);
    if (!visible) return;

    const craftingIds = new Set(crafts.map((c) => c && c.recipeId).filter(Boolean));
    const inProgress = pins.filter((p) => craftingIds.has(p.recipeId));
    const followed = pins.filter((p) => !craftingIds.has(p.recipeId));

    const shown = [];
    inProgress.forEach((p) => { if (shown.length < max) shown.push({ p, craft: craftFor(p.recipeId, crafts) }); });
    followed.forEach((p) => { if (shown.length < max) shown.push({ p, craft: null }); });
    const hiddenN = Math.max(0, pins.length - shown.length);

    if (els.count) els.count.textContent = String(pins.length);
    if (!els.list) return;
    els.list.innerHTML = '';
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
      more.textContent = `+${hiddenN}`;
      els.list.appendChild(more);
    }
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
      post('bookToggleHud', { enabled: true });
    });
  }
  if (els.hide) {
    els.hide.addEventListener('click', (ev) => {
      ev.stopPropagation();
      root.classList.remove('is-visible');
      post('bookToggleHud', { enabled: false });
    });
  }

  window.addEventListener('message', (ev) => {
    const data = ev.data || {};
    if (data.action === 'pinsHud') render(data);
  });

  applyChrome();
})();
