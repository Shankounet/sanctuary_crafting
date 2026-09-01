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
  };

  /* Primary journal pages first; secondary tools grouped — gated by Config.Book modules */
  const NAV_GROUPS = [
    {
      id: 'journal',
      label: 'Journal',
      items: [
        { id: 'dashboard', label: 'Tableau de bord', mod: 'Dashboard', icon: 'fa-table-columns' },
        { id: 'progression', label: 'Progression', mod: 'Progression', icon: 'fa-chart-line' },
        { id: 'objectives', label: 'Objectifs', mod: 'Objectives', icon: 'fa-bullseye' },
        { id: 'projects', label: 'Projets', mod: 'Projects', icon: 'fa-folder-open' },
        { id: 'resources', label: 'Ressources', mod: 'Resources', icon: 'fa-boxes-stacked' },
        { id: 'blueprints', label: 'Plans', mod: 'Blueprints', icon: 'fa-scroll' },
        { id: 'artisans', label: 'Artisans', mod: 'Artisans', icon: 'fa-address-book' },
        { id: 'network', label: 'Réseau', mod: 'Network', icon: 'fa-network-wired' },
        { id: 'notes', label: 'Notes', mod: 'Notes', icon: 'fa-pen-to-square' },
        { id: 'productions', label: 'Productions', mod: 'Productions', icon: 'fa-industry' },
        { id: 'history', label: 'Historique', mod: 'History', icon: 'fa-clock-rotate-left' },
      ],
    },
    {
      id: 'terrain',
      label: 'Terrain',
      items: [
        { id: 'pins', label: 'Épingles', mod: 'Pins', icon: 'fa-thumbtack' },
        { id: 'nextUnlocks', label: 'Déblocages', mod: 'NextUnlocks', icon: 'fa-unlock' },
        { id: 'canCraft', label: 'Faisable', mod: 'CanCraft', icon: 'fa-check' },
        { id: 'suggestions', label: 'Suggestions', mod: 'Suggestions', icon: 'fa-lightbulb' },
        { id: 'shopping', label: 'Courses', mod: 'Shopping', icon: 'fa-basket-shopping' },
        { id: 'tree', label: 'Arbre craft', mod: 'CraftTree', icon: 'fa-sitemap' },
        { id: 'discoveries', label: 'Découvertes', mod: 'Discoveries', icon: 'fa-compass' },
        { id: 'orders', label: 'Commandes', mod: 'Orders', icon: 'fa-handshake' },
        { id: 'workshop', label: 'Mon atelier', mod: 'Workshop', icon: 'fa-warehouse' },
        { id: 'maintenance', label: 'Maintenance', mod: 'Maintenance', icon: 'fa-wrench' },
        { id: 'stats', label: 'Stats', mod: 'Stats', icon: 'fa-chart-simple' },
      ],
    },
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

  function pageHead(title, lede, actionsHtml) {
    return `<div class="page-head">
      <div><h2>${esc(title)}</h2>${lede ? `<p class="lede">${esc(lede)}</p>` : ''}</div>
      ${actionsHtml || ''}
    </div>`;
  }

  function modEnabled(mod) {
    if (!mod) return true;
    return state.modules[mod] !== false;
  }

  function renderNav() {
    const nav = $('#book-nav');
    nav.innerHTML = '';
    NAV_GROUPS.forEach((g) => {
      const visible = g.items.filter((n) => modEnabled(n.mod));
      if (!visible.length) return;
      const lab = document.createElement('div');
      lab.className = 'book-nav-group';
      lab.textContent = g.label;
      nav.appendChild(lab);
      visible.forEach((n) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.dataset.page = n.id;
        b.innerHTML = `<i class="fa-solid ${n.icon}" aria-hidden="true"></i><span>${esc(n.label)}</span>`;
        if (state.page === n.id) b.classList.add('active');
        b.addEventListener('click', () => navigate(n.id));
        nav.appendChild(b);
      });
    });
  }

  function setContext(html) {
    const ctx = $('#book-context');
    if (!ctx) return;
    if (!html) {
      ctx.classList.add('hidden');
      ctx.innerHTML = '';
      book.classList.remove('has-context');
      return;
    }
    ctx.innerHTML = html;
    ctx.classList.remove('hidden');
    book.classList.add('has-context');
  }

  async function loadModule(name, payload) {
    const key = name + JSON.stringify(payload || {});
    const r = await post('bookModule', { module: name, payload: payload || {} });
    if (r && r.ok) state.cache[key] = r.data;
    return r;
  }

  async function navigate(page) {
    state.page = page;
    renderNav();
    setContext('');
    const main = $('#book-main');
    main.innerHTML = '<p class="empty">Chargement…</p>';
    try {
      if (page === 'dashboard') await renderDashboard(main);
      else if (page === 'progression') await renderProgression(main);
      else if (page === 'objectives') await renderObjectives(main);
      else if (page === 'projects') await renderProjects(main);
      else if (page === 'resources') await renderResources(main);
      else if (page === 'blueprints') await renderPlans(main);
      else if (page === 'artisans') await renderArtisans(main);
      else if (page === 'network') await renderNetwork(main);
      else if (page === 'notes') await renderNotes(main);
      else if (page === 'productions') await renderProductions(main);
      else if (page === 'history' || page === 'discoveries') await renderHistory(main, page);
      else if (page === 'nextUnlocks') await renderNextUnlocks(main);
      else if (page === 'pins') await renderPins(main);
      else if (page === 'canCraft') await renderCanCraft(main);
      else if (page === 'suggestions') await renderSuggestions(main);
      else if (page === 'shopping') await renderShopping(main);
      else if (page === 'tree') await renderTree(main);
      else if (page === 'orders') await renderOrders(main);
      else if (page === 'workshop') await renderWorkshop(main);
      else if (page === 'maintenance') await renderMaintenance(main);
      else if (page === 'stats') await renderStats(main);
      else main.innerHTML = emptyBox('fa-circle-question', 'Module inconnu', 'Cette page n’existe pas dans le carnet.');
      main.classList.remove('page-enter');
      void main.offsetWidth;
      main.classList.add('page-enter');
    } catch (e) {
      main.innerHTML = `<p class="empty">Erreur: ${esc(e.message || e)}</p>`;
    }
  }

  /* ========== DASHBOARD ========== */
  async function renderDashboard(main) {
    const r = await post('bookDashboard', {});
    if (!r || !r.ok) {
      main.innerHTML = emptyBox('fa-table-columns', 'Dashboard indisponible', 'Le module Tableau de bord est désactivé ou inaccessible.');
      return;
    }
    const d = r.data || {};
    const st = d.stats || {};
    const prog = d.progression || {};
    const levels = prog.levels || {};
    const levelKeys = Object.keys(levels);
    const mainSkill = levelKeys[0] ? levels[levelKeys[0]] : null;
    const next = (d.nextUnlocks || [])[0];
    const objs = d.objectives || [];
    const pins = d.pins || [];
    const prods = (d.productions && d.productions.queue) || [];
    const projects = (d.productions && d.productions.projects) || [];
    const almost = (d.suggestions && d.suggestions.almost) || [];
    const canCraft = d.canCraft || [];

    const skillWidgets = levelKeys.map((k) => {
      const lv = levels[k] || {};
      const pct = Math.min(100, Math.max(8, (Number(lv.level) || 0) * 8));
      return `<div class="widget">
        <div class="widget-k"><i class="fa-solid fa-chart-line"></i> Compétence · ${esc(k)}</div>
        <div class="widget-v">Niv. ${esc(lv.level || 0)}</div>
        <div class="skill-bar"><span style="width:${pct}%"></span></div>
        <div class="widget-foot">Bonus ${esc(lv.bonus || 0)}% · ml_skills (lecture seule)</div>
      </div>`;
    }).join('') || `<div class="widget"><div class="widget-k"><i class="fa-solid fa-chart-line"></i> Spécialisation</div>
      <div class="widget-body empty">ml_skills indisponible</div></div>`;

    main.innerHTML = `
      ${pageHead('Tableau de bord', 'Synthèse de votre dossier technique de terrain')}
      <div class="widget-grid">
        ${skillWidgets}
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-bullseye"></i> Objectifs actifs</div>
          <div class="widget-v">${st.objectivesOpen || objs.length || 0}</div>
          <ul class="mini-list">${(objs.slice(0, 3).map((o) => `<li><span>${esc(o.title)}</span><span class="badge">${esc(o.kind || '')}</span></li>`).join('')) || '<li class="empty">Aucun objectif ouvert</li>'}</ul>
        </div>
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-folder-open"></i> Projet principal</div>
          ${projects[0]
            ? `<div class="widget-body"><strong>${esc(projects[0].label)}</strong>
                <div class="widget-foot">${projects[0].isOwner ? 'Propriétaire' : 'Contributeur'} · ${esc(projects[0].status || 'open')}</div></div>`
            : `<div class="widget-body empty">Aucun projet ouvert</div>`}
        </div>
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-unlock"></i> Prochain déblocage</div>
          ${next
            ? `<div class="widget-body"><strong>${esc(next.label)}</strong>
                <div class="widget-foot">${next.requireSkill ? `Skill: ${esc(next.requireSkill)}` : `Niv. ${esc(next.requireLevel)} (Δ ${esc(next.delta || '?')})`}</div></div>`
            : `<div class="widget-body empty">Rien de proche</div>`}
        </div>
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-thumbtack"></i> Épingles</div>
          <div class="widget-v">${st.pins || pins.length || 0}</div>
          <ul class="mini-list">${pins.slice(0, 3).map((p) => `<li><span>${esc(p.label)}</span></li>`).join('') || '<li class="empty">—</li>'}</ul>
        </div>
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-industry"></i> Productions</div>
          <div class="widget-v">${prods.length}</div>
          <ul class="mini-list">${prods.slice(0, 3).map((q) => `<li><span>${esc(q.label)}</span><span class="badge">x${q.batch || 1}</span></li>`).join('') || '<li class="empty">File vide</li>'}</ul>
        </div>
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-compass"></i> Dernière piste</div>
          ${almost[0]
            ? `<div class="widget-body"><strong>${esc(almost[0].label)}</strong>
                <div class="widget-foot">Presque craftable · manque ${(almost[0].missing || []).length}</div></div>`
            : canCraft[0]
              ? `<div class="widget-body"><strong>${esc(canCraft[0].label)}</strong><div class="widget-foot">Faisable maintenant</div></div>`
              : `<div class="widget-body empty">Pas de découverte récente</div>`}
        </div>
        <div class="widget">
          <div class="widget-k"><i class="fa-solid fa-address-book"></i> Artisans / notes</div>
          <div class="widget-body">
            <div class="pill-row" style="margin-bottom:8px">
              <span class="badge accent">${st.artisans || 0} contacts</span>
              <span class="badge">${st.notes || 0} notes</span>
              <span class="badge">${st.blueprints || 0} plans</span>
              <span class="badge">${st.resources || 0} ressources</span>
            </div>
            <div class="widget-foot">Rappels personnels & réseau de terrain</div>
          </div>
        </div>
        <div class="widget wide">
          <div class="widget-k"><i class="fa-solid fa-check"></i> Faisable maintenant</div>
          <ul class="mini-list">${canCraft.slice(0, 6).map((x) => `<li><span>${esc(x.label)}</span><span class="badge ok">${esc(x.category || '')}</span></li>`).join('') || '<li class="empty">Rien de prêt — ouvrez Suggestions</li>'}</ul>
        </div>
      </div>`;
  }

  /* ========== PROGRESSION ========== */
  async function renderProgression(main) {
    const r = await loadModule('progression');
    const p = (r && r.data) || {};
    const unlocks = await loadModule('nextUnlocks');
    const next = (unlocks && unlocks.data) || [];
    if (!p.available) {
      main.innerHTML = `
        ${pageHead('Progression', 'Lecture seule ml_skills — aucune XP parallèle')}
        ${emptyBox('fa-chart-line', 'ml_skills indisponible', 'Le carnet lit CraftingSkills en lecture seule. Aucune table XP craft.')}`;
      return;
    }
    const levels = p.levels || {};
    main.innerHTML = `
      ${pageHead('Progression', 'Compétences ml_skills · lecture seule')}
      <div class="cards">${Object.keys(levels).map((k) => {
        const lv = levels[k] || {};
        const pct = Math.min(100, Math.max(6, (Number(lv.level) || 0) * 8));
        return `<div class="skill-card">
          <div class="skill-name"><span>${esc(k)}</span><span class="badge accent">Niv. ${esc(lv.level || 0)}</span></div>
          <div class="skill-bar"><span style="width:${pct}%"></span></div>
          <div class="widget-foot">Bonus catégorie ${esc(lv.bonus || 0)}%</div>
        </div>`;
      }).join('')}</div>
      <div class="section">
        <h3 class="section-title">Prochains déblocages (recettes)</h3>
        <div class="unlock-list">${next.length ? next.map((x) => `
          <div class="unlock-row">
            <span>${esc(x.label)}</span>
            <span class="badge warn">${x.requireSkill ? `skill · ${esc(x.requireSkill)}` : `niv. ${esc(x.requireLevel)} · Δ${esc(x.delta || '')}`}</span>
          </div>`).join('') : '<p class="empty">Aucun déblocage proche</p>'}
        </div>
      </div>`;
  }

  async function renderNextUnlocks(main) {
    const r = await loadModule('nextUnlocks');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Déblocages', 'Recettes proches de votre niveau / skill')}
      <div class="unlock-list">${arr.length ? arr.map((x) => `
        <div class="unlock-row"><span>${esc(x.label)}</span>
        <span class="badge warn">${x.requireSkill ? 'skill' : 'niv. ' + esc(x.requireLevel)}</span></div>`).join('') : emptyBox('fa-unlock', 'Rien à débloquer', 'Revenez après progression ml_skills.')}
      </div>`;
  }

  /* ========== OBJECTIVES ========== */
  async function renderObjectives(main) {
    const r = await loadModule('objectives');
    const arr = (r && r.data) || [];
    const pinsR = modEnabled('Pins') ? await loadModule('pins') : { data: [] };
    const pinIds = new Set(((pinsR && pinsR.data) || []).map((p) => p.recipeId));

    main.innerHTML = `
      ${pageHead('Objectifs', 'Cartes de mission — priorité, détail, suivi')}
      <div class="note-editor" style="margin-bottom:14px">
        <div class="editor-label">Nouvel objectif</div>
        <div class="row-actions" style="margin-top:0">
          <input id="obj-title" type="text" placeholder="Titre de l’objectif…" style="flex:1;margin-top:0" />
          <button type="button" class="primary" id="obj-add">Ajouter</button>
        </div>
      </div>
      <div class="obj-grid" id="obj-grid"></div>`;

    const grid = $('#obj-grid');
    if (!arr.length) {
      grid.innerHTML = emptyBox('fa-bullseye', 'Aucun objectif', 'Ajoutez une mission manuelle ou depuis le craft.');
    } else {
      grid.innerHTML = arr.map((o) => {
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
      }).join('');
    }

    $('#obj-add').onclick = async () => {
      const title = $('#obj-title').value.trim();
      if (!title) return;
      await post('bookAction', { action: 'addObjective', payload: { title, kind: 'manual' } });
      navigate('objectives');
    };
    grid.onclick = async (ev) => {
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
  async function renderProjects(main) {
    const r = await loadModule('projects');
    const d = (r && r.data) || { queue: [], projects: [] };
    const projects = d.projects || [];
    main.innerHTML = `
      ${pageHead('Projets', 'Dossiers de chantier — progression & liens terrain')}
      <div class="dossier-grid" id="proj-grid"></div>`;
    const grid = $('#proj-grid');
    if (!projects.length) {
      grid.innerHTML = emptyBox('fa-folder-open', 'Aucun projet ouvert', 'Les projets craft auxquels vous participez apparaîtront ici.');
      return;
    }
    grid.innerHTML = projects.map((p) => `
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
      </article>`).join('');
    grid.onclick = (ev) => {
      const btn = ev.target.closest('button[data-act]');
      if (!btn) return;
      if (btn.dataset.act === 'tree') { state._treePrefill = btn.dataset.rid; navigate('tree'); }
      if (btn.dataset.act === 'shop') { state._shopPrefill = btn.dataset.rid; navigate('shopping'); }
    };
  }

  /* ========== RESOURCES ========== */
  async function renderResources(main) {
    const r = await loadModule('resources');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Codex ressources', 'Connaissance par découverte — pas de wiki omniscient')}
      <div class="codex-grid" id="codex"></div>`;
    const grid = $('#codex');
    if (!arr.length) {
      grid.innerHTML = emptyBox('fa-boxes-stacked', 'Codex vide', 'Craft & explorations révèlent les ressources. Les inconnues restent silhouettes.');
      // elegant unknown placeholder samples
      grid.innerHTML += Array.from({ length: 3 }).map(() => `
        <article class="codex-card unknown">
          <div class="codex-sil"><i class="fa-solid fa-question"></i></div>
          <div class="codex-label">Ressource inconnue</div>
          <div class="codex-id">non découverte</div>
        </article>`).join('');
      return;
    }
    grid.innerHTML = arr.map((x) => {
      const unknown = !x.label || x.label === '???' || x.known === false;
      return `<article class="codex-card ${unknown ? 'unknown' : ''}">
        <div class="codex-sil"><i class="fa-solid ${unknown ? 'fa-question' : 'fa-cube'}"></i></div>
        <div class="codex-label">${unknown ? 'Ressource inconnue' : esc(x.label)}</div>
        <div class="codex-id">${esc(x.item || '')}</div>
      </article>`;
    }).join('');
  }

  /* ========== PLANS (blueprints) ========== */
  async function renderPlans(main) {
    const r = await loadModule('blueprints');
    const arr = (r && r.data) || [];
    const filter = state.planFilter || 'known';
    main.innerHTML = `
      ${pageHead('Plans', 'Dossiers de schémas — connus, fragments, verrouillés')}
      <div class="plan-tabs">
        <button type="button" data-f="known" class="${filter === 'known' ? 'active' : ''}">Connus (${arr.length})</button>
        <button type="button" data-f="incomplete" class="${filter === 'incomplete' ? 'active' : ''}">Incomplets</button>
        <button type="button" data-f="fragments" class="${filter === 'fragments' ? 'active' : ''}">Fragments</button>
        <button type="button" data-f="locked" class="${filter === 'locked' ? 'active' : ''}">Verrouillés</button>
        <button type="button" data-f="recent" class="${filter === 'recent' ? 'active' : ''}">Récents</button>
      </div>
      <div class="dossier-grid" id="plans-grid"></div>`;
    const grid = $('#plans-grid');
    main.querySelectorAll('.plan-tabs button').forEach((b) => {
      b.onclick = () => { state.planFilter = b.dataset.f; renderPlans(main); };
    });
    if (filter === 'known' || filter === 'recent') {
      const list = filter === 'recent' ? arr.slice(0, 8) : arr;
      if (!list.length) {
        grid.innerHTML = emptyBox('fa-scroll', 'Aucun plan connu', 'Apprenez des blueprints via le craft pour les archiver ici.');
      } else {
        grid.innerHTML = list.map((x) => `
          <article class="dossier-card">
            <div class="dossier-mark">Schéma · connu</div>
            <h4>${esc(x.label || x.id)}</h4>
            <div class="dossier-meta"><span class="badge ok">BP</span><span class="badge">${esc(x.id)}</span></div>
            <div class="pct-ring">Archivé dans votre carnet technique</div>
          </article>`).join('');
      }
    } else {
      const hints = {
        incomplete: ['fa-puzzle-piece', 'Pas de plans incomplets', 'Les schémas partiels apparaîtront ici lorsqu’ils seront supportés par vos découvertes.'],
        fragments: ['fa-clone', 'Aucun fragment', 'Les fragments de plans collectés s’assemblent progressivement — dossier prêt.'],
        locked: ['fa-lock', 'Rien de verrouillé listé', 'Les plans au-delà de votre connaissance restent hors dossier (pas de spoil).'],
      };
      const h = hints[filter] || hints.incomplete;
      grid.innerHTML = emptyBox(h[0], h[1], h[2]);
    }
  }

  /* ========== ARTISANS ========== */
  async function renderArtisans(main) {
    const r = await loadModule('artisans');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Artisans', 'Contacts terrain — tiers qualitatifs uniquement')}
      <div class="contact-grid" id="art-grid"></div>`;
    const grid = $('#art-grid');
    if (!arr.length) {
      grid.innerHTML = emptyBox('fa-address-book', 'Aucun contact', 'Rencontrez des artisans via ox_target, carte ou craft.');
      return;
    }
    grid.innerHTML = arr.map((a) => {
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
        ${note ? `<div class="meta-line"><i class="fa-solid fa-sticky-note"></i> ${esc(note)}</div>` : '<div class="meta-line">Services : échange RP / craft (pas d’inventaire exact)</div>'}
      </article>`;
    }).join('');
  }

  /* ========== NETWORK ========== */
  async function renderNetwork(main) {
    const r = await loadModule('network');
    const net = (r && r.data) || {};
    const keys = Object.keys(net);
    main.innerHTML = `
      ${pageHead('Réseau', 'Domaines & densités de contacts par spécialité')}
      <div class="domain-grid" id="net-grid"></div>`;
    const grid = $('#net-grid');
    if (!keys.length) {
      grid.innerHTML = emptyBox('fa-network-wired', 'Réseau vide', 'Chaque spécialité rencontrée devient un domaine ici.');
      return;
    }
    grid.innerHTML = keys.map((k) => {
      const list = net[k] || [];
      return `<article class="domain-card">
        <div class="widget-k"><i class="fa-solid fa-diagram-project"></i> ${esc(k)}</div>
        <div class="count">${list.length}</div>
        <div class="widget-foot">${list.slice(0, 3).map((a) => esc(a.displayName)).join(' · ') || '—'}${list.length > 3 ? '…' : ''}</div>
      </article>`;
    }).join('');
  }

  /* ========== NOTES ========== */
  async function renderNotes(main) {
    const r = await loadModule('notes');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Notes', 'Carnet éditorial — notes libres, checklists, liens')}
      <div class="notes-layout">
        <div class="note-editor">
          <div class="editor-label">Nouvelle page</div>
          <input id="note-title" type="text" placeholder="Titre" />
          <textarea id="note-body" placeholder="Contenu, rappels, observations de terrain…"></textarea>
          <input id="note-check" type="text" placeholder="Checklist (items séparés par | )" />
          <div class="row-actions"><button type="button" class="primary" id="note-save">Enregistrer</button></div>
        </div>
        <div class="note-list" id="note-list"></div>
      </div>`;
    const list = $('#note-list');
    if (!arr.length) {
      list.innerHTML = emptyBox('fa-pen-to-square', 'Carnet vide', 'Vos notes personnelles s’accumulent ici.');
    } else {
      list.innerHTML = arr.map((n) => {
        const checks = Array.isArray(n.checklist) ? n.checklist : [];
        return `<article class="note-card" data-id="${n.id}">
          <div class="obj-top"><h4>${esc(n.title)}</h4>
            <button type="button" class="ghost small" data-act="del">✕</button></div>
          <p>${esc((n.body || '').slice(0, 280))}${(n.body || '').length > 280 ? '…' : ''}</p>
          ${checks.length ? `<ul class="checklist">${checks.map((c) => {
            const text = typeof c === 'string' ? c : (c && c.text) || '';
            const done = typeof c === 'object' && c && c.done;
            return `<li><i class="fa-solid ${done ? 'fa-square-check' : 'fa-square'}"></i>${esc(text)}</li>`;
          }).join('')}</ul>` : ''}
          <div class="widget-foot">${fmtTime(n.updatedAt)}</div>
        </article>`;
      }).join('');
    }
    $('#note-save').onclick = async () => {
      const raw = ($('#note-check').value || '').trim();
      const checklist = raw ? raw.split('|').map((t) => ({ text: t.trim(), done: false })).filter((x) => x.text) : [];
      await post('bookAction', {
        action: 'saveNote',
        payload: { title: $('#note-title').value, body: $('#note-body').value, checklist },
      });
      navigate('notes');
    };
    list.onclick = async (ev) => {
      const btn = ev.target.closest('button[data-act="del"]');
      if (!btn) return;
      await post('bookAction', { action: 'deleteNote', payload: { id: Number(btn.closest('[data-id]').dataset.id) } });
      navigate('notes');
    };
  }

  /* ========== PRODUCTIONS (board) ========== */
  async function renderProductions(main) {
    const r = await loadModule('productions');
    const d = (r && r.data) || { queue: [], projects: [] };
    const queue = d.queue || [];
    const projects = d.projects || [];
    main.innerHTML = `
      ${pageHead('Productions', 'Tableau de suivi — file & chantiers (pas le panneau craft)')}
      <div class="board">
        <div class="board-col">
          <h3>En file</h3>
          ${queue.length ? queue.map((q) => `
            <div class="board-card">
              <strong>${esc(q.label)}</strong>
              <div class="pill-row" style="margin-top:8px">
                <span class="badge">x${q.batch || 1}</span>
                ${q.finishAt ? `<span class="badge warn">fin ${fmtTime(q.finishAt)}</span>` : ''}
              </div>
            </div>`).join('') : '<p class="empty">File vide</p>'}
        </div>
        <div class="board-col">
          <h3>En cours / projets</h3>
          ${projects.length ? projects.map((p) => `
            <div class="board-card">
              <strong>${esc(p.label)}</strong>
              <div class="pill-row" style="margin-top:8px">
                <span class="badge accent">${esc(p.status || 'open')}</span>
                <span class="badge">${p.isOwner ? 'owner' : 'contrib'}</span>
              </div>
            </div>`).join('') : '<p class="empty">Aucun chantier</p>'}
        </div>
        <div class="board-col">
          <h3>Prêt / à collecter</h3>
          <p class="empty">La collecte se fait à l’atelier craft. Ce tableau suit l’état sans cloner le banc.</p>
        </div>
      </div>`;
  }

  /* ========== HISTORY ========== */
  async function renderHistory(main, page) {
    const mod = page === 'discoveries' ? 'discoveries' : 'history';
    const r = await loadModule(mod);
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead(page === 'discoveries' ? 'Découvertes' : 'Historique', 'Chronologie de terrain')}
      <div class="timeline" id="tl"></div>`;
    const tl = $('#tl');
    if (!arr.length) {
      tl.innerHTML = emptyBox('fa-clock-rotate-left', 'Journal vide', 'Découvertes, objectifs et rencontres s’empilent ici.');
      return;
    }
    tl.innerHTML = arr.map((x) => {
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
    }).join('');
  }

  /* ========== SECONDARY MODULES (richer than plain lists) ========== */
  async function renderPins(main) {
    const r = await loadModule('pins');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Épingles', 'Raccourcis + mini HUD')}
      <div class="row-actions" style="margin-top:0;margin-bottom:12px">
        <button type="button" class="ghost" id="hud-toggle"><i class="fa-solid fa-eye"></i> Basculer mini HUD</button>
      </div>
      <div class="dossier-grid">${arr.length ? arr.map((p) => `
        <article class="dossier-card">
          <div class="dossier-mark">Épingle</div>
          <h4>${esc(p.label)}</h4>
          <div class="dossier-meta"><span class="badge">${esc(p.category || '')}</span></div>
          <div class="row-actions">
            <button type="button" class="ghost small" data-rid="${esc(p.recipeId)}">Retirer</button>
          </div>
        </article>`).join('') : emptyBox('fa-thumbtack', 'Aucune épingle', 'Épinglez depuis l’UI craft ou un objectif recette.')}
      </div>`;
    main.querySelectorAll('button[data-rid]').forEach((b) => {
      b.onclick = async () => {
        await post('bookAction', { action: 'unpin', payload: { recipeId: b.dataset.rid } });
        navigate('pins');
      };
    });
    const ht = $('#hud-toggle');
    if (ht) ht.onclick = () => post('bookToggleHud', { enabled: true });
  }

  async function renderCanCraft(main) {
    const r = await loadModule('canCraft');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Faisable maintenant', 'Recettes prêtes avec votre inventaire & skills')}
      <div class="dossier-grid">${arr.length ? arr.map((x) => `
        <article class="dossier-card"><div class="dossier-mark">Prêt</div>
        <h4>${esc(x.label)}</h4>
        <div class="dossier-meta"><span class="badge ok">${esc(x.category || '')}</span></div></article>`).join('') : emptyBox('fa-check', 'Rien de faisable', 'Manque de composants ou de niveau.')}
      </div>`;
  }

  async function renderSuggestions(main) {
    const r = await loadModule('suggestions');
    const d = (r && r.data) || { almost: [], oneLevel: [] };
    main.innerHTML = `
      ${pageHead('Suggestions', 'Pistes de progression & crafts proches')}
      <div class="split">
        <div class="section"><h3 class="section-title">Presque craftable</h3>
          <div class="unlock-list">${(d.almost || []).map((x) => `
            <div class="unlock-row"><span>${esc(x.label)}</span><span class="badge warn">manque ${(x.missing || []).length}</span></div>`).join('') || '<p class="empty">—</p>'}
          </div>
        </div>
        <div class="section"><h3 class="section-title">À un niveau</h3>
          <div class="unlock-list">${(d.oneLevel || []).map((x) => `
            <div class="unlock-row"><span>${esc(x.label)}</span><span class="badge">+1</span></div>`).join('') || '<p class="empty">—</p>'}
          </div>
        </div>
      </div>`;
  }

  async function renderShopping(main) {
    main.innerHTML = `
      ${pageHead('Courses intelligentes', 'Expansion récursive, sans double-compte')}
      <div class="note-editor">
        <div class="row-actions" style="margin-top:0">
          <input id="shop-rid" type="text" placeholder="recipeId (ex: ex_metal_plate)" style="flex:1;margin-top:0" value="${esc(state._shopPrefill || '')}" />
          <input id="shop-batch" type="number" min="1" value="1" style="width:70px;margin-top:0" />
          <button type="button" class="primary" id="shop-go">Calculer</button>
        </div>
        <ul class="list" id="shop-out" style="margin-top:12px"></ul>
      </div>`;
    state._shopPrefill = '';
    $('#shop-go').onclick = async () => {
      const recipeId = $('#shop-rid').value.trim();
      const batch = Number($('#shop-batch').value) || 1;
      const r = await loadModule('shopping', { recipeId, batch });
      const list = (r && r.data) || [];
      $('#shop-out').innerHTML = list.map((x) =>
        `<li><span>${itemLabel(x)} <span class="badge">x${x.count}</span></span><span class="badge">inv ${x.have || 0}</span></li>`
      ).join('') || '<li class="empty">Rien à récupérer / recette invalide</li>';
    };
    if ($('#shop-rid').value) $('#shop-go').click();
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

  async function renderTree(main) {
    main.innerHTML = `
      ${pageHead('Arbre de craft', 'Dépendances masquées pour les inconnues')}
      <div class="note-editor">
        <div class="row-actions" style="margin-top:0">
          <input id="tree-rid" type="text" placeholder="recipeId" style="flex:1;margin-top:0" value="${esc(state._treePrefill || '')}" />
          <button type="button" class="primary" id="tree-go">Afficher</button>
        </div>
        <pre class="tree-pre" id="tree-out" style="margin-top:12px">—</pre>
      </div>`;
    state._treePrefill = '';
    $('#tree-go').onclick = async () => {
      const recipeId = $('#tree-rid').value.trim();
      const r = await loadModule('tree', { recipeId, depth: 3 });
      $('#tree-out').textContent = r && r.ok ? treeText(r.data) : (r && r.reason) || 'Erreur';
    };
    if ($('#tree-rid').value) $('#tree-go').click();
  }

  async function renderOrders(main) {
    const r = await loadModule('orders');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Commandes', 'Échange physique / RP — aucun téléport d’items')}
      <div class="note-editor" style="margin-bottom:14px">
        <div class="row-actions" style="margin-top:0">
          <input id="ord-note" type="text" placeholder="Note commande" style="flex:1;margin-top:0" />
          <input id="ord-rid" type="text" placeholder="recipeId optionnel" style="flex:1;margin-top:0" />
          <button type="button" class="primary" id="ord-add">Créer</button>
        </div>
      </div>
      <div class="dossier-grid">${arr.length ? arr.map((o) => `
        <article class="dossier-card">
          <div class="dossier-mark">Commande</div>
          <h4>${esc((o.orderUid || '').slice(0, 8))}…</h4>
          <div class="dossier-meta">
            <span class="badge">${esc(o.status)}</span>
            ${o.note || o.recipeId ? `<span class="badge accent">${esc(o.note || o.recipeId)}</span>` : ''}
          </div>
        </article>`).join('') : emptyBox('fa-handshake', 'Aucune commande', 'Créez une demande d’échange RP.')}
      </div>`;
    $('#ord-add').onclick = async () => {
      await post('bookAction', {
        action: 'createOrder',
        payload: { note: $('#ord-note').value, recipeId: $('#ord-rid').value.trim() || null, items: [] },
      });
      navigate('orders');
    };
  }

  async function renderWorkshop(main) {
    const r = await loadModule('workshop');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Mon atelier', 'Bancs connus — pas de GPS')}
      <div class="dossier-grid">${arr.length ? arr.map((s) => `
        <article class="dossier-card">
          <div class="dossier-mark">${esc(s.kind || 'banc')}</div>
          <h4>${esc(s.category)}</h4>
          <div class="dossier-meta">
            <span class="badge">L${s.stationLevel || 1}</span>
            <span class="badge ${s.powered === false ? 'warn' : 'ok'}">${s.powered === false ? 'OFF' : 'OK'}</span>
          </div>
        </article>`).join('') : emptyBox('fa-warehouse', 'Aucun banc', 'Placez ou découvrez des ateliers.')}
      </div>`;
  }

  async function renderMaintenance(main) {
    const r = await loadModule('maintenance');
    const arr = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Maintenance', 'Alertes outils & énergie')}
      <div class="unlock-list">${arr.length ? arr.map((h) => `
        <div class="unlock-row">
          <span>${esc(h.kind)} · ${esc(h.label || h.category || h.item || '')}</span>
          <span class="badge warn">${esc(h.hint || '')}</span>
        </div>`).join('') : emptyBox('fa-wrench', 'Rien à signaler', 'Tout semble en ordre.')}
      </div>`;
  }

  async function renderStats(main) {
    const r = await loadModule('stats');
    const st = (r && r.data) || {};
    const keys = Object.keys(st);
    main.innerHTML = `
      ${pageHead('Stats', 'Compteurs du dossier personnel')}
      <div class="cards">${keys.length ? keys.map((k) => `
        <div class="card"><div class="k">${esc(k)}</div><div class="v">${esc(st[k])}</div></div>`).join('') : emptyBox('fa-chart-simple', 'Pas de stats', '')}
      </div>`;
  }

  async function doSearch(q) {
    if (!q || q.length < 2) return;
    state.page = 'search';
    renderNav();
    setContext('');
    const main = $('#book-main');
    const r = await loadModule('search', { q });
    const hits = (r && r.data) || [];
    main.innerHTML = `
      ${pageHead('Recherche', `Résultats pour « ${q} »`)}
      <div class="unlock-list">${hits.length ? hits.map((h) => `
        <div class="unlock-row"><span>${esc(h.label)}</span><span class="badge">${esc(h.kind)}</span></div>`).join('') : emptyBox('fa-magnifying-glass', 'Aucun résultat', 'Élargissez les termes.')}
      </div>`;
  }

  function openBook(msg) {
    state.open = true;
    state.meta = msg.meta || {};
    state.modules = (state.meta.modules) || {};
    if (state.meta.accent) {
      document.documentElement.style.setProperty('--book-accent', state.meta.accent);
      document.documentElement.style.setProperty('--accent', state.meta.accent);
    }
    const title = state.meta.title || 'CARNET DE SURVIE';
    const titleEl = $('#book-title');
    const subEl = $('#book-sub');
    if (titleEl) titleEl.textContent = String(title).toUpperCase();
    if (subEl) subEl.textContent = state.meta.subtitle || 'Journal technique de terrain';
    book.classList.remove('hidden');
    book.classList.remove('is-opening');
    void book.offsetWidth;
    book.classList.add('is-opening');
    book.style.opacity = '1';
    book.style.visibility = 'visible';
    book.style.display = 'flex';
    renderNav();
    navigate(msg.page || 'dashboard');
  }

  function closeBook() {
    state.open = false;
    book.classList.add('hidden');
    setContext('');
    post('bookClose', {});
  }

  // Register open/close handlers BEFORE optional DOM binds — a missing node must never kill bookOpen
  window.addEventListener('message', (ev) => {
    const data = ev.data || {};
    if (data.action === 'bookOpen') {
      try { openBook(data); } catch (err) { console.error('[sanctuary_crafting bookOpen]', err); }
    }
    if (data.action === 'bookClose') {
      state.open = false;
      book.classList.add('hidden');
      setContext('');
    }
    if (data.action === 'bookPins') {
      // HUD handled in Lua
    }
    if (data.action === 'bookEvent' && state.open) {
      if (state.page === 'dashboard' || state.page === 'history' || state.page === 'artisans' || state.page === 'resources') {
        navigate(state.page);
      }
    }
  });

  window.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape' && state.open) closeBook();
  });

  const closeBtn = $('#book-btn-close');
  if (closeBtn) closeBtn.addEventListener('click', closeBook);
  const searchEl = $('#book-search');
  if (searchEl) searchEl.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') doSearch(ev.target.value.trim());
  });
})();
