(() => {
  /* Central HUD prefs (NUI-owned). Validate on boot. Restore path for pins + tracker. */
  const resName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const KEY_MODE = 'sanctuary_hud.trackerMode';
  const KEY_PINS = 'sanctuary_hud.pinsVisible';
  const KEY_POS = 'sanctuary_hud.trackerPos';
  const KEY_XY = 'craftTrackerPosition';
  const OLD_MODE = 'sc_tracker_mode';
  const OLD_POS = 'sc_tracker_pos';
  const OLD_COLLAPSE = 'sanctuary_crafting:pinsHudCollapsed';
  const MODES = ['expanded', 'compact', 'minimal', 'hidden'];
  const DEFAULT_POS = { top: 24, right: 24 };

  function post(name, data) {
    return fetch(`https://${resName}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({ ok: false }));
  }

  function lsGet(key) {
    try { return localStorage.getItem(key); } catch (_) { return null; }
  }
  function lsSet(key, value) {
    try { localStorage.setItem(key, value); } catch (_) { /* ignore */ }
  }
  function lsDel(key) {
    try { localStorage.removeItem(key); } catch (_) { /* ignore */ }
  }

  function normalizeMode(raw) {
    if (raw === 'normal') return 'expanded';
    if (MODES.indexOf(raw) !== -1) return raw;
    return 'expanded';
  }

  function parsePinsVisible(raw) {
    if (raw == null || raw === '') return true;
    if (raw === '0' || raw === 'false' || raw === 'off') return false;
    if (raw === '1' || raw === 'true' || raw === 'on') return true;
    return true;
  }

  function parsePos(raw) {
    if (!raw) return null;
    try {
      const o = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!o || typeof o !== 'object') return null;
      const top = Number(o.top);
      const right = Number(o.right);
      if (!Number.isFinite(top) || !Number.isFinite(right)) return null;
      return { top, right };
    } catch (_) {
      return null;
    }
  }

  function migrateBoot() {
    /* F: mode not in allowed → expanded. Empty key migrates sc_tracker_mode (normal→expanded). */
    const raw = lsGet(KEY_MODE);
    let mode;
    if (raw == null || raw === '') {
      mode = normalizeMode(lsGet(OLD_MODE));
    } else {
      mode = normalizeMode(raw);
    }
    lsSet(KEY_MODE, mode);

    const pinsRaw = lsGet(KEY_PINS);
    if (pinsRaw !== '0' && pinsRaw !== '1') {
      lsSet(KEY_PINS, parsePinsVisible(pinsRaw) ? '1' : '0');
    }

    if (!parsePos(lsGet(KEY_POS))) {
      const migrated = parsePos(lsGet(OLD_POS));
      if (migrated) lsSet(KEY_POS, JSON.stringify(migrated));
    }
    if (!lsGet(KEY_XY)) {
      const pos = parsePos(lsGet(KEY_POS));
      if (pos) {
        const w = 292;
        const x = Math.round((window.innerWidth || 800) - (pos.right || 24) - w);
        const y = Math.round(pos.top);
        lsSet(KEY_XY, JSON.stringify({ x, y }));
      }
    }
    return { mode: normalizeMode(lsGet(KEY_MODE)), pinsVisible: parsePinsVisible(lsGet(KEY_PINS)) };
  }

  const boot = migrateBoot();

  function emit(extra) {
    const detail = Object.assign({
      trackerMode: readMode(),
      pinsVisible: readPinsVisible(),
      trackerPos: readPos(),
    }, extra || {});
    window.dispatchEvent(new CustomEvent('sanctuary-hud:change', { detail }));
    refreshPanel();
  }

  function readMode() {
    return normalizeMode(lsGet(KEY_MODE));
  }
  function readPinsVisible() {
    return parsePinsVisible(lsGet(KEY_PINS));
  }
  function readPos() {
    return parsePos(lsGet(KEY_POS));
  }

  function writeMode(next, opts) {
    const mode = normalizeMode(next);
    lsSet(KEY_MODE, mode);
    if (!(opts && opts.silentPost)) {
      post('trackerMode', { mode });
      post('hudSettingsTracker', { mode });
    }
    if (!(opts && opts.silent)) emit({ trackerMode: mode, source: (opts && opts.source) || 'store' });
    return mode;
  }

  function writePinsVisible(on, opts) {
    const vis = !!on;
    lsSet(KEY_PINS, vis ? '1' : '0');
    if (!(opts && opts.silentPost)) {
      post('hudSettingsPins', { visible: vis });
      if (vis) post('bookToggleHud', { enabled: true });
    }
    if (!(opts && opts.silent)) emit({ pinsVisible: vis, source: (opts && opts.source) || 'store' });
    return vis;
  }

  function writePos(pos, opts) {
    const parsed = parsePos(pos) || DEFAULT_POS;
    lsSet(KEY_POS, JSON.stringify(parsed));
    let x = pos && Number(pos.x);
    let y = pos && Number(pos.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      const w = 292;
      x = Math.round((window.innerWidth || 800) - (parsed.right || 24) - w);
      y = Math.round(parsed.top);
    } else {
      x = Math.round(x);
      y = Math.round(y);
    }
    lsSet(KEY_XY, JSON.stringify({ x, y }));
    if (!(opts && opts.silent)) emit({ trackerPos: parsed, source: (opts && opts.source) || 'store' });
    return parsed;
  }

  function reset() {
    lsDel(OLD_MODE);
    lsDel(OLD_POS);
    lsDel(OLD_COLLAPSE);
    lsDel(KEY_XY);
    lsSet(KEY_MODE, 'expanded');
    lsSet(KEY_PINS, '1');
    lsSet(KEY_POS, JSON.stringify(DEFAULT_POS));
    {
      const w = 292;
      const x = Math.round((window.innerWidth || 800) - (DEFAULT_POS.right || 24) - w);
      lsSet(KEY_XY, JSON.stringify({ x, y: DEFAULT_POS.top }));
    }
    post('hudReset', {});
    post('bookToggleHud', { enabled: true });
    post('hudSettingsPins', { visible: true });
    post('trackerMode', { mode: 'expanded' });
    post('hudSettingsTracker', { mode: 'expanded' });
    post('trackerResetPosition', {});
    emit({ reset: true, trackerMode: 'expanded', pinsVisible: true, trackerPos: DEFAULT_POS, source: 'reset' });
  }

  const overlay = document.getElementById('hud-settings');
  const els = {
    pins: document.getElementById('hud-set-pins'),
    tracker: document.getElementById('hud-set-tracker'),
    mode: document.getElementById('hud-set-tracker-mode'),
    reset: document.getElementById('hud-set-reset'),
    close: document.getElementById('hud-settings-close'),
  };

  function refreshPanel() {
    const mode = readMode();
    const pinsOn = readPinsVisible();
    if (els.pins) els.pins.checked = pinsOn;
    if (els.tracker) els.tracker.checked = mode !== 'hidden';
    if (els.mode) {
      els.mode.value = mode === 'hidden' ? 'expanded' : mode;
      els.mode.disabled = mode === 'hidden';
    }
  }

  function open() {
    if (!overlay) return;
    overlay.classList.remove('hidden');
    overlay.classList.add('is-open');
    overlay.setAttribute('aria-hidden', 'false');
    refreshPanel();
  }
  function close() {
    if (!overlay) return;
    overlay.classList.add('hidden');
    overlay.classList.remove('is-open');
    overlay.setAttribute('aria-hidden', 'true');
  }

  if (els.pins) {
    els.pins.addEventListener('change', () => writePinsVisible(els.pins.checked, { source: 'settings' }));
  }
  if (els.tracker) {
    els.tracker.addEventListener('change', () => {
      if (els.tracker.checked) writeMode('expanded', { source: 'settings' });
      else writeMode('hidden', { source: 'settings' });
    });
  }
  if (els.mode) {
    els.mode.addEventListener('change', () => {
      if (readMode() === 'hidden') return;
      writeMode(els.mode.value, { source: 'settings' });
    });
  }
  if (els.reset) els.reset.addEventListener('click', () => reset());
  if (els.close) els.close.addEventListener('click', close);
  if (overlay) {
    overlay.addEventListener('click', (ev) => {
      if (ev.target === overlay) close();
    });
  }

  /* #btn-hud is bound in app.js (open settings). Backdrop/close here. */

  /* Heal persisted miniHud=false from old hide path (NUI owns pinsVisible). */
  if (boot.pinsVisible) {
    post('bookToggleHud', { enabled: true });
    post('hudSettingsPins', { visible: true });
  }

  window.SanctuaryHud = {
    KEYS: { mode: KEY_MODE, pins: KEY_PINS, pos: KEY_POS },
    MODES,
    DEFAULT_POS,
    normalizeMode,
    readMode,
    writeMode,
    readPinsVisible,
    writePinsVisible,
    readPos,
    writePos,
    reset,
    open,
    close,
    refreshPanel,
    post,
  };

  refreshPanel();

  /* Tests A–G (structurally true — no FiveM runtime):
   * A compact: header [+] / reduced body click → expanded
   * B minimal: same reduced chrome as compact; [+] returns to expanded (not trapped)
   * C hidden → settings Afficher tracker → writeMode('expanded')
   * D pins hide → pinsVisible=false only; settings Afficher épingles → true; Lua never pins=[]
   * E hidden pins/tracker: display:none + width/height 0 (no 248/292px CEF box)
   * F LS invalid mode → normalizeMode → expanded on boot
   * G new craft while hidden → compact (showOnNewCraftIfHidden)
   */
})();
