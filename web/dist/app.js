(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const $ = (s) => document.querySelector(s);
  const app = $('#app');
  let state = {
    benchKey: null, recipes: [], favorites: [], selected: null,
    filter: 'all', search: '', compact: false, crafting: false,
    craftId: null, queue: [], shop: {}, flags: {},
    sounds: { Enabled: true, Volume: 0.35, Files: {} },
    audioCtx: null,
  };

  function post(name, data = {}) {
    return fetch(`https://${res}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => ({}));
  }

  function ensureAudio() {
    if (!state.audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) state.audioCtx = new AC();
    }
    return state.audioCtx;
  }

  function beep(kind) {
    const cfg = state.sounds || {};
    if (cfg.Enabled === false) return;
    const vol = typeof cfg.Volume === 'number' ? cfg.Volume : 0.35;
    const files = cfg.Files || {};
    const src = files[kind];
    // Prefer short .ogg placeholder if present
    if (src) {
      try {
        const a = new Audio(src);
        a.volume = Math.max(0, Math.min(1, vol));
        const p = a.play();
        if (p && p.catch) p.catch(() => webBeep(kind, vol));
        return;
      } catch (_) { /* fall through */ }
    }
    webBeep(kind, vol);
  }

  function webBeep(kind, vol) {
    try {
      const ctx = ensureAudio();
      if (!ctx) return;
      if (ctx.state === 'suspended') ctx.resume();
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.connect(g); g.connect(ctx.destination);
      const now = ctx.currentTime;
      const map = {
        click: { f: 880, d: 0.04, type: 'square' },
        success: { f: 660, d: 0.1, type: 'sine' },
        error: { f: 220, d: 0.12, type: 'sawtooth' },
        blueprint: { f: 520, d: 0.14, type: 'triangle' },
      };
      const m = map[kind] || map.click;
      o.type = m.type; o.frequency.value = m.f;
      g.gain.setValueAtTime(0.0001, now);
      g.gain.exponentialRampToValueAtTime(Math.max(0.001, vol), now + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, now + m.d);
      o.start(now); o.stop(now + m.d + 0.02);
    } catch (_) { /* ignore */ }
  }

  function playTick() { beep('click'); }

  function matchesFilter(r) {
    if (state.filter === 'craftable' && !r.canCraft) return false;
    if (state.filter === 'locked' && !r.locked) return false;
    if (state.filter === 'favorites' && !state.favorites.includes(r.id)) return false;
    if (state.search) {
      const q = state.search.toLowerCase();
      const tags = (r.tags || []).join(' ');
      if (!(`${r.label} ${r.id} ${tags}`).toLowerCase().includes(q)) return false;
    }
    return true;
  }

  function lockText(r) {
    if (!r.locked) return r.missingItems ? '✕ Ingrédients manquants' : '✓ Disponible';
    const map = {
      craft_level_required: '✕ Niveau requis',
      craft_skill_required: '✕ Compétence requise',
      craft_blueprint_required: '✕ Blueprint requis',
      craft_skills_unavailable: '✕ Skills indisponibles',
      craft_station_level: '✕ Niveau atelier',
      craft_no_power: '✕ Pas d\'énergie',
    };
    return map[r.lockReason] || ('✕ ' + (r.lockReason || 'Verrouillé'));
  }

  function renderList() {
    const ul = $('#recipe-list');
    ul.innerHTML = '';
    state.recipes.filter(matchesFilter).forEach((r) => {
      const li = document.createElement('li');
      if (r.locked) li.classList.add('locked');
      if (state.selected && state.selected.id === r.id) li.classList.add('selected');
      const st = r.canCraft ? 'ok' : 'bad';
      li.innerHTML = `<span class="name">${escapeHtml(r.label)}</span><span class="status ${st}">${r.canCraft ? '✓' : '✕'}</span>`;
      li.addEventListener('click', () => selectRecipe(r));
      ul.appendChild(li);
    });
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  function selectRecipe(r) {
    state.selected = r;
    playTick();
    $('#detail-empty').classList.add('hidden');
    $('#detail').classList.remove('hidden');
    $('#d-title').textContent = r.label;
    $('#d-locks').textContent = lockText(r);
    const ings = $('#d-ings');
    ings.innerHTML = '';
    (r.ingredients || []).forEach((ing) => {
      const li = document.createElement('li');
      li.textContent = `${ing.count}× ${ing.item}`;
      ings.appendChild(li);
    });
    const res = r.result || {};
    $('#d-result').textContent = `${res.count || 1}× ${res.item || '?'}`;
    $('#d-duration').textContent = `${Math.round((r.duration || 0) / 1000)}s`;
    $('#d-xp').textContent = r.xp ? `+${r.xp.amount} XP (${r.xp.category})` : '';
    $('#d-mastery').textContent = state.flags.mastery ? `Maîtrise ${r.mastery || 0}` : '';
    $('#btn-craft').disabled = !r.canCraft || state.crafting;
    $('#batch-wrap').classList.toggle('hidden', !state.flags.batch);
    $('#btn-queue').classList.toggle('hidden', !state.flags.queue);
    renderList();
  }

  function runProgress(duration, onDone) {
    $('#progress-wrap').classList.remove('hidden');
    $('#btn-craft').disabled = true;
    $('#progress-fill').style.width = '0%';
    const start = performance.now();
    const dur = duration || 5000;
    const tick = (now) => {
      if (!state.crafting) return;
      const p = Math.min(1, (now - start) / dur);
      $('#progress-fill').style.width = `${p * 100}%`;
      if (p < 1) requestAnimationFrame(tick);
      else onDone();
    };
    requestAnimationFrame(tick);
  }

  async function startCraft() {
    if (!state.selected || state.crafting) return;
    playTick();
    const batch = parseInt($('#batch').value, 10) || 1;
    const data = await post('craft', { recipeId: state.selected.id, benchKey: state.benchKey, batch });
    if (!data.ok) {
      beep('error');
      await post('notify', { type: 'error', reason: data.reason });
      return;
    }
    state.crafting = true;
    state.craftId = data.craftId;
    runProgress(data.duration, finishCraft);
  }

  async function finishCraft() {
    const data = await post('complete', { craftId: state.craftId });
    if (data && data.ok && data.advanced) {
      // même craftId — étape suivante
      beep('click');
      await post('notify', {
        type: 'inform',
        reason: 'craft_step_advance',
        label: data.stepLabel || data.label,
        args: [data.stepIndex, data.totalSteps, data.stepLabel || data.label],
      });
      runProgress(data.duration, finishCraft);
      return;
    }
    state.crafting = false;
    state.craftId = null;
    $('#progress-wrap').classList.add('hidden');
    $('#progress-fill').style.width = '0%';
    if (data && data.ok) {
      beep('success');
      if (data.chainNext) beep('blueprint');
    } else {
      beep('error');
    }
    await post('notify', { type: data.ok ? 'success' : 'error', reason: data.ok ? 'craft_success' : (data.reason || 'craft_failed'), label: data.label });
    await refresh();
  }

  async function cancelCraft() {
    if (!state.craftId) return;
    await post('cancel', { craftId: state.craftId });
    state.crafting = false;
    state.craftId = null;
    $('#progress-wrap').classList.add('hidden');
    $('#progress-fill').style.width = '0%';
    $('#btn-craft').disabled = !(state.selected && state.selected.canCraft);
  }

  async function refresh() {
    const data = await post('refresh', { benchKey: state.benchKey });
    if (data && data.ok) applyMenu(data);
  }

  function applyMenu(data) {
    state.benchKey = data.benchKey;
    state.recipes = data.recipes || [];
    state.favorites = data.favorites || [];
    state.flags = data.flags || {};
    if (data.ui && data.ui.Sounds) state.sounds = data.ui.Sounds;
    $('#station-title').textContent = data.label || 'Atelier';
    $('#station-meta').textContent = `${data.category || ''} · niv.${data.stationLevel || 1}${data.powered === false ? ' · hors tension' : ''}`;
    renderList();
    if (state.selected) {
      const again = state.recipes.find((r) => r.id === state.selected.id);
      if (again) selectRecipe(again);
    }
  }

  function renderQueue() {
    const ul = $('#queue-list');
    ul.innerHTML = '';
    const empty = $('#queue-empty');
    empty.classList.toggle('hidden', state.queue.length > 0);
    state.queue.forEach((e) => {
      const li = document.createElement('li');
      const left = Math.max(0, (e.finishAt || 0) - Math.floor(Date.now() / 1000));
      li.innerHTML = `<span>${escapeHtml(e.label || e.recipeId)}</span><span>${left > 0 ? left + 's' : 'Prêt'}</span>`;
      li.addEventListener('click', async () => {
        if (left <= 0) {
          await post('queueCollect', { craftId: e.craftId });
          await loadQueue();
        }
      });
      ul.appendChild(li);
    });
  }

  async function loadQueue() {
    const data = await post('queueList', {});
    state.queue = (data && data.queue) || [];
    renderQueue();
  }

  function renderShop() {
    const ul = $('#shop-list');
    ul.innerHTML = '';
    Object.entries(state.shop || {}).forEach(([item, count]) => {
      const li = document.createElement('li');
      li.innerHTML = `<span>${escapeHtml(item)}</span><span>×${count}</span>`;
      ul.appendChild(li);
    });
  }

  function renderTree(node, indent = 0) {
    if (!node) return '—';
    if (node.type === 'raw') return `${'  '.repeat(indent)}• ${node.item} ×${node.count}\n`;
    let s = `${'  '.repeat(indent)}⚙ ${node.label} → ${node.result.item}\n`;
    (node.children || []).forEach((c) => { s += renderTree(c, indent + 1); });
    return s;
  }

  // events
  $('#btn-close').addEventListener('click', () => post('close', {}));
  $('#btn-compact').addEventListener('click', () => {
    state.compact = !state.compact;
    app.dataset.compact = state.compact ? '1' : '0';
  });
  $('#search').addEventListener('input', (e) => { state.search = e.target.value; renderList(); });
  document.querySelectorAll('.chip').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.chip').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.filter = btn.dataset.filter;
      renderList();
    });
  });
  document.querySelectorAll('.tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      ['queue', 'tree', 'shop'].forEach((t) => {
        $(`#tab-${t}`).classList.toggle('hidden', btn.dataset.tab !== t);
      });
    });
  });
  $('#btn-craft').addEventListener('click', startCraft);
  $('#btn-cancel').addEventListener('click', cancelCraft);
  $('#btn-fav').addEventListener('click', async () => {
    if (!state.selected) return;
    await post('favorite', { recipeId: state.selected.id });
    await refresh();
  });
  $('#btn-queue').addEventListener('click', async () => {
    if (!state.selected) return;
    const batch = parseInt($('#batch').value, 10) || 1;
    await post('queue', { recipeId: state.selected.id, benchKey: state.benchKey, batch });
    await loadQueue();
  });
  $('#btn-shop').addEventListener('click', async () => {
    if (!state.selected) return;
    const batch = parseInt($('#batch').value, 10) || 1;
    const data = await post('shopping', { recipeId: state.selected.id, batch });
    state.shop = (data && data.list) || {};
    renderShop();
    document.querySelector('.tab[data-tab="shop"]').click();
  });
  $('#btn-shop-clear').addEventListener('click', async () => {
    await post('shoppingClear', {});
    state.shop = {};
    renderShop();
  });
  $('#btn-tree').addEventListener('click', async () => {
    if (!state.selected) return;
    const data = await post('tree', { recipeId: state.selected.id });
    $('#tree-view').textContent = renderTree(data.tree);
    document.querySelector('.tab[data-tab="tree"]').click();
  });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'open') {
      app.classList.remove('hidden');
      applyMenu(msg.data || {});
      loadQueue();
      if (msg.data && msg.data.ui && msg.data.ui.Accent) {
        document.documentElement.style.setProperty('--accent', msg.data.ui.Accent);
      }
      if (msg.data && msg.data.ui && msg.data.ui.Sounds) state.sounds = msg.data.ui.Sounds;
    } else if (msg.action === 'close') {
      app.classList.add('hidden');
      state.crafting = false;
      state.craftId = null;
    } else if (msg.action === 'queue') {
      state.queue = msg.queue || [];
      renderQueue();
    }
  });

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') post('close', {});
  });
})();
