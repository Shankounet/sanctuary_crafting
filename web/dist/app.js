(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const $ = (s) => document.querySelector(s);
  const $$ = (s) => Array.from(document.querySelectorAll(s));
  const app = $('#app');
  const IMG_BASE = 'nui://ox_inventory/web/images/';

  let state = {
    benchKey: null,
    recipes: [],
    favorites: [],
    selected: null,
    filter: 'all',
    category: 'all',
    search: '',
    compact: false,
    crafting: false,
    craftId: null,
    queue: [],
    shop: {},
    flags: {},
    menuMeta: {},
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

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  function itemImageUrl(item) {
    if (!item) return '';
    return `${IMG_BASE}${encodeURIComponent(String(item))}.png`;
  }

  function bindItemImg(img, item, fallbackEl) {
    if (!img) return;
    const url = itemImageUrl(item);
    img.classList.remove('is-fallback');
    img.removeAttribute('hidden');
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

  function humanize(id) {
    if (!id) return '—';
    return String(id).replace(/[_-]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function categoryLabel(cat) {
    if (!cat || cat === 'all') return 'Toutes';
    return humanize(cat);
  }

  function isFavorite(id) {
    return state.favorites.includes(id);
  }

  function hasKnownPlan(r) {
    if (!r.requireBlueprint) return true;
    return r.lockReason !== 'craft_blueprint_required';
  }

  function isNewRecipe(r) {
    if (state.flags.mastery) return !r.mastery || r.mastery <= 0;
    const tags = r.tags || [];
    return tags.includes('new') || tags.includes('nouveau') || r.rarity === 'new';
  }

  function matchesFilter(r) {
    if (state.category && state.category !== 'all' && r.category !== state.category) return false;
    if (state.filter === 'craftable' && !r.canCraft) return false;
    if (state.filter === 'locked' && !r.locked) return false;
    if (state.filter === 'favorites' && !isFavorite(r.id)) return false;
    if (state.filter === 'new' && !isNewRecipe(r)) return false;
    if (state.filter === 'plans' && !hasKnownPlan(r)) return false;
    if (state.search) {
      const q = state.search.toLowerCase();
      const tags = (r.tags || []).join(' ');
      const hay = `${r.label} ${r.id} ${tags} ${r.category || ''} ${r.result && r.result.item || ''}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    return true;
  }

  const LOCK_LABELS = {
    craft_level_required: (r) => {
      const need = (r.lockArgs && r.lockArgs[0]) || r.requireLevel;
      const cur = r.lockArgs && r.lockArgs[1];
      if (need != null && cur != null) return `Niveau ${need} requis (actuel : ${cur})`;
      if (need != null) return `Niveau ${need} requis`;
      return 'Niveau requis';
    },
    craft_skill_required: (r) => {
      const sk = (r.lockArgs && r.lockArgs[0]) || r.requireSkill;
      return sk ? `Spécialisation requise : ${humanize(sk)}` : 'Compétence requise';
    },
    craft_blueprint_required: (r) => {
      const bp = (r.lockArgs && r.lockArgs[0]) || r.requireBlueprint;
      return bp ? `Plan requis : ${humanize(bp)}` : 'Plan requis';
    },
    craft_skills_unavailable: () => 'Système de compétences indisponible',
    craft_station_level: (r) => {
      const need = r.stationLevel;
      return need ? `Atelier niveau ${need} requis` : 'Niveau d\'atelier insuffisant';
    },
    craft_no_power: () => 'Atelier hors tension',
    craft_tool_required: () => 'Outil requis manquant ou usé',
  };

  function lockText(r) {
    if (!r.locked && r.missingItems) return { text: 'Matériaux manquants', cls: 'bad' };
    if (!r.locked) return { text: 'Disponible', cls: 'ok' };
    const fn = LOCK_LABELS[r.lockReason];
    const text = fn ? fn(r) : (r.lockReason ? humanize(r.lockReason) : 'Verrouillé');
    return { text, cls: 'warn' };
  }

  function disableWhy(r) {
    if (!r) return 'Sélectionnez une recette';
    if (state.crafting) return 'Fabrication en cours…';
    if (r.locked) return lockText(r).text;
    if (r.missingItems) return 'Matériaux insuffisants pour fabriquer';
    if (!r.canCraft) return 'Conditions non remplies';
    return '';
  }

  function durationLabel(ms) {
    const s = Math.round((ms || 0) / 1000);
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return rem ? `${m}m ${rem}s` : `${m}m`;
  }

  function qualityHint(r) {
    if (!state.flags.quality) return '—';
    if (r.quality === false) return 'Standard';
    const mastery = r.mastery || 0;
    if (mastery >= 50) return 'Élevée';
    if (mastery >= 20) return 'Bonne';
    if (mastery > 0) return 'Correcte';
    return 'Variable';
  }

  function filteredRecipes() {
    return state.recipes.filter(matchesFilter);
  }

  function renderCategories() {
    const nav = $('#cat-list');
    if (!nav) return;
    const counts = {};
    state.recipes.forEach((r) => {
      const c = r.category || 'autre';
      counts[c] = (counts[c] || 0) + 1;
    });
    const cats = Object.keys(counts).sort((a, b) => categoryLabel(a).localeCompare(categoryLabel(b), 'fr'));
    const total = state.recipes.length;
    let html = `<button type="button" class="cat-item${state.category === 'all' ? ' active' : ''}" data-cat="all">
      <i class="fa-solid fa-layer-group" aria-hidden="true"></i>
      <span>Toutes</span><span class="count">${total}</span>
    </button>`;
    cats.forEach((c) => {
      html += `<button type="button" class="cat-item${state.category === c ? ' active' : ''}" data-cat="${escapeHtml(c)}">
        <i class="fa-solid fa-tag" aria-hidden="true"></i>
        <span>${escapeHtml(categoryLabel(c))}</span><span class="count">${counts[c]}</span>
      </button>`;
    });
    nav.innerHTML = html;
    nav.querySelectorAll('.cat-item').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.category = btn.dataset.cat || 'all';
        playTick();
        renderCategories();
        renderList();
      });
    });
  }

  function renderList() {
    const grid = $('#recipe-grid');
    const empty = $('#recipe-empty');
    const countEl = $('#recipe-count');
    if (!grid) return;
    grid.innerHTML = '';
    const list = filteredRecipes();
    if (countEl) countEl.textContent = `${list.length} / ${state.recipes.length}`;
    if (empty) empty.classList.toggle('hidden', list.length > 0);

    list.forEach((r) => {
      const card = document.createElement('article');
      card.className = 'recipe-card';
      if (r.locked) card.classList.add('locked');
      if (state.selected && state.selected.id === r.id) card.classList.add('selected');
      card.dataset.id = r.id;

      const favOn = isFavorite(r.id);
      const lock = lockText(r);
      const resultItem = (r.result && r.result.item) || r.id;
      const ings = (r.ingredients || []).slice(0, 4);
      const more = (r.ingredients || []).length - ings.length;
      const availCls = r.canCraft ? 'ok' : (r.locked ? 'warn' : 'bad');
      const availTxt = r.canCraft ? 'Faisable' : (r.locked ? 'Verrouillé' : 'Manquant');

      card.innerHTML = `
        <button type="button" class="card-fav${favOn ? ' on' : ''}" data-fav="${escapeHtml(r.id)}" title="Favori" aria-label="Favori">
          <i class="fa-${favOn ? 'solid' : 'regular'} fa-star" aria-hidden="true"></i>
        </button>
        <div class="card-top">
          <div class="card-img">
            <span class="ph"><i class="fa-solid fa-cube"></i></span>
            <img alt="" />
          </div>
          <div class="card-title-wrap">
            <div class="card-title">${escapeHtml(r.label)}</div>
            <div class="card-cat">${escapeHtml(categoryLabel(r.category))}</div>
          </div>
        </div>
        <div class="card-meta">
          <span class="pill ${availCls}">${availTxt}</span>
          ${r.requireLevel != null ? `<span class="pill">Niv. ${escapeHtml(r.requireLevel)}</span>` : ''}
          <span class="pill"><i class="fa-regular fa-clock"></i> ${escapeHtml(durationLabel(r.duration))}</span>
          ${state.flags.quality ? `<span class="pill">${escapeHtml(qualityHint(r))}</span>` : ''}
        </div>
        <div class="card-ings">
          ${ings.map((ing) => {
            const ok = r.canCraft;
            const bad = r.missingItems && !r.locked;
            const cls = ok ? 'ok' : (bad ? 'bad' : '');
            const mark = ok ? '✓' : (bad || r.missingItems ? '✕' : '·');
            return `<span class="ing-chip ${cls}">${mark} ${escapeHtml(ing.count)}× ${escapeHtml(ing.item)}</span>`;
          }).join('')}
          ${more > 0 ? `<span class="ing-chip">+${more}</span>` : ''}
        </div>
        ${r.locked || r.missingItems ? `<div class="card-lock">${escapeHtml(lock.text)}</div>` : ''}
      `;

      const img = card.querySelector('.card-img img');
      const ph = card.querySelector('.card-img .ph');
      bindItemImg(img, resultItem, ph);

      card.addEventListener('click', (e) => {
        if (e.target.closest('[data-fav]')) return;
        selectRecipe(r);
      });
      const favBtn = card.querySelector('[data-fav]');
      if (favBtn) {
        favBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          await post('favorite', { recipeId: r.id });
          await refresh();
        });
      }
      grid.appendChild(card);
    });
  }

  function toolList(r) {
    const out = [];
    if (r.requireTool) {
      if (typeof r.requireTool === 'string') out.push({ item: r.requireTool, count: 1 });
      else if (r.requireTool.item) out.push({ item: r.requireTool.item, count: 1 });
    }
    if (Array.isArray(r.tools)) {
      r.tools.forEach((t) => {
        if (typeof t === 'string') out.push({ item: t, count: 1 });
        else if (t && t.item) out.push({ item: t.item, count: t.count || 1 });
      });
    }
    return out;
  }

  function selectRecipe(r) {
    state.selected = r;
    playTick();
    $('#detail-empty').classList.add('hidden');
    $('#detail').classList.remove('hidden');

    const resultItem = (r.result && r.result.item) || r.id;
    bindItemImg($('#d-image'), resultItem, $('#d-image-fallback'));

    $('#d-title').textContent = r.label;
    $('#d-category').textContent = categoryLabel(r.category);
    const rarityEl = $('#d-rarity');
    if (r.rarity) {
      rarityEl.classList.remove('hidden');
      rarityEl.textContent = humanize(r.rarity);
    } else {
      rarityEl.classList.add('hidden');
      rarityEl.textContent = '';
    }

    const desc = r.description || (r.tags && r.tags.length ? r.tags.map(humanize).join(' · ') : '');
    $('#d-desc').textContent = desc || '';
    $('#d-desc').style.display = desc ? '' : 'none';

    const lock = lockText(r);
    const locksEl = $('#d-locks');
    locksEl.textContent = lock.text;
    locksEl.className = `locks ${lock.cls === 'ok' ? 'ok' : (lock.cls === 'bad' ? 'bad' : '')}`;

    $('#d-quality').textContent = qualityHint(r);
    const resCount = (r.result && r.result.count) || 1;
    const resItem = (r.result && r.result.item) || '—';
    $('#d-result').textContent = `${resCount}× ${resItem}`;
    $('#d-duration').textContent = durationLabel(r.duration);
    $('#d-qty').textContent = `×${resCount}`;

    // skills
    const skill = r.xp && r.xp.category ? r.xp.category : (r.requireSkill || null);
    $('#d-skill').textContent = skill ? humanize(skill) : '—';
    let lvlTxt = '—';
    if (r.requireLevel != null) {
      const cur = r.lockArgs && r.lockReason === 'craft_level_required' ? r.lockArgs[1] : null;
      lvlTxt = cur != null ? `${cur} / ${r.requireLevel}` : `requis ${r.requireLevel}`;
    }
    $('#d-skill-level').textContent = lvlTxt;
    $('#d-spec').textContent = r.requireSkill ? humanize(r.requireSkill) : '—';

    $('#d-station').textContent = r.station ? humanize(r.station) : (state.menuMeta.label || '—');
    $('#d-station-lvl').textContent = r.stationLevel != null ? String(r.stationLevel) : '—';

    // ingredients
    const ings = $('#d-ings');
    ings.innerHTML = '';
    (r.ingredients || []).forEach((ing) => {
      const li = document.createElement('li');
      const ok = !!r.canCraft;
      const bad = !!r.missingItems && !r.locked;
      const markCls = ok ? 'ok' : (bad ? 'bad' : '');
      const mark = ok ? '✓' : (r.missingItems ? '✕' : '·');
      li.innerHTML = `
        <img class="ing-thumb" alt="" />
        <span class="mark ${markCls}">${mark}</span>
        <span class="iname">${escapeHtml(ing.item)}</span>
        <span class="icount">×${escapeHtml(ing.count)}</span>
      `;
      bindItemImg(li.querySelector('img'), ing.item, null);
      ings.appendChild(li);
    });
    if (!(r.ingredients || []).length) {
      ings.innerHTML = '<li><span class="iname muted">Aucun matériau</span></li>';
    }

    // tools
    const tools = toolList(r);
    const toolsBlock = $('#block-tools');
    const toolsUl = $('#d-tools');
    toolsUl.innerHTML = '';
    if (!tools.length) {
      toolsBlock.classList.add('hidden');
    } else {
      toolsBlock.classList.remove('hidden');
      tools.forEach((t) => {
        const li = document.createElement('li');
        li.innerHTML = `
          <img class="ing-thumb" alt="" />
          <span class="mark">·</span>
          <span class="iname">${escapeHtml(t.item)}</span>
          <span class="icount">×${escapeHtml(t.count || 1)}</span>
        `;
        bindItemImg(li.querySelector('img'), t.item, null);
        toolsUl.appendChild(li);
      });
    }

    const power = r.powerCost;
    const noise = r.noiseLevel;
    $('#d-power').textContent = power != null ? String(power) : '—';
    $('#d-noise').textContent = noise != null ? String(noise) : '—';

    const bp = r.requireBlueprint;
    const bpBlock = $('#block-bp');
    if (bp) {
      bpBlock.classList.remove('hidden');
      const known = hasKnownPlan(r);
      $('#d-bp').textContent = known ? `${humanize(bp)} · connu` : `${humanize(bp)} · manquant`;
      $('#d-bp').style.color = known ? 'var(--ok)' : 'var(--bad)';
    } else {
      bpBlock.classList.add('hidden');
    }

    $('#d-xp').textContent = r.xp ? `+${r.xp.amount} (${humanize(r.xp.category)})` : '—';
    $('#d-mastery').textContent = state.flags.mastery ? String(r.mastery || 0) : '—';
    $('#block-xp').classList.toggle('hidden', !r.xp && !state.flags.mastery);

    const can = !!r.canCraft && !state.crafting;
    $('#btn-craft').disabled = !can;
    const why = disableWhy(r);
    const whyEl = $('#craft-why');
    if (!can && why) {
      whyEl.textContent = why;
      whyEl.classList.remove('hidden');
    } else {
      whyEl.classList.add('hidden');
    }

    $('#batch-wrap').classList.toggle('hidden', !state.flags.batch);
    $('#btn-queue').classList.toggle('hidden', !state.flags.queue);
    $('#btn-shop').classList.toggle('hidden', state.flags.shopping === false);

    const favBtn = $('#btn-fav');
    const on = isFavorite(r.id);
    favBtn.classList.toggle('on', on);
    favBtn.innerHTML = `<i class="fa-${on ? 'solid' : 'regular'} fa-star" aria-hidden="true"></i>`;

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
    await post('notify', {
      type: data.ok ? 'success' : 'error',
      reason: data.ok ? 'craft_success' : (data.reason || 'craft_failed'),
      label: data.label,
    });
    await refresh();
  }

  async function cancelCraft() {
    if (!state.craftId) return;
    await post('cancel', { craftId: state.craftId });
    state.crafting = false;
    state.craftId = null;
    $('#progress-wrap').classList.add('hidden');
    $('#progress-fill').style.width = '0%';
    if (state.selected) selectRecipe(state.selected);
  }

  async function refresh() {
    const data = await post('refresh', { benchKey: state.benchKey });
    if (data && data.ok) applyMenu(data);
  }

  function updateStationHeader(data) {
    state.menuMeta = {
      label: data.label,
      category: data.category,
      stationLevel: data.stationLevel,
      powered: data.powered,
      modules: data.modules || {},
      energy: data.energy,
      efficiency: data.efficiency,
      condition: data.condition || data.etat,
    };
    $('#station-title').textContent = data.label || 'Atelier';
    const powered = data.powered !== false;
    const lvl = data.stationLevel || 1;
    $('#station-meta').textContent = `${categoryLabel(data.category)} · niveau ${lvl}${powered ? '' : ' · hors tension'}`;

    $('#stat-type').textContent = categoryLabel(data.category);
    $('#stat-level').textContent = String(lvl);

    const stateEl = $('#stat-state');
    if (data.condition != null || data.etat != null) {
      stateEl.textContent = String(data.condition || data.etat);
      stateEl.className = 'stat-v';
    } else {
      stateEl.textContent = powered ? 'Opérationnel' : 'Hors tension';
      stateEl.className = `stat-v ${powered ? 'ok' : 'bad'}`;
    }

    const mods = data.modules || {};
    const modCount = Array.isArray(mods) ? mods.length : Object.keys(mods).length;
    const eff = data.efficiency != null ? data.efficiency : (100 + modCount * 5);
    $('#stat-eff').textContent = typeof eff === 'number' ? `${eff}%` : String(eff);

    const energyWrap = $('#stat-energy-wrap');
    if (data.energy != null || data.power != null) {
      energyWrap.classList.remove('hidden');
      $('#stat-energy').textContent = String(data.energy != null ? data.energy : data.power);
    } else if (data.powered != null) {
      energyWrap.classList.remove('hidden');
      $('#stat-energy').textContent = data.powered ? 'OK' : 'Off';
      $('#stat-energy').className = `stat-v ${data.powered ? 'ok' : 'bad'}`;
    } else {
      energyWrap.classList.add('hidden');
    }
  }

  function applyMenu(data) {
    state.benchKey = data.benchKey;
    state.recipes = data.recipes || [];
    state.favorites = data.favorites || [];
    state.flags = data.flags || {};
    if (data.ui && data.ui.Sounds) state.sounds = data.ui.Sounds;
    updateStationHeader(data);
    renderCategories();
    renderList();
    if (state.selected) {
      const again = state.recipes.find((r) => r.id === state.selected.id);
      if (again) selectRecipe(again);
    }
  }

  function renderQueue() {
    const track = $('#queue-list');
    const empty = $('#queue-empty');
    if (!track) return;
    track.innerHTML = '';
    const has = state.queue && state.queue.length > 0;
    if (empty) empty.classList.toggle('hidden', has);
    (state.queue || []).forEach((e) => {
      const now = Math.floor(Date.now() / 1000);
      const finishAt = e.finishAt || 0;
      const startAt = e.startAt || (finishAt - Math.round((e.duration || 0) / 1000));
      const left = Math.max(0, finishAt - now);
      const total = Math.max(1, finishAt - startAt);
      const done = finishAt ? Math.min(1, Math.max(0, 1 - left / total)) : (left <= 0 ? 1 : 0);
      const card = document.createElement('div');
      card.className = `queue-card${left <= 0 ? ' ready' : ''}`;
      card.innerHTML = `
        <div class="qlabel">${escapeHtml(e.label || e.recipeId)}</div>
        <div class="qmeta">${left > 0 ? left + 's restantes' : 'Prêt — collecter'}</div>
        <div class="qbar"><div class="qfill" style="width:${Math.round(done * 100)}%"></div></div>
      `;
      card.addEventListener('click', async () => {
        if (left <= 0) {
          await post('queueCollect', { craftId: e.craftId });
          await loadQueue();
        }
      });
      track.appendChild(card);
    });
  }

  async function loadQueue() {
    const data = await post('queueList', {});
    state.queue = (data && data.queue) || [];
    renderQueue();
  }

  function renderShop() {
    const ul = $('#shop-list');
    const empty = $('#shop-empty');
    if (!ul) return;
    ul.innerHTML = '';
    const entries = Object.entries(state.shop || {});
    if (empty) empty.classList.toggle('hidden', entries.length > 0);
    entries.forEach(([item, count]) => {
      const li = document.createElement('li');
      li.innerHTML = `
        <img class="ing-thumb" alt="" />
        <span>${escapeHtml(item)}</span>
        <span>×${escapeHtml(count)}</span>
        <button type="button" class="pin" title="Épingler au carnet" data-pin-item="${escapeHtml(item)}">
          <i class="fa-solid fa-thumbtack"></i>
        </button>
      `;
      bindItemImg(li.querySelector('img'), item, null);
      const pin = li.querySelector('[data-pin-item]');
      if (pin) {
        pin.addEventListener('click', () => {
          // reuse existing book pin callback when a recipe is selected; otherwise notify
          if (state.selected) {
            post('bookPinRecipe', { recipeId: state.selected }).then((r) => {
              post('notify', { type: r && r.ok ? 'success' : 'error', reason: r && r.ok ? 'book_pinned' : (r && r.reason) || 'craft_failed' });
              beep(r && r.ok ? 'click' : 'error');
            });
          }
        });
      }
      ul.appendChild(li);
    });
  }

  function renderTreeNode(node, depth = 0) {
    if (!node) return '';
    if (node.type === 'raw') {
      return `<div class="tree-node raw" style="margin-left:${depth * 4}px">
        <div class="t-label">${escapeHtml(node.item)} ×${escapeHtml(node.count)}</div>
        <div class="t-sub">Ressource brute</div>
      </div>`;
    }
    const rid = node.recipeId || node.id || '';
    const label = node.label || rid || 'Recette';
    const result = node.result && node.result.item ? `${node.result.item}` : '';
    let html = `<div class="tree-node" data-tree-id="${escapeHtml(rid)}" style="margin-left:${depth * 4}px">
      <div class="t-label">${escapeHtml(label)}</div>
      <div class="t-sub">${result ? '→ ' + escapeHtml(result) : 'Étape de craft'}</div>
    </div>`;
    const kids = node.children || [];
    if (kids.length) {
      html += `<div class="tree-children">${kids.map((c) => renderTreeNode(c, depth + 1)).join('')}</div>`;
    }
    return html;
  }

  function mountTree(tree) {
    const view = $('#tree-view');
    if (!view) return;
    if (!tree) {
      view.innerHTML = `<div class="empty-state compact"><i class="fa-solid fa-diagram-project"></i><p>Arbre indisponible</p></div>`;
      return;
    }
    view.innerHTML = renderTreeNode(tree);
    view.querySelectorAll('.tree-node[data-tree-id]').forEach((el) => {
      el.addEventListener('click', () => {
        const id = el.getAttribute('data-tree-id');
        if (!id) return;
        const found = state.recipes.find((r) => r.id === id);
        if (found) selectRecipe(found);
      });
    });
  }

  function openTab(name) {
    $$('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === name));
    ['queue', 'tree', 'shop'].forEach((t) => {
      const el = $(`#tab-${t}`);
      if (el) el.classList.toggle('hidden', t !== name);
    });
  }

  // events
  $('#btn-close').addEventListener('click', () => post('close', {}));
  $('#btn-compact').addEventListener('click', () => {
    state.compact = !state.compact;
    app.dataset.compact = state.compact ? '1' : '0';
  });
  $('#search').addEventListener('input', (e) => { state.search = e.target.value; renderList(); });

  $$('.chip').forEach((btn) => {
    btn.addEventListener('click', () => {
      $$('.chip').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.filter = btn.dataset.filter;
      playTick();
      renderList();
    });
  });

  $$('.tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      openTab(btn.dataset.tab);
      playTick();
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
    openTab('queue');
  });
  $('#btn-shop').addEventListener('click', async () => {
    if (!state.selected) return;
    const batch = parseInt($('#batch').value, 10) || 1;
    const data = await post('shopping', { recipeId: state.selected.id, batch });
    state.shop = (data && data.list) || {};
    renderShop();
    openTab('shop');
  });
  $('#btn-shop-clear').addEventListener('click', async () => {
    await post('shoppingClear', {});
    state.shop = {};
    renderShop();
  });
  $('#btn-tree').addEventListener('click', async () => {
    if (!state.selected) return;
    const data = await post('tree', { recipeId: state.selected.id });
    mountTree(data && data.tree);
    openTab('tree');
  });

  const btnPin = $('#btn-pin');
  if (btnPin) btnPin.addEventListener('click', () => {
    if (!state.selected) return;
    post('bookPinRecipe', { recipeId: state.selected }).then((r) => {
      post('notify', { type: r && r.ok ? 'success' : 'error', reason: r && r.ok ? 'book_pinned' : (r && r.reason) || 'craft_failed' });
      beep(r && r.ok ? 'click' : 'error');
    });
  });
  const btnObj = $('#btn-obj');
  if (btnObj) btnObj.addEventListener('click', () => {
    if (!state.selected) return;
    post('bookObjectiveRecipe', { recipeId: state.selected }).then((r) => {
      post('notify', { type: r && r.ok ? 'success' : 'error', reason: r && r.ok ? 'book_objective_added' : (r && r.reason) || 'craft_failed' });
      beep(r && r.ok ? 'click' : 'error');
    });
  });
  const btnBook = $('#btn-book');
  if (btnBook) btnBook.addEventListener('click', () => {
    post('bookOpenFromCraft', { page: 'dashboard' });
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
