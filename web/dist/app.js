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
    pinned: [],
    selected: null,
    filter: 'all',
    category: 'all',
    search: '',
    compact: false,
    crafting: false,
    craftId: null,
    session: null,
    progressGen: 0,
    craftDurationMs: null,
    queue: [],
    shop: {},
    flags: {},
    ux: {},
    compare: { enabled: false, map: {} },
    queueMax: 5,
    lastCraft: null,
    menuMeta: {},
    itemLabels: {},
    sounds: { Enabled: true, Volume: 0.35, Files: {} },
    audioCtx: null,
    sideTab: 'queue',
    searchIndex: {},
    sort: 'name',
    rarityFilter: 'all',
    playerSpec: null,
    recentlyCrafted: [],
    newlyLearned: [],
    teaching: {},
    teachTarget: null,
  };

  const SEEN_KEY = 'sanctuary_crafting:seenRecipes';
  const LAST_CRAFT_KEY = 'sanctuary_crafting:lastCraft';

  function loadSeenRecipes() {
    try {
      const raw = localStorage.getItem(SEEN_KEY);
      const arr = raw ? JSON.parse(raw) : [];
      return new Set(Array.isArray(arr) ? arr : []);
    } catch (_) {
      return new Set();
    }
  }

  function saveSeenRecipes(set) {
    try {
      localStorage.setItem(SEEN_KEY, JSON.stringify(Array.from(set)));
    } catch (_) { /* ignore */ }
  }

  let seenRecipes = loadSeenRecipes();

  function uxOn(key, fallback = true) {
    if (state.flags && state.flags[key] != null) return !!state.flags[key];
    if (state.ux && state.ux[key] != null) return !!state.ux[key];
    /* PascalCase mirror from Config.UI.Ux */
    const pascal = key.charAt(0).toUpperCase() + key.slice(1);
    if (state.ux && state.ux[pascal] != null) return !!state.ux[pascal];
    return fallback;
  }

  function isPinned(id) {
    return (state.pinned || []).includes(id);
  }

  function showToast(message, kind) {
    if (!uxOn('microToasts', true) && !uxOn('MicroToasts', true)) return;
    if (state.flags && state.flags.microToasts === false) return;
    const host = $('#craft-toasts');
    if (!host || !message) return;
    const el = document.createElement('div');
    el.className = `craft-toast ${kind || ''}`.trim();
    el.textContent = message;
    host.appendChild(el);
    setTimeout(() => {
      el.classList.add('out');
      setTimeout(() => el.remove(), 180);
    }, 2200);
  }

  function markRecipeSeen(id) {
    if (!id) return;
    if (seenRecipes.has(id)) return;
    seenRecipes.add(id);
    saveSeenRecipes(seenRecipes);
  }

  function recipeMarkedNew(r) {
    if (!r) return false;
    if (r.isNew || r.newlyUnlocked) return true;
    const tags = r.tags || [];
    return tags.includes('new') || tags.includes('nouveau') || tags.includes('newlyUnlocked') || tags.includes('newly_unlocked');
  }

  function compareTargetFor(r) {
    if (!r) return null;
    const enabled = !!(state.compare && state.compare.enabled) || uxOn('compare', false);
    if (!enabled) return null;
    if (r.compareWith) return r.compareWith;
    if (r.relatedRecipeId) return r.relatedRecipeId;
    const map = (state.compare && state.compare.map) || {};
    if (map[r.id]) return map[r.id];
    return null;
  }

  function masteryDots(value) {
    const v = Math.max(0, Math.min(100, Number(value) || 0));
    if (v <= 0) return 0;
    if (v < 34) return 1;
    if (v < 67) return 2;
    return 3;
  }

  function primaryBadgeReason(r) {
    if (!r) return '';
    if (r.canCraft) return 'Conditions remplies';
    if (r.primaryMissing && r.primaryMissing.item) {
      const pm = r.primaryMissing;
      return `${humanize(pm.item)} ${pm.owned || 0}/${pm.count || 1}`;
    }
    const ings = r.ingredients || [];
    const miss = ings.find((ing) => {
      if (typeof ing.owned !== 'number') return false;
      return ing.owned < (ing.count || 1);
    });
    if (miss) return `${humanize(miss.item)} ${miss.owned}/${miss.count || 1}`;
    if (r.lockReason === 'craft_blueprint_required') {
      const bp = (r.lockArgs && r.lockArgs[0]) || r.requireBlueprint;
      return bp ? `Plan requis : ${humanize(bp)}` : 'Plan requis';
    }
    if (r.lockReason === 'craft_level_required') {
      const need = (r.lockArgs && r.lockArgs[0]) || r.requireLevel;
      const cur = (r.lockArgs && r.lockArgs[1]) != null ? r.lockArgs[1] : r.playerSkillLevel;
      if (need != null && cur != null) return `Niveau ${need} requis (actuel : ${cur})`;
      if (need != null) return `Niveau ${need} requis`;
      return 'Niveau requis';
    }
    if (r.lockReason === 'craft_station_level') {
      const need = r.stationLevel;
      const cur = state.menuMeta && state.menuMeta.stationLevel;
      if (need != null && cur != null) return `Atelier niveau ${need} (actuel : ${cur})`;
      return need ? `Atelier niveau ${need} requis` : 'Niveau d\'atelier insuffisant';
    }
    if (r.toolDurability != null && r.toolDurability <= 15) {
      return `Outil usé (${r.toolDurability}%)`;
    }
    const lt = lockText(r);
    return lt.text || 'Non faisable';
  }

  function computeAlmost(r) {
    if (!r || r.canCraft) return false;
    if (r.almostCraftable === true) return true;
    let missing = typeof r.missingCount === 'number' ? r.missingCount : null;
    if (missing == null && Array.isArray(r.ingredients)) {
      missing = r.ingredients.filter((ing) => typeof ing.owned === 'number' && ing.owned < (ing.count || 1)).length;
    }
    if (!r.locked && missing === 1) return true;
    if (typeof r.levelGap === 'number' && r.levelGap > 0 && r.levelGap <= 2) return true;
    if (r.lockReason === 'craft_level_required') {
      const need = (r.lockArgs && r.lockArgs[0]) || r.requireLevel;
      const cur = (r.lockArgs && r.lockArgs[1]) != null ? r.lockArgs[1] : r.playerSkillLevel;
      if (need != null && cur != null) {
        const gap = need - cur;
        if (gap > 0 && gap <= 2) return true;
      }
    }
    if (r.lockReason === 'craft_station_level' && r.stationLevel != null && state.menuMeta && state.menuMeta.stationLevel != null) {
      const gap = r.stationLevel - state.menuMeta.stationLevel;
      if (gap > 0 && gap <= 2) return true;
    }
    if (r.toolDurability != null && r.toolDurability > 0 && r.toolDurability <= 15) return true;
    return false;
  }

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


  const RARITY_NORM = {
    common: 'common', commun: 'common', normale: 'common', normal: 'common', standard: 'common',
    uncommon: 'uncommon', 'peu-commun': 'uncommon', peucommun: 'uncommon', 'peu_commun': 'uncommon',
    rare: 'rare',
    epic: 'epic', epique: 'epic', épique: 'epic',
    legendary: 'legendary', legendaire: 'legendary', légendaire: 'legendary', mythic: 'legendary', mythique: 'legendary',
  };
  const RARITY_LABEL = {
    common: 'COMMUN',
    uncommon: 'PEU COMMUN',
    rare: 'RARE',
    epic: 'ÉPIQUE',
    legendary: 'LÉGENDAIRE',
  };
  const RARITY_ICON = {
    common: 'fa-circle',
    uncommon: 'fa-leaf',
    rare: 'fa-gem',
    epic: 'fa-crown',
    legendary: 'fa-star',
  };

  function rarityKey(raw) {
    if (!raw) return '';
    const k = String(raw).toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    if (RARITY_NORM[k]) return RARITY_NORM[k];
    if (RARITY_NORM[k.replace(/-/g, '')]) return RARITY_NORM[k.replace(/-/g, '')];
    return k;
  }

  function rarityLabel(raw) {
    const k = rarityKey(raw);
    return RARITY_LABEL[k] || String(humanize(raw) || raw).toUpperCase();
  }

  function humanize(id) {
    if (!id) return '—';
    return String(id).replace(/[_-]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }


  function looksLikeItemId(s) {
    return typeof s === 'string' && /^[a-z0-9_]+$/.test(s) && !/\s/.test(s);
  }

  function itemDisplayName(id, fallback) {
    if (fallback && !looksLikeItemId(fallback)) return fallback;
    if (id && state.itemLabels && state.itemLabels[id]) return state.itemLabels[id];
    if (fallback) return fallback;
    if (id && state.itemLabels && state.itemLabels[id]) return state.itemLabels[id];
    return humanize(id);
  }

  function recipeDescription(r) {
    if (!r) return 'Aucune description disponible.';
    const raw = r.descriptionOverride
      || r.description
      || r.desc
      || r.itemDescription
      || (r.result && (r.result.description || r.result.desc));
    if (raw == null) return 'Aucune description disponible.';
    const s = String(raw).trim();
    if (!s || s === 'null' || s === 'undefined' || s === 'nil') return 'Aucune description disponible.';
    if (/^Composant documenté/.test(s)) return 'Aucune description disponible.';
    return s;
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
    if (!r) return false;
    if (r.unread) return true;
    if ((state.newlyLearned || []).includes(r.id)) return true;
    return recipeMarkedNew(r) && !seenRecipes.has(r.id);
  }

  function buildRecipeHaystack(r) {
    const parts = [
      r.label, r.id, r.category, r.description, r.desc,
      r.station, r.skillCategory,
      (r.tags || []).join(' '),
    ];
    (r.ingredients || []).forEach((ing) => {
      parts.push(ing.item, ing.label);
    });
    if (r.result) {
      parts.push(r.result.item, r.result.label);
    }
    if (r.blueprintId || r.requireBlueprint) {
      parts.push(r.blueprintId || r.requireBlueprint);
    }
    if (r.knowledge) parts.push(r.knowledge);
    return parts.filter(Boolean).join(' ').toLowerCase();
  }

  function rebuildSearchIndex(recipes) {
    const idx = {};
    (recipes || []).forEach((r) => {
      if (!r || !r.id) return;
      idx[r.id] = buildRecipeHaystack(r);
    });
    state.searchIndex = idx;
  }

  function matchesFilter(r) {
    if (state.category && state.category !== 'all' && r.category !== state.category) return false;
    if (state.filter === 'craftable' && !r.canCraft) return false;
    if (state.filter === 'almost') {
      if (r.canCraft || !uxOn('almostCraftable', true) || !computeAlmost(r)) return false;
    }
    if (state.filter === 'locked' && !r.locked) return false;
    if (state.filter === 'favorites' && !isFavorite(r.id)) return false;
    if (state.filter === 'new' && !isNewRecipe(r)) return false;
    if (state.filter === 'plans' && !hasKnownPlan(r)) return false;
    if (state.rarityFilter && state.rarityFilter !== 'all') {
      const rk = rarityKey(r.rarity);
      if (rk !== state.rarityFilter) return false;
    }
    if (state.search) {
      const q = state.search.toLowerCase().trim();
      if (q) {
        if (uxOn('smartSearch', true)) {
          const hay = (state.searchIndex && state.searchIndex[r.id]) || buildRecipeHaystack(r);
          if (!hay.includes(q)) return false;
        } else {
          const tags = (r.tags || []).join(' ');
          const hay = `${r.label} ${r.id} ${tags} ${r.category || ''} ${r.result && r.result.item || ''}`.toLowerCase();
          if (!hay.includes(q)) return false;
        }
      }
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
    craft_spec_required: (r) => {
      const sp = (r.lockArgs && r.lockArgs[0]) || r.requireSpec;
      return sp ? `Spécialisation requise : ${humanize(sp)}` : 'Spécialisation requise';
    },
    craft_knowledge_required: () => 'Recette non connue',
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


  function knowledgeMarkHtml(kn) {
    if (!kn || kn === 'learned') return '';
    const map = {
      unknown: { ico: 'fa-question', title: 'Inconnu — silhouette seulement' },
      partial: { ico: 'fa-eye-low-vision', title: 'Connaissance partielle — détails incomplets' },
      blueprint: { ico: 'fa-drafting-compass', title: 'Appris via blueprint / plan technique' },
      mastered: { ico: 'fa-certificate', title: 'Recette maîtrisée (expérience sur cette fabrication)' },
    };
    const m = map[kn];
    if (!m) return '';
    return `<span class="card-knowledge-mark kn-${kn}" title="${m.title}"><i class="fa-solid ${m.ico}" aria-hidden="true"></i></span>`;
  }

  function cardStatus(r) {
    if (r.canCraft) {
      const bits = ['Prêt à fabriquer'];
      if (r.duration) bits.push(`Durée ${durationLabel(r.duration)}`);
      if (r.xpReward || r.xp) bits.push(`XP ${r.xpReward || r.xp}`);
      return { text: 'FAISABLE', cls: 'ok', tip: bits.join(' · ') };
    }
    const almostEnabled = uxOn('almostCraftable', true);
    const reason = primaryBadgeReason(r);
    if (almostEnabled && computeAlmost(r)) {
      return { text: 'PRESQUE', cls: 'almost', tip: reason ? `Presque — ${reason}` : 'Une seule condition mineure manque' };
    }
    return { text: 'NON FAISABLE', cls: 'bad', tip: reason || 'Conditions non remplies' };
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

  const RARITY_RANK = { common: 1, uncommon: 2, rare: 3, epic: 4, legendary: 5 };

  function feasibilityRank(r) {
    if (r.canCraft) return 0;
    if (uxOn('almostCraftable', true) && computeAlmost(r)) return 1;
    if (r.locked) return 3;
    return 2;
  }

  function sortedRecipes(list) {
    const arr = list.slice();
    const mode = state.sort || 'name';
    arr.sort((a, b) => {
      if (mode === 'feasibility') {
        const d = feasibilityRank(a) - feasibilityRank(b);
        if (d) return d;
      } else if (mode === 'rarity') {
        const d = (RARITY_RANK[rarityKey(b.rarity)] || 0) - (RARITY_RANK[rarityKey(a.rarity)] || 0);
        if (d) return d;
      } else if (mode === 'duration') {
        const d = (a.duration || 0) - (b.duration || 0);
        if (d) return d;
      } else if (mode === 'mastery') {
        const d = (b.mastery || 0) - (a.mastery || 0);
        if (d) return d;
      }
      return String(a.label || a.id || '').localeCompare(String(b.label || b.id || ''), 'fr', { sensitivity: 'base' });
    });
    return arr;
  }

  function filteredRecipes() {
    return sortedRecipes(state.recipes.filter(matchesFilter));
  }

  function setEmpty(el, show) {
    if (el) el.classList.toggle('hidden', !show);
  }

  function categoryIcon(cat) {
    const map = {
      all: 'fa-layer-group',
      scrap: 'fa-recycle',
      medical: 'fa-kit-medical',
      weapons: 'fa-gun',
      survival: 'fa-campground',
      survie: 'fa-campground',
      mechanic: 'fa-wrench',
      mecano: 'fa-wrench',
      ingenieur: 'fa-gears',
      tailleur: 'fa-scissors',
      boucherie: 'fa-drumstick-bite',
      forgeron: 'fa-hammer',
      manche_forgeron: 'fa-hammer',
      fonderie_forgeron: 'fa-fire',
      reparation_forgeron: 'fa-screwdriver-wrench',
      agriculture: 'fa-seedling',
      schema: 'fa-drafting-compass',
      accessoires: 'fa-puzzle-piece',
      decoration: 'fa-couch',
      munition: 'fa-bullseye',
      cuisine: 'fa-utensils',
      construction: 'fa-helmet-safety',
      armurier: 'fa-shield-halved',
    };
    return map[String(cat || '').toLowerCase()] || 'fa-tag';
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
      <i class="fa-solid ${categoryIcon('all')}" aria-hidden="true"></i>
      <span>Toutes</span><span class="count">${total}</span>
    </button>`;
    cats.forEach((c) => {
      html += `<button type="button" class="cat-item${state.category === c ? ' active' : ''}" data-cat="${escapeHtml(c)}">
        <i class="fa-solid ${categoryIcon(c)}" aria-hidden="true"></i>
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

    const makeCard = (r) => {
      const card = document.createElement('article');
      card.className = 'recipe-card';
      if (r.locked) card.classList.add('locked');
      if (state.selected && state.selected.id === r.id) card.classList.add('selected');
      card.dataset.id = r.id;

      const favOn = isFavorite(r.id);
      const status = cardStatus(r);
      card.classList.add(`state-${status.cls || 'bad'}`);
      if (r.rarity) {
        const rk = rarityKey(r.rarity);
        if (rk) {
          card.classList.add(`rarity-${rk}`);
          card.dataset.rarity = rk;
        }
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
      const showNouveau = uxOn('nouveauIndicator', true) && isNewRecipe(r);
      const tip = uxOn('badgeTooltips', true) ? (status.tip || status.text) : status.text;
      const nouveauHtml = showNouveau
        ? '<span class="card-nouveau">NOUVEAU</span>'
        : '';
      const kn = (uxOn('knowledgeMarks', true) && (state.flags.knowledge !== false)) ? (r.knowledge || null) : null;
      if (kn) {
        card.classList.add(`knowledge-${kn}`);
        card.dataset.knowledge = kn;
      }
      let cornerHtml = '';
      const masteredOn = uxOn('masteredBadge', true) && (r.mastered === true || kn === 'mastered');
      if (masteredOn) {
        cornerHtml = '<span class="card-corner-mark is-mastered" title="Maîtrisé"><i class="fa-solid fa-certificate" aria-hidden="true"></i></span>';
      } else if (kn === 'blueprint') {
        cornerHtml = '<span class="card-corner-mark is-blueprint" title="Appris via blueprint / plan technique"><i class="fa-solid fa-drafting-compass" aria-hidden="true"></i></span>';
      } else if (isPinned(r.id)) {
        cornerHtml = '<span class="card-corner-mark is-followed" title="Suivi dans le Carnet"><i class="fa-solid fa-bookmark" aria-hidden="true"></i></span>';
      }
      const titleText = kn === 'unknown' ? '???' : r.label;
      const veilImg = (kn === 'unknown' || kn === 'partial');

      card.innerHTML = `
        <button type="button" class="card-fav${favOn ? ' on' : ''}" data-fav="${escapeHtml(r.id)}" title="Favori" aria-label="Favori">
          <i class="fa-${favOn ? 'solid' : 'regular'} fa-star" aria-hidden="true"></i>
        </button>
        <div class="card-img-zone${veilImg ? ' is-veiled' : ''}${kn === 'unknown' ? ' is-unknown' : ''}">
          <span class="ph" aria-hidden="true"><i class="fa-solid ${kn === 'unknown' ? 'fa-question' : 'fa-cube'}"></i></span>
          <img alt="" />
          ${nouveauHtml}
          ${cornerHtml}
          <span class="card-state-badge ${status.cls}" title="${escapeHtml(tip)}">${status.text}</span>
        </div>
        <div class="card-body">
          <div class="card-identity">
            <div class="card-title">${escapeHtml(titleText)}</div>
            <div class="card-meta-line">
              <span class="card-cat">${escapeHtml(categoryLabel(r.category))}</span>
              <span class="card-code">${escapeHtml(code)}</span>
            </div>
          </div>
        </div>
      `;

      const img = card.querySelector('.card-img-zone img');
      const ph = card.querySelector('.card-img-zone .ph');
      if (kn === 'unknown') {
        if (img) { img.hidden = true; img.classList.add('is-fallback'); }
        if (ph) ph.style.display = '';
      } else {
        bindItemImg(img, resultItem, ph);
      }

      card.addEventListener('click', (e) => {
        if (e.target.closest('[data-fav]')) return;
        selectRecipe(r);
      });
      const favBtn = card.querySelector('[data-fav]');
      if (favBtn) {
        favBtn.addEventListener('click', async (e) => {
          e.stopPropagation();
          const was = isFavorite(r.id);
          await post('favorite', { recipeId: r.id });
          showToast(was ? 'Retiré des favoris' : 'Ajouté aux favoris', 'ok');
          await refresh();
        });
      }
      return card;
    };

    const appendGroup = (title, recipes) => {
      if (!recipes.length) return;
      const h = document.createElement('h3');
      h.className = 'catalog-group-title';
      h.textContent = title;
      grid.appendChild(h);
      recipes.forEach((r) => grid.appendChild(makeCard(r)));
    };

    const byId = {};
    list.forEach((r) => { byId[r.id] = r; });
    const showGroups = state.filter === 'all' && !state.search;
    const used = new Set();
    if (showGroups) {
      const favs = list.filter((r) => isFavorite(r.id));
      appendGroup('FAVORIS', favs);
      favs.forEach((r) => used.add(r.id));
      const recents = [];
      (state.recentlyCrafted || []).forEach((id) => {
        if (byId[id] && !used.has(id)) recents.push(byId[id]);
      });
      appendGroup('RÉCEMMENT FABRIQUÉS', recents);
      recents.forEach((r) => used.add(r.id));
      const news = list.filter((r) => isNewRecipe(r) && !used.has(r.id));
      appendGroup('NOUVEAUX', news);
      news.forEach((r) => used.add(r.id));
      const rest = list.filter((r) => !used.has(r.id));
      if (used.size && rest.length) appendGroup('CATALOGUE', rest);
      else rest.forEach((r) => grid.appendChild(makeCard(r)));
    } else {
      list.forEach((r) => grid.appendChild(makeCard(r)));
    }
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
    if (r.unread || isNewRecipe(r)) {
      post('newlyConsult', { recipeId: r.id }).then(() => {
        r.unread = false;
        state.newlyLearned = (state.newlyLearned || []).filter((id) => id !== r.id);
      });
      markRecipeSeen(r.id);
    } else if (uxOn('nouveauIndicator', true) && recipeMarkedNew(r)) {
      const first = !seenRecipes.has(r.id);
      markRecipeSeen(r.id);
      if (first && (r.newlyUnlocked || r.isNew)) showToast('Nouveau plan déverrouillé', 'warn');
    }
    $('#detail-empty').classList.add('hidden');
    $('#detail').classList.remove('hidden');

    const resultItem = (r.result && r.result.item) || r.id;
    bindItemImg($('#d-image'), resultItem, $('#d-image-fallback'));

    $('#d-title').textContent = r.label;
    $('#d-category').textContent = categoryLabel(r.category);
    const codeEl = $('#d-code');
    if (codeEl) codeEl.textContent = recipeCode(r);

    const rarityEl = $('#d-rarity');
    const fiche = $('#detail');
    const hero = fiche && fiche.querySelector('.fiche-hero');
    // clear previous rarity classes
    if (rarityEl) {
      rarityEl.className = 'badge soft rarity-plate hidden';
    }
    if (fiche) {
      [...fiche.classList].filter((c) => c.startsWith('rarity-')).forEach((c) => fiche.classList.remove(c));
      delete fiche.dataset.rarity;
    }
    if (hero) {
      [...hero.classList].filter((c) => c.startsWith('rarity-')).forEach((c) => hero.classList.remove(c));
    }
    if (r.rarity && rarityEl) {
      const rk = rarityKey(r.rarity);
      rarityEl.classList.remove('hidden');
      rarityEl.classList.add(`rarity-${rk}`);
      rarityEl.dataset.rarity = rk;
      rarityEl.innerHTML = `<i class="fa-solid ${RARITY_ICON[rk] || 'fa-circle'} rarity-ico" aria-hidden="true"></i><span class="rarity-txt">${escapeHtml(rarityLabel(r.rarity))}</span>`;
      if (fiche) {
        fiche.classList.add(`rarity-${rk}`);
        fiche.dataset.rarity = rk;
      }
      if (hero) hero.classList.add(`rarity-${rk}`);
    } else if (rarityEl) {
      rarityEl.classList.add('hidden');
      rarityEl.innerHTML = '';
      rarityEl.textContent = '';
    }

    const desc = recipeDescription(r);
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
    const resLabel = (r.result && r.result.label) || r.label || itemDisplayName(resItem);
    $('#d-result').textContent = `${resCount}× ${resLabel}`;
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
    const specNeed = r.requireSpec || r.requireSkill;
    if (specNeed) {
      specBlock.classList.remove('hidden');
      $('#d-spec-need').textContent = humanize(specNeed);
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
    const ventRow = $('#row-station-vent');
    const ventEl = $('#d-station-vent');
    const qRow = $('#row-station-queue');
    const qEl2 = $('#d-station-queue');
    const meta = state.menuMeta || {};
    if (ventRow && ventEl) {
      if (meta.ventilation != null) {
        ventRow.classList.remove('hidden');
        ventEl.textContent = String(meta.ventilation);
      } else ventRow.classList.add('hidden');
    }
    if (qRow && qEl2) {
      const used = meta.queue != null ? meta.queue : ((state.queue && state.queue.length) || 0);
      const cap = meta.queueSize || state.queueMax || 5;
      qEl2.textContent = `${used}/${cap}`;
      qRow.classList.remove('hidden');
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
        <span class="iname">${escapeHtml(ing.label || itemDisplayName(ing.item))}</span>
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
          <span class="iname">${escapeHtml(t.label || itemDisplayName(t.item))}</span>
          <span class="icount">×${escapeHtml(t.count || 1)}</span>
          <span class="wear-bar" aria-hidden="true"><i></i></span>
        `;
        bindItemImg(li.querySelector('img'), t.item, null);
        const bar = li.querySelector('.wear-bar i');
        if (bar) {
          const dur = (r.toolDurability != null) ? Number(r.toolDurability) : null;
          bar.style.width = (dur != null && !Number.isNaN(dur)) ? `${Math.max(0, Math.min(100, dur))}%` : '0%';
        }
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

    // —— Knowledge source / blueprint identity ——
    renderKnowledgeSource(r);

    // —— Recommended path + artisans (server fields only) ——
    renderPathHints(r);
    renderArtisanHints(r);

    // —— FABRIQUER / module fabrication ——
    updateActionBar(r);

    const favBtn = $('#btn-fav');
    const on = isFavorite(r.id);
    favBtn.classList.toggle('on', on);
    favBtn.innerHTML = `<i class="fa-${on ? 'solid' : 'regular'} fa-star" aria-hidden="true"></i>`;

    syncPinButton(r);
    syncCompareButton(r);
    syncTeachButton(r);

    renderList();
  }

  function syncTeachButton(r) {
    const btn = $('#btn-teach');
    if (!btn) return;
    const show = !!(r && r.teachable && r.known !== false && r.teacherKnows !== false);
    btn.classList.toggle('hidden', !show);
  }

  function blueprintTierLabel(meta) {
    if (!meta) return null;
    if (meta.label) return meta.label;
    const t = (meta.tier || meta.type || '').toLowerCase();
    const map = {
      military: 'PLAN MILITAIRE',
      industrial: 'PLAN INDUSTRIEL',
      industriel: 'PLAN INDUSTRIEL',
      medical: 'PLAN MÉDICAL',
      experimental: 'PLAN EXPÉRIMENTAL',
    };
    return map[t] || null;
  }

  function renderKnowledgeSource(r) {
    const block = $('#block-knowledge-source');
    const fiche = $('#detail');
    const hero = fiche && fiche.querySelector('.fiche-hero');
    if (fiche) {
      fiche.classList.remove('from-blueprint', 'has-blueprint-cue');
      delete fiche.dataset.knowledgeSource;
    }
    if (hero) hero.classList.remove('from-blueprint');
    if (!block) return;
    const src = r.knowledgeSource;
    const kn = r.knowledge;
    const show = !!(src === 'blueprint' || kn === 'blueprint' || (r.blueprintId && hasKnownPlan(r) && src === 'blueprint'));
    if (!show) {
      block.classList.add('hidden');
      return;
    }
    block.classList.remove('hidden');
    if (fiche) {
      fiche.classList.add('from-blueprint', 'has-blueprint-cue');
      fiche.dataset.knowledgeSource = 'blueprint';
    }
    if (hero) hero.classList.add('from-blueprint');
    const txt = $('#d-knowledge-source');
    if (txt) {
      txt.textContent = 'SOURCE DE CONNAISSANCE · Plan technique';
    }
    const tierEl = $('#d-blueprint-tier');
    const tier = blueprintTierLabel(r.blueprintMeta);
    if (tierEl) {
      if (tier) {
        tierEl.textContent = tier;
        tierEl.classList.remove('hidden');
      } else {
        tierEl.textContent = '';
        tierEl.classList.add('hidden');
      }
    }
  }

  function renderPathHints(r) {
    const block = $('#block-path');
    const list = $('#d-path-hints');
    const countEl = $('#path-count');
    const moreBtn = $('#btn-path-more');
    if (!block || !list) return;
    const enabled = uxOn('pathHints', true) && state.flags.pathHints !== false;
    const hints = (enabled && Array.isArray(r.pathHints)) ? r.pathHints.slice(0, 3) : [];
    if (!enabled || !hints.length) {
      block.classList.add('hidden');
      list.innerHTML = '';
      return;
    }
    block.classList.remove('hidden');
    if (countEl) countEl.textContent = String(hints.length);
    list.innerHTML = '';
    hints.forEach((h) => {
      const li = document.createElement('li');
      li.className = `path-hint kind-${escapeHtml(h.kind || 'info')}`;
      const canLink = h.recipeId && state.recipes.some((x) => x.id === h.recipeId);
      li.innerHTML = `
        <div class="path-hint-head">
          <span class="path-kind">${escapeHtml(h.title || '')}</span>
          ${canLink ? `<button type="button" class="ghost compact path-goto" data-recipe="${escapeHtml(h.recipeId)}">Voir la recette</button>` : ''}
        </div>
        <p class="path-detail">${escapeHtml(h.detail || '')}</p>
      `;
      list.appendChild(li);
    });
    list.querySelectorAll('.path-goto').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        const id = btn.getAttribute('data-recipe');
        const found = state.recipes.find((x) => x.id === id);
        if (found) selectRecipe(found);
      });
    });
    if (moreBtn) {
      const more = r.pathHintsMore === true;
      moreBtn.classList.toggle('hidden', !more);
      moreBtn.onclick = () => {
        if (!r.id) return;
        post('pathHints', { recipeId: r.id }).then((data) => {
          if (!(data && data.ok)) return;
          // display only server-provided hints — never invent
          const merged = Object.assign({}, r, {
            pathHints: data.pathHints || r.pathHints,
            pathHintsMore: data.moreAvailable,
            artisanHints: data.artisanHints || r.artisanHints,
          });
          const idx = state.recipes.findIndex((x) => x.id === r.id);
          if (idx >= 0) state.recipes[idx] = merged;
          state.selected = merged;
          renderPathHints(merged);
          renderArtisanHints(merged);
        });
      };
    }
  }

  function renderArtisanHints(r) {
    const block = $('#block-artisans');
    const host = $('#d-artisans');
    const countEl = $('#artisan-count');
    if (!block || !host) return;
    const enabled = uxOn('artisanHints', true) && state.flags.artisanHints !== false;
    const hints = (r && r.artisanHints) || { potential: [], confirmed: [] };
    const pot = enabled ? (hints.potential || []) : [];
    const conf = enabled ? (hints.confirmed || []) : [];
    if (!enabled || (!pot.length && !conf.length)) {
      block.classList.add('hidden');
      host.innerHTML = '';
      return;
    }
    block.classList.remove('hidden');
    if (countEl) countEl.textContent = String(pot.length + conf.length);
    let html = '';
    conf.forEach((a) => {
      html += `<div class="artisan-row confirmed">
        <span class="artisan-tag">SERVICE CONFIRMÉ</span>
        <span class="artisan-name">${escapeHtml(a.name || a.id || '')}</span>
        <span class="artisan-spec muted">${escapeHtml(a.specialty || a.serviceLabel || '')}</span>
      </div>`;
    });
    pot.forEach((a) => {
      html += `<div class="artisan-row potential">
        <span class="artisan-tag">CONTACT POTENTIEL</span>
        <span class="artisan-name">${escapeHtml(a.name || a.id || '')}</span>
        <span class="artisan-spec muted">${escapeHtml(a.specialty || '')}</span>
      </div>`;
    });
    host.innerHTML = html;
  }

  function syncPinButton(r) {
    const btnPin = $('#btn-pin');
    if (!btnPin) return;
    const follow = uxOn('pinFollow', true);
    const pinned = !!(r && isPinned(r.id));
    btnPin.title = follow ? 'Suivre dans le Carnet' : 'Épingler au carnet';
    btnPin.setAttribute('aria-label', btnPin.title);
    btnPin.classList.toggle('on', pinned);
    btnPin.classList.toggle('is-pinned', pinned);
    const label = btnPin.querySelector('.tool-label');
    if (label) label.textContent = pinned ? 'Suivi' : 'Suivre';
  }

  function syncCompareButton(r) {
    const btn = $('#btn-compare');
    if (!btn) return;
    const target = compareTargetFor(r);
    btn.classList.toggle('hidden', !target);
    if (target) {
      btn.dataset.compareTarget = target;
      btn.title = `Comparer avec ${humanize(target)}`;
    } else {
      delete btn.dataset.compareTarget;
    }
  }

  let fabDoneTimer = null;

  function setFabState(mode) {
    const mod = $('#fab-module');
    const ready = $('#fab-ready');
    const active = $('#fab-active');
    const done = $('#fab-done');
    if (!ready || !active || !done) return;
    const next = mode === 'active' || mode === 'done' ? mode : 'ready';
    if (fabDoneTimer && next !== 'done') {
      clearTimeout(fabDoneTimer);
      fabDoneTimer = null;
    }
    ready.classList.toggle('hidden', next !== 'ready');
    active.classList.toggle('hidden', next !== 'active');
    done.classList.toggle('hidden', next !== 'done');
    if (mod) mod.setAttribute('data-fab-state', next);
  }

  function setFabCancelVisible(show) {
    const btn = $('#btn-cancel');
    if (!btn) return;
    btn.classList.toggle('hidden', !show);
    btn.disabled = !show;
  }

  function craftPhaseFor(recipe, progress) {
    const p = Math.max(0, Math.min(1, progress || 0));
    if (p >= 1) return 'TERMINÉ';
    const cat = String((recipe && recipe.category) || '').toLowerCase();
    let mid = 'Assemblage';
    if (/medical|medecin|soin|pharma/.test(cat)) mid = 'Stérilisation';
    else if (/cuisine|boucherie|food|cook/.test(cat)) mid = 'Cuisson';
    else if (/forge|fonderie|forgeron/.test(cat)) mid = 'Forge';
    else if (/mechanic|mecano|ingenieur|armurier|weapon|munition|construction/.test(cat)) mid = 'Réglage';
    if (p < 0.22) return 'Préparation';
    if (p < 0.48) return 'Assemblage';
    if (p < 0.78) return mid;
    return 'Finalisation';
  }

  function fillFabActive(recipe, batch, remainingMs, durationMs) {
    if (!recipe) return;
    const qty = Math.max(1, batch || 1);
    const resCount = ((recipe.result && recipe.result.count) || 1) * qty;
    const nameEl = $('#fab-active-name');
    const qtyEl = $('#fab-active-qty');
    if (nameEl) nameEl.textContent = recipe.label || recipe.id || '—';
    if (qtyEl) qtyEl.textContent = `×${resCount}`;
    const orig = Number(durationMs != null ? durationMs : recipe.duration) || 0;
    const rem = remainingMs != null ? Math.max(0, Number(remainingMs) || 0) : orig;
    const p = orig > 0 ? Math.min(1, Math.max(0, 1 - rem / orig)) : 0;
    const phaseEl = $('#fab-active-phase');
    if (phaseEl) phaseEl.textContent = craftPhaseFor(recipe, p);
    setFabCancelVisible(p < 1);
    const timeEl = $('#fab-active-time');
    if (timeEl) timeEl.textContent = durationLabel(rem);
    const pctEl = $('#fab-active-pct');
    if (pctEl) pctEl.textContent = `${Math.round(p * 100)}%`;
    const fill = $('#progress-fill');
    if (fill) fill.style.width = `${p * 100}%`;
    const resultItem = (recipe.result && recipe.result.item) || recipe.id;
    bindItemImg($('#fab-active-img'), resultItem, $('#fab-active-img-fallback'));
  }

  function batchCap(recipe) {
    const cfg = state.batch || {};
    const hard = Number(cfg.hardCap) || 100;
    const maxB = Number(cfg.maxBatch) || 50;
    let cap = Math.min(maxB, hard);
    if (recipe) {
      const rec = Number(recipe.batchMax || recipe.maxQuantity);
      if (!Number.isNaN(rec) && rec > 0) cap = Math.min(cap, rec);
      (recipe.ingredients || []).forEach((ing) => {
        const need = Number(ing.count) || 1;
        const owned = Number(ing.owned) || 0;
        if (need > 0) cap = Math.min(cap, Math.floor(owned / need));
      });
      if (recipe.toolDurability != null && Number(recipe.toolDurability) <= 0 && (recipe.tools || recipe.requireTool)) {
        cap = 0;
      }
    }
    if (cap < 0 || !Number.isFinite(cap)) cap = 0;
    return cap;
  }

  function clampBatchInput(recipe) {
    const el = $('#batch');
    if (!el) return 1;
    let n = parseInt(el.value, 10);
    if (!Number.isFinite(n) || n < 1) n = 1;
    const cap = Math.max(1, batchCap(recipe || state.selected) || 1);
    const hard = (state.batch && state.batch.hardCap) || 100;
    if (n > hard) n = hard;
    if (n > cap) n = cap;
    if (n < 1) n = 1;
    el.value = String(n);
    el.max = String(Math.min(hard, Math.max(1, cap)));
    return n;
  }

  function updateActionBar(r) {

    const recipe = r || state.selected;
    const batchEl = $('#batch');
    const batch = clampBatchInput(recipe);

    const lotEl = $('#fab-ready-lot');
    if (lotEl) lotEl.textContent = `×${batch}`;

    if (recipe) {
      const resCount = ((recipe.result && recipe.result.count) || 1) * batch;
      const resItem = (recipe.result && recipe.result.item) || recipe.id || '—';
      const resLabel = recipe.label || humanize(resItem);
      const resultEl = $('#fab-ready-result');
      if (resultEl) resultEl.textContent = `${resCount}× ${resLabel}`;
      const durEl = $('#fab-ready-dur');
      if (durEl) {
        const base = recipe.duration || 0;
        durEl.textContent = durationLabel(state.flags.batch ? base * batch : base);
      }
      const xpEl = $('#fab-ready-xp');
      if (xpEl) {
        if (recipe.xp && recipe.xp.amount != null) {
          const amt = recipe.xp.amount * (state.flags.batch ? batch : 1);
          xpEl.textContent = `+${amt}`;
        } else {
          xpEl.textContent = '—';
        }
      }
      const matsEl = $('#fab-ready-mats');
      if (matsEl) {
        const ings = recipe.ingredients || [];
        const missing = ings.filter((ing) => (ing.owned || 0) < ((ing.count || 1) * batch)).length;
        const ok = ings.length - missing;
        matsEl.textContent = ings.length ? `${ok}/${ings.length}` : '—';
      }
      const noiseChip = $('#fab-chip-noise');
      const noiseVal = $('#fab-ready-noise');
      if (noiseChip && noiseVal) {
        if (recipe.noiseLevel != null) {
          noiseChip.classList.remove('hidden');
          noiseVal.textContent = String(recipe.noiseLevel);
        } else {
          noiseChip.classList.add('hidden');
        }
      }
      const energyChip = $('#fab-chip-energy');
      const energyVal = $('#fab-ready-energy');
      if (energyChip && energyVal) {
        if (recipe.powerCost != null) {
          energyChip.classList.remove('hidden');
          energyVal.textContent = String((Number(recipe.powerCost) || 0) * (state.flags.batch ? batch : 1));
        } else {
          energyChip.classList.add('hidden');
        }
      }
    } else {
      const resultEl = $('#fab-ready-result');
      if (resultEl) resultEl.textContent = '—';
      const durEl = $('#fab-ready-dur');
      if (durEl) durEl.textContent = '—';
      const xpEl = $('#fab-ready-xp');
      if (xpEl) xpEl.textContent = '—';
    }

    const can = !!(recipe && recipe.canCraft && !state.crafting);
    const craftBtn = $('#btn-craft');
    if (craftBtn) {
      craftBtn.disabled = !can;
      const reasons = recipe ? disableReasons(recipe) : ['Aucune recette sélectionnée'];
      const whyEl = $('#craft-why');
      if (!can && reasons.length && !state.crafting) {
        if (whyEl) {
          whyEl.textContent = reasons[0];
          whyEl.classList.remove('hidden');
        }
        craftBtn.title = reasons.length > 1 ? reasons.join(' · ') : reasons[0];
      } else {
        if (whyEl) whyEl.classList.add('hidden');
        craftBtn.title = can ? 'Lancer la fabrication' : '';
      }
    }

    const batchWrap = $('#batch-wrap');
    if (batchWrap) batchWrap.classList.toggle('hidden', !state.flags.batch);
    const qBtn = $('#btn-queue');
    if (qBtn) qBtn.classList.toggle('hidden', !state.flags.queue);
    const sBtn = $('#btn-shop');
    if (sBtn) sBtn.classList.toggle('hidden', state.flags.shopping === false);

    if (!state.crafting) {
      const mod = $('#fab-module');
      const cur = mod && mod.getAttribute('data-fab-state');
      if (cur !== 'done') setFabState('ready');
    }

    updateFabIdleConsole();
  }

  function updateFabIdleConsole() {
    const cons = $('#fab-idle-console');
    if (!cons) return;
    const show = uxOn('fabReadyConsole', true);
    cons.classList.toggle('hidden', !show);
    if (!show) return;
    const qEl = $('#fab-idle-queue');
    const maxQ = state.queueMax || 5;
    const n = (state.queue && state.queue.length) || 0;
    if (qEl) qEl.textContent = `${n}/${maxQ}`;
    const lastEl = $('#fab-idle-last');
    if (lastEl) {
      const last = state.lastCraft || (function () {
        try { return localStorage.getItem(LAST_CRAFT_KEY); } catch (_) { return null; }
      })();
      lastEl.textContent = last || '—';
    }
  }

  function syncFabQueueMini() {
    const mini = $('#fab-queue-mini');
    if (!mini) return;
    const show = !!(state.flags.queue && state.queue && state.queue.length > 0);
    mini.classList.toggle('hidden', !show);
    if (!show) {
      mini.innerHTML = '';
      return;
    }
    const e = state.queue[0];
    const qty = e.batch || e.count || e.qty || 1;
    const now = Math.floor(Date.now() / 1000);
    const left = Math.max(0, (e.finishAt || 0) - now);
    const eta = left > 0 ? `ETA ${left}s` : 'PRÊT';
    mini.innerHTML = `
      <span class="fab-q-k">File</span>
      <span class="fab-q-v">${escapeHtml(e.label || e.recipeId)} · ×${escapeHtml(qty)}</span>
      <span class="fab-q-eta">${escapeHtml(eta)}</span>
    `;
  }

  function runProgress(duration, onDone) {
    state.progressGen = (state.progressGen || 0) + 1;
    const gen = state.progressGen;
    const craftBtn = $('#btn-craft');
    if (craftBtn) craftBtn.disabled = true;
    const remaining = Math.max(0, Number(duration) || 0);
    const original = Number(state.craftDurationMs) || remaining || 5000;
    const elapsed = Math.max(0, original - remaining);
    const start = performance.now() - elapsed;
    const recipe = state.progressRecipe || state.selected;
    const fill = $('#progress-fill');
    const paint = (now) => {
      const p = original > 0 ? Math.min(1, Math.max(0, (now - start) / original)) : 1;
      if (fill) fill.style.width = `${p * 100}%`;
      const pctEl = $('#fab-active-pct');
      if (pctEl) pctEl.textContent = `${Math.round(p * 100)}%`;
      const leftMs = Math.max(0, original - (now - start));
      const timeEl = $('#fab-active-time');
      if (timeEl) timeEl.textContent = durationLabel(leftMs);
      const phaseEl = $('#fab-active-phase');
      if (phaseEl) phaseEl.textContent = craftPhaseFor(recipe, p);
      setFabCancelVisible(p < 1);
      return p;
    };
    paint(performance.now());
    const tick = (now) => {
      if (gen !== state.progressGen) return;
      if (!state.crafting) return;
      const p = paint(now);
      if (p < 1) requestAnimationFrame(tick);
      else if (typeof onDone === 'function') onDone();
    };
    requestAnimationFrame(tick);
  }

  function recipeFromSession(active) {
    if (!active) return null;
    const found = (state.recipes || []).find((r) => r.id === active.recipeId);
    if (found) return found;
    return {
      id: active.recipeId,
      label: active.label || active.stepLabel || active.recipeId,
      result: { item: active.resultItem, count: active.resultCount || 1 },
      duration: active.durationMs || active.duration,
      category: active.category,
    };
  }

  function hydrateSession(session) {
    if (!session || typeof session !== 'object') return;
    state.session = session;
    const stationId = session.stationId || state.benchKey;
    const scoped = (list) => (list || []).filter((e) => {
      if (!stationId || !e || !e.benchKey) return true;
      return e.benchKey === stationId;
    });
    const activeList = scoped(session.active);
    state.queue = scoped(session.queued);
    renderQueue();
    updateFabIdleConsole();

    const active = activeList[0];
    if (active) {
      const recipe = recipeFromSession(active);
      const batch = active.batch || active.quantity || 1;
      const remaining = Math.max(0, Number(
        active.remainingMs != null ? active.remainingMs : active.duration
      ) || 0);
      const orig = Number(active.durationMs) || remaining;
      state.crafting = true;
      state.craftId = active.craftId;
      state.craftDurationMs = orig;
      state.progressRecipe = recipe;
      fillFabActive(recipe, batch, remaining, orig);
      setFabState('active');
      const whyEl = $('#craft-why');
      if (whyEl) whyEl.classList.add('hidden');
      const craftBtn = $('#btn-craft');
      if (craftBtn) craftBtn.disabled = true;
      if (remaining <= 0) {
        const phaseEl = $('#fab-active-phase');
        if (phaseEl) phaseEl.textContent = 'TERMINÉ';
        setFabCancelVisible(false);
        finishCraft();
      } else {
        runProgress(remaining, finishCraft);
      }
      return;
    }

    // Session wins: no active at this station → clear leftover crafting UI
    state.progressGen = (state.progressGen || 0) + 1;
    state.crafting = false;
    state.craftId = null;
    state.craftDurationMs = null;
    state.progressRecipe = null;
    const fill = $('#progress-fill');
    if (fill) fill.style.width = '0%';
    const mod = $('#fab-module');
    const cur = mod && mod.getAttribute('data-fab-state');
    if (!(cur === 'done' && fabDoneTimer)) setFabState('ready');
  }

  async function startCraft() {
    if (!state.selected || state.crafting) return;
    playTick();
    const batch = parseInt($('#batch').value, 10) || 1;
    const data = await post('craft', { recipeId: state.selected.id, benchKey: state.benchKey, batch });
    if (!data.ok) {
      beep('error');
      showToast('Craft impossible', 'err');
      await post('notify', { type: 'error', reason: data.reason });
      return;
    }
    state.crafting = true;
    state.craftId = data.craftId;
    state.craftDurationMs = data.duration;
    state.progressRecipe = state.selected;
    fillFabActive(state.selected, batch, data.duration, data.duration);
    setFabCancelVisible(true);
    setFabState('active');
    const whyEl = $('#craft-why');
    if (whyEl) whyEl.classList.add('hidden');
    runProgress(data.duration, finishCraft);
  }

  function showFabTerminated(label) {
    const phaseEl = $('#fab-active-phase');
    if (phaseEl) phaseEl.textContent = 'TERMINÉ';
    const pctEl = $('#fab-active-pct');
    if (pctEl) pctEl.textContent = '100%';
    const timeEl = $('#fab-active-time');
    if (timeEl) timeEl.textContent = '0s';
    const fill = $('#progress-fill');
    if (fill) fill.style.width = '100%';
    setFabCancelVisible(false);
    const doneLabel = $('#fab-done-label');
    const craftName = label
        || (state.progressRecipe && state.progressRecipe.label)
        || (state.selected && state.selected.label)
        || 'Objet fabriqué';
    if (doneLabel) doneLabel.textContent = craftName;
    state.lastCraft = craftName;
    try { localStorage.setItem(LAST_CRAFT_KEY, craftName); } catch (_) { /* ignore */ }
    updateFabIdleConsole();
    setFabState('done');
    if (fabDoneTimer) clearTimeout(fabDoneTimer);
    fabDoneTimer = setTimeout(() => {
      fabDoneTimer = null;
      setFabState('ready');
      if (state.selected) updateActionBar(state.selected);
    }, 1600);
    return craftName;
  }

  async function finishCraft() {
    if (state.finishLock) return;
    state.finishLock = true;
    const craftId = state.craftId;
    // Visual TERMINÉ immediately — never sit on FINALISATION at 100%
    showFabTerminated();
    let settled = false;
    const watchdogUi = setTimeout(() => {
      if (settled) return;
      settled = true;
      // No reply in ~1.5s: keep TERMINÉ; server watchdog grants
      state.progressGen = (state.progressGen || 0) + 1;
      state.crafting = false;
      state.craftId = null;
      state.craftDurationMs = null;
      state.finishLock = false;
    }, 1500);

    let data;
    try {
      data = await post('complete', { craftId });
    } catch (_) {
      data = { ok: true, already: true, timeout: true };
    }
    if (settled && !(data && data.ok && data.advanced)) return;
    settled = true;
    clearTimeout(watchdogUi);

    if (data && data.ok && data.advanced) {
      beep('click');
      await post('notify', {
        type: 'inform',
        reason: 'craft_step_advance',
        label: data.stepLabel || data.label,
        args: [data.stepIndex, data.totalSteps, data.stepLabel || data.label],
      });
      if (fabDoneTimer) {
        clearTimeout(fabDoneTimer);
        fabDoneTimer = null;
      }
      const phaseEl = $('#fab-active-phase');
      if (phaseEl && data.stepLabel) phaseEl.textContent = data.stepLabel;
      state.craftDurationMs = data.duration;
      state.crafting = true;
      setFabCancelVisible(true);
      setFabState('active');
      state.finishLock = false;
      runProgress(data.duration, finishCraft);
      return;
    }

    state.progressGen = (state.progressGen || 0) + 1;
    state.crafting = false;
    state.craftId = null;
    state.craftDurationMs = null;
    const alreadyDone = !!(data && (data.already || data.reason === 'craft_invalid' || data.reason === 'craft_too_far'));
    const success = !!(data && data.ok) || alreadyDone || !data;
    if (success) {
      beep('success');
      if (data && data.chainNext) beep('blueprint');
      showFabTerminated(data && data.label);
    } else {
      beep('error');
      setFabState('ready');
    }
    if (!alreadyDone && data && !data.timeout) {
      await post('notify', {
        type: success ? 'success' : 'error',
        reason: success ? 'craft_success' : ((data && data.reason) || 'craft_failed'),
        label: data && data.label,
      });
    }
    await refresh();
    if (!success && state.selected) {
      updateActionBar(state.selected);
    }
    state.finishLock = false;
  }

  async function cancelCraft() {
    if (!state.craftId || state.finishLock) return;
    await post('cancel', { craftId: state.craftId });
    state.progressGen = (state.progressGen || 0) + 1;
    state.crafting = false;
    state.craftId = null;
    state.craftDurationMs = null;
    const fill = $('#progress-fill');
    if (fill) fill.style.width = '0%';
    setFabState('ready');
    if (state.selected) selectRecipe(state.selected);
  }

  async function refresh() {
    const data = await post('refresh', { benchKey: state.benchKey });
    if (data && data.ok) {
      applyMenu(data);
      if (data.session) hydrateSession(data.session);
    }
  }

  function fillStationOps(data) {
    const wrap = $('#station-ops');
    if (!wrap) return;
    const show = !!(data && (data.canUpgrade || data.canModule || data.conditionEnabled));
    wrap.classList.toggle('hidden', !show);
    if (!show) return;
    const btnM = $('#btn-maintain');
    const btnR = $('#btn-repair');
    const btnU = $('#btn-upgrade');
    if (btnM) btnM.classList.toggle('hidden', !data.conditionEnabled);
    if (btnR) btnR.classList.toggle('hidden', !data.conditionEnabled);
    if (btnU) {
      const lvl = data.stationLevel || 1;
      const max = data.maxLevel || 3;
      btnU.classList.toggle('hidden', !data.canUpgrade || lvl >= max);
    }
    const ul = $('#station-modules');
    if (!ul) return;
    ul.innerHTML = '';
    const catalog = data.moduleCatalog || [];
    const installed = Array.isArray(data.modules) ? data.modules : Object.keys(data.modules || {});
    const instSet = {};
    installed.forEach((id) => { instSet[id] = true; });
    const rows = catalog.length ? catalog : installed.map((id) => ({ id, label: id, installed: true }));
    rows.forEach((mod) => {
      const li = document.createElement('li');
      const on = mod.installed || instSet[mod.id];
      li.innerHTML = `<span class="${on ? 'mod-on' : 'mod-off'}">${escapeHtml(mod.label || mod.id)}</span>`;
      if (!on && data.canModule) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = 'ghost compact';
        b.textContent = 'Installer';
        b.addEventListener('click', async (ev) => {
          ev.stopPropagation();
          const r = await post('addStationModule', { benchKey: state.benchKey, moduleId: mod.id });
          if (r && r.ok) showToast('Module installé', 'ok');
          else showToast('Installation impossible', 'err');
          await refresh();
        });
        li.appendChild(b);
      }
      ul.appendChild(li);
    });
    if (!rows.length) {
      ul.innerHTML = '<li class="mod-off">Aucun module</li>';
    }
  }

  function updateStationHeader(data) {

    state.menuMeta = {
      label: data.label,
      category: data.category,
      stationLevel: data.stationLevel,
      powered: data.powered,
      modules: data.modules || [],
      energy: data.energy,
      efficiency: data.efficiency,
      condition: data.condition || data.etat,
      temp: data.temp,
      ventilation: data.ventilation,
      queue: data.queue,
      queueSize: data.queueSize,
      moduleCatalog: data.moduleCatalog || [],
      canUpgrade: data.canUpgrade,
      canModule: data.canModule,
      conditionEnabled: data.conditionEnabled,
      heatEnabled: data.heatEnabled,
      brokenParts: data.brokenParts || [],
      maxLevel: data.maxLevel,
    };
    if (data.batch) state.batch = data.batch;
    const title = data.label || 'Atelier';
    $('#station-title').textContent = title;
    const powered = data.powered !== false;
    const lvl = data.stationLevel || 1;
    const catLabel = categoryLabel(data.category);
    const stencil = $('#station-stencil');
    if (stencil) {
      const raw = String(data.benchKey || data.category || 'NG');
      const code = raw.replace(/[^a-zA-Z0-9]/g, '').slice(0, 6).toUpperCase() || 'NG';
      stencil.textContent = `STATION ${code} · ${catLabel.toUpperCase()}`;
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

    const mods = data.modules || [];
    const eff = data.efficiency;
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

    const plateTemp = $('#plate-temp');
    const tempEl = $('#stat-temp');
    const gaugeTemp = $('#gauge-temp');
    if (data.heatEnabled && data.temp != null && plateTemp) {
      plateTemp.classList.remove('hidden');
      const temp = Number(data.temp);
      tempEl.textContent = Number.isNaN(temp) ? String(data.temp) : `${Math.round(temp)}°`;
      tempEl.className = 't-l5' + (temp >= 95 ? ' bad' : temp >= 85 ? ' warn' : '');
      plateTemp.classList.toggle('bad', temp >= 95);
      plateTemp.classList.toggle('warn', temp >= 85 && temp < 95);
      if (gaugeTemp && !Number.isNaN(temp)) gaugeTemp.style.width = `${Math.max(5, Math.min(100, temp))}%`;
    } else if (plateTemp) {
      plateTemp.classList.add('hidden');
    }

    fillStationOps(data);

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
    if (data.itemLabels) state.itemLabels = data.itemLabels;
    state.favorites = data.favorites || [];
    state.pinned = data.pinned || [];
    state.playerSpec = data.playerSpec || null;
    state.recentlyCrafted = data.recentlyCrafted || [];
    state.newlyLearned = data.newlyLearned || [];
    state.teaching = data.teaching || {};
    if (data.shoppingPins) {
      state.shop = data.shoppingPins;
      renderShop();
    }
    const rarityNav = $('#rarity-filters');
    if (rarityNav) rarityNav.hidden = !uxOn('rarityFilters', true);
    state.flags = data.flags || {};
    if (data.batch) state.batch = data.batch;
    if (data.queueSize != null) state.queueMax = data.queueSize;
    state.ux = (data.ui && data.ui.Ux) || data.ux || state.ux || {};
    state.compare = data.compare || { enabled: !!(state.flags && state.flags.compare), map: {} };
    if (data.queueMax != null) state.queueMax = data.queueMax;
    if (data.ui && data.ui.Sounds) state.sounds = data.ui.Sounds;
    if (app) {
      app.dataset.uxSel = uxOn('selectionTransition', true) ? '1' : '0';
    }
    rebuildSearchIndex(state.recipes);
    updateStationHeader(data);
    renderCategories();
    renderList();
    updateFabIdleConsole();
    const session = data.session;
    const hasActive = !!(session && session.active && session.active[0]);
    if (hasActive) {
      // Prevent selectRecipe/updateActionBar from flipping fab back to ready
      state.crafting = true;
      state.craftId = session.active[0].craftId;
    }
    if (state.selected) {
      const again = state.recipes.find((r) => r.id === state.selected.id);
      if (again) selectRecipe(again);
    }
    if (session) hydrateSession(session);
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
        <div class="qactions">
          <button type="button" class="ghost compact qcancel" data-qid="${escapeHtml(e.craftId)}">Annuler</button>
        </div>
      `;
      card.addEventListener('click', async (ev) => {
        if (ev.target && ev.target.closest && ev.target.closest('.qcancel')) return;
        if (left <= 0) {
          await post('queueCollect', { craftId: e.craftId });
          await loadQueue();
          await refresh();
        }
      });
      const cancelBtn = card.querySelector('.qcancel');
      if (cancelBtn) {
        cancelBtn.addEventListener('click', async (ev) => {
          ev.stopPropagation();
          const r = await post('queueCancel', { craftId: e.craftId });
          if (r && r.ok) showToast('Retiré de la file', 'ok');
          else showToast('Annulation impossible', 'err');
          await loadQueue();
          await refresh();
        });
      }
      track.appendChild(card);
    });
    syncFabQueueMini();
  }

  async function loadQueue() {
    if (state.benchKey) {
      const sess = await post('getCraftSession', { benchKey: state.benchKey });
      if (sess && sess.ok && sess.session) {
        const stationId = sess.session.stationId || state.benchKey;
        state.queue = (sess.session.queued || []).filter((e) => !stationId || !e.benchKey || e.benchKey === stationId);
        renderQueue();
        return;
      }
    }
    const data = await post('queueList', {});
    const all = (data && data.queue) || [];
    state.queue = all.filter((e) => !state.benchKey || !e.benchKey || e.benchKey === state.benchKey);
    renderQueue();
  }

  function shopRows() {
    const raw = state.shop;
    if (Array.isArray(raw)) return raw;
    if (!raw || typeof raw !== 'object') return [];
    return Object.entries(raw).map(([item, count]) => {
      if (typeof count === 'object' && count) {
        return {
          item,
          label: count.label,
          need: count.need || count.count || 1,
          owned: count.owned,
          remaining: count.remaining != null ? count.remaining : count.count,
          sources: count.sources || [],
        };
      }
      return { item, need: count, remaining: count, sources: [] };
    });
  }

  function renderShop() {
    const ul = $('#shop-list');
    const empty = $('#shop-empty');
    if (!ul) return;
    ul.innerHTML = '';
    const rows = shopRows();
    setEmpty(empty, rows.length === 0);
    rows.forEach((row) => {
      const li = document.createElement('li');
      const need = row.need || row.count || 1;
      const owned = typeof row.owned === 'number' ? row.owned : null;
      const remaining = row.remaining != null ? row.remaining : (owned != null ? Math.max(0, need - owned) : need);
      const ownedTxt = owned != null ? `${owned}/${need}` : `×${need}`;
      const miss = remaining > 0;
      const srcs = (row.sources || []).map((s) => `${s.label || s.recipeId} ×${s.count}`).join(' · ');
      li.innerHTML = `
        <span class="check-mark" aria-hidden="true"><i class="fa-${miss ? 'regular fa-square' : 'solid fa-square-check'}"></i></span>
        <img class="ing-thumb" alt="" />
        <span class="iname">${escapeHtml(row.label || itemDisplayName(row.item))}</span>
        <span class="shop-need${miss ? '' : ' ok'}">${escapeHtml(ownedTxt)}</span>
        ${srcs ? `<span class="shop-src t-l6">${escapeHtml(srcs)}</span>` : ''}
      `;
      bindItemImg(li.querySelector('img'), row.item, null);
      ul.appendChild(li);
    });
  }

  function renderTreeNode(node, depth = 0) {
    if (!node) return '';
    if (node.type === 'raw') {
      return `<div class="tree-node raw">
        <div class="t-label">${escapeHtml(node.label || itemDisplayName(node.item))} ×${escapeHtml(node.count)}</div>
        <div class="t-sub">Ressource · brute</div>
      </div>`;
    }
    const rid = node.recipeId || node.id || '';
    const label = node.label || rid || 'Recette';
    const result = node.result && node.result.item ? `${node.result.item}` : '';
    let html = `<div class="tree-node" data-tree-id="${escapeHtml(rid)}">
      <div class="t-label">${escapeHtml(label)}</div>
      <div class="t-sub">${result ? 'Nœud · ' + escapeHtml((node.result && node.result.label) || itemDisplayName(result)) : 'Nœud de fabrication'}</div>
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
  bindUi('#btn-hud', 'click', () => {
    const hud = window.SanctuaryHud;
    if (!hud) return;
    const panel = document.getElementById('hud-settings');
    if (panel && panel.classList.contains('is-open') && hud.close) hud.close();
    else if (hud.open) hud.open();
  });
  bindUi('#btn-compact', 'click', () => {
    state.compact = !state.compact;
    app.dataset.compact = state.compact ? '1' : '0';
  });
  bindUi('#search', 'input', (e) => { state.search = e.target.value; renderList(); });

  $$('#filters .chip').forEach((btn) => {
    btn.addEventListener('click', () => {
      $$('#filters .chip').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.filter = btn.dataset.filter;
      playTick();
      renderList();
    });
  });

  const rarityNav = $('#rarity-filters');
  if (rarityNav) {
    const showRarity = uxOn('rarityFilters', true);
    rarityNav.hidden = !showRarity;
    rarityNav.querySelectorAll('.chip').forEach((btn) => {
      btn.addEventListener('click', () => {
        rarityNav.querySelectorAll('.chip').forEach((b) => b.classList.remove('active'));
        btn.classList.add('active');
        state.rarityFilter = btn.dataset.rarity || 'all';
        playTick();
        renderList();
      });
    });
  }

  const sortEl = $('#catalog-sort');
  if (sortEl) {
    sortEl.value = state.sort || 'name';
    sortEl.addEventListener('change', () => {
      state.sort = sortEl.value || 'name';
      playTick();
      renderList();
    });
  }

  $$('.tab').forEach((btn) => {
    btn.addEventListener('click', () => {
      openTab(btn.dataset.tab);
      playTick();
    });
  });

  bindUi('#btn-craft', 'click', startCraft);
  bindUi('#btn-cancel', 'click', cancelCraft);
  const batchInput = $('#batch');
  if (batchInput) {
    batchInput.addEventListener('input', () => {
      if (state.selected) updateActionBar(state.selected);
    });
    batchInput.addEventListener('change', () => {
      if (state.selected) updateActionBar(state.selected);
    });
  }
  const presets = $('#batch-presets');
  if (presets) {
    presets.addEventListener('click', (ev) => {
      const btn = ev.target && ev.target.closest && ev.target.closest('[data-batch]');
      if (!btn || !batchInput) return;
      const v = btn.getAttribute('data-batch');
      if (v === 'max') {
        batchInput.value = String(Math.max(1, batchCap(state.selected)));
      } else {
        batchInput.value = String(v);
      }
      if (state.selected) updateActionBar(state.selected);
    });
  }
  bindUi('#btn-maintain', 'click', async () => {
    const r = await post('maintainStation', { benchKey: state.benchKey });
    if (r && r.ok) showToast('Station entretenue', 'ok');
    else showToast('Entretien impossible', 'err');
    await refresh();
  });
  bindUi('#btn-repair', 'click', async () => {
    const r = await post('repairStation', { benchKey: state.benchKey });
    if (r && r.ok) showToast('Station réparée', 'ok');
    else showToast('Réparation impossible', 'err');
    await refresh();
  });
  bindUi('#btn-upgrade', 'click', async () => {
    const r = await post('upgradeStation', { benchKey: state.benchKey });
    if (r && r.ok) showToast('Station améliorée', 'ok');
    else showToast('Amélioration impossible', 'err');
    await refresh();
  });
  bindUi('#btn-fav', 'click', async () => {
    if (!state.selected) return;
    const was = isFavorite(state.selected.id);
    await post('favorite', { recipeId: state.selected.id });
    showToast(was ? 'Retiré des favoris' : 'Ajouté aux favoris', 'ok');
    await refresh();
  });
  bindUi('#btn-queue', 'click', async () => {
    if (!state.selected) return;
    const batchEl = $('#batch');
    const batch = parseInt(batchEl && batchEl.value, 10) || 1;
    const r = await post('queue', { recipeId: state.selected.id, benchKey: state.benchKey, batch });
    if (r && r.ok === false) showToast('Impossible d\'ajouter à la file', 'err');
    else showToast('Ajouté à la file', 'ok');
    await loadQueue();
    updateFabIdleConsole();
    openTab('queue');
  });
  bindUi('#btn-shop', 'click', async () => {
    if (!state.selected) return;
    if (!isPinned(state.selected.id)) {
      const pin = await post('bookPinRecipe', { recipeId: state.selected.id });
      if (pin && pin.pins) {
        state.pinned = (pin.pins || []).map((x) => x.recipeId || x).filter(Boolean);
        syncPinButton(state.selected);
      }
    }
    const data = await post('shoppingFromPins', {});
    state.shop = (data && data.list) || [];
    renderShop();
    openTab('shop');
    showToast('Courses reconstruites depuis les suivis', 'ok');
  });
  bindUi('#btn-shop-clear', 'click', async () => {
    await post('shoppingClear', {});
    const data = await post('shoppingFromPins', {});
    state.shop = (data && data.list) || [];
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
    const id = state.selected.id;
    const was = isPinned(id);
    /* optimistic visual toggle */
    if (was) state.pinned = (state.pinned || []).filter((x) => x !== id);
    else state.pinned = [...(state.pinned || []), id];
    syncPinButton(state.selected);
    const cbName = was ? 'bookUnpinRecipe' : 'bookPinRecipe';
    post(cbName, { recipeId: id }).then((r) => {
      if (r && r.pins) {
        state.pinned = (r.pins || []).map((p) => p.recipeId || p).filter(Boolean);
      } else if (!(r && r.ok)) {
        /* revert optimistic */
        if (was) state.pinned = [...(state.pinned || []), id];
        else state.pinned = (state.pinned || []).filter((x) => x !== id);
      }
      syncPinButton(state.selected);
      showToast(was ? 'Suivi retiré' : 'Suivi dans le Carnet', r && r.ok !== false ? 'ok' : 'err');
      post('notify', { type: r && r.ok !== false ? 'success' : 'error', reason: was ? (r && r.ok !== false ? 'book_pinned' : (r && r.reason) || 'craft_failed') : (r && r.ok ? 'book_pinned' : (r && r.reason) || 'craft_failed') });
      beep(r && r.ok !== false ? 'click' : 'error');
    });
  });

  bindUi('#btn-compare', 'click', () => {
    if (!state.selected) return;
    const target = compareTargetFor(state.selected);
    if (!target) return;
    const found = state.recipes.find((r) => r.id === target);
    if (found) {
      selectRecipe(found);
      playTick();
    } else {
      showToast('Recette liée introuvable', 'warn');
    }
  });
  const btnObj = $('#btn-obj');
  if (btnObj) btnObj.addEventListener('click', () => {
    if (!state.selected) return;
    post('bookObjectiveRecipe', { recipeId: state.selected.id }).then((r) => {
      post('notify', { type: r && r.ok ? 'success' : 'error', reason: r && r.ok ? 'book_objective_added' : (r && r.reason) || 'craft_failed' });
      beep(r && r.ok ? 'click' : 'error');
      if (r && r.ok) showToast('Objectif ajouté au Carnet', 'ok');
    });
  });
  const btnBook = $('#btn-book');
  if (btnBook) btnBook.addEventListener('click', () => {
    post('bookOpenFromCraft', { page: 'dashboard' });
  });
  bindUi('#btn-path-objective', 'click', () => {
    if (!state.selected) return;
    post('bookObjectiveRecipe', { recipeId: state.selected.id, withMissing: true }).then((r) => {
      post('notify', { type: r && r.ok ? 'success' : 'error', reason: r && r.ok ? 'book_objective_added' : (r && r.reason) || 'craft_failed' });
      beep(r && r.ok ? 'click' : 'error');
      if (r && r.ok) showToast('Objectifs (recette + manquants) ajoutés', 'ok');
    });
  });
  bindUi('#btn-path-follow', 'click', () => {
    if (!state.selected) return;
    const id = state.selected.id;
    post('bookPinRecipe', { recipeId: id }).then((r) => {
      if (r && r.pins) {
        state.pinned = (r.pins || []).map((p) => p.recipeId || p).filter(Boolean);
        syncPinButton(state.selected);
      }
      post('bookOpenFromCraft', { page: 'objectives' });
    });
  });
  bindUi('#btn-artisans-book', 'click', () => {
    post('bookOpenFromCraft', { page: 'artisans' });
  });

  function markCond(ok, label) {
    const mark = ok ? '✓' : '✕';
    const cls = ok ? 'ok' : 'bad';
    return `<li class="${cls}"><span class="mark">${mark}</span> ${escapeHtml(label)}</li>`;
  }

  async function openTeachOverlay() {
    const overlay = $('#teach-overlay');
    if (!overlay || !state.selected) return;
    overlay.classList.remove('hidden');
    const title = $('#teach-title');
    if (title) title.textContent = `Enseigner · ${state.selected.label}`;
    const nearby = await post('teachNearby', {});
    const players = (nearby && nearby.players) || [];
    const list = $('#teach-players');
    const empty = $('#teach-empty');
    const startBtn = $('#teach-start');
    state.teachTarget = null;
    if (startBtn) startBtn.disabled = true;
    if (list) {
      list.innerHTML = '';
      players.forEach((pl) => {
        const li = document.createElement('li');
        li.innerHTML = `<button type="button" class="ghost small teach-pick" data-id="${pl.id}">${escapeHtml(pl.name)} <span class="t-l6">${pl.distance} m</span></button>`;
        list.appendChild(li);
      });
      list.querySelectorAll('.teach-pick').forEach((btn) => {
        btn.addEventListener('click', async () => {
          list.querySelectorAll('.teach-pick').forEach((b) => b.classList.remove('on'));
          btn.classList.add('on');
          state.teachTarget = Number(btn.dataset.id);
          const prev = await post('teachPreview', { recipeId: state.selected.id, target: state.teachTarget });
          paintTeachConds(prev);
          if (startBtn) startBtn.disabled = !(prev && prev.canStart);
        });
      });
    }
    if (empty) empty.classList.toggle('hidden', players.length > 0);
    const prev = await post('teachPreview', { recipeId: state.selected.id });
    paintTeachConds(prev);
  }

  function paintTeachConds(prev) {
    const ul = $('#teach-conds');
    if (!ul) return;
    const c = (prev && prev.conditions) || {};
    ul.innerHTML = [
      markCond(c.teachable !== false, 'Transmissible'),
      markCond(c.teacherKnown !== false, 'Connaissance'),
      markCond(c.teacherSpec !== false, 'Spécialisation'),
      markCond(c.teacherLevel !== false, 'Niveau'),
      c.proximity == null ? markCond(false, 'Proximité') : markCond(!!c.proximity, 'Proximité'),
      c.studentAlreadyKnown ? markCond(false, 'Élève : déjà connue') : markCond(c.studentKnown !== true, 'Élève : à enseigner'),
      c.studentSpec == null ? '' : markCond(!!c.studentSpec, 'Élève : spécialisation'),
    ].filter(Boolean).join('');
  }

  bindUi('#btn-teach', 'click', () => openTeachOverlay());
  bindUi('#teach-close', 'click', () => {
    const overlay = $('#teach-overlay');
    if (overlay) overlay.classList.add('hidden');
  });
  bindUi('#teach-start', 'click', async () => {
    if (!state.selected || !state.teachTarget) return;
    const r = await post('teachStart', { recipeId: state.selected.id, target: state.teachTarget });
    const overlay = $('#teach-overlay');
    if (overlay) overlay.classList.add('hidden');
    if (!(r && r.ok)) showToast('Enseignement refusé', 'err');
    else showToast('Enseignement lancé', 'ok');
  });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'selectRecipe' && msg.recipeId) {
      const r = (state.recipes || []).find((x) => x.id === msg.recipeId);
      if (r && typeof selectRecipe === 'function') selectRecipe(r);
    } else if (msg.action === 'open') {
      app.classList.remove('hidden');
      try { state.lastCraft = localStorage.getItem(LAST_CRAFT_KEY); } catch (_) { /* ignore */ }
      applyMenu(msg.data || {});
      // Session last: do not let applyMenu/selectRecipe overwrite fab-active
      if (msg.data && msg.data.session) {
        hydrateSession(msg.data.session);
      } else {
        loadQueue().then(() => updateFabIdleConsole());
      }
      openTab(state.sideTab || 'queue');
      if (msg.data && msg.data.ui && msg.data.ui.Accent) {
        document.documentElement.style.setProperty('--accent', msg.data.ui.Accent);
      }
      if (msg.data && msg.data.ui && msg.data.ui.Sounds) state.sounds = msg.data.ui.Sounds;
    } else if (msg.action === 'close' || msg.action === 'craftUiClose') {
      // Close craft catalogue only — do NOT cancel active craft / clear craftId.
      // Tracker (sibling #craft-tracker) keeps progress + completion ownership when pinned.
      app.classList.add('hidden');
    } else if (msg.action === 'queue') {
      state.queue = msg.queue || [];
      renderQueue();
    } else if (msg.action === 'craftFinished') {
      const same = !msg.craftId || !state.craftId || msg.craftId === state.craftId;
      state.progressGen = (state.progressGen || 0) + 1;
      state.crafting = false;
      if (same) {
        state.craftId = null;
        state.craftDurationMs = null;
      }
      showFabTerminated(msg.label);
    } else if (msg.action === 'craftAdvanced') {
      if (msg.craftId && state.craftId && msg.craftId !== state.craftId) return;
      state.crafting = true;
      state.craftId = msg.craftId || state.craftId;
      state.craftDurationMs = msg.duration;
      if (fabDoneTimer) {
        clearTimeout(fabDoneTimer);
        fabDoneTimer = null;
      }
      setFabCancelVisible(true);
      setFabState('active');
      const phaseEl = $('#fab-active-phase');
      if (phaseEl && msg.stepLabel) phaseEl.textContent = msg.stepLabel;
      runProgress(msg.duration, finishCraft);
    }
  });

  window.addEventListener('keydown', (e) => {
    // Only close craft when craft shell is visible — never steal Escape from the Survival Book
    if (e.key === 'Escape' && app && !app.classList.contains('hidden')) post('close', {});
  });
})();
