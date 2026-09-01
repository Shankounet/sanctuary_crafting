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
  };

  /* Primary edge tabs — Accueil + 7 modules */
  const PRIMARY_TABS = [
    { id: 'dashboard', label: 'Accueil', mod: 'Dashboard' },
    { id: 'progression', label: 'Progression', mod: 'Progression' },
    { id: 'objectives', label: 'Objectifs', mod: 'Objectives' },
    { id: 'projects', label: 'Projets', mod: 'Projects' },
    { id: 'resources', label: 'Ressources', mod: 'Resources' },
    { id: 'blueprints', label: 'Plans', mod: 'Blueprints' },
    { id: 'artisans', label: 'Artisans', mod: 'Artisans' },
    { id: 'notes', label: 'Notes', mod: 'Notes' },
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

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function itemLabel(it) {
    if (!it) return '???';
    if (it.known === false || it.label === '???') {
      return `<span class="unknown">Ressource inconnue</span>`;
    }
    return esc(it.label || it.item || '???');
  }

  function fmtTime(ts) {
    if (!ts) return '—';
    const d = new Date((Number(ts) < 1e12 ? Number(ts) * 1000 : Number(ts)));
    if (Number.isNaN(d.getTime())) return '—';
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
      <hr class="book-rule" />
    </div>`;
  }

  function folio(n) {
    return `<div class="folio">— ${esc(n)} —</div>`;
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
      void L.offsetWidth;
      L.classList.add('page-turn');
    }
    if (R) {
      R.innerHTML = rightHtml || '';
      R.classList.remove('page-turn');
      void R.offsetWidth;
      R.classList.add('page-turn');
    }
    /* Compat: keep #book-main in sync for any external peek */
    const main = $('#book-main');
    if (main) main.innerHTML = (leftHtml || '') + (rightHtml || '');
  }

  function setContext() { /* no sidebar context in physical book */ }

  function renderTabs() {
    const nav = $('#book-tabs');
    if (!nav) return;
    nav.innerHTML = '';
    PRIMARY_TABS.forEach((n) => {
      if (!modEnabled(n.mod)) return;
      const b = document.createElement('button');
      b.type = 'button';
      b.dataset.page = n.id;
      b.textContent = n.label;
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

  async function loadModule(name, payload) {
    const key = name + JSON.stringify(payload || {});
    const r = await post('bookModule', { module: name, payload: payload || {} });
    if (r && r.ok) state.cache[key] = r.data;
    return r;
  }

  async function navigate(page) {
    state.page = page;
    renderTabs();
    setContext();
    setPages('<p class="empty">Chargement…</p>', '<p class="empty">…</p>');
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

  /* ========== ACCUEIL (editorial spread) ========== */
  async function renderDashboard() {
    const r = await post('bookDashboard', {});
    if (!r || !r.ok) {
      setPages(
        pageHead('Accueil', 'Synthèse indisponible') + emptyBox('fa-book-open', 'Dashboard indisponible', 'Le module Tableau de bord est désactivé ou inaccessible.'),
        ''
      );
      return;
    }
    const d = r.data || {};
    const st = d.stats || {};
    const prog = d.progression || {};
    const levels = prog.levels || {};
    const levelKeys = Object.keys(levels);
    const next = (d.nextUnlocks || [])[0];
    const objs = d.objectives || [];
    const pins = d.pins || [];
    const prods = (d.productions && d.productions.queue) || [];
    const projects = (d.productions && d.productions.projects) || [];
    const almost = (d.suggestions && d.suggestions.almost) || [];
    const canCraft = d.canCraft || [];
    const title = (state.meta && state.meta.title) || 'Carnet de survie';
    const subtitle = (state.meta && state.meta.subtitle) || 'Journal technique de terrain';

    const skillBlock = levelKeys.length
      ? levelKeys.map((k) => {
          const lv = levels[k] || {};
          const pct = Math.min(100, Math.max(8, (Number(lv.level) || 0) * 8));
          return `<div class="skill-card">
            <div class="skill-name"><span>${esc(k)}</span><span class="badge accent">Niv. ${esc(lv.level || 0)}</span></div>
            <div class="skill-bar"><span style="width:${pct}%"></span></div>
            <div class="widget-foot">Bonus ${esc(lv.bonus || 0)}% · ml_skills</div>
          </div>`;
        }).join('')
      : `<div class="paper-card empty">ml_skills indisponible</div>`;

    const left = `
      <div class="accueil-hero">
        <p class="book-stamp">Dossier personnel</p>
        <h2 class="accueil-title">${esc(String(title))}</h2>
        <p class="accueil-sub">${esc(subtitle)}</p>
        <hr class="book-rule" />
        <p class="hand-note">Notes de terrain — synthèse du jour.</p>
        <div class="ink-stamp">Ouvert</div>
      </div>
      <h3 class="section-title">Compétences</h3>
      ${skillBlock}
      <h3 class="section-title">Repères</h3>
      <div class="pill-row">
        <span class="badge accent">${st.artisans || 0} contacts</span>
        <span class="badge">${st.notes || 0} notes</span>
        <span class="badge">${st.blueprints || 0} plans</span>
        <span class="badge">${st.resources || 0} ressources</span>
      </div>
      ${folio('i')}`;

    const right = `
      <p class="book-stamp">Feuillet droit</p>
      <h2 class="book-page-title">Situation</h2>
      <hr class="book-rule" />
      <div class="widget-grid">
        <div class="widget">
          <div class="widget-k">Objectifs actifs</div>
          <div class="widget-v">${st.objectivesOpen || objs.length || 0}</div>
          <ul class="mini-list">${(objs.slice(0, 3).map((o) => `<li><span>${esc(o.title)}</span><span class="badge">${esc(o.kind || '')}</span></li>`).join('')) || '<li class="empty">Aucun objectif ouvert</li>'}</ul>
        </div>
        <div class="widget">
          <div class="widget-k">Projet principal</div>
          ${projects[0]
            ? `<div class="widget-body"><strong>${esc(projects[0].label)}</strong>
                <div class="widget-foot">${projects[0].isOwner ? 'Propriétaire' : 'Contributeur'} · ${esc(projects[0].status || 'open')}</div></div>`
            : `<div class="widget-body empty">Aucun projet ouvert</div>`}
        </div>
        <div class="widget">
          <div class="widget-k">Prochain déblocage</div>
          ${next
            ? `<div class="widget-body"><strong>${esc(next.label)}</strong>
                <div class="widget-foot">${next.requireSkill ? `Skill: ${esc(next.requireSkill)}` : `Niv. ${esc(next.requireLevel)} (Δ ${esc(next.delta || '?')})`}</div></div>`
            : `<div class="widget-body empty">Rien de proche</div>`}
        </div>
        <div class="widget">
          <div class="widget-k">Épingles</div>
          <div class="widget-v">${st.pins || pins.length || 0}</div>
          <ul class="mini-list">${pins.slice(0, 3).map((p) => `<li><span>${esc(p.label)}</span></li>`).join('') || '<li class="empty">—</li>'}</ul>
        </div>
        <div class="widget">
          <div class="widget-k">Productions</div>
          <div class="widget-v">${prods.length}</div>
          <ul class="mini-list">${prods.slice(0, 3).map((q) => `<li><span>${esc(q.label)}</span><span class="badge">x${q.batch || 1}</span></li>`).join('') || '<li class="empty">File vide</li>'}</ul>
        </div>
        <div class="widget">
          <div class="widget-k">Dernière piste</div>
          ${almost[0]
            ? `<div class="widget-body"><strong>${esc(almost[0].label)}</strong>
                <div class="widget-foot">Presque craftable · manque ${(almost[0].missing || []).length}</div></div>`
            : canCraft[0]
              ? `<div class="widget-body"><strong>${esc(canCraft[0].label)}</strong><div class="widget-foot">Faisable maintenant</div></div>`
              : `<div class="widget-body empty">Pas de découverte récente</div>`}
        </div>
        <div class="widget wide">
          <div class="widget-k">Faisable maintenant</div>
          <ul class="mini-list">${canCraft.slice(0, 6).map((x) => `<li><span>${esc(x.label)}</span><span class="badge ok">${esc(x.category || '')}</span></li>`).join('') || '<li class="empty">Rien de prêt — ouvrez Suggestions (Index)</li>'}</ul>
        </div>
      </div>
      ${folio('ii')}`;

    setPages(left, right);
  }

  /* ========== PROGRESSION ========== */
  async function renderProgression() {
    const r = await loadModule('progression');
    const p = (r && r.data) || {};
    const unlocks = await loadModule('nextUnlocks');
    const next = (unlocks && unlocks.data) || [];
    if (!p.available) {
      setPages(
        pageHead('Progression', 'Lecture seule ml_skills — aucune XP parallèle') +
          emptyBox('fa-chart-line', 'ml_skills indisponible', 'Le carnet lit CraftingSkills en lecture seule.'),
        folio('12')
      );
      return;
    }
    const levels = p.levels || {};
    const left = pageHead('Progression', 'Compétences ml_skills · lecture seule') +
      `<div class="cards">${Object.keys(levels).map((k) => {
        const lv = levels[k] || {};
        const pct = Math.min(100, Math.max(6, (Number(lv.level) || 0) * 8));
        return `<div class="skill-card">
          <div class="skill-name"><span>${esc(k)}</span><span class="badge accent">Niv. ${esc(lv.level || 0)}</span></div>
          <div class="skill-bar"><span style="width:${pct}%"></span></div>
          <div class="widget-foot">Bonus catégorie ${esc(lv.bonus || 0)}%</div>
        </div>`;
      }).join('')}</div>${folio('12')}`;
    const right = `<p class="book-stamp">Annexes</p>
      <h2 class="book-page-title">Déblocages proches</h2>
      <hr class="book-rule" />
      <div class="unlock-list">${next.length ? next.map((x) => `
        <div class="unlock-row">
          <span>${esc(x.label)}</span>
          <span class="badge warn">${x.requireSkill ? `skill · ${esc(x.requireSkill)}` : `niv. ${esc(x.requireLevel)} · Δ${esc(x.delta || '')}`}</span>
        </div>`).join('') : '<p class="empty">Aucun déblocage proche</p>'}
      </div>${folio('13')}`;
    setPages(left, right);
  }

  async function renderNextUnlocks() {
    const r = await loadModule('nextUnlocks');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Déblocages', 'Recettes proches de votre niveau / skill') +
        `<div class="unlock-list">${arr.length ? arr.map((x) => `
          <div class="unlock-row"><span>${esc(x.label)}</span>
          <span class="badge warn">${x.requireSkill ? 'skill' : 'niv. ' + esc(x.requireLevel)}</span></div>`).join('') : emptyBox('fa-unlock', 'Rien à débloquer', 'Revenez après progression ml_skills.')}
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

    const left = pageHead('Objectifs', 'Cartes de mission — priorité, détail, suivi') + `
      <div class="note-editor">
        <div class="editor-label">Nouvel objectif</div>
        <div class="row-actions" style="margin-top:0">
          <input id="obj-title" type="text" placeholder="Titre de l’objectif…" style="flex:1;margin-top:0" />
          <button type="button" class="primary" id="obj-add">Ajouter</button>
        </div>
      </div>
      ${folio('20')}`;

    let cards = '';
    if (!arr.length) {
      cards = emptyBox('fa-bullseye', 'Aucun objectif', 'Ajoutez une mission manuelle ou depuis le craft.');
    } else {
      cards = `<div class="obj-grid" id="obj-grid">${arr.map((o) => {
        const rid = o.payload && o.payload.recipeId;
        const pinned = rid && pinIds.has(rid);
        const priority = o.done ? 'done' : (o.kind === 'recipe' ? 'haute' : 'normale');
        return `<article class="obj-card ${o.done ? 'done' : ''}" data-id="${o.id}">
          <div class="obj-top">
            <div class="obj-title">${o.done ? '✓ ' : ''}${esc(o.title)}</div>
            <span class="badge ${o.done ? 'ok' : 'accent'}">${esc(o.kind || 'manual')}</span>
          </div>
          <div class="pill-row">
            <span class="badge">${esc(priority)}</span>
            ${pinned ? '<span class="badge warn">épinglé</span>' : ''}
            ${rid ? `<span class="badge">${esc(rid)}</span>` : ''}
          </div>
          <div class="obj-progress"><span style="width:${o.done ? 100 : 18}%"></span></div>
          <div class="obj-actions">
            ${!o.done ? `<button type="button" class="primary small" data-act="done">Terminer</button>` : ''}
            ${rid && modEnabled('Pins') && !pinned ? `<button type="button" class="ghost small" data-act="pin" data-rid="${esc(rid)}">Épingler</button>` : ''}
            ${rid && modEnabled('CraftTree') ? `<button type="button" class="ghost small" data-act="tree" data-rid="${esc(rid)}">Arbre</button>` : ''}
            <button type="button" class="ghost small" data-act="del">Retirer</button>
          </div>
          <div class="widget-foot">${fmtTime(o.createdAt)}</div>
        </article>`;
      }).join('')}</div>`;
    }
    const right = `<p class="book-stamp">Missions</p><h2 class="book-page-title">Suivi</h2><hr class="book-rule" />${cards}${folio('21')}`;
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
    const left = pageHead('Projets', 'Dossiers de chantier — progression & liens terrain') +
      `<p class="hand-note">Chaque chantier ouvert apparaît ici comme un dossier de terrain.</p>${folio('30')}`;
    let right;
    if (!projects.length) {
      right = emptyBox('fa-folder-open', 'Aucun projet ouvert', 'Les projets craft auxquels vous participez apparaîtront ici.') + folio('31');
    } else {
      right = `<div class="dossier-grid" id="proj-grid">${projects.map((p) => `
        <article class="dossier-card" data-rid="${esc(p.recipeId || '')}">
          <div class="dossier-mark">Dossier projet</div>
          <h4>${esc(p.label || p.recipeId)}</h4>
          <div class="dossier-meta">
            <span class="badge accent">${esc(p.status || 'open')}</span>
            <span class="badge">${p.isOwner ? 'Propriétaire' : 'Contributeur'}</span>
            ${p.projectUid ? `<span class="badge">${esc(String(p.projectUid).slice(0, 8))}…</span>` : ''}
          </div>
          <div class="pct-ring">Suivi chantier · composants via arbre / courses</div>
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

  /* ========== RESOURCES ========== */
  async function renderResources() {
    const r = await loadModule('resources');
    const arr = (r && r.data) || [];
    const left = pageHead('Ressources', 'Codex par découverte — pas de wiki omniscient') +
      `<p class="hand-note">Les silhouettes restent inconnues jusqu’à découverte.</p>${folio('50')}`;
    let right;
    if (!arr.length) {
      right = emptyBox('fa-boxes-stacked', 'Codex vide', 'Craft & explorations révèlent les ressources.') +
        Array.from({ length: 3 }).map(() => `
        <article class="codex-card unknown" style="margin-top:8px">
          <div class="codex-sil"><i class="fa-solid fa-question"></i></div>
          <div class="codex-label">Ressource inconnue</div>
          <div class="codex-id">non découverte</div>
        </article>`).join('') + folio('51');
    } else {
      right = `<div class="codex-grid">${arr.map((x) => {
        const unknown = !x.label || x.label === '???' || x.known === false;
        return `<article class="codex-card ${unknown ? 'unknown' : ''}">
          <div class="codex-sil"><i class="fa-solid ${unknown ? 'fa-question' : 'fa-cube'}"></i></div>
          <div class="codex-label">${unknown ? 'Ressource inconnue' : esc(x.label)}</div>
          <div class="codex-id">${esc(x.item || '')}</div>
        </article>`;
      }).join('')}</div>${folio('51')}`;
    }
    setPages(left, right);
  }

  /* ========== PLANS ========== */
  async function renderPlans() {
    const r = await loadModule('blueprints');
    const arr = (r && r.data) || [];
    const filter = state.planFilter || 'known';
    const left = pageHead('Plans', 'Dossiers de schémas — connus, fragments, verrouillés') + `
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
        gridHtml = `<div class="dossier-grid">${list.map((x) => `
          <article class="dossier-card">
            <div class="dossier-mark">Schéma · connu</div>
            <h4>${esc(x.label || x.id)}</h4>
            <div class="dossier-meta"><span class="badge ok">BP</span><span class="badge">${esc(x.id)}</span></div>
            <div class="pct-ring">Archivé dans votre carnet technique</div>
          </article>`).join('')}</div>`;
      }
    } else {
      const hints = {
        incomplete: ['fa-puzzle-piece', 'Pas de plans incomplets', 'Les schémas partiels apparaîtront ici lorsqu’ils seront supportés.'],
        fragments: ['fa-clone', 'Aucun fragment', 'Les fragments de plans collectés s’assemblent progressivement.'],
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
    const left = pageHead('Artisans', 'Contacts terrain — tiers qualitatifs uniquement') +
      `<p class="hand-note">Pas d’inventaire exact — rencontres & spécialités seulement.</p>${folio('70')}`;
    let right;
    if (!arr.length) {
      right = emptyBox('fa-address-book', 'Aucun contact', 'Rencontrez des artisans via ox_target, carte ou craft.') + folio('71');
    } else {
      right = `<div class="contact-grid">${arr.map((a) => {
        const note = (a.meta && a.meta.note) || '';
        const fav = !!(a.meta && a.meta.favorite);
        return `<article class="contact-card">
          <div class="avatar"><i class="fa-solid fa-user-gear"></i></div>
          <h4>${esc(a.displayName)} ${fav ? '<i class="fa-solid fa-star" style="color:var(--book-accent);font-size:12px"></i>' : ''}</h4>
          <div class="pill-row">
            <span class="badge accent">${esc(a.specialty || 'general')}</span>
            <span class="badge warn">${esc(TIER_LABEL[a.tier] || a.tier || 'Inconnu')}</span>
          </div>
          <div class="meta-line"><i class="fa-solid fa-clock"></i> Dernière rencontre · ${fmtTime(a.metAt)}</div>
          <div class="meta-line"><i class="fa-solid fa-location-crosshairs"></i> Source · ${esc(a.source || 'meet')}</div>
          ${note ? `<div class="meta-line"><i class="fa-solid fa-sticky-note"></i> ${esc(note)}</div>` : '<div class="meta-line">Services : échange RP / craft</div>'}
        </article>`;
      }).join('')}</div>${folio('71')}`;
    }
    setPages(left, right);
  }

  /* ========== NETWORK ========== */
  async function renderNetwork() {
    const r = await loadModule('network');
    const net = (r && r.data) || {};
    const keys = Object.keys(net);
    const left = pageHead('Réseau', 'Domaines & densités de contacts par spécialité') + folio('72');
    let right;
    if (!keys.length) {
      right = emptyBox('fa-network-wired', 'Réseau vide', 'Chaque spécialité rencontrée devient un domaine ici.') + folio('73');
    } else {
      right = `<div class="domain-grid">${keys.map((k) => {
        const list = net[k] || [];
        return `<article class="domain-card">
          <div class="widget-k">${esc(k)}</div>
          <div class="count">${list.length}</div>
          <div class="widget-foot">${list.slice(0, 3).map((a) => esc(a.displayName)).join(' · ') || '—'}${list.length > 3 ? '…' : ''}</div>
        </article>`;
      }).join('')}</div>${folio('73')}`;
    }
    setPages(left, right);
  }

  /* ========== NOTES ========== */
  async function renderNotes() {
    const r = await loadModule('notes');
    const arr = (r && r.data) || [];
    const left = pageHead('Notes', 'Carnet éditorial — notes libres, checklists') + `
      <div class="note-editor">
        <div class="editor-label">Nouvelle page</div>
        <input id="note-title" type="text" placeholder="Titre" />
        <textarea id="note-body" placeholder="Contenu, rappels, observations de terrain…"></textarea>
        <input id="note-check" type="text" placeholder="Checklist (items séparés par | )" />
        <div class="row-actions"><button type="button" class="primary" id="note-save">Enregistrer</button></div>
      </div>${folio('80')}`;

    let listHtml;
    if (!arr.length) {
      listHtml = emptyBox('fa-pen-to-square', 'Carnet vide', 'Vos notes personnelles s’accumulent ici.');
    } else {
      listHtml = `<div class="note-list" id="note-list">${arr.map((n) => {
        const checks = Array.isArray(n.checklist) ? n.checklist : [];
        return `<article class="note-card" data-id="${n.id}">
          <div class="obj-top"><h4>${esc(n.title)}</h4>
            <button type="button" class="ghost small" data-act="del">Retirer</button></div>
          <p>${esc((n.body || '').slice(0, 280))}${(n.body || '').length > 280 ? '…' : ''}</p>
          ${checks.length ? `<ul class="checklist">${checks.map((c) => {
            const text = typeof c === 'string' ? c : (c && c.text) || '';
            const done = typeof c === 'object' && c && c.done;
            return `<li><i class="fa-solid ${done ? 'fa-square-check' : 'fa-square'}"></i>${esc(text)}</li>`;
          }).join('')}</ul>` : ''}
          <div class="widget-foot">${fmtTime(n.updatedAt)}</div>
        </article>`;
      }).join('')}</div>`;
    }
    setPages(left, listHtml + folio('81'));

    const save = $('#note-save');
    if (save) save.onclick = async () => {
      const raw = (($('#note-check') || {}).value || '').trim();
      const checklist = raw ? raw.split('|').map((t) => ({ text: t.trim(), done: false })).filter((x) => x.text) : [];
      await post('bookAction', {
        action: 'saveNote',
        payload: {
          title: ($('#note-title') || {}).value,
          body: ($('#note-body') || {}).value,
          checklist,
        },
      });
      navigate('notes');
    };
    const list = $('#note-list');
    if (list) list.onclick = async (ev) => {
      const btn = ev.target.closest('button[data-act="del"]');
      if (!btn) return;
      await post('bookAction', { action: 'deleteNote', payload: { id: Number(btn.closest('[data-id]').dataset.id) } });
      navigate('notes');
    };
  }

  /* ========== PRODUCTIONS ========== */
  async function renderProductions() {
    const r = await loadModule('productions');
    const d = (r && r.data) || { queue: [], projects: [] };
    const queue = d.queue || [];
    const projects = d.projects || [];
    const left = pageHead('Productions', 'File & chantiers (pas le panneau craft)') + `
      <div class="board-col">
        <h3 class="section-title">En file</h3>
        ${queue.length ? queue.map((q) => `
          <div class="board-card" style="margin-bottom:8px">
            <strong>${esc(q.label)}</strong>
            <div class="pill-row" style="margin-top:8px">
              <span class="badge">x${q.batch || 1}</span>
              ${q.finishAt ? `<span class="badge warn">fin ${fmtTime(q.finishAt)}</span>` : ''}
            </div>
          </div>`).join('') : '<p class="empty">File vide</p>'}
      </div>${folio('90')}`;
    const right = `
      <h3 class="section-title">En cours / projets</h3>
      ${projects.length ? projects.map((p) => `
        <div class="board-card" style="margin-bottom:8px">
          <strong>${esc(p.label)}</strong>
          <div class="pill-row" style="margin-top:8px">
            <span class="badge accent">${esc(p.status || 'open')}</span>
            <span class="badge">${p.isOwner ? 'owner' : 'contrib'}</span>
          </div>
        </div>`).join('') : '<p class="empty">Aucun chantier</p>'}
      <h3 class="section-title">Prêt / à collecter</h3>
      <p class="empty">La collecte se fait à l’atelier craft. Ce feuillet suit l’état sans cloner le banc.</p>
      ${folio('91')}`;
    setPages(left, right);
  }

  /* ========== HISTORY ========== */
  async function renderHistory(page) {
    const mod = page === 'discoveries' ? 'discoveries' : 'history';
    const r = await loadModule(mod);
    const arr = (r && r.data) || [];
    const left = pageHead(page === 'discoveries' ? 'Découvertes' : 'Historique', 'Chronologie de terrain') + folio('100');
    let right;
    if (!arr.length) {
      right = emptyBox('fa-clock-rotate-left', 'Journal vide', 'Découvertes, objectifs et rencontres s’empilent ici.') + folio('101');
    } else {
      right = `<div class="timeline">${arr.map((x) => {
        let body = '';
        try {
          const p = x.payload || {};
          body = p.label || p.name || p.item || p.title || p.recipeId || JSON.stringify(p).slice(0, 80);
        } catch (_) { body = '—'; }
        return `<article class="timeline-item">
          <div class="t-type">${esc(x.type || 'event')}</div>
          <div class="t-body">${esc(body)}</div>
          <div class="t-time">${fmtTime(x.ts || x.createdAt || x.at)}</div>
        </article>`;
      }).join('')}</div>${folio('101')}`;
    }
    setPages(left, right);
  }

  /* ========== SECONDARY ========== */
  async function renderPins() {
    const r = await loadModule('pins');
    const arr = (r && r.data) || [];
    const left = pageHead('Épingles', 'Raccourcis + mini HUD') + `
      <div class="row-actions" style="margin-top:0">
        <button type="button" class="ghost" id="hud-toggle"><i class="fa-solid fa-eye"></i> Basculer mini HUD</button>
      </div>${folio('110')}`;
    const right = `<div class="dossier-grid">${arr.length ? arr.map((p) => `
      <article class="dossier-card">
        <div class="dossier-mark">Épingle</div>
        <h4>${esc(p.label)}</h4>
        <div class="dossier-meta"><span class="badge">${esc(p.category || '')}</span></div>
        <div class="row-actions">
          <button type="button" class="ghost small" data-rid="${esc(p.recipeId)}">Retirer</button>
        </div>
      </article>`).join('') : emptyBox('fa-thumbtack', 'Aucune épingle', 'Épinglez depuis l’UI craft ou un objectif recette.')}
    </div>${folio('111')}`;
    setPages(left, right);
    rightEl() && rightEl().querySelectorAll('button[data-rid]').forEach((b) => {
      b.onclick = async () => {
        await post('bookAction', { action: 'unpin', payload: { recipeId: b.dataset.rid } });
        navigate('pins');
      };
    });
    const ht = $('#hud-toggle');
    if (ht) ht.onclick = () => post('bookToggleHud', { enabled: true });
  }

  async function renderCanCraft() {
    const r = await loadModule('canCraft');
    const arr = (r && r.data) || [];
    setPages(
      pageHead('Faisable maintenant', 'Recettes prêtes avec inventaire & skills') + folio('120'),
      `<div class="dossier-grid">${arr.length ? arr.map((x) => `
        <article class="dossier-card"><div class="dossier-mark">Prêt</div>
        <h4>${esc(x.label)}</h4>
        <div class="dossier-meta"><span class="badge ok">${esc(x.category || '')}</span></div></article>`).join('') : emptyBox('fa-check', 'Rien de faisable', 'Manque de composants ou de niveau.')}
      </div>${folio('121')}`
    );
  }

  async function renderSuggestions() {
    const r = await loadModule('suggestions');
    const d = (r && r.data) || { almost: [], oneLevel: [] };
    setPages(
      pageHead('Suggestions', 'Pistes de progression & crafts proches') + `
        <h3 class="section-title">Presque craftable</h3>
        <div class="unlock-list">${(d.almost || []).map((x) => `
          <div class="unlock-row"><span>${esc(x.label)}</span><span class="badge warn">manque ${(x.missing || []).length}</span></div>`).join('') || '<p class="empty">—</p>'}
        </div>${folio('130')}`,
      `<h3 class="section-title">À un niveau</h3>
        <div class="unlock-list">${(d.oneLevel || []).map((x) => `
          <div class="unlock-row"><span>${esc(x.label)}</span><span class="badge">+1</span></div>`).join('') || '<p class="empty">—</p>'}
        </div>${folio('131')}`
    );
  }

  async function renderShopping() {
    setPages(
      pageHead('Courses intelligentes', 'Expansion récursive, sans double-compte') + `
        <div class="note-editor">
          <div class="row-actions" style="margin-top:0">
            <input id="shop-rid" type="text" placeholder="recipeId (ex: ex_metal_plate)" style="flex:1;margin-top:0" value="${esc(state._shopPrefill || '')}" />
            <input id="shop-batch" type="number" min="1" value="1" style="width:70px;margin-top:0" />
            <button type="button" class="primary" id="shop-go">Calculer</button>
          </div>
        </div>${folio('140')}`,
      `<ul class="list" id="shop-out"></ul>${folio('141')}`
    );
    state._shopPrefill = '';
    const go = $('#shop-go');
    if (go) go.onclick = async () => {
      const recipeId = (($('#shop-rid') || {}).value || '').trim();
      const batch = Number(($('#shop-batch') || {}).value) || 1;
      const r = await loadModule('shopping', { recipeId, batch });
      const list = (r && r.data) || [];
      const out = $('#shop-out');
      if (out) out.innerHTML = list.map((x) =>
        `<li><span>${itemLabel(x)} <span class="badge">x${x.count}</span></span><span class="badge">inv ${x.have || 0}</span></li>`
      ).join('') || '<li class="empty">Rien à récupérer / recette invalide</li>';
    };
    if (go && ($('#shop-rid') || {}).value) go.click();
  }

  function treeText(node, indent) {
    if (!node) return '';
    indent = indent || '';
    if (node.type === 'raw') {
      const lab = node.known === false ? 'Ressource inconnue' : (node.label || node.item);
      return `${indent}- ${lab} x${node.count || 1}\n`;
    }
    let s = `${indent}* ${node.label || node.id}\n`;
    (node.children || []).forEach((c) => { s += treeText(c, indent + '  '); });
    return s;
  }

  async function renderTree() {
    setPages(
      pageHead('Arbre de craft', 'Dépendances masquées pour les inconnues') + `
        <div class="note-editor">
          <div class="row-actions" style="margin-top:0">
            <input id="tree-rid" type="text" placeholder="recipeId" style="flex:1;margin-top:0" value="${esc(state._treePrefill || '')}" />
            <button type="button" class="primary" id="tree-go">Afficher</button>
          </div>
        </div>${folio('150')}`,
      `<pre class="tree-pre" id="tree-out">—</pre>${folio('151')}`
    );
    state._treePrefill = '';
    const go = $('#tree-go');
    if (go) go.onclick = async () => {
      const recipeId = (($('#tree-rid') || {}).value || '').trim();
      const r = await loadModule('tree', { recipeId, depth: 3 });
      const out = $('#tree-out');
      if (out) out.textContent = r && r.ok ? treeText(r.data) : (r && r.reason) || 'Erreur';
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
            <input id="ord-rid" type="text" placeholder="recipeId optionnel" style="flex:1;margin-top:0" />
            <button type="button" class="primary" id="ord-add">Créer</button>
          </div>
        </div>${folio('160')}`,
      `<div class="dossier-grid">${arr.length ? arr.map((o) => `
        <article class="dossier-card">
          <div class="dossier-mark">Commande</div>
          <h4>${esc((o.orderUid || '').slice(0, 8))}…</h4>
          <div class="dossier-meta">
            <span class="badge">${esc(o.status)}</span>
            ${o.note || o.recipeId ? `<span class="badge accent">${esc(o.note || o.recipeId)}</span>` : ''}
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
      pageHead('Mon atelier', 'Bancs connus — pas de GPS') + folio('170'),
      `<div class="dossier-grid">${arr.length ? arr.map((s) => `
        <article class="dossier-card">
          <div class="dossier-mark">${esc(s.kind || 'banc')}</div>
          <h4>${esc(s.category)}</h4>
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
          <span>${esc(h.kind)} · ${esc(h.label || h.category || h.item || '')}</span>
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
      `<div class="cards">${keys.length ? keys.map((k) => `
        <div class="card paper-card"><div class="k">${esc(k)}</div><div class="v">${esc(st[k])}</div></div>`).join('') : emptyBox('fa-chart-simple', 'Pas de stats', '')}
      </div>${folio('191')}`
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
        <div class="unlock-row"><span>${esc(h.label)}</span><span class="badge">${esc(h.kind)}</span></div>`).join('') : emptyBox('fa-magnifying-glass', 'Aucun résultat', 'Élargissez les termes.')}
      </div>${folio('201')}`
    );
  }

  function openBook(msg) {
    state.open = true;
    state.meta = (msg && msg.meta) || {};
    state.modules = (state.meta.modules) || {};
    if (state.meta.accent) {
      try {
        document.documentElement.style.setProperty('--book-accent', state.meta.accent);
      } catch (_) { /* ignore */ }
    }
    const title = state.meta.title || 'CARNET DE SURVIE';
    const titleEl = $('#book-title');
    const subEl = $('#book-sub');
    if (titleEl) titleEl.textContent = String(title).toUpperCase();
    if (subEl) subEl.textContent = state.meta.subtitle || 'Journal technique de terrain';
    /* Force visible BEFORE async navigate (blank NUI = classic focus-without-paint) */
    book.classList.remove('hidden');
    book.classList.add('is-open');
    book.removeAttribute('hidden');
    book.setAttribute('aria-hidden', 'false');
    book.style.display = 'block';
    book.style.visibility = 'visible';
    book.style.opacity = '1';
    book.classList.remove('is-opening');
    void book.offsetWidth;
    book.classList.add('is-opening');
    closeIndex();
    renderTabs();
    const page = (msg && msg.page) || 'dashboard';
    Promise.resolve()
      .then(() => navigate(page))
      .catch((err) => {
        console.error('[sanctuary_crafting book navigate]', err);
        setPages(
          pageHead('Carnet de survie', 'Ouverture partielle') +
            emptyBox('fa-book-open', 'Contenu indisponible', 'Réessaie ou rouvre le carnet.'),
          folio('—')
        );
      });
  }

  function closeBook() {
    state.open = false;
    closeIndex();
    book.classList.add('hidden');
    book.classList.remove('is-open', 'is-opening');
    book.setAttribute('aria-hidden', 'true');
    book.style.display = '';
    book.style.visibility = '';
    book.style.opacity = '';
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
      book.classList.add('hidden');
      book.classList.remove('is-open', 'is-opening');
      book.setAttribute('aria-hidden', 'true');
      book.style.display = '';
      book.style.visibility = '';
      book.style.opacity = '';
    }
    if (data.action === 'bookPins') {
      // HUD handled in Lua
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
})();
