(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const $ = (s, r) => (r || document).querySelector(s);
  const book = $('#book-app');
  if (!book) return;

  const state = {
    open: false,
    page: 'dashboard',
    modules: {},
    cache: {},
    meta: {},
    planFilter: 'known',
    indexOpen: false,
    resSelId: null,
    resQ: '',
    resPeek: null,
    resList: [],
    noteEditId: null,
    noteViewId: null,
    notesList: [],
  };

  const OX_IMG_BASE = 'nui://ox_inventory/web/images/';

  /* v2.21.2 — never paint a partial book; mute all Carnet audio */
  let journalReady = false;
  let assetsReady = false;
  let firstPaintDone = false;
  let preloadPromise = null;
  const JOURNAL_PRELOAD = [
    'tex/paper_page.png',
    'tex/paper_sheet_tan.png',
    'tex/paper_sheet_worn.png',
    'tex/paper_sheet_lined.png',
    'tex/paper_page_alt.png',
    'tex/ref_cover.png',
    'tex/postit_yellow.png',
    'tex/postit_blue.png',
    'tex/postit_green.png',
    'tex/postit_pink.png',
  ];

  function playBookSound() { /* muted: no Howler / Audio / PlaySound */ }

  function preloadImage(src) {
    return new Promise((resolve) => {
      try {
        const img = new Image();
        img.onload = () => resolve(true);
        img.onerror = () => resolve(false);
        img.src = src;
      } catch (_) {
        resolve(false);
      }
    });
  }

  function waitFonts(ms) {
    try {
      if (document.fonts && document.fonts.ready) {
        return Promise.race([
          document.fonts.ready.then(() => true).catch(() => false),
          new Promise((r) => setTimeout(() => r(false), ms || 400)),
        ]);
      }
    } catch (_) { /* CEF without FontFaceSet */ }
    return new Promise((r) => setTimeout(() => r(false), 0));
  }

  function ensurePreload() {
    if (preloadPromise) return preloadPromise;
    preloadPromise = Promise.all([
      Promise.all(JOURNAL_PRELOAD.map(preloadImage)),
      waitFonts(400),
    ]).then(() => {
      assetsReady = true;
    }).catch(() => {
      assetsReady = true;
    });
    return preloadPromise;
  }

  function openingOverlay() { return document.getElementById('book-opening-overlay'); }

  function showOpeningOverlay() {
    const ov = openingOverlay();
    if (!ov) return;
    ov.classList.remove('hidden');
    ov.setAttribute('aria-hidden', 'false');
  }

  function hideOpeningOverlay() {
    const ov = openingOverlay();
    if (!ov) return;
    ov.classList.add('hidden');
    ov.setAttribute('aria-hidden', 'true');
  }

  function hasPageContent() {
    const L = document.getElementById('book-left');
    return !!(L && String(L.innerHTML || '').trim());
  }

  function hideBookShell() {
    hideOpeningOverlay();
    book.classList.add('hidden');
    book.classList.remove('is-open', 'is-opening');
    /* keep .is-ready after first success so reopen does not remount */
    book.setAttribute('aria-hidden', 'true');
    book.style.pointerEvents = 'none';
    /* do not display:none, do not wipe innerHTML, do not force opacity via cssText */
  }

  function revealBookShell() {
    hideOpeningOverlay();
    book.classList.remove('hidden', 'is-opening');
    book.classList.add('is-open', 'is-ready');
    book.setAttribute('aria-hidden', 'false');
    book.removeAttribute('hidden');
    book.style.pointerEvents = '';
    book.style.display = '';
    book.style.visibility = '';
    book.style.opacity = '';
  }

  function tryReveal() {
    if (!state.open) return;
    if (journalReady) {
      revealBookShell();
      return;
    }
    if (!assetsReady) return;
    if (!firstPaintDone && !hasPageContent()) return;
    journalReady = true;
    revealBookShell();
  }


  /* Primary edge tabs — short labels so they do not clip */
  const PRIMARY_TABS = [
    { id: 'dashboard', label: 'Accueil', mod: 'Dashboard', icon: 'fa-house' },
    { id: 'progression', label: 'Progrès', mod: 'Progression', icon: 'fa-chart-simple' },
    { id: 'objectives', label: 'Objectifs', mod: 'Objectives', icon: 'fa-bullseye' },
    { id: 'projects', label: 'Projets', mod: 'Projects', icon: 'fa-screwdriver-wrench' },
    { id: 'resources', label: 'Ressources', mod: 'Resources', icon: 'fa-box' },
    { id: 'blueprints', label: 'Plans', mod: 'Blueprints', icon: 'fa-map' },
    { id: 'artisans', label: 'Artisans', mod: 'Artisans', icon: 'fa-hammer' },
    { id: 'notes', label: 'Notes', mod: 'Notes', icon: 'fa-book' },
  ];

  /* Secondary tools via Index */
  const INDEX_ITEMS = [
    { id: 'network', label: 'Réseau', mod: 'Network', group: 'Contacts' },
    { id: 'productions', label: 'Productions', mod: 'Productions', group: 'Atelier' },
    { id: 'history', label: 'Historique', mod: 'History', group: 'Journal' },
    { id: 'discoveries', label: 'Découvertes', mod: 'Discoveries', group: 'Journal' },
    { id: 'pins', label: 'Épingles', mod: 'Pins', group: 'Terrain' },
    { id: 'nextUnlocks', label: 'Déblocages', mod: 'NextUnlocks', group: 'Terrain' },
    { id: 'canCraft', label: 'Faisable', mod: 'CanCraft', group: 'Terrain' },
    { id: 'suggestions', label: 'Suggestions', mod: 'Suggestions', group: 'Terrain' },
    { id: 'shopping', label: 'Courses', mod: 'Shopping', group: 'Outils' },
    { id: 'tree', label: 'Arbre craft', mod: 'CraftTree', group: 'Outils' },
    { id: 'orders', label: 'Commandes', mod: 'Orders', group: 'Outils' },
    { id: 'workshop', label: 'Mon atelier', mod: 'Workshop', group: 'Atelier' },
    { id: 'maintenance', label: 'Maintenance', mod: 'Maintenance', group: 'Atelier' },
    { id: 'stats', label: 'Stats', mod: 'Stats', group: 'Journal' },
  ];

  const TIER_LABEL = {
    novice: 'Novice',
    capable: 'Capable',
    seasoned: 'Chevronné',
    master: 'Maître',
    unknown: 'Inconnu',
  };

  function post(name, data = {}) {
    return fetch(`https://${res}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => ({}));
  }

  function postWithTimeout(name, data = {}, ms = 2500) {
    return Promise.race([
      post(name, data),
      new Promise((resolve) => setTimeout(() => resolve({ ok: false, timeout: true }), ms)),
    ]);
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function prettySkill(k) {
    const map = {
      crafting: 'Artisanat', survival: 'Survie', survie: 'Survie',
      ingenieur: 'Ingénieur', engineer: 'Ingénieur', engineering: 'Ingénierie',
      medic: 'Médecin', medecin: 'Médecin', medical: 'Médical',
      gunsmith: 'Armurier', armurier: 'Armurier',
      mechanic: 'Mécanique', cooking: 'Cuisine',
      scavenging: 'Récupération', farming: 'Culture',
      general: 'Général',
    };
    if (!k) return '';
    const key = String(k).toLowerCase();
    if (map[key]) return map[key];
    return String(k).replace(/[_-]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function humanizeItemId(id) {
    if (!id) return 'Objet';
    const map = { chest4: 'Caisse', medical_chest: 'Caisse médicale', ifak: 'IFAK' };
    if (map[id]) return map[id];
    let s = String(id).replace(/[_-]+/g, ' ').replace(/\d+$/, '').trim();
    if (!s) return 'Objet';
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  function displayItem(it) {
    if (!it) return "Quelque chose d'inconnu";
    if (typeof it === 'string') {
      if (/^[a-z0-9_]+$/.test(it) && !/\s/.test(it)) {
        const fromMeta = state.meta && state.meta.itemLabels && state.meta.itemLabels[it];
        if (fromMeta) return fromMeta;
        return humanizeItemId(it);
      }
      return it;
    }
    if (it.known === false || it.label === '???') return 'Ressource inconnue';
    if (it.label && it.label !== '???') return it.label;
    return humanizeItemId(it.item || it.id || it.recipeId) || 'Objet';
  }

  function oxImageUrl(entry) {
    if (!entry || entry.state === 'spotted') return '';
    const raw = entry.image && String(entry.image);
    if (raw && /^(nui|https?):\/\//i.test(raw)) return raw;
    if (raw && raw.indexOf('/') >= 0) return raw;
    const file = raw || (entry.item ? String(entry.item) + '.png' : '');
    if (!file) return '';
    const base = file.replace(/\.png$/i, '');
    return OX_IMG_BASE + encodeURIComponent(base) + '.png';
  }

  function encyDateFr(ts) {
    const p = parisDateParts(ts);
    if (!p) return '';
    const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    const name = months[Number(p.month) - 1] || '';
    return (p.day + ' ' + name + ' ' + p.year).trim();
  }

  function emptyPhrase(kind) {
    const m = {
      skills: "Aucune competence notée pour l'instant.",
      objective: 'Aucun objectif pour le moment.',
      project: 'Aucun projet suivi.',
      artisan: 'Aucun artisan rencontré.',
      discovery: "Rien de nouveau aujourd'hui.",
      unlock: 'Rien de proche à débloquer.',
      name: 'Nom encore à inscrire.',
      place: 'Lieu non noté.',
      date: '',
    };
    return m[kind] || "Rien de noté pour l'instant.";
  }

  function looksLikeId(s) {
    return typeof s === 'string' && /^[a-z0-9_]+$/.test(s) && !/\s/.test(s);
  }

  function itemLabel(it) {
    const lab = displayItem(it);
    if (!it) return esc(lab);
    if (typeof it !== 'string' && (it.known === false || it.label === '???')) {
      return `<span class="unknown">${esc(lab)}</span>`;
    }
    return esc(lab);
  }

  function pencilDate(ts) {
    if (ts) {
      const t = fmtTime(ts);
      if (t) return t;
    }
    try {
      return new Date().toLocaleDateString('fr-FR', { dateStyle: 'short' });
    } catch (_) {
      const d = new Date();
      const dd = String(d.getDate()).padStart(2, '0');
      const mm = String(d.getMonth() + 1).padStart(2, '0');
      return dd + '/' + mm + '/' + d.getFullYear();
    }
  }

  function objectiveTitle(o) {
    if (!o) return emptyPhrase('objective');
    const payload = o.payload || {};
    const recipeLab = payload.label || payload.recipeLabel || o.recipeLabel || o.label;
    const raw = o.title || '';
    if (raw && !looksLikeId(raw)) return raw;
    if (recipeLab && !looksLikeId(String(recipeLab))) return recipeLab;
    if (recipeLab) return displayItem(recipeLab);
    if (raw) return humanizeItemId(raw);
    return emptyPhrase('objective');
  }

  function kindDisplay(k) {
    if (!k) return '';
    const key = String(k).toLowerCase();
    if (key === 'manual' || key === 'recipe' || key === 'craft' || key === 'gather' || key === 'system' || key === 'internal') return '';
    return prettySkill(k);
  }

  function unlockNeed(x) {
    if (!x) return '';
    if (x.requiredSkillLabel) return 'Talent requis ' + x.requiredSkillLabel;
    if (x.requireSkill) return 'Talent requis ' + prettySkill(x.requireSkill);
    if (x.requireLevel != null && x.requireLevel !== '') return 'Niv. ' + String(x.requireLevel);
    return '';
  }

  function sketchClass(cat) {
    const c = String(cat || '').toLowerCase();
    if (/mech|eng|gear|metal|tool|craft|technic/.test(c)) return 'gear';
    if (/tool|atelier/.test(c)) return 'tool';
    return 'plant';
  }

  function fmtTime(ts) {
    if (!ts) return '';
    const d = new Date((Number(ts) < 1e12 ? Number(ts) * 1000 : Number(ts)));
    if (Number.isNaN(d.getTime())) return '';
    try {
      return d.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
    } catch (_) {
      return d.toISOString();
    }
  }

  function emptyBox(icon, title, hint) {
    return `<div class="empty-box"><i class="fa-solid ${icon}"></i><strong>${esc(title)}</strong><div class="empty">${esc(hint || '')}</div></div>`;
  }

  function pageHead(title, lede) {
    return `<div class="page-head">
      <p class="book-stamp">Carnet de survie</p>
      <h2 class="book-page-title">${esc(title)}</h2>
      ${lede ? `<p class="book-lede">${esc(lede)}</p>` : ''}
      <hr class="ink-rule" />
    </div>`;
  }

  function folio(n) {
    return `<div class="folio">— ${esc(n)} —</div>`;
  }

  function skillLabel(k) {
    return prettySkill(k);
  }

  function pickSpecialization(levels) {
    const meta = state.meta || {};
    if (meta.playerSpec && meta.playerSpec.label) return meta.playerSpec.label;
    if (typeof meta.specialization === 'string' && meta.specialization) return meta.specialization;
    if (meta.specialization && meta.specialization.label) return meta.specialization.label;
    return null;
  }

  function characterName() {
    return (state.meta && (state.meta.characterName || state.meta.playerName || state.meta.name)) || null;
  }

  function msSkillLines(levels) {
    const keys = Object.keys(levels || {});
    if (!keys.length) return `<p class="hand-note">${emptyPhrase('skills')}</p>`;
    return `<div class="ms-lines">${keys.map((k) => {
      const lv = levels[k] || {};
      const level = Math.max(0, Number(lv.level) || 0);
      const xp = Number(lv.xp);
      const totalXp = Number(lv.totalXp);
      const name = lv.label || prettySkill(k);
      const talents = Array.isArray(lv.talents) ? lv.talents.filter(Boolean) : [];
      const xpNote = Number.isFinite(xp)
        ? `<p class="ms-bonus hand-note">XP actuel : ${esc(xp)}${Number.isFinite(totalXp) && totalXp > 0 ? ` · total ${esc(totalXp)}` : ''}</p>`
        : '';
      const talentNote = talents.length
        ? `<p class="ms-bonus hand-note">Talents : ${esc(talents.join(', '))}</p>`
        : '';
      return `<div class="ms-line">
        <span class="ms-name">${esc(name)}</span>
        <span class="ms-lvl hand-note">Niveau ${esc(level)}</span>
        ${xpNote}
        ${talentNote}
      </div>`;
    }).join('')}</div>`;
  }

  function pickLastArtisan(d, st) {
    const metaA = state.meta && state.meta.lastArtisan;
    const fromObj = (a) => {
      if (!a) return '';
      if (typeof a === 'string') {
        if (/recens/i.test(a) || /contact/i.test(a) && /\d/.test(a)) return '';
        if (looksLikeId(a)) return '';
        return a;
      }
      return a.name || a.displayName || a.label || '';
    };
    let n = fromObj(metaA);
    if (n) return n;
    const list = d.artisans || [];
    n = fromObj(list[0]);
    if (n) return n;
    n = fromObj(d.lastArtisan);
    if (n) return n;
    const count = Number((st && st.artisans) || 0);
    if (count === 1) return 'Un contact noté, nom à compléter.';
    if (count > 1) return 'Quelques contacts notés, noms à compléter.';
    return emptyPhrase('artisan');
  }

  function projectNeeds(p) {
    if (!p) return [];
    const arr = p.needs || p.ingredients || p.missing || [];
    if (!Array.isArray(arr)) return [];
    return arr.slice(0, 3).map((x) => displayItem(x)).filter(Boolean);
  }

  function projectPct(p) {
    if (!p) return null;
    const n = p.progress != null ? p.progress : (p.pct != null ? p.pct : p.percent);
    if (n == null || n === '') return null;
    const num = Number(n);
    return Number.isFinite(num) ? num : null;
  }


  function metaOrDash(v) {
    if (v == null || v === '') return { text: '—', empty: true };
    return { text: String(v), empty: false };
  }

  function fieldRow(label, value) {
    const m = metaOrDash(value);
    return `<div class="field-row"><span class="fk">${esc(label)}</span><span class="fv${m.empty ? ' is-empty' : ''}">${esc(m.text)}</span></div>`;
  }

  function dayNoteFromStats(st, objs) {
    const open = st.objectivesOpen || (objs && objs.length) || 0;
    const arts = st.artisans || 0;
    const bp = st.blueprints || 0;
    if (open > 0) return `Aujourd'hui : ${open} objectif${open > 1 ? 's' : ''} encore ouverts. Tenir le cap.`;
    if (arts > 0) return `${arts} contact${arts > 1 ? 's' : ''} notés dans le carnet. Le réseau tient.`;
    if (bp > 0) return `${bp} plan${bp > 1 ? 's' : ''} archivés. Continuer les relevés de terrain.`;
    return 'Journée calme. Noter toute découverte avant la nuit.';
  }

  function modEnabled(mod) {
    if (!mod) return true;
    return state.modules[mod] !== false;
  }

  function leftEl() { return $('#book-left'); }
  function rightEl() { return $('#book-right'); }

  function setPages(leftHtml, rightHtml) {
    const L = leftEl();
    const R = rightEl();
    if (L) {
      L.innerHTML = leftHtml || '';
      L.classList.remove('page-turn');
    }
    if (R) {
      R.innerHTML = rightHtml || '';
      R.classList.remove('page-turn');
    }
    /* Compat: keep #book-main in sync for any external peek */
    const main = $('#book-main');
    if (main) main.innerHTML = (leftHtml || '') + (rightHtml || '');
    firstPaintDone = true;
    tryReveal();
  }

  function setContext() { /* no sidebar context in physical book */ }

  const TAB_MATERIALS = ['mat-terre', 'mat-olive', 'mat-ocre', 'mat-bleu', 'mat-brun', 'mat-beige', 'mat-cardboard', 'mat-cloth'];

  function renderTabs() {
    const nav = $('#book-tabs');
    if (!nav) return;
    nav.innerHTML = '';
    let ti = 0;
    PRIMARY_TABS.forEach((n) => {
      if (!modEnabled(n.mod)) return;
      const b = document.createElement('button');
      b.type = 'button';
      b.dataset.page = n.id;
      b.innerHTML = '<i class="fa-solid ' + n.icon + '" aria-hidden="true"></i><span>' + n.label + '</span>';
      b.classList.add(TAB_MATERIALS[ti % TAB_MATERIALS.length]);
      ti += 1;
      if (state.page === n.id) b.classList.add('active');
      b.addEventListener('click', () => {
        closeIndex();
        navigate(n.id);
      });
      nav.appendChild(b);
    });
  }

  function renderIndexGrid() {
    const grid = $('#book-index-grid');
    if (!grid) return;
    grid.innerHTML = '';
    INDEX_ITEMS.forEach((n) => {
      if (!modEnabled(n.mod)) return;
      const b = document.createElement('button');
      b.type = 'button';
      b.innerHTML = `<span class="idx-kicker">${esc(n.group)}</span>${esc(n.label)}`;
      b.addEventListener('click', () => {
        closeIndex();
        navigate(n.id);
      });
      grid.appendChild(b);
    });
  }

  function openIndex() {
    state.indexOpen = true;
    const ov = $('#book-index');
    if (ov) ov.classList.remove('hidden');
    renderIndexGrid();
  }

  function closeIndex() {
    state.indexOpen = false;
    const ov = $('#book-index');
    if (ov) ov.classList.add('hidden');
  }

  let nuiReq = 0;
  const moduleWaiters = new Map();
  const moduleBuf = new Map();
  let dashGen = 0;
  let lastDash = {};

  function takeModuleResult(reqId, ms) {
    if (moduleBuf.has(reqId)) {
      const payload = moduleBuf.get(reqId);
      moduleBuf.delete(reqId);
      return Promise.resolve(payload);
    }
    return new Promise((resolve) => {
      const t = setTimeout(() => {
        moduleWaiters.delete(reqId);
        resolve({ ok: false, timeout: true });
      }, ms);
      moduleWaiters.set(reqId, (payload) => {
        clearTimeout(t);
        resolve(payload || { ok: false });
      });
    });
  }

  async function loadModule(name, payload) {
    const key = name + JSON.stringify(payload || {});
    const reqId = ++nuiReq;
    const r = await post('bookModule', { module: name, payload: payload || {}, reqId });
    let out = r;
    if (r && r.pending) out = await takeModuleResult(reqId, 2500);
    if (out && out.ok) state.cache[key] = out.data;
    return out;
  }

  async function navigate(page) {
    state.page = page;
    renderTabs();
    setContext();
    /* Keep boot skeleton / last content. Never wipe to a blank Chargement spread. */
    const L0 = leftEl();
    if (L0 && !String(L0.innerHTML || '').trim()) {
      paintBootPages(
        (state.meta && state.meta.title) || 'Carnet de survie',
        (state.meta && state.meta.subtitle) || 'Journal de terrain'
      );
    }
    try {
      if (page === 'dashboard') await renderDashboard();
      else if (page === 'progression') await renderProgression();
      else if (page === 'objectives') await renderObjectives();
      else if (page === 'projects') await renderProjects();
      else if (page === 'resources') await renderResources();
      else if (page === 'blueprints') await renderPlans();
      else if (page === 'artisans') await renderArtisans();
      else if (page === 'network') await renderNetwork();
      else if (page === 'notes') await renderNotes();
      else if (page === 'productions') await renderProductions();
      else if (page === 'history' || page === 'discoveries') await renderHistory(page);
      else if (page === 'nextUnlocks') await renderNextUnlocks();
      else if (page === 'pins') await renderPins();
      else if (page === 'canCraft') await renderCanCraft();
      else if (page === 'suggestions') await renderSuggestions();
      else if (page === 'shopping') await renderShopping();
      else if (page === 'tree') await renderTree();
      else if (page === 'orders') await renderOrders();
      else if (page === 'workshop') await renderWorkshop();
      else if (page === 'maintenance') await renderMaintenance();
      else if (page === 'stats') await renderStats();
      else if (page === 'search') { /* filled by doSearch */ }
      else setPages(emptyBox('fa-circle-question', 'Module inconnu', 'Cette page n’existe pas dans le carnet.'), '');
    } catch (e) {
      setPages(`<p class="empty">Erreur: ${esc(e.message || e)}</p>`, '');
    }
  }

  /* ========== ACCUEIL (diegetic spread) ========== */
  function mergeDash(extra) {
    lastDash = Object.assign({}, lastDash, extra || {});
    lastDash._ready = true;
    return lastDash;
  }

  function paintDashboard(d, opts) {
    d = d || {};
    opts = opts || {};
    const st = d.stats || {};
    const prog = d.progression || {};
    const levels = prog.levels || {};
    const next = (d.nextUnlocks || [])[0];
    const objs = d.objectives || [];
    const pins = d.pins || [];
    const prods = (d.productions && d.productions.queue) || [];
    const projects = (d.productions && d.productions.projects) || [];
    const toCollect = (d.productions && (d.productions.toCollect || 0)) || 0;
    const collectStations = (d.productions && d.productions.stations) || [];
    const almost = (d.suggestions && d.suggestions.almost) || [];
    const canCraft = d.canCraft || [];
    const title = (state.meta && state.meta.title) || 'Carnet de survie';
    const charName = characterName();
    const spec = pickSpecialization(levels);
    const discovery = almost[0] || canCraft[0] || null;

    const place = (d && (d.place || d.location))
      || (state.meta && (state.meta.place || state.meta.location))
      || null;
    const placeLabel = place
      || (state.meta && state.meta.subtitle)
      || emptyPhrase('place');
    const dateStr = (d && (d.date || d.openedAt || d.day))
      || (state.meta && (state.meta.date || state.meta.openedAt || state.meta.day))
      || null;
    const daily = (state.meta && (state.meta.dailyNote || state.meta.noteDuJour)) || dayNoteFromStats(st, objs);
    const mainObj = (state.meta && (state.meta.mainObjective || state.meta.objectif))
      || (objs[0] && objectiveTitle(objs[0]))
      || (projects[0] && (projects[0].label || projects[0].name))
      || emptyPhrase('objective');
    const lastArtisan = pickLastArtisan(d, st);
    const lastDiscRaw = (state.meta && state.meta.lastDiscovery)
      || (discovery && (discovery.label || discovery.name))
      || null;
    const lastDisc = lastDiscRaw
      ? (looksLikeId(String(lastDiscRaw)) ? displayItem(lastDiscRaw) : lastDiscRaw)
      : emptyPhrase('discovery');

    const proj = projects[0];
    const needs = projectNeeds(proj);
    const pct = projectPct(proj);
    let projHtml;
    if (!proj) {
      projHtml = `<div class="scrap-body"><p class="hand-note">${emptyPhrase('project')}</p></div>`;
    } else {
      const pname = proj.label || proj.name || 'Projet';
      const needLis = needs.map((n) => `<li><span class="box"></span><span>${esc(n)}</span></li>`).join('');
      projHtml = `<div class="scrap-body">
        <strong>${esc(displayItem(pname))}</strong>
        ${pct != null ? `<p class="hand-note pencil">Avancement ~ ${esc(pct)}%</p>` : ''}
        ${needLis ? `<ul class="checklist">${needLis}</ul>` : ''}
        <p class="hand-note">annot. : tenir le chantier</p>
        ${modEnabled('Projects') ? `<a href="#" class="hand-link" data-open-project="${esc(proj.projectUid || '')}">voir le dossier →</a>` : ''}
      </div>`;
    }

    const objLis = objs.slice(0, 4).map((o) =>
      `<li class="${o.done ? 'done' : ''}"><span class="box ${o.done ? 'checked' : ''}"></span><span>${esc(objectiveTitle(o))}</span>${o.done ? '<span class="check-annot">ok ✓</span>' : ''}</li>`
    ).join('');

    const discCat = discovery && (discovery.category || discovery.kind || discovery.type);
    const discSketch = sketchClass(discCat);
    let discHtml;
    if (!discovery) {
      discHtml = `<div class="scrap-body"><p class="hand-note">${emptyPhrase('discovery')}</p></div>`;
    } else {
      const dlab = discovery.label || discovery.name || displayItem(discovery);
      const ddate = pencilDate(discovery.at || discovery.ts || discovery.createdAt);
      const annot = almost[0] ? 'Encore quelques pièces à réunir.' : 'Noté sur le terrain.';
      discHtml = `<div class="scrap-body">
        <strong>${esc(looksLikeId(String(dlab)) ? displayItem(dlab) : dlab)}</strong>
        <p class="id-date">${esc(ddate)}</p>
        ${discCat ? `<p class="hand-note">${esc(prettySkill(discCat))}</p>` : ''}
        <p class="hand-note">${annot}</p>
        <span class="stamp stamp-decouvert" style="font-size:9px;padding:2px 6px">DÉCOUVERT</span>
        <span class="ink-sketch ${discSketch}" aria-hidden="true"></span>
      </div>`;
    }

    const faint = opts.faint
      ? `<p class="hand-note" style="opacity:.55">Feuillet en cours de copie…</p>`
      : '';

    const left = `
      <div class="accueil-hero">
        <p class="book-stamp">Carnet de terrain</p>
        <div class="id-polaroid accueil-sheet">
          <span class="tape top-r extra-tape"></span>
          <span class="paperclip"></span>
          <div class="id-photo" aria-hidden="true"><span class="id-silhouette"></span></div>
          <p class="hand-name">${esc(charName || emptyPhrase('name'))}</p>
          <p class="id-date">${esc(pencilDate(dateStr))}</p>
          <p class="id-place hand-note${place ? '' : ' pencil'}">${esc(placeLabel)}</p>
        </div>
        <h2 class="accueil-title">${esc(String(title))}</h2>
        <div class="accueil-seal-row">
          ${spec ? `<span class="stamp stamp-specialisation">SPÉCIALISATION · ${esc(spec)}</span>` : `<span class="stamp">Terrain</span>`}
          <span class="stamp seal">SC<br/>OK</span>
          <span class="ink-sketch gear" aria-hidden="true"></span>
        </div>
        <hr class="ink-rule" />
      </div>
      <h3 class="section-title">Compétences</h3>
      ${msSkillLines(levels)}
      <div class="day-note accueil-sheet"><span class="tape top-l"></span>${esc(daily)}</div>
      ${faint}
      ${folio('i')}`;

    const right = `
      <div class="situation-page">
      <p class="book-stamp">Feuillet du jour</p>
      <h2 class="book-page-title">Situation</h2>
      <hr class="ink-rule" />

      <p class="sit-block"><span class="sit-k">Objectif principal</span>
      <span class="sit-v hand-note">${esc(mainObj)}</span></p>
      <p class="sit-block"><span class="sit-k">Dernier contact</span>
      <span class="sit-v hand-note">${esc(lastArtisan)}</span></p>
      <p class="sit-block"><span class="sit-k">Dernière découverte</span>
      <span class="sit-v hand-note">${esc(lastDisc)}</span></p>

      <div class="scrap-note rot-l tint-warm accueil-sheet">
        <span class="tape top-l"></span>
        <span class="tape top-r"></span>
        <span class="paperclip"></span>
        <div class="scrap-title">Projet principal</div>
        ${projHtml}
      </div>

      <h3 class="section-title">Objectifs</h3>
      <ul class="checklist">
        ${objLis || `<li><span class="box"></span><span class="hand-note">${emptyPhrase('objective')}</span></li>`}
      </ul>

      <div class="scrap-note rot-r tint-cool accueil-sheet" style="margin-top:14px">
        <span class="tape top-l"></span>
        <span class="paperclip"></span>
        <div class="scrap-title">Dernière découverte</div>
        ${discHtml}
      </div>

      <div class="dossier-sheet accueil-sheet">
        <span class="tape top-l"></span>
        <span class="paperclip"></span>
        <div class="dossier-mark">Prochain déblocage</div>
        ${next
          ? `<h4>${esc(next.label || displayItem(next))}</h4>
             <p class="hand-note" style="font-size:14px;margin:4px 0">${esc(unlockNeed(next))}</p>`
          : `<p class="hand-note">${emptyPhrase('unlock')}</p>`}
      </div>

      ${pins.length ? `<p class="hand-note" style="margin-top:10px">Épingles : ${pins.length}.</p>` : ''}
      ${toCollect > 0 ? `<p class="hand-note">Productions à récupérer : ${toCollect}${collectStations.length ? ' — ' + collectStations.map((st) => esc(st.stationLabel || st.stationUid) + ' ×' + (st.count || 1)).join(', ') : ''}.</p>` : ''}
      ${prods.length ? `<p class="hand-note">File atelier : ${prods.slice(0, 2).map((q) => esc(q.label || displayItem(q))).join(', ')}</p>` : ''}
      ${folio('ii')}
      </div>`;

    setPages(left, right);
    const R = rightEl();
    if (R) R.querySelectorAll('[data-open-project]').forEach((a) => {
      a.addEventListener('click', (ev) => {
        ev.preventDefault();
        navigate('projects');
      });
    });
  }

  function applyDashboardPayload(payload, token) {
    if (token != null && token !== dashGen) return;
    if (state.page !== 'dashboard') return;
    const r = payload || {};
    if (r.ok && r.data && !r.pending) {
      paintDashboard(mergeDash(r.data));
      return;
    }
    if (r.data && !r.pending) {
      paintDashboard(mergeDash(r.data));
      return;
    }
    /* pending / fail / timeout: Accueil from meta + emptyPhrase scraps */
    paintDashboard(lastDash, { fromMeta: true, faint: !!r.pending });
  }

  async function renderDashboard() {
    const token = ++dashGen;
    lastDash = {};
    /* Immediate Accueil from ShellMeta — pages never stay empty / Chargement. */
    paintDashboard({}, { fromMeta: true, faint: true });
    post('bookDashboard', {}).then((r) => {
      if (token !== dashGen) return;
      if (r && r.ok && r.data && !r.pending) applyDashboardPayload(r, token);
    }).catch(() => {});
    window.setTimeout(() => {
      if (token !== dashGen || state.page !== 'dashboard') return;
      if (!lastDash._ready) {
        paintDashboard(lastDash, { fromMeta: true, faint: false });
      }
    }, 2000);
  }


  /* ========== PROGRESSION ========== */
  async function renderProgression() {
    const r = await loadModule('progression');
    const p = (r && r.data) || {};
    const unlocks = await loadModule('nextUnlocks');
    const next = (unlocks && unlocks.data) || [];
    if (!p.available) {
      setPages(
        pageHead('Progrès', 'Cahier de competences') +
          `<p class="hand-note">Les competences ne sont pas encore lisibles.</p>`,
        folio('12')
      );
      return;
    }
    const levels = p.levels || {};
    const spec = pickSpecialization(levels);
    const left = `
      <p class="book-stamp">Cahier de progression</p>
      <h2 class="book-page-title">Compétences</h2>
      <p class="hand-note">Lignes de manuscrit — expérience actuelle.</p>
      <hr class="ink-rule" />
      ${spec ? `<span class="stamp stamp-specialisation">SPÉCIALISATION · ${esc(spec)}</span>` : ''}
      <span class="ink-sketch tool" aria-hidden="true"></span>
      ${msSkillLines(levels)}
      ${folio('12')}`;
    const right = `
      <p class="book-stamp">Annexes</p>
      <h2 class="book-page-title">Déblocages proches</h2>
      <hr class="ink-rule" />
      <div class="unlock-list">${next.length ? next.map((x) => `
        <div class="unlock-row">
          <span>${esc(x.label)}</span>
          <span class="stamp" style="transform:rotate(-2deg);padding:2px 6px;font-size:9px;margin:0">${esc(unlockNeed(x))}</span>
        </div>`).join('') : `<p class="hand-note">${emptyPhrase('unlock')}</p>`}
      </div>
      <p class="hand-note" style="margin-top:14px">Tampons de niveau = jalons notés à la main.</p>
      ${folio('13')}`;
    setPages(left, right);
  }


  async function renderNextUnlocks() {
    const r = await loadModule('nextUnlocks');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Déblocages', 'Ce qui est presque à portée') +
        `<div class="unlock-list">${arr.length ? arr.map((x) => `
          <div class="unlock-row"><span>${esc(x.label)}</span>
          <span class="stamp" style="transform:rotate(-2deg);padding:2px 6px;font-size:9px;margin:0">${esc(unlockNeed(x))}</span></div>`).join('') : `<p class="hand-note">${emptyPhrase('unlock')}</p>`}
        </div>${folio('40')}`,
      `<p class="hand-note">Ces pages listent ce qui est presque à portée — sans spoil des recettes lointaines.</p>${folio('41')}`
    );
  }

  /* ========== OBJECTIVES ========== */
  async function renderObjectives() {
    const r = await loadModule('objectives');
    const arr = (r && r.data) || [];
    const pinsR = modEnabled('Pins') ? await loadModule('pins') : { data: [] };
    const pinIds = new Set(((pinsR && pinsR.data) || []).map((p) => p.recipeId));

    const left = `
      <p class="book-stamp">Missions de terrain</p>
      <h2 class="book-page-title">Objectifs</h2>
      <p class="hand-note">Checklist et papillons collés — priorité et suivi.</p>
      <hr class="ink-rule" />
      <div class="note-editor">
        <div class="editor-label">Nouvel objectif</div>
        <div class="row-actions" style="margin-top:0">
          <input id="obj-title" type="text" placeholder="Titre de l'objectif…" style="flex:1;margin-top:0" />
          <button type="button" class="primary" id="obj-add">Ajouter</button>
        </div>
      </div>
      ${folio('20')}`;

    let cards = '';
    if (!arr.length) {
      cards = `<p class="hand-note">${emptyPhrase('objective')}</p>`;
    } else {
      const top = arr.filter((o) => !(o.payload && o.payload.parentObjectiveId));
      cards = `<div id="obj-grid">${top.map((o) => {
        const rid = o.payload && o.payload.recipeId;
        const pinned = rid && pinIds.has(rid);
        const kd = kindDisplay(o.kind);
        const kindLine = kd ? `<span class="hand-note">${esc(kd)}${pinned ? ' · épinglé' : ''}</span>` : (pinned ? '<span class="hand-note">épinglé</span>' : '');
        const kids = o.children || [];
        const checks = (kids.length ? kids : [o]).map((c) => {
          const done = !!(c.done || c.liveDone);
          const prog = (c.need != null && c.owned != null) ? ` ${c.owned}/${c.need}` : '';
          return `<li class="${done ? 'done' : ''}"><span class="box ${done ? 'checked' : ''}"></span><span>${esc((c.title || objectiveTitle(c)) + prog)}</span>${done ? '<span class="check-annot">✓</span>' : ''}</li>`;
        }).join('');
        return `<article class="sticky-note ${o.done ? 'done' : ''}" data-id="${o.id}">
          <div class="st-title">${esc(objectiveTitle(o))}</div>
          ${o.done ? '<span class="check-annot">fait — rayé</span>' : ''}
          <ul class="checklist">${checks}</ul>
          ${kindLine}
          <div class="st-actions obj-actions">
            ${!o.done ? `<button type="button" class="primary small" data-act="done">Terminer</button>` : ''}
            ${rid && modEnabled('Pins') && !pinned ? `<button type="button" class="ghost small" data-act="pin" data-rid="${esc(rid)}">Épingler</button>` : ''}
            ${rid && modEnabled('CraftTree') ? `<button type="button" class="ghost small" data-act="tree" data-rid="${esc(rid)}">Arbre</button>` : ''}
            <button type="button" class="ghost small" data-act="del">Retirer</button>
          </div>
          <p class="hand-note id-date">${esc(fmtTime(o.createdAt))}</p>
        </article>`;
      }).join('')}</div>`;
    }
    const right = `
      <p class="book-stamp">Suivi</p>
      <h2 class="book-page-title">Papillons</h2>
      <hr class="ink-rule" />
      ${cards}
      ${folio('21')}`;
    setPages(left, right);

    const addBtn = $('#obj-add');
    if (addBtn) addBtn.onclick = async () => {
      const title = ($('#obj-title') || {}).value;
      const t = (title || '').trim();
      if (!t) return;
      await post('bookAction', { action: 'addObjective', payload: { title: t, kind: 'manual' } });
      navigate('objectives');
    };
    const grid = $('#obj-grid');
    if (grid) grid.onclick = async (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      const card = btn.closest('[data-id]');
      const id = Number(card && card.dataset.id);
      const act = btn.dataset.act;
      if (act === 'done') await post('bookAction', { action: 'completeObjective', payload: { id } });
      if (act === 'del') await post('bookAction', { action: 'removeObjective', payload: { id } });
      if (act === 'pin' && btn.dataset.rid) await post('bookAction', { action: 'pin', payload: { recipeId: btn.dataset.rid } });
      if (act === 'tree' && btn.dataset.rid) {
        state._treePrefill = btn.dataset.rid;
        navigate('tree');
        return;
      }
      navigate('objectives');
    };
  }


  /* ========== PROJECTS ========== */
  async function renderProjects() {
    const r = await loadModule('projects');
    const d = (r && r.data) || { queue: [], projects: [] };
    const projects = d.projects || [];
    const left = `
      <p class="book-stamp">Chantiers</p>
      <h2 class="book-page-title">Projets</h2>
      <p class="hand-note">Plans techniques annotés — flèches et listes de ressources.</p>
      <hr class="ink-rule" />
      <p class="hand-note">Chaque chantier ouvert apparaît ici comme un dossier de terrain.</p>
      ${folio('30')}`;
    let right;
    if (!projects.length) {
      right = `<p class="hand-note">${emptyPhrase('project')}</p>` + folio('31');
    } else {
      right = `<div id="proj-grid">${projects.map((p) => `
        <article class="tech-plan" data-rid="${esc(p.recipeId || '')}">
          <span class="paperclip"></span>
          <div class="tp-head">
            <h4>${esc(p.label || displayItem(p.name) || 'Projet')}</h4>
            <span class="stamp" style="margin:0;transform:rotate(3deg);padding:3px 6px;font-size:9px">${esc(p.status === 'open' ? 'ouvert' : (p.status || 'ouvert'))}</span>
          </div>
          <div class="tp-arrow">→ ${p.isOwner ? 'Responsable du chantier' : 'Contributeur'}</div>
          <ul class="checklist">
            <li><span class="box"></span><span>Composants via arbre / courses</span></li>
            <li><span class="box"></span><span>Suivi d'avancement terrain</span></li>
          </ul>
          <div class="tp-annot">annot. : vérifier stocks avant reprise</div>
          <div class="row-actions">
            ${p.recipeId && modEnabled('CraftTree') ? `<button type="button" class="ghost small" data-act="tree" data-rid="${esc(p.recipeId)}">Arbre</button>` : ''}
            ${p.recipeId && modEnabled('Shopping') ? `<button type="button" class="ghost small" data-act="shop" data-rid="${esc(p.recipeId)}">Courses</button>` : ''}
          </div>
        </article>`).join('')}</div>${folio('31')}`;
    }
    setPages(left, right);
    const grid = $('#proj-grid');
    if (grid) grid.onclick = (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      if (btn.dataset.act === 'tree') { state._treePrefill = btn.dataset.rid; navigate('tree'); }
      if (btn.dataset.act === 'shop') { state._shopPrefill = btn.dataset.rid; navigate('shopping'); }
    };
  }


  /* ========== RESOURCES (encyclopédie de terrain) ========== */
  function paintResources() {
    const arr = state.resList || [];
    const q = String(state.resQ || '').trim().toLowerCase();
    const shown = arr.filter((x) => {
      if (!q) return true;
      if (x.state === 'spotted') return false;
      const lab = String(x.label || '').toLowerCase();
      return lab.indexOf(q) >= 0;
    });
    let selected = null;
    if (state.resSelId != null) {
      selected = arr.find((x) => x.id === state.resSelId) || null;
    }

    let left;
    if (state.resPeek) {
      const pk = state.resPeek;
      const role = pk.role === 'result'
        ? 'Résultat connu de cet assemblage.'
        : 'Sert d’ingrédient dans cet assemblage.';
      left = `
        <div class="ency-fiche">
          <span class="tape top-l"></span>
          <p class="hand-note"><a href="#" class="hand-link" data-act="back-res">← retour à la fiche</a></p>
          <p class="book-stamp">Schéma noté</p>
          <h2 class="book-page-title">${esc(pk.label || 'Assemblage')}</h2>
          <hr class="ink-rule" />
          <p class="hand-note">${esc(role)}</p>
        </div>${folio('50')}`;
    } else if (!selected) {
      left = `
        <div class="ency-empty">
          <p class="book-stamp">Encyclopédie de terrain</p>
          <h2 class="book-page-title">Fiche</h2>
          <p class="hand-note pencil">Rien de documenté pour l’instant.</p>
          <span class="ink-sketch tool" aria-hidden="true"></span>
        </div>${folio('50')}`;
    } else if (selected.state === 'spotted') {
      left = `
        <div class="ency-fiche spotted">
          <span class="tape top-r"></span>
          <p class="book-stamp">Croquis incomplet</p>
          <h2 class="book-page-title">Non identifié</h2>
          <div class="ency-polaroid rot-sp">
            <span class="tape top-l"></span>
            <div class="ency-sil" aria-hidden="true"><span>?</span></div>
          </div>
          <p class="hand-note">Objet encore non identifié.</p>
          <p class="ency-st">repéré</p>
        </div>${folio('50')}`;
    } else {
      const documented = selected.state === 'documented';
      const img = oxImageUrl(selected);
      const annot = documented && selected.annot
        ? `<span class="ency-annot">${esc(selected.annot)}</span>`
        : '';
      const obs = documented && selected.description
        ? `<div class="ency-block"><p class="ency-sec">Observations</p><p class="hand-note">${esc(selected.description)}</p></div>`
        : '';
      const uses = (documented && Array.isArray(selected.knownUses) && selected.knownUses.length)
        ? `<div class="ency-block"><p class="ency-sec">Utilisations connues</p><ul class="ency-uses">${selected.knownUses.map((u, ui) =>
            `<li><a href="#" class="hand-link" data-act="use" data-ui="${ui}">${esc(u.label || 'assemblage')}</a></li>`
          ).join('')}</ul></div>`
        : '';
      const found = documented && selected.discoveredAt
        ? `<p class="hand-note">Dernière découverte : ${esc(encyDateFr(selected.discoveredAt))}</p>`
        : (selected.discoveredAt ? `<p class="hand-note">Dernière découverte : ${esc(encyDateFr(selected.discoveredAt))}</p>` : '');
      const noteVal = documented ? (selected.note || '') : (selected.note || '');
      const noteBlock = (selected.state === 'identified' || documented) ? `
          <div class="ency-note">
            <p class="ency-sec">Note personnelle</p>
            <textarea class="ency-note-ink" id="ency-note" rows="3" placeholder="quelques mots au crayon…">${esc(noteVal)}</textarea>
            <button type="button" class="ency-ink-act" data-act="save-note">noter</button>
          </div>` : '';
      const follow = (selected.state === 'identified' || documented) ? `
          <button type="button" class="note-stamp ency-follow" data-act="follow">${selected.pinned ? 'NE PLUS SUIVRE' : 'SUIVRE CETTE RESSOURCE'}</button>` : '';
      left = `
        <div class="ency-fiche">
          <span class="tape top-l"></span>
          <p class="book-stamp">Fiche de terrain</p>
          <h2 class="book-page-title">${esc(selected.label || '')}</h2>
          <p class="ency-st">${documented ? 'documenté' : 'identifié'}</p>
          <div class="ency-polaroid">
            <span class="tape top-r"></span>
            ${img ? `<img class="ency-ox" alt="${esc(selected.label || '')}" />` : '<div class="ency-sil" aria-hidden="true"></div>'}
            ${annot}
          </div>
          ${obs}
          ${uses}
          ${found}
          ${noteBlock}
          ${follow}
        </div>${folio('50')}`;
    }

    const filterHtml = arr.length >= 8 ? `
        <label class="ency-index-field">
          <span>repères</span>
          <input type="text" class="ency-ink-field" id="ency-q" value="${esc(state.resQ || '')}" autocomplete="off" />
        </label>` : '';

    let slips;
    if (!arr.length) {
      slips = `<p class="hand-note pencil">Les feuillets restent blancs. Rien vu de près.</p>
        <span class="ink-sketch plant" aria-hidden="true"></span>`;
    } else if (!shown.length) {
      slips = `<p class="hand-note pencil">Rien sous ce repère.</p>`;
    } else {
      slips = `<div class="ency-index">${shown.map((x, i) => {
        const on = x.id === state.resSelId ? ' is-on' : '';
        const st = x.state === 'spotted' ? 'repéré' : (x.state === 'documented' ? 'documenté' : 'identifié');
        if (x.state === 'spotted') {
          return `<article class="ency-slip spotted${on}" data-idx="${i}">
            <div class="ency-sil" aria-hidden="true"><span>?</span></div>
            <div class="ency-name">???</div>
            <div class="ency-st">${st}</div>
          </article>`;
        }
        const img = oxImageUrl(x);
        return `<article class="ency-slip${on}" data-idx="${i}">
          <div class="ency-thumb">${img ? `<img class="ency-ox" alt="${esc(x.label || '')}" />` : '<div class="ency-sil" aria-hidden="true"></div>'}</div>
          <div class="ency-name">${esc(x.label || '')}</div>
          <div class="ency-st">${st}</div>
        </article>`;
      }).join('')}</div>`;
    }

    const right = `
      <p class="book-stamp">Index des matériaux</p>
      <h2 class="book-page-title">Ressources</h2>
      <p class="hand-note">On n’inscrit que ce qu’on a vu de près.</p>
      <hr class="ink-rule" />
      ${filterHtml}
      ${slips}${folio('51')}`;

    setPages(left, right);
    const L0 = leftEl();
    const R0 = rightEl();
    if (L0 && selected && selected.state !== 'spotted') {
      const im = L0.querySelector('img.ency-ox');
      if (im) {
        const url = oxImageUrl(selected);
        im.onerror = () => { im.hidden = true; };
        if (url) im.src = url;
        else im.hidden = true;
      }
    }
    if (R0) {
      R0.querySelectorAll('.ency-slip').forEach((el, i) => {
        const row = shown[i];
        const im = el.querySelector('img.ency-ox');
        if (!im || !row) return;
        const url = oxImageUrl(row);
        im.onerror = () => { im.hidden = true; };
        if (url) im.src = url;
        else im.hidden = true;
      });
    }

    const L = leftEl();
    const R = rightEl();
    if (R) {
      R.querySelectorAll('.ency-slip').forEach((el) => {
        el.onclick = () => {
          const idx = Number(el.getAttribute('data-idx'));
          const row = shown[idx];
          if (!row) return;
          state.resSelId = row.id;
          state.resPeek = null;
          paintResources();
        };
      });
      const qEl = R.querySelector('#ency-q');
      if (qEl) {
        qEl.oninput = () => {
          state.resQ = qEl.value || '';
          state._resCaret = qEl.selectionStart;
          paintResources();
        };
        if (state._resCaret != null) {
          try {
            qEl.focus();
            const n = qEl.value.length;
            const c = Math.max(0, Math.min(state._resCaret, n));
            qEl.setSelectionRange(c, c);
          } catch (_) {}
        }
      }
    }
    if (L) {
      L.querySelectorAll('[data-act]').forEach((btn) => {
        btn.onclick = async (ev) => {
          ev.preventDefault();
          const act = btn.getAttribute('data-act');
          const cur = (state.resList || []).find((x) => x.id === state.resSelId);
          if (act === 'back-res') {
            state.resPeek = null;
            paintResources();
            return;
          }
          if (act === 'use') {
            const ui = Number(btn.getAttribute('data-ui'));
            const use = cur && Array.isArray(cur.knownUses) ? cur.knownUses[ui] : null;
            if (use && use.label) {
              state.resPeek = { label: use.label, role: use.role, recipeId: use.recipeId };
              paintResources();
            }
            return;
          }
          if (!cur || cur.state === 'spotted' || !cur.item) return;
          if (act === 'follow') {
            await post('bookAction', {
              action: cur.pinned ? 'unpin' : 'pin',
              payload: { kind: 'resource', item: cur.item },
            });
            await renderResources();
            return;
          }
          if (act === 'save-note') {
            const ta = L.querySelector('#ency-note');
            const note = ta ? ta.value : '';
            await post('bookAction', {
              action: 'saveResourceNote',
              payload: { item: cur.item, note },
            });
            await renderResources();
          }
        };
      });
    }
  }

  async function renderResources() {
    const r = await loadModule('resources');
    state.resList = (r && r.data) || [];
    if (state.resSelId && !(state.resList || []).some((x) => x.id === state.resSelId)) {
      state.resSelId = null;
    }
    paintResources();
  }


  /* ========== PLANS ========== */
  async function renderPlans() {
    const r = await loadModule('blueprints');
    const arr = (r && r.data) || [];
    const filter = state.planFilter || 'known';
    const left = `
      <p class="book-stamp">Schémas</p>
      <h2 class="book-page-title">Plans</h2>
      <p class="hand-note">Feuillets bleus scotchés — connus, fragments, verrouillés.</p>
      <hr class="ink-rule" />
      <div class="plan-tabs">
        <button type="button" data-f="known" class="${filter === 'known' ? 'active' : ''}">Connus (${arr.length})</button>
        <button type="button" data-f="incomplete" class="${filter === 'incomplete' ? 'active' : ''}">Incomplets</button>
        <button type="button" data-f="fragments" class="${filter === 'fragments' ? 'active' : ''}">Fragments</button>
        <button type="button" data-f="locked" class="${filter === 'locked' ? 'active' : ''}">Verrouillés</button>
        <button type="button" data-f="recent" class="${filter === 'recent' ? 'active' : ''}">Récents</button>
      </div>${folio('60')}`;

    let gridHtml = '';
    if (filter === 'known' || filter === 'recent') {
      const list = filter === 'recent' ? arr.slice(0, 8) : arr;
      if (!list.length) {
        gridHtml = emptyBox('fa-scroll', 'Aucun plan connu', 'Apprenez des blueprints via le craft pour les archiver ici.');
      } else {
        gridHtml = list.map((x, i) => `
          <article class="blueprint-sheet folded">
            <span class="tape top-l"></span>
            ${i % 3 === 0 ? '<span class="paperclip"></span>' : ''}
            <div class="bp-mark">Plan technique · connu</div>
            <h4>${esc(x.label || displayItem(x.id) || 'Plan')}</h4>
            <div class="bp-id"></div>
            <p class="bp-annot">annot. : fragment collé — vérifier cotes avant atelier</p>
            <span class="stamp stamp-ouvert" style="font-size:9px;padding:2px 6px">OUVERT</span>
          </article>`).join('');
      }
    } else {
      const hints = {
        incomplete: ['fa-puzzle-piece', 'Pas de plans incomplets', 'Les schémas partiels apparaîtront ici lorsqu\'ils seront supportés.'],
        fragments: ['fa-clone', 'Aucun fragment', 'Les fragments de plans collectés s\'assemblent progressivement.'],
        locked: ['fa-lock', 'Rien de verrouillé listé', 'Les plans au-delà de votre connaissance restent hors dossier.'],
      };
      const h = hints[filter] || hints.incomplete;
      gridHtml = emptyBox(h[0], h[1], h[2]);
    }
    setPages(left, gridHtml + folio('61'));
    const L = leftEl();
    if (L) L.querySelectorAll('.plan-tabs button').forEach((b) => {
      b.onclick = () => { state.planFilter = b.dataset.f; renderPlans(); };
    });
  }


  /* ========== ARTISANS ========== */
  async function renderArtisans() {
    const r = await loadModule('artisans');
    const arr = (r && r.data) || [];
    const left = `
      <p class="book-stamp">Carnet d'adresses</p>
      <h2 class="book-page-title">Artisans</h2>
      <p class="hand-note">Cartes de visite clipées — tiers qualitatifs uniquement.</p>
      <hr class="ink-rule" />
      <p class="hand-note">Pas d'inventaire exact — rencontres et spécialités seulement.</p>
      ${folio('70')}`;
    let right;
    if (!arr.length) {
      right = `<p class="hand-note">${emptyPhrase('artisan')}</p>` + folio('71');
    } else {
      right = arr.map((a) => {
        const note = (a.meta && a.meta.note) || '';
        const fav = !!(a.meta && a.meta.favorite);
        return `<article class="visit-card business-card">
          <span class="paperclip"></span>
          <div class="photo-clip" title="Portrait manquant"></div>
          <h4>${esc(a.displayName)}${fav ? ' ★' : ''}</h4>
          <div class="vc-meta">${esc(prettySkill(a.specialty || 'general'))} · ${esc(TIER_LABEL[a.tier] || prettySkill(a.tier) || 'Inconnu')}</div>
          <div class="vc-meta">Dernière rencontre · ${esc(fmtTime(a.metAt) || emptyPhrase('date'))}</div>
          <div class="vc-note">${note ? esc(note) : 'Services : échange RP / craft — noter après rencontre'}</div>
          ${a.tier === 'master' || a.tier === 'seasoned' ? '<span class="stamp stamp-valide" style="font-size:9px;padding:2px 6px;margin-top:6px">VALIDÉ</span>' : ''}
        </article>`;
      }).join('') + folio('71');
    }
    setPages(left, right);
  }


  /* ========== NETWORK ========== */
  async function renderNetwork() {
    const r = await loadModule('network');
    const net = (r && r.data) || {};
    const keys = Object.keys(net);
    const left = `
      <p class="book-stamp">Croquis de relations</p>
      <h2 class="book-page-title">Réseau</h2>
      <p class="hand-note">Nœuds à l'encre — densités par spécialité.</p>
      <hr class="ink-rule" />
      ${folio('72')}`;
    let right;
    if (!keys.length) {
      right = emptyBox('fa-network-wired', 'Réseau vide', 'Chaque spécialité rencontrée devient un domaine ici.') + folio('73');
    } else {
      const nodes = keys.map((k) => {
        const list = net[k] || [];
        return `<span class="net-node">${esc(prettySkill(k))}<span class="nn-count">${list.length} contact${list.length > 1 ? 's' : ''}</span></span>`;
      }).join('');
      const links = keys.map((k) => {
        const list = net[k] || [];
        const names = list.slice(0, 3).map((a) => a.displayName).join(', ');
        return `${esc(prettySkill(k))} → ${esc(names) || emptyPhrase('artisan')}${list.length > 3 ? '…' : ''}`;
      }).join('<br/>');
      right = `<div class="net-sketch">${nodes}<div class="net-links">${links}</div></div>${folio('73')}`;
    }
    setPages(left, right);
  }


  const POSTIT_CYCLE = ['yellow', 'blue', 'green', 'pink'];
  const NOTE_ROTS = ['rot-a', 'rot-b', 'rot-c', 'rot-d', 'rot-e'];

  function parisDateParts(ts) {
    const d = (ts != null && ts !== '')
      ? new Date((Number(ts) < 1e12 ? Number(ts) * 1000 : Number(ts)))
      : new Date();
    if (Number.isNaN(d.getTime())) return null;
    try {
      const parts = new Intl.DateTimeFormat('fr-FR', {
        timeZone: 'Europe/Paris',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).formatToParts(d);
      const get = (t) => ((parts.find((p) => p.type === t) || {}).value || '');
      return { day: get('day'), month: get('month'), year: get('year') };
    } catch (_) {
      return {
        day: String(d.getDate()).padStart(2, '0'),
        month: String(d.getMonth() + 1).padStart(2, '0'),
        year: String(d.getFullYear()),
      };
    }
  }

  function notesTodayFr() {
    const p = parisDateParts();
    if (!p) return '';
    return p.day + '/' + p.month + '/' + p.year;
  }

  const FR_MONTHS = ['JANVIER', 'FÉVRIER', 'MARS', 'AVRIL', 'MAI', 'JUIN', 'JUILLET', 'AOÛT', 'SEPTEMBRE', 'OCTOBRE', 'NOVEMBRE', 'DÉCEMBRE'];

  function noteClipDate(ts) {
    const p = parisDateParts(ts);
    if (!p) return '';
    const name = FR_MONTHS[Number(p.month) - 1] || '';
    return (p.day + ' ' + name).trim();
  }

  function noteChecks(n) {
    const raw = Array.isArray(n && n.checklist) ? n.checklist : [];
    const out = [];
    for (let i = 0; i < raw.length; i++) {
      const c = raw[i];
      if (typeof c === 'string') {
        const text = c.trim();
        if (text) out.push({ text, done: false });
      } else if (c && typeof c === 'object') {
        const text = String(c.text || '').trim();
        if (text) out.push({ text, done: !!c.done });
      }
    }
    return out;
  }

  function noteExistingLink(n) {
    if (!n || typeof n !== 'object') return null;
    const pick = (kind, label) => {
      const lab = String(label || '').trim();
      if (!lab || looksLikeId(lab)) return { kind, label: '' };
      return { kind, label: lab };
    };
    if (n.link && typeof n.link === 'object') {
      const kind = n.link.kind || n.link.type || '';
      const label = n.link.label || n.link.name || n.link.title || '';
      if (kind && label && !looksLikeId(String(label))) return { kind, label: String(label) };
    }
    const candidates = [
      n.resourceLabel && pick('resource', n.resourceLabel),
      n.itemLabel && pick('resource', n.itemLabel),
      n.recipeLabel && pick('recipe', n.recipeLabel),
      n.artisanName && pick('artisan', n.artisanName),
      (n.artisan && n.artisan.displayName) && pick('artisan', n.artisan.displayName),
    ];
    for (let i = 0; i < candidates.length; i++) {
      const c = candidates[i];
      if (c && c.label) return c;
    }
    const checks = noteChecks(n);
    for (let i = 0; i < checks.length; i++) {
      const c = (Array.isArray(n.checklist) ? n.checklist[i] : null);
      if (!c || typeof c !== 'object') continue;
      const lab = c.label || c.resourceLabel || c.recipeLabel || c.artisanName;
      if (lab && !looksLikeId(String(lab))) {
        const kind = c.kind || (c.recipeId ? 'recipe' : (c.artisanId ? 'artisan' : (c.item || c.resourceId ? 'resource' : '')));
        if (kind) return { kind, label: String(lab) };
      }
    }
    return null;
  }

  function noteLinkPhrase(link) {
    if (!link || !link.label) return '';
    if (link.kind === 'artisan') return 'Artisan · ' + link.label;
    if (link.kind === 'recipe') return 'Assemblage · ' + link.label;
    if (link.kind === 'resource') return 'Ressource · ' + link.label;
    return link.label;
  }

  function noteExcerpt(body) {
    const t = String(body || '').replace(/\s+/g, ' ').trim();
    if (!t) return '';
    const cut = t.length > 160 ? t.slice(0, 160) + '\u2026' : t;
    return '\u00ab ' + esc(cut) + ' \u00bb';
  }

  function noteTaskRow(index, text, done) {
    const wrap = document.createElement('div');
    wrap.className = 'note-task postit postit-' + POSTIT_CYCLE[(index || 0) % 4] + (done ? ' is-done' : '');
    wrap.dataset.done = done ? '1' : '0';
    wrap.innerHTML = '<button type="button" class="note-check-box" data-act="toggle-check" aria-label="cocher">'
      + (done ? '\u2611' : '\u2610') + '</button>'
      + '<input type="text" class="note-task-input" />'
      + '<button type="button" class="note-task-remove" data-act="remove-task" aria-label="retirer">\u00d7</button>';
    const inp = wrap.querySelector('.note-task-input');
    if (inp && text) inp.value = text;
    return wrap;
  }

  function collectNoteChecklist() {
    const checklist = [];
    document.querySelectorAll('#note-tasks .note-task').forEach((row) => {
      const inp = row.querySelector('.note-task-input');
      const text = ((inp && inp.value) || '').trim();
      if (!text) return;
      checklist.push({ text, done: row.dataset.done === '1' });
    });
    return checklist;
  }

  function growNoteBody(el) {
    if (!el) return;
    el.style.height = 'auto';
    const h = Math.max(196, Math.min(280, el.scrollHeight));
    el.style.height = h + 'px';
  }

  function fillComposer(note) {
    const title = $('#note-title');
    const body = $('#note-body');
    const tasksEl = $('#note-tasks');
    if (title) title.value = (note && note.title) || '';
    if (body) {
      body.value = (note && note.body) || '';
      growNoteBody(body);
    }
    if (tasksEl) {
      tasksEl.innerHTML = '';
      const checks = noteChecks(note || {});
      checks.forEach((c, i) => tasksEl.appendChild(noteTaskRow(i, c.text, c.done)));
    }
    state.noteEditId = note && note.id != null ? Number(note.id) : null;
    if (title) title.focus();
  }

  function notesEmptyHtml() {
    return `
        <div class="notes-empty">
          <h2 class="notes-empty-title">Carnet vide</h2>
          <p class="hand-note">Rien n\u2019a encore \u00e9t\u00e9 \u00e9crit ici.</p>
          <span class="ink-sketch pencil" aria-hidden="true"></span>
        </div>`;
  }

  function notesListHtml(arr) {
    return `<div id="note-list">${arr.map((n, idx) => {
      const checks = noteChecks(n).slice(0, 4);
      const excerpt = noteExcerpt(n.body);
      const checkHtml = checks.length ? `<ul class="note-clip-checks">${checks.map((c) =>
        `<li class="${c.done ? 'done' : ''}"><span class="note-check-box">${c.done ? '\u2611' : '\u2610'}</span><span>${esc(c.text)}</span></li>`
      ).join('')}</ul>` : '';
      const rot = NOTE_ROTS[idx % NOTE_ROTS.length];
      const tape = idx % 3 === 1 ? '<span class="tape top-r"></span>' : '<span class="tape top-l"></span>';
      const clip = idx % 2 === 0 ? '<span class="paperclip"></span>' : '';
      return `<article class="note-clip ${rot}" data-id="${n.id}" role="button">
          ${tape}
          ${clip}
          <p class="note-clip-date">${esc(noteClipDate(n.updatedAt || n.createdAt))}</p>
          <h3 class="note-clip-title">${esc(n.title || '')}</h3>
          ${excerpt ? `<p class="note-clip-excerpt">${excerpt}</p>` : ''}
          ${checkHtml}
        </article>`;
    }).join('')}</div>`;
  }

  function noteDetailHtml(n) {
    if (!n) return notesEmptyHtml();
    const checks = noteChecks(n);
    const checkHtml = checks.length ? `<ul class="note-clip-checks">${checks.map((c) =>
      `<li class="${c.done ? 'done' : ''}"><span class="note-check-box">${c.done ? '\u2611' : '\u2610'}</span><span>${esc(c.text)}</span></li>`
    ).join('')}</ul>` : '';
    const body = String(n.body || '');
    const link = noteExistingLink(n);
    const linkHtml = (link && link.label)
      ? `<p class="note-link">${esc(noteLinkPhrase(link))}</p>`
      : '';
    return `
        <button type="button" class="note-back" data-act="back-notes">\u2190 les notes</button>
        <article class="note-detail" data-id="${n.id}">
          <span class="tape top-l"></span>
          <span class="paperclip"></span>
          <p class="note-clip-date">${esc(noteClipDate(n.updatedAt || n.createdAt))}</p>
          <h3 class="note-clip-title">${esc(n.title || '')}</h3>
          ${body ? `<div class="note-detail-body">${esc(body)}</div>` : ''}
          ${checkHtml}
          ${linkHtml}
          <div class="note-detail-acts">
            <button type="button" class="note-annot" data-act="edit">modifier</button>
            <button type="button" class="note-stamp-sm" data-act="del">supprimer</button>
          </div>
        </article>`;
  }

  function notesRightHtml() {
    const arr = state.notesList || [];
    if (!arr.length) return notesEmptyHtml() + folio('81');
    if (state.noteViewId != null) {
      const n = arr.find((x) => Number(x.id) === Number(state.noteViewId));
      if (n) return noteDetailHtml(n) + folio('81');
      state.noteViewId = null;
    }
    return notesListHtml(arr) + folio('81');
  }

  function setNotesRight() {
    const R = rightEl();
    if (!R) return;
    R.innerHTML = notesRightHtml();
    R.classList.remove('page-turn');
    bindNotesRight();
  }

  function bindNotesRight() {
    const R = rightEl();
    if (!R) return;
    R.onclick = async (ev) => {
      if (state.page !== 'notes') return;
      const back = ev.target.closest('[data-act="back-notes"]');
      if (back) {
        state.noteViewId = null;
        setNotesRight();
        return;
      }
      const editBtn = ev.target.closest('[data-act="edit"]');
      if (editBtn) {
        const host = editBtn.closest('[data-id]');
        const n = host && (state.notesList || []).find((x) => Number(x.id) === Number(host.dataset.id));
        if (n) fillComposer(n);
        return;
      }
      const delBtn = ev.target.closest('[data-act="del"]');
      if (delBtn) {
        const host = delBtn.closest('[data-id]');
        if (!host) return;
        await post('bookAction', { action: 'deleteNote', payload: { id: Number(host.dataset.id) } });
        state.noteViewId = null;
        if (state.noteEditId === Number(host.dataset.id)) state.noteEditId = null;
        await renderNotes({ keepComposer: true });
        return;
      }
      const clip = ev.target.closest('.note-clip[data-id]');
      if (clip) {
        state.noteViewId = Number(clip.dataset.id);
        setNotesRight();
      }
    };
  }

  function bindNotesComposer() {
    const tasksEl = $('#note-tasks');
    const addTask = $('#note-add-task');
    if (addTask && tasksEl) {
      addTask.onclick = () => {
        tasksEl.appendChild(noteTaskRow(tasksEl.querySelectorAll('.note-task').length));
        const inp = tasksEl.querySelector('.note-task:last-child .note-task-input');
        if (inp) inp.focus();
      };
      tasksEl.onclick = (ev) => {
        const tog = ev.target.closest('[data-act="toggle-check"]');
        if (tog) {
          const row = tog.closest('.note-task');
          if (!row) return;
          const done = row.dataset.done !== '1';
          row.dataset.done = done ? '1' : '0';
          row.classList.toggle('is-done', done);
          tog.textContent = done ? '\u2611' : '\u2610';
          return;
        }
        const rm = ev.target.closest('[data-act="remove-task"]');
        if (!rm) return;
        const row = rm.closest('.note-task');
        if (row) row.remove();
      };
    }
    const body = $('#note-body');
    if (body) {
      body.addEventListener('input', () => growNoteBody(body));
      growNoteBody(body);
    }
    const save = $('#note-save');
    if (save) save.onclick = async () => {
      save.classList.remove('is-inking');
      void save.offsetWidth;
      save.classList.add('is-inking');
      const payload = {
        title: ($('#note-title') || {}).value,
        body: ($('#note-body') || {}).value,
        checklist: collectNoteChecklist(),
      };
      if (state.noteEditId) payload.id = state.noteEditId;
      await post('bookAction', {
        action: 'saveNote',
        payload,
      });
      await new Promise((resolve) => setTimeout(resolve, 320));
      state.noteEditId = null;
      state.noteViewId = null;
      await renderNotes();
    };
  }

  /* ========== NOTES ========== */
  async function renderNotes(opts) {
    opts = opts || {};
    const r = await loadModule('notes');
    const arr = (r && r.data) || [];
    state.notesList = arr;
    const keep = !!opts.keepComposer;
    const snap = keep ? {
      title: (($('#note-title') || {}).value) || '',
      body: (($('#note-body') || {}).value) || '',
      checklist: collectNoteChecklist(),
      id: state.noteEditId,
    } : null;
    const today = notesTodayFr();
    const left = `
      <div class="note-leaf-wrap">
        <span class="tape top-l"></span>
        <span class="paperclip"></span>
        <div class="note-leaf">
          <p class="note-leaf-head">NOUVELLE NOTE</p>
          <input id="note-title" type="text" placeholder="Titre" autocomplete="off" />
          <p class="note-date" id="note-date">Date : ${esc(today)}</p>
          <textarea id="note-body" rows="8"></textarea>
          <div class="note-tasks" id="note-tasks"></div>
          <button type="button" class="note-add-task" id="note-add-task">+ Ajouter une t\u00e2che</button>
          <button type="button" class="note-stamp" id="note-save">ENREGISTRER</button>
        </div>
      </div>${folio('80')}`;

    setPages(left, notesRightHtml());
    bindNotesComposer();
    bindNotesRight();
    if (snap && (snap.title || snap.body || (snap.checklist && snap.checklist.length) || snap.id)) {
      fillComposer({ id: snap.id, title: snap.title, body: snap.body, checklist: snap.checklist });
    }
  }


  /* ========== PRODUCTIONS ========== */
  async function renderProductions() {
    const r = await loadModule('productions');
    const d = (r && r.data) || { queue: [], projects: [] };
    const queue = d.queue || [];
    const projects = d.projects || [];
    const left = `
      <p class="book-stamp">Atelier</p>
      <h2 class="book-page-title">Productions</h2>
      <p class="hand-note">Journal de fabrication manuscrit — pas le panneau craft. Le suivi flottant (tracker) est séparé.</p>
      <hr class="ink-rule" />
      <h3 class="section-title">En file</h3>
      <div class="fab-log">
        ${queue.length ? queue.map((q) => `
          <div class="fab-row">
            <span class="fab-time">${q.finishAt ? fmtTime(q.finishAt) : 'en cours'}</span>
            <span class="fab-label">${esc(q.label)}</span>
            <span class="badge">x${q.batch || 1}</span>
          </div>`).join('') : `<p class="hand-note">File vide pour l'instant.</p>`}
      </div>
      ${folio('90')}`;
    const right = `
      <h3 class="section-title">Chantiers / en cours</h3>
      <div class="fab-log">
        ${projects.length ? projects.map((p) => `
          <div class="fab-row">
            <span class="fab-time">${esc(p.status || 'open')}</span>
            <span class="fab-label">${esc(p.label)}</span>
            <span class="badge">${p.isOwner ? 'responsable' : 'aide'}</span>
          </div>`).join('') : `<p class="hand-note">${emptyPhrase('project')}</p>`}
      </div>
      <div class="scrap-note rot-r" style="margin-top:16px">
        <span class="tape top-l"></span>
        <div class="scrap-title">Productions à récupérer</div>
        <div class="scrap-body">${(d.toCollect || 0) > 0
          ? `${d.toCollect} pièce(s) en sortie.${(d.stations || []).length ? '<br/>' + (d.stations || []).map((st) => esc(st.stationLabel || st.stationUid)).join(', ') : ''}`
          : 'La collecte se fait à l\'atelier. Rien en attente.'}</div>
      </div>
      ${folio('91')}`;
    setPages(left, right);
  }


  /* ========== HISTORY ========== */
  async function renderHistory(page) {
    const mod = page === 'discoveries' ? 'discoveries' : 'history';
    const r = await loadModule(mod);
    const arr = (r && r.data) || [];
    const left = `
      <p class="book-stamp">Chronologie</p>
      <h2 class="book-page-title">${page === 'discoveries' ? 'Découvertes' : 'Historique'}</h2>
      <p class="hand-note">Journal papier classé par date.</p>
      <hr class="ink-rule" />
      ${folio('100')}`;
    let right;
    if (!arr.length) {
      right = emptyBox('fa-clock-rotate-left', 'Journal vide', 'Découvertes, objectifs et rencontres s\'empilent ici.') + folio('101');
    } else {
      const isDisc = page === 'discoveries';
      right = `<div class="journal-log">${arr.map((x, i) => {
        let body = '';
        let source = '';
        try {
          const p = x.payload || {};
          body = p.label || p.name || p.title || displayItem(p.item) || '';
          if (!body || looksLikeId(String(body))) body = displayItem(body || p.item || '');
          source = p.source || p.from || x.source || '';
          if (source && looksLikeId(String(source))) source = prettySkill(source);
        } catch (_) { body = emptyPhrase('discovery'); }
        if (isDisc) {
          const sketch = i % 4 === 0 ? '<span class="ink-sketch plant disc-sketch" aria-hidden="true"></span>'
            : (i % 4 === 2 ? '<span class="ink-sketch gear disc-sketch" aria-hidden="true"></span>' : '');
          return `<article class="discovery-card">
            ${sketch}
            <div class="je-date">${fmtTime(x.ts || x.createdAt || x.at)}</div>
            <span class="stamp stamp-decouvert" style="font-size:9px;padding:2px 6px">DÉCOUVERT</span>
            <div class="je-body" style="margin-top:6px">${esc(body)}</div>
            <div class="disc-annot">${esc(prettySkill(x.type || 'observation'))} — noté sur le terrain</div>
            ${source ? `<div class="disc-source">Source · ${esc(source)}</div>` : ''}
          </article>`;
        }
        return `<article class="journal-entry">
          <div class="je-date">${fmtTime(x.ts || x.createdAt || x.at)}</div>
          <div class="je-type">${esc(prettySkill(x.type || 'note'))}</div>
          <div class="je-body">${esc(body || emptyPhrase())}</div>
        </article>`;
      }).join('')}</div>${folio('101')}`;
    }
    setPages(left, right);
  }


  /* ========== SECONDARY ========== */
  async function renderPins() {
    const r = await loadModule('pins');
    const arr = (r && r.data) || [];
    const hud = window.SanctuaryHud;
    const pinsOn = hud ? hud.readPinsVisible() : true;
    const trackerOn = hud ? hud.readMode() !== 'hidden' : true;
    const left = pageHead('Épingles', 'Widget HUD + raccourcis') + `
      <div class="hud-settings-inline" style="margin-top:4px">
        <p class="hand-note">Paramètres HUD</p>
        <label class="hud-set-row" style="display:flex;gap:8px;align-items:center;margin:8px 0">
          <input type="checkbox" id="hud-book-pins" ${pinsOn ? 'checked' : ''} />
          Afficher le widget épingles
        </label>
        <label class="hud-set-row" style="display:flex;gap:8px;align-items:center;margin:8px 0">
          <input type="checkbox" id="hud-book-tracker" ${trackerOn ? 'checked' : ''} />
          Afficher le tracker
        </label>
        <div class="row-actions" style="margin-top:8px">
          <button type="button" class="ghost" id="hud-book-reset">RÉINITIALISER LES WIDGETS</button>
        </div>
      </div>${folio('110')}`;
    const right = `${arr.length ? arr.map((p) => `
      <article class="dossier-sheet">
        <span class="paperclip"></span>
        <div class="dossier-mark">${p.kind === 'resource' ? 'Ressource' : 'Épingle'}</div>
        <h4>${esc(p.label)}</h4>
        <div class="dossier-meta">${p.category ? `<span class="badge">${esc(prettySkill(p.category))}</span>` : ''}</div>
        <div class="row-actions">
          <button type="button" class="ghost small" data-rid="${esc(p.recipeId)}">Retirer</button>
        </div>
      </article>`).join('') : emptyBox('fa-thumbtack', 'Aucune épingle', 'Épinglez depuis l’UI craft ou un objectif recette.')}
    ${folio('111')}`;
    setPages(left, right);
    rightEl() && rightEl().querySelectorAll('button[data-rid]').forEach((b) => {
      b.onclick = async () => {
        await post('bookAction', { action: 'unpin', payload: { recipeId: b.dataset.rid } });
        navigate('pins');
      };
    });
    const hudApi = window.SanctuaryHud;
    const bp = $('#hud-book-pins');
    if (bp) {
      bp.onchange = () => {
        if (hudApi) hudApi.writePinsVisible(bp.checked, { source: 'book' });
        else post('bookToggleHud', { enabled: !!bp.checked });
      };
    }
    const bt = $('#hud-book-tracker');
    if (bt) {
      bt.onchange = () => {
        if (hudApi) hudApi.writeMode(bt.checked ? 'expanded' : 'hidden', { source: 'book' });
      };
    }
    const br = $('#hud-book-reset');
    if (br) br.onclick = () => { if (hudApi) hudApi.reset(); };
  }

  async function renderCanCraft() {
    const r = await loadModule('canCraft');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Faisable maintenant', 'Recettes prêtes avec ce que l\'on a sous la main') + folio('120'),
      `${arr.length ? arr.map((x) => `
        <article class="scrap-note flat"><span class="tape top-l"></span>
        <div class="dossier-mark">Prêt</div>
        <h4 class="scrap-title">${esc(x.label)}</h4>
        <div class="scrap-foot">${esc(x.category || '')}</div></article>`).join('') : emptyBox('fa-check', 'Rien de faisable', 'Manque de composants ou de niveau.')}
      ${folio('121')}`
    );
  }

  async function renderSuggestions() {
    const r = await loadModule('suggestions');
    const d = (r && r.data) || { almost: [], oneLevel: [] };
    setPages(
      pageHead('Suggestions', 'Pistes de progression & crafts proches') + `
        <h3 class="section-title">Presque craftable</h3>
        <div class="unlock-list">${(d.almost || []).map((x) => `
          <div class="unlock-row"><span>${esc(x.label)}</span><span class="hand-note">${(x.missing || []).length ? 'Encore quelques pièces à réunir.' : ''}</span></div>`).join('') || `<p class="hand-note">${emptyPhrase()}</p>`}
        </div>${folio('130')}`,
      `<h3 class="section-title">À un niveau</h3>
        <div class="unlock-list">${(d.oneLevel || []).map((x) => `
          <div class="unlock-row"><span>${esc(x.label)}</span><span class="hand-note">Encore un cran</span></div>`).join('') || `<p class="hand-note">${emptyPhrase()}</p>`}
        </div>${folio('131')}`
    );
  }

  function shopRowHtml(x) {
    const need = x.need || x.count || 0;
    const owned = x.owned != null ? x.owned : (x.have || 0);
    const remaining = x.remaining != null ? x.remaining : Math.max(0, need - owned);
    const srcs = (x.sources || []).map((s) => `${s.label || s.recipeId} ×${s.count}`).join(' · ');
    return `<li>
      <span>${itemLabel(x)} <span class="badge">${owned}/${need}</span></span>
      <span class="badge">${remaining > 0 ? 'reste ' + remaining : 'ok'}</span>
      ${srcs ? `<div class="hand-note">${esc(srcs)}</div>` : ''}
    </li>`;
  }

  async function renderShopping() {
    const prefill = state._shopPrefill || '';
    setPages(
      pageHead('Courses', 'Fusionnée depuis les suivis — owned soustrait une fois') + `
        <p class="hand-note">Liste reconstruite à l'ouverture. Un schéma unique reste calculable ci-dessous.</p>
        <div class="note-editor">
          <div class="row-actions" style="margin-top:0">
            <input id="shop-rid" type="text" placeholder="Schéma à déplier…" style="flex:1;margin-top:0" value="${esc(prefill)}" />
            <input id="shop-batch" type="number" min="1" value="1" style="width:70px;margin-top:0" />
            <button type="button" class="primary" id="shop-go">Calculer</button>
          </div>
        </div>${folio('140')}`,
      `<ul class="list" id="shop-out"></ul>${folio('141')}`
    );
    state._shopPrefill = '';
    const out = $('#shop-out');
    const paint = (list) => {
      if (!out) return;
      out.innerHTML = (list || []).map(shopRowHtml).join('') || '<li class="empty">Aucun suivi / rien à récupérer</li>';
    };
    if (!prefill) {
      const pinsShop = await loadModule('shopping', {});
      paint((pinsShop && pinsShop.data) || []);
    }
    const go = $('#shop-go');
    if (go) go.onclick = async () => {
      const recipeId = (($('#shop-rid') || {}).value || '').trim();
      const batch = Number(($('#shop-batch') || {}).value) || 1;
      const r = await loadModule('shopping', recipeId ? { recipeId, batch } : {});
      paint((r && r.data) || []);
    };
    if (go && prefill) go.click();
  }

  function treeText(node, indent) {
    if (!node) return '';
    indent = indent || '';
    if (node.type === 'raw') {
      const lab = displayItem(node);
      return `${indent}- ${lab} x${node.count || 1}\n`;
    }
    let s = `${indent}* ${displayItem(node.label || node)}\n`;
    (node.children || []).forEach((c) => { s += treeText(c, indent + '  '); });
    return s;
  }

  async function renderTree() {
    setPages(
      pageHead('Arbre de craft', 'Dépendances masquées pour les inconnues') + `
        <div class="note-editor">
          <div class="row-actions" style="margin-top:0">
            <input id="tree-rid" type="text" placeholder="Schéma à déplier…" style="flex:1;margin-top:0" value="${esc(state._treePrefill || '')}" />
            <button type="button" class="primary" id="tree-go">Afficher</button>
          </div>
        </div>${folio('150')}`,
      `<pre class="tree-pre" id="tree-out">${emptyPhrase()}</pre>${folio('151')}`
    );
    state._treePrefill = '';
    const go = $('#tree-go');
    if (go) go.onclick = async () => {
      const recipeId = (($('#tree-rid') || {}).value || '').trim();
      const r = await loadModule('tree', { recipeId, depth: 3 });
      const out = $('#tree-out');
      if (out) out.textContent = r && r.ok ? treeText(r.data) : 'Impossible de déplier ce schéma.';
    };
    if (go && ($('#tree-rid') || {}).value) go.click();
  }

  async function renderOrders() {
    const r = await loadModule('orders');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Commandes', 'Échange physique / RP — aucun téléport d’items') + `
        <div class="note-editor">
          <div class="row-actions" style="margin-top:0">
            <input id="ord-note" type="text" placeholder="Note commande" style="flex:1;margin-top:0" />
            <input id="ord-rid" type="text" placeholder="Schéma (optionnel)" style="flex:1;margin-top:0" />
            <button type="button" class="primary" id="ord-add">Créer</button>
          </div>
        </div>${folio('160')}`,
      `<div class="dossier-grid">${arr.length ? arr.map((o) => `
        <article class="dossier-card">
          <div class="dossier-mark">Commande</div>
          <h4>${esc(o.note || 'Commande')}</h4>
          <div class="dossier-meta">
            <span class="badge">${esc(o.status === 'open' ? 'ouverte' : (o.status || ''))}</span>
          </div>
        </article>`).join('') : emptyBox('fa-handshake', 'Aucune commande', 'Créez une demande d’échange RP.')}
      </div>${folio('161')}`
    );
    const add = $('#ord-add');
    if (add) add.onclick = async () => {
      await post('bookAction', {
        action: 'createOrder',
        payload: {
          note: ($('#ord-note') || {}).value,
          recipeId: (($('#ord-rid') || {}).value || '').trim() || null,
          items: [],
        },
      });
      navigate('orders');
    };
  }

  async function renderWorkshop() {
    const r = await loadModule('workshop');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Mon atelier', 'Bancs connus, relevés de terrain') + folio('170'),
      `<div class="dossier-grid">${arr.length ? arr.map((s) => `
        <article class="dossier-card">
          <div class="dossier-mark">${esc(s.kind === 'world' ? 'banc de zone' : 'banc')}</div>
          <h4>${esc(prettySkill(s.category) || s.category || 'Atelier')}</h4>
          <div class="dossier-meta">
            <span class="badge">L${s.stationLevel || 1}</span>
            <span class="badge ${s.powered === false ? 'warn' : 'ok'}">${s.powered === false ? 'OFF' : 'OK'}</span>
          </div>
        </article>`).join('') : emptyBox('fa-warehouse', 'Aucun banc', 'Placez ou découvrez des ateliers.')}
      </div>${folio('171')}`
    );
  }

  async function renderMaintenance() {
    const r = await loadModule('maintenance');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Maintenance', 'Alertes outils & énergie') + folio('180'),
      `<div class="unlock-list">${arr.length ? arr.map((h) => `
        <div class="unlock-row">
          <span>${esc(prettySkill(h.kind))} · ${esc(h.label || prettySkill(h.category) || displayItem(h.item) || '')}</span>
          <span class="badge warn">${esc(h.hint || '')}</span>
        </div>`).join('') : emptyBox('fa-wrench', 'Rien à signaler', 'Tout semble en ordre.')}
      </div>${folio('181')}`
    );
  }

  async function renderStats() {
    const r = await loadModule('stats');
    const st = (r && r.data) || {};
    const keys = Object.keys(st);
    setPages(
      pageHead('Stats', 'Compteurs du dossier personnel') + folio('190'),
      (keys.length ? keys.map((k, i) => `
        <div class="scrap-note ${i % 2 ? 'rot-r' : 'rot-l'}" style="margin:8px 2px">
          <span class="tape top-l"></span>
          <div class="dossier-mark">${esc(prettySkill(k))}</div>
          <div class="widget-v">${esc(st[k])}</div>
        </div>`).join('') : emptyBox('fa-chart-simple', 'Pas de stats', '')) + folio('191')
    );
  }

  async function doSearch(q) {
    if (!q || q.length < 2) return;
    state.page = 'search';
    renderTabs();
    closeIndex();
    const r = await loadModule('search', { q });
    const hits = (r && r.data) || [];
    setPages(
      pageHead('Recherche', `Résultats pour « ${q} »`) + folio('200'),
      `<div class="unlock-list">${hits.length ? hits.map((h) => `
        <div class="unlock-row"><span>${esc(h.label)}</span><span class="hand-note">${esc(kindDisplay(h.kind) || prettySkill(h.kind) || '')}</span></div>`).join('') : emptyBox('fa-magnifying-glass', 'Aucun résultat', 'Élargissez les termes.')}
      </div>${folio('201')}`
    );
  }

  function applyBookMeta(msg) {
    if (msg && msg.meta) state.meta = msg.meta;
    state.modules = (state.meta && state.meta.modules) || state.modules || {};
    if (state.meta && state.meta.accent) {
      try {
        document.documentElement.style.setProperty('--book-accent', state.meta.accent);
      } catch (_) { /* ignore */ }
    }
    const title = (state.meta && state.meta.title) || 'CARNET DE SURVIE';
    const subtitle = (state.meta && state.meta.subtitle) || 'Journal technique de terrain';
    const titleEl = $('#book-title');
    const subEl = $('#book-sub');
    if (titleEl) titleEl.textContent = String(title).toUpperCase();
    if (subEl) subEl.textContent = subtitle;
  }

  function paintBootPages(title, subtitle) {
    /* Kept as last-resort hidden paint; never shown as incomplete book. */
    if (hasPageContent()) return;
    const left = `
      <div class="accueil-hero">
        <p class="book-stamp">Carnet de terrain</p>
        <h2 class="accueil-title">${esc(String(title || 'Carnet de survie'))}</h2>
        <p class="accueil-sub">${esc(subtitle || 'Journal de terrain')}</p>
        <hr class="ink-rule" />
        <span class="stamp">Terrain</span>
      </div>
      ${folio('i')}`;
    const right = `
      <p class="book-stamp">Feuillet du jour</p>
      <h2 class="book-page-title">Situation</h2>
      <hr class="ink-rule" />
      ${folio('ii')}`;
    setPages(left, right);
  }

  function openBook(msg) {
    playBookSound(); /* no-op */
    const wasOpen = state.open;
    applyBookMeta(msg);
    closeIndex();
    renderTabs();
    const page = (msg && msg.page) || state.page || 'dashboard';

    if (wasOpen && journalReady) {
      revealBookShell();
      return;
    }

    if (wasOpen && !journalReady) {
      /* duplicate bookOpen while preloading (CEF retries) — keep last paint */
      return;
    }

    state.open = true;
    book.classList.remove('is-opening');

    if (journalReady) {
      /* subsequent open: DOM + assets live — fade in, keep last pages */
      if (page !== state.page || !hasPageContent()) {
        Promise.resolve()
          .then(() => navigate(page))
          .catch((err) => {
            console.error('[sanctuary_crafting book navigate]', err);
          });
      }
      revealBookShell();
      return;
    }

    /* First open after resource restart: overlay only, book stays opacity 0 */
    if (!assetsReady) showOpeningOverlay();
    ensurePreload().then(() => {
      assetsReady = true;
      tryReveal();
    });
    window.setTimeout(() => {
      if (!state.open || journalReady) return;
      tryReveal();
    }, 800);
    Promise.resolve()
      .then(() => navigate(page))
      .catch((err) => {
        console.error('[sanctuary_crafting book navigate]', err);
        paintBootPages(
          (state.meta && state.meta.title) || 'Carnet de survie',
          (state.meta && state.meta.subtitle) || 'Journal de terrain'
        );
      });
  }

  function closeBook() {
    state.open = false;
    closeIndex();
    hideBookShell();
    post('bookClose', {});
  }

  // Register open/close handlers BEFORE optional DOM binds — never throw so page dies
  window.addEventListener('message', (ev) => {
    const data = ev.data || {};
    if (data.action === 'bookOpen') {
      try { openBook(data); } catch (err) { console.error('[sanctuary_crafting bookOpen]', err); }
    }
    if (data.action === 'bookClose') {
      state.open = false;
      closeIndex();
      hideBookShell();
    }
    if (data.action === 'bookPins') {
      /* HUD is #book-pins-hud via pinsHud */
    }
    if (data.action === 'bookDashboardResult') {
      applyDashboardPayload(data.payload || {}, dashGen);
    }
    if (data.action === 'bookDashboardExtra') {
      if (state.page === 'dashboard' && state.open) {
        const extra = (data.payload && (data.payload.data || data.payload)) || {};
        paintDashboard(mergeDash(extra));
      }
    }
    if (data.action === 'bookModuleResult') {
      const id = data.reqId;
      const payload = data.payload || { ok: false };
      const fn = moduleWaiters.get(id);
      if (fn) {
        moduleWaiters.delete(id);
        fn(payload);
      } else if (id != null) {
        moduleBuf.set(id, payload);
      }
    }
    if (data.action === 'bookEvent' && state.open) {
      if (state.page === 'dashboard' || state.page === 'history' || state.page === 'artisans' || state.page === 'resources') {
        try { navigate(state.page); } catch (_) { /* ignore */ }
      }
    }
  });

  window.addEventListener('keydown', (ev) => {
    if (!state.open) return;
    if (ev.key === 'Escape') {
      if (state.indexOpen) { closeIndex(); return; }
      closeBook();
    }
  });

  const closeBtn = $('#book-btn-close');
  if (closeBtn) closeBtn.addEventListener('click', closeBook);
  const indexBtn = $('#book-btn-index');
  if (indexBtn) indexBtn.addEventListener('click', openIndex);
  const indexClose = $('#book-index-close');
  if (indexClose) indexClose.addEventListener('click', closeIndex);
  const searchEl = $('#book-search');
  if (searchEl) searchEl.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') doSearch(ev.target.value.trim());
  });

  ensurePreload();
})();
