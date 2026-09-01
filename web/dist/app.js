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
    sideTab: 'queue',
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

  function recipeCode(r) {
    if (!r) return '';
    const cat = String(r.category || 'GEN').replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase() || 'GEN';
    let n = 0;
    const id = String(r.id || '');
    for (let i = 0; i < id.length; i++) n = (n * 31 + id.charCodeAt(i)) >>> 0;
    const num = String((n % 900) + 100);
    return `${cat}-${num}`;
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
    if (r.canCraft) return { text: 'Conditions remplies', cls: 'ok', tag: 'FAISABLE' };
    if (!r.locked && r.missingItems) return { text: 'Matériaux manquants', cls: 'bad', tag: 'MANQUANT' };
    if (!r.locked) return { text: 'Disponible', cls: 'ok', tag: 'FAISABLE' };
    const fn = LOCK_LABELS[r.lockReason];
    const text = fn ? fn(r) : (r.lockReason ? humanize(r.lockReason) : 'Verrouillé');
    let tag = 'VERROUILLÉ';
    if (r.lockReason === 'craft_blueprint_required') tag = 'PLAN REQUIS';
    else if (r.lockReason === 'craft_level_required' || r.lockReason === 'craft_station_level') tag = 'NIVEAU REQUIS';
    else if (r.lockReason === 'craft_skill_required') tag = 'VERROUILLÉ';
    return { text, cls: 'warn', tag };
  }

  function cardStatus(r) {
    /* Catalogue cards: binary glanceable state only. Details stay in right panel. */
    if (r.canCraft) return { text: 'FAISABLE', cls: 'ok' };
    return { text: 'NON FAISABLE', cls: 'bad' };
  }

  function disableReasons(r) {
    const reasons = [];
    if (!r) return ['Sélectionnez une recette'];
    if (state.crafting) reasons.push('Fabrication en cours…');
    if (r.locked) reasons.push(lockText(r).text);
    if (r.missingItems) reasons.push('Matériaux insuffisants pour fabriquer');
    if (!r.canCraft && !r.locked && !r.missingItems) reasons.push('Conditions non remplies');
    return reasons;
  }

  function durationLabel(ms) {
    const s = Math.round((ms || 0) / 1000);
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return rem ? `${m}m ${rem}s` : `${m}m`;
  }

  function qualityHint(r) {
    if (!state.flags.quality) return null;
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

  function setEmpty(el, show) {
    if (el) el.classList.toggle('hidden', !show);
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

  function ingOwnedRequired(ing, r) {
    const need = ing.count || 1;
    const owned = typeof ing.owned === 'number' ? ing.owned : null;
    if (owned == null) {
      if (r.canCraft) return { text: `${need}/${need}`, cls: 'ok', mark: '✓' };
      if (r.missingItems && !r.locked) return { text: `?/${need}`, cls: 'bad', mark: '✕' };
      return { text: `×${need}`, cls: '', mark: '·' };
    }
    const ok = owned >= need;
    return {
      text: `${owned}/${need}`,
      cls: ok ? 'ok' : 'bad',
      mark: ok ? '✓' : '✕',
    };
  }

  function renderList() {
    const grid = $('#recipe-grid');
    const empty = $('#recipe-empty');
    const countEl = $('#recipe-count');
    if (!grid) return;
    grid.innerHTML = '';
    const list = filteredRecipes();
    if (countEl) countEl.textContent = `${list.length} / ${state.recipes.length}`;
    setEmpty(empty, list.length === 0);

    list.forEach((r) => {
      const card = document.createElement('article');
      card.className = 'recipe-card';
      if (r.locked) card.classList.add('locked');
      if (state.selected && state.selected.id === r.id) card.classList.add('selected');
      card.dataset.id = r.id;

      const favOn = isFavorite(r.id);
      const status = cardStatus(r);
      card.classList.add(`state-${status.cls || 'bad'}`);
      if (r.rarity) {
        const rk = String(r.rarity).toLowerCase().replace(/[^a-z0-9]+/g, '-');
        if (rk) card.classList.add(`rarity-${rk}`);
      }
      if (r.category) {
        const ck = String(r.category).toLowerCase().replace(/[^a-z0-9]+/g, '-');
        if (ck) {
          card.classList.add(`cat-${ck}`);
          card.dataset.cat = ck;
        }
      }
      const resultItem = (r.result && r.result.item) || r.id;
      const code = recipeCode(r);

      card.innerHTML = `
        <button type="button" class="card-fav${favOn ? ' on' : ''}" data-fav="${escapeHtml(r.id)}" title="Favori" aria-label="Favori">
          <i class="fa-${favOn ? 'solid' : 'regular'} fa-star" aria-hidden="true"></i>
        </button>
        <div class="card-img-zone" aria-hidden="true">
          <span class="ph"><i class="fa-solid fa-cube"></i></span>
          <img alt="" />
        </div>
        <div class="card-body">
          <div class="card-identity">
            <div class="card-title">${escapeHtml(r.label)}</div>
            <div class="card-meta-line">
              <span class="card-cat">${escapeHtml(categoryLabel(r.category))}</span>
              <span class="card-code">${escapeHtml(code)}</span>
            </div>
          </div>
          <div class="card-status-row">
            <span class="status-plate status-pill ${status.cls}">${status.text}</span>
          </div>
        </div>
      `;

      const img = card.querySelector('.card-img-zone img');
      const ph = card.querySelector('.card-img-zone .ph');
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

  function toggleRow(el, show) {
    if (!el) return;
    el.classList.toggle('hidden', !show);
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
    const codeEl = $('#d-code');
    if (codeEl) codeEl.textContent = recipeCode(r);

    const rarityEl = $('#d-rarity');
    if (r.rarity) {
      rarityEl.classList.remove('hidden');
      rarityEl.textContent = humanize(r.rarity);
    } else {
      rarityEl.classList.add('hidden');
      rarityEl.textContent = '';
    }

    const desc = r.description
      || r.desc
      || r.itemDescription
      || (r.result && (r.result.description || r.result.desc))
      || (r.tags && r.tags.length ? r.tags.map(humanize).join(' · ') : '')
      || `Composant documenté pour atelier. Assemblage « ${r.label} » — procédure reconstruite et maintenue.`;
    const descEl = $('#d-desc');
    if (descEl) {
      descEl.textContent = desc;
      descEl.style.display = '';
    }

    const lock = lockText(r);
    const locksEl = $('#d-locks');
    locksEl.textContent = lock.tag || lock.text;
    locksEl.title = lock.text;
    locksEl.className = `status-tag ${lock.cls}`;

    const qh = qualityHint(r);
    $('#d-quality').textContent = qh || '—';
    const resCount = (r.result && r.result.count) || 1;
    const resItem = (r.result && r.result.item) || '—';
    $('#d-result').textContent = `${resCount}× ${resItem}`;
    $('#d-duration').textContent = durationLabel(r.duration);
    $('#d-qty').textContent = `×${resCount}`;

    // —— Skill (ml_skills payload only) ——
    const skillBlock = $('#block-skill');
    const skillName = r.skillCategory || (r.xp && r.xp.category) || null;
    const reqLvl = r.requireLevel;
    let curLvl = typeof r.playerSkillLevel === 'number' ? r.playerSkillLevel : null;
    if (curLvl == null && r.lockReason === 'craft_level_required' && r.lockArgs && r.lockArgs[1] != null) {
      curLvl = r.lockArgs[1];
    }
    const hasSkillInfo = !!(skillName || reqLvl != null || curLvl != null);
    toggleRow(skillBlock, hasSkillInfo);
    if (hasSkillInfo) {
      $('#d-skill').textContent = skillName ? humanize(skillName) : 'Compétence';
      if (reqLvl != null && curLvl != null) {
        $('#d-skill-level').textContent = `${curLvl} / ${reqLvl}`;
      } else if (reqLvl != null) {
        $('#d-skill-level').textContent = `requis ${reqLvl}`;
      } else if (curLvl != null) {
        $('#d-skill-level').textContent = `niv. ${curLvl}`;
      } else {
        $('#d-skill-level').textContent = 'Aucun niveau requis';
      }
      const barWrap = $('#d-skill-bar-wrap');
      const fill = $('#d-skill-fill');
      const barLabel = $('#d-skill-bar-label');
      if (reqLvl != null && curLvl != null) {
        barWrap.classList.remove('hidden');
        const pct = Math.max(0, Math.min(100, Math.round((curLvl / Math.max(1, reqLvl)) * 100)));
        fill.style.width = `${pct}%`;
        if (curLvl >= reqLvl) {
          barLabel.textContent = 'Niveau requis atteint';
        } else {
          barLabel.textContent = `Progression vers niv. ${reqLvl}`;
        }
      } else if (curLvl != null) {
        barWrap.classList.remove('hidden');
        fill.style.width = `${Math.min(100, (curLvl % 10) * 10)}%`;
        barLabel.textContent = `Niveau actuel ${curLvl}`;
      } else {
        barWrap.classList.add('hidden');
      }
    }

    // —— Specialization ——
    const specBlock = $('#block-spec');
    if (r.requireSkill) {
      specBlock.classList.remove('hidden');
      $('#d-spec-need').textContent = humanize(r.requireSkill);
      const yours = $('#d-spec-yours');
      const has = r.hasSpecialization;
      if (has === true) {
        yours.textContent = '✓ Vôtre';
        yours.className = 'spec-yours ok';
      } else if (has === false) {
        yours.textContent = '✕ Manquante';
        yours.className = 'spec-yours bad';
      } else if (r.lockReason === 'craft_skill_required') {
        yours.textContent = '✕ Manquante';
        yours.className = 'spec-yours bad';
      } else if (!r.locked) {
        yours.textContent = '✓ Vôtre';
        yours.className = 'spec-yours ok';
      } else {
        yours.textContent = '—';
        yours.className = 'spec-yours';
      }
    } else {
      specBlock.classList.add('hidden');
    }

    // —— Station ——
    const stationBlock = $('#block-station');
    const stationName = r.station ? humanize(r.station) : (state.menuMeta.label || null);
    const stationLvl = r.stationLevel;
    const showStation = !!(stationName || stationLvl != null);
    toggleRow(stationBlock, showStation);
    if (showStation) {
      const rowS = $('#row-station');
      const rowL = $('#row-station-lvl');
      if (stationName) {
        rowS.classList.remove('hidden');
        $('#d-station').textContent = stationName;
      } else {
        rowS.classList.add('hidden');
      }
      if (stationLvl != null) {
        rowL.classList.remove('hidden');
        $('#d-station-lvl').textContent = String(stationLvl);
      } else {
        rowL.classList.add('hidden');
      }
    }

    // —— Materials ——
    const ings = $('#d-ings');
    ings.innerHTML = '';
    (r.ingredients || []).forEach((ing) => {
      const li = document.createElement('li');
      const info = ingOwnedRequired(ing, r);
      li.innerHTML = `
        <img class="ing-thumb" alt="" />
        <span class="mark ${info.cls}">${info.mark}</span>
        <span class="iname">${escapeHtml(humanize(ing.item))}</span>
        <span class="icount ${info.cls}">${escapeHtml(info.text)}</span>
      `;
      bindItemImg(li.querySelector('img'), ing.item, null);
      ings.appendChild(li);
    });
    if (!(r.ingredients || []).length) {
      ings.innerHTML = '<li><span class="iname muted">Aucun matériau</span></li>';
    }

    // —— Tools ——
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
          <span class="iname">${escapeHtml(humanize(t.item))}</span>
          <span class="icount">×${escapeHtml(t.count || 1)}</span>
          <span class="wear-bar" aria-hidden="true"><i></i></span>
        `;
        bindItemImg(li.querySelector('img'), t.item, null);
        toolsUl.appendChild(li);
      });
    }

    // —— Power / noise ——
    const power = r.powerCost;
    const noise = r.noiseLevel;
    const pnBlock = $('#block-power-noise');
    const hasPower = power != null;
    const hasNoise = noise != null;
    toggleRow(pnBlock, hasPower || hasNoise);
    if (hasPower || hasNoise) {
      toggleRow($('#power-wrap'), hasPower);
      toggleRow($('#noise-wrap'), hasNoise);
      if (hasPower) {
        $('#d-power').textContent = String(power);
        const bar = $('#d-power-bar');
        if (bar) {
          const pct = Math.max(8, Math.min(100, Number(power) * 10));
          bar.style.width = `${pct}%`;
        }
      }
      if (hasNoise) $('#d-noise').textContent = String(noise);
    }

    // —— Blueprint ——
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

    // —— XP / mastery ——
    const xpBlock = $('#block-xp');
    const hasXp = !!r.xp;
    const hasMastery = !!state.flags.mastery;
    toggleRow(xpBlock, hasXp || hasMastery);
    if (hasXp || hasMastery) {
      const rowXp = $('#row-xp');
      const rowMa = $('#row-mastery');
      if (hasXp) {
        rowXp.classList.remove('hidden');
        $('#d-xp').textContent = `+${r.xp.amount} (${humanize(r.xp.category)})`;
      } else {
        rowXp.classList.add('hidden');
      }
      if (hasMastery) {
        rowMa.classList.remove('hidden');
        $('#d-mastery').textContent = String(r.mastery || 0);
      } else {
        rowMa.classList.add('hidden');
      }
    }

    // —— FABRIQUER ——
    const can = !!r.canCraft && !state.crafting;
    const craftBtn = $('#btn-craft');
    craftBtn.disabled = !can;
    const reasons = disableReasons(r);
    const whyEl = $('#craft-why');
    if (!can && reasons.length) {
      whyEl.textContent = reasons[0];
      whyEl.classList.remove('hidden');
      craftBtn.title = reasons.length > 1 ? reasons.join(' · ') : reasons[0];
    } else {
      whyEl.classList.add('hidden');
      craftBtn.title = can ? 'Lancer la fabrication' : '';
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
    const title = data.label || 'Atelier';
    $('#station-title').textContent = title;
    const powered = data.powered !== false;
    const lvl = data.stationLevel || 1;
    const catLabel = categoryLabel(data.category);
    const stencil = $('#station-stencil');
    if (stencil) {
      const code = String(data.benchKey || data.category || '03').replace(/[^a-zA-Z0-9]/g, '').slice(-2).toUpperCase() || '03';
      stencil.textContent = `STATION ${code} · ${catLabel}`;
    }
    const metaBits = [];
    if (data.category) metaBits.push(catLabel);
    metaBits.push(`niveau ${lvl}`);
    if (!powered) metaBits.push('hors tension');
    $('#station-meta').textContent = metaBits.join(' · ');

    const typeEl = $('#stat-type');
    const plateType = $('#plate-type');
    if (data.category) {
      typeEl.textContent = catLabel;
      if (plateType) plateType.classList.remove('hidden');
    } else if (plateType) {
      plateType.classList.add('hidden');
    }

    $('#stat-level').textContent = String(lvl);

    const stateEl = $('#stat-state');
    const gaugeState = $('#gauge-state');
    const ledState = $('#led-state');
    let statePct = 72;
    let stateCls = 'ok';
    let stateLabel = 'OPÉRATIONNEL';

    if (data.condition != null || data.etat != null) {
      const raw = data.condition != null ? data.condition : data.etat;
      const n = Number(raw);
      if (!Number.isNaN(n)) {
        statePct = Math.max(5, Math.min(100, n > 1 ? n : n * 100));
        if (statePct >= 60) { stateCls = 'ok'; stateLabel = 'OPÉRATIONNEL'; }
        else if (statePct >= 30) { stateCls = 'warn'; stateLabel = 'DÉGRADÉ'; }
        else { stateCls = 'bad'; stateLabel = 'HORS SERVICE'; }
      } else {
        const s = String(raw).toLowerCase();
        if (/hors|off|down|critique|fail/.test(s)) { stateCls = 'bad'; stateLabel = 'HORS SERVICE'; statePct = 12; }
        else if (/dégrad|degrad|warn|moyen/.test(s)) { stateCls = 'warn'; stateLabel = 'DÉGRADÉ'; statePct = 45; }
        else { stateCls = 'ok'; stateLabel = 'OPÉRATIONNEL'; statePct = 88; }
      }
    } else if (!powered) {
      stateCls = 'bad'; stateLabel = 'HORS SERVICE'; statePct = 12;
    } else {
      stateCls = 'ok'; stateLabel = 'OPÉRATIONNEL'; statePct = 88;
    }
    stateEl.textContent = stateLabel;
    stateEl.className = `t-l5 ${stateCls}`;
    if (ledState) ledState.className = `led-dot ${stateCls}`;
    if (gaugeState) gaugeState.style.width = `${statePct}%`;

    const mods = data.modules || {};
    const modCount = Array.isArray(mods) ? mods.length : Object.keys(mods).length;
    const eff = data.efficiency != null ? data.efficiency : (100 + modCount * 5);
    const effEl = $('#stat-eff');
    const gaugeEff = $('#gauge-eff');
    const plateEff = $('#plate-eff');
    if (eff != null && String(eff) !== '—' && String(eff) !== '') {
      const effNum = typeof eff === 'number' ? eff : Number(eff);
      effEl.textContent = typeof eff === 'number' || !Number.isNaN(effNum) ? `${Number.isNaN(effNum) ? eff : effNum}%` : String(eff);
      if (plateEff) plateEff.classList.remove('hidden');
      if (gaugeEff && !Number.isNaN(effNum)) {
        gaugeEff.style.width = `${Math.max(5, Math.min(100, effNum))}%`;
      }
    } else if (plateEff) {
      plateEff.classList.add('hidden');
    }

    const energyWrap = $('#stat-energy-wrap');
    const led = $('#led-power');
    const gaugeEnergy = $('#gauge-energy');
    if (data.energy != null || data.power != null) {
      energyWrap.classList.remove('hidden');
      const val = data.energy != null ? data.energy : data.power;
      $('#stat-energy').textContent = String(val);
      const n = Number(val);
      const pct = !Number.isNaN(n) ? Math.max(5, Math.min(100, n > 1 ? n : n * 100)) : (powered ? 80 : 10);
      if (gaugeEnergy) gaugeEnergy.style.width = `${pct}%`;
      if (led) {
        led.classList.toggle('on', powered);
        led.classList.toggle('off', !powered);
      }
    } else if (data.powered != null) {
      energyWrap.classList.remove('hidden');
      $('#stat-energy').textContent = data.powered ? 'OK' : 'Off';
      $('#stat-energy').className = `t-l5 ${data.powered ? 'ok' : 'bad'}`;
      if (gaugeEnergy) gaugeEnergy.style.width = data.powered ? '90%' : '8%';
      if (led) {
        led.classList.toggle('on', !!data.powered);
        led.classList.toggle('off', !data.powered);
      }
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
    setEmpty(empty, !has);
    (state.queue || []).forEach((e) => {
      const now = Math.floor(Date.now() / 1000);
      const finishAt = e.finishAt || 0;
      const startAt = e.startAt || (finishAt - Math.round((e.duration || 0) / 1000));
      const left = Math.max(0, finishAt - now);
      const total = Math.max(1, finishAt - startAt);
      const done = finishAt ? Math.min(1, Math.max(0, 1 - left / total)) : (left <= 0 ? 1 : 0);
      const qty = e.batch || e.count || e.qty || 1;
      const card = document.createElement('div');
      card.className = `queue-card${left <= 0 ? ' ready' : ''}`;
      const eta = left > 0 ? `ETA ${left}s` : 'PRÊT';
      card.innerHTML = `
        <div class="qlabel">${escapeHtml(e.label || e.recipeId)}</div>
        <div class="qmeta"><span>Lot ×${escapeHtml(qty)} · ${Math.round(done * 100)}%</span><span>${eta}</span></div>
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
    setEmpty(empty, entries.length === 0);
    entries.forEach(([item, count]) => {
      const li = document.createElement('li');
      const need = typeof count === 'object' && count != null
        ? (count.need || count.count || count.required || 1)
        : count;
      const owned = typeof count === 'object' && count != null && typeof count.owned === 'number'
        ? count.owned
        : null;
      const ownedTxt = owned != null ? `${owned}/${need}` : `×${need}`;
      const miss = owned != null ? owned < need : true;
      li.innerHTML = `
        <span class="check-mark" aria-hidden="true"><i class="fa-${miss ? 'regular fa-square' : 'solid fa-square-check'}"></i></span>
        <img class="ing-thumb" alt="" />
        <span class="iname">${escapeHtml(humanize(item))}</span>
        <span class="shop-need${miss ? '' : ' ok'}">${escapeHtml(ownedTxt)}</span>
        <button type="button" class="pin" title="Épingler au carnet" data-pin-item="${escapeHtml(item)}">
          <i class="fa-solid fa-thumbtack"></i>
        </button>
      `;
      bindItemImg(li.querySelector('img'), item, null);
      const pin = li.querySelector('[data-pin-item]');
      if (pin) {
        pin.addEventListener('click', () => {
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
      return `<div class="tree-node raw">
        <div class="t-label">${escapeHtml(humanize(node.item))} ×${escapeHtml(node.count)}</div>
        <div class="t-sub">Ressource · brute</div>
      </div>`;
    }
    const rid = node.recipeId || node.id || '';
    const label = node.label || rid || 'Recette';
    const result = node.result && node.result.item ? `${node.result.item}` : '';
    let html = `<div class="tree-node" data-tree-id="${escapeHtml(rid)}">
      <div class="t-label">${escapeHtml(label)}</div>
      <div class="t-sub">${result ? 'Nœud · ' + escapeHtml(humanize(result)) : 'Nœud de fabrication'}</div>
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
      view.innerHTML = `<div class="empty-state compact"><span class="empty-ico" aria-hidden="true"><i class="fa-solid fa-diagram-project"></i></span><span class="empty-kicker">Schéma technique</span><p>Plan indisponible</p><span class="empty-hint">Aucune dépendance documentée pour cette recette</span></div>`;
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
    state.sideTab = name;
    if (app) app.dataset.side = name || '';
    $$('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === name));
    ['queue', 'tree', 'shop'].forEach((t) => {
      const el = $(`#tab-${t}`);
      if (el) el.classList.toggle('hidden', t !== name);
    });
  }

  // events — null-safe so a missing craft control never kills the NUI page (book.js needs the page alive)
  const bindUi = (id, ev, fn) => { const el = $(id); if (el) el.addEventListener(ev, fn); };
  bindUi('#btn-close', 'click', () => post('close', {}));
  bindUi('#btn-compact', 'click', () => {
    state.compact = !state.compact;
    app.dataset.compact = state.compact ? '1' : '0';
  });
  bindUi('#search', 'input', (e) => { state.search = e.target.value; renderList(); });

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

  bindUi('#btn-craft', 'click', startCraft);
  bindUi('#btn-cancel', 'click', cancelCraft);
  bindUi('#btn-fav', 'click', async () => {
    if (!state.selected) return;
    await post('favorite', { recipeId: state.selected.id });
    await refresh();
  });
  bindUi('#btn-queue', 'click', async () => {
    if (!state.selected) return;
    const batchEl = $('#batch');
    const batch = parseInt(batchEl && batchEl.value, 10) || 1;
    await post('queue', { recipeId: state.selected.id, benchKey: state.benchKey, batch });
    await loadQueue();
    openTab('queue');
  });
  bindUi('#btn-shop', 'click', async () => {
    if (!state.selected) return;
    const batchEl = $('#batch');
    const batch = parseInt(batchEl && batchEl.value, 10) || 1;
    const data = await post('shopping', { recipeId: state.selected.id, batch });
    state.shop = (data && data.list) || {};
    renderShop();
    openTab('shop');
  });
  bindUi('#btn-shop-clear', 'click', async () => {
    await post('shoppingClear', {});
    state.shop = {};
    renderShop();
  });
  bindUi('#btn-tree', 'click', async () => {
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
      openTab(state.sideTab || 'queue');
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
    // Only close craft when craft shell is visible — never steal Escape from the Survival Book
    if (e.key === 'Escape' && app && !app.classList.contains('hidden')) post('close', {});
  });
})();
