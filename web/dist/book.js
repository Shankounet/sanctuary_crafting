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
  };

  const NAV = [
    { id: 'dashboard', label: 'Tableau de bord', mod: 'Dashboard' },
    { id: 'progression', label: 'Progression', mod: 'Progression' },
    { id: 'nextUnlocks', label: 'Prochains déblocages', mod: 'NextUnlocks' },
    { id: 'objectives', label: 'Objectifs', mod: 'Objectives' },
    { id: 'pins', label: 'Épingles', mod: 'Pins' },
    { id: 'canCraft', label: 'Faisable maintenant', mod: 'CanCraft' },
    { id: 'suggestions', label: 'Suggestions', mod: 'Suggestions' },
    { id: 'shopping', label: 'Courses (smart)', mod: 'Shopping' },
    { id: 'tree', label: 'Arbre de craft', mod: 'CraftTree' },
    { id: 'resources', label: 'Codex ressources', mod: 'Resources' },
    { id: 'discoveries', label: 'Découvertes', mod: 'Discoveries' },
    { id: 'blueprints', label: 'Schémas', mod: 'Blueprints' },
    { id: 'artisans', label: 'Artisans', mod: 'Artisans' },
    { id: 'network', label: 'Réseau', mod: 'Network' },
    { id: 'orders', label: 'Commandes', mod: 'Orders' },
    { id: 'productions', label: 'Productions', mod: 'Productions' },
    { id: 'workshop', label: 'Mon atelier', mod: 'Workshop' },
    { id: 'maintenance', label: 'Maintenance', mod: 'Maintenance' },
    { id: 'notes', label: 'Notes', mod: 'Notes' },
    { id: 'history', label: 'Historique', mod: 'History' },
    { id: 'stats', label: 'Stats', mod: 'Stats' },
  ];

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
    if (it.known === false || it.label === '???') return `<span class="unknown">???</span>`;
    return esc(it.label || it.item || '???');
  }

  function renderNav() {
    const nav = $('#book-nav');
    nav.innerHTML = '';
    NAV.forEach((n) => {
      if (state.modules[n.mod] === false) return;
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = n.label;
      b.dataset.page = n.id;
      if (state.page === n.id) b.classList.add('active');
      b.addEventListener('click', () => navigate(n.id));
      nav.appendChild(b);
    });
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
    const main = $('#book-main');
    main.innerHTML = '<p class="empty">Chargement…</p>';
    try {
      if (page === 'dashboard') await renderDashboard(main);
      else if (page === 'progression') await renderProgression(main);
      else if (page === 'nextUnlocks') await renderListModule(main, 'nextUnlocks', 'Prochains déblocages', (x) =>
        `<li><span>${esc(x.label)}</span><span class="badge warn">${x.requireSkill ? 'skill' : 'niv. ' + x.requireLevel}</span></li>`);
      else if (page === 'objectives') await renderObjectives(main);
      else if (page === 'pins') await renderPins(main);
      else if (page === 'canCraft') await renderListModule(main, 'canCraft', 'Faisable maintenant', (x) =>
        `<li><span>${esc(x.label)}</span><span class="badge ok">${esc(x.category || '')}</span></li>`);
      else if (page === 'suggestions') await renderSuggestions(main);
      else if (page === 'shopping') await renderShopping(main);
      else if (page === 'tree') await renderTree(main);
      else if (page === 'resources') await renderResources(main);
      else if (page === 'discoveries' || page === 'history') await renderHistory(main, page);
      else if (page === 'blueprints') await renderListModule(main, 'blueprints', 'Schémas connus', (x) =>
        `<li><span>${esc(x.label || x.id)}</span><span class="badge">BP</span></li>`);
      else if (page === 'artisans') await renderArtisans(main);
      else if (page === 'network') await renderNetwork(main);
      else if (page === 'orders') await renderOrders(main);
      else if (page === 'productions') await renderProductions(main);
      else if (page === 'workshop') await renderWorkshop(main);
      else if (page === 'maintenance') await renderMaintenance(main);
      else if (page === 'notes') await renderNotes(main);
      else if (page === 'stats') await renderStats(main);
      else main.innerHTML = '<p class="empty">Module inconnu</p>';
    } catch (e) {
      main.innerHTML = `<p class="empty">Erreur: ${esc(e.message || e)}</p>`;
    }
  }

  async function renderDashboard(main) {
    const r = await post('bookDashboard', {});
    if (!r || !r.ok) { main.innerHTML = '<p class="empty">Dashboard indisponible</p>'; return; }
    const d = r.data || {};
    const st = d.stats || {};
    main.innerHTML = `
      <div class="cards">
        <div class="card"><div class="k">Ressources</div><div class="v">${st.resources || 0}</div></div>
        <div class="card"><div class="k">Objectifs</div><div class="v">${st.objectivesOpen || 0}</div></div>
        <div class="card"><div class="k">Épingles</div><div class="v">${st.pins || 0}</div></div>
        <div class="card"><div class="k">Artisans</div><div class="v">${st.artisans || 0}</div></div>
        <div class="card"><div class="k">Schémas</div><div class="v">${st.blueprints || 0}</div></div>
      </div>
      <div class="split">
        <div class="section"><h2>Épingles</h2><ul class="list" id="dash-pins"></ul></div>
        <div class="section"><h2>Objectifs ouverts</h2><ul class="list" id="dash-obj"></ul></div>
      </div>
      <div class="split">
        <div class="section"><h2>Faisable</h2><ul class="list" id="dash-craft"></ul></div>
        <div class="section"><h2>Presque</h2><ul class="list" id="dash-almost"></ul></div>
      </div>`;
    const fill = (sel, arr, fn) => {
      const el = $(sel);
      if (!arr || !arr.length) { el.innerHTML = '<li class="empty">—</li>'; return; }
      el.innerHTML = arr.map(fn).join('');
    };
    fill('#dash-pins', d.pins, (x) => `<li><span>${esc(x.label)}</span><span class="badge">${esc(x.category || '')}</span></li>`);
    fill('#dash-obj', d.objectives, (x) => `<li><span>${esc(x.title)}</span><span class="badge">${esc(x.kind)}</span></li>`);
    fill('#dash-craft', d.canCraft, (x) => `<li><span>${esc(x.label)}</span><span class="badge ok">OK</span></li>`);
    fill('#dash-almost', (d.suggestions && d.suggestions.almost) || [], (x) => `<li><span>${esc(x.label)}</span><span class="badge warn">~</span></li>`);
  }

  async function renderProgression(main) {
    const r = await loadModule('progression');
    const p = (r && r.data) || {};
    if (!p.available) {
      main.innerHTML = `<div class="section"><h2>Progression</h2><p class="empty">ml_skills indisponible (lecture seule — aucun XP parallèle).</p></div>`;
      return;
    }
    const levels = p.levels || {};
    main.innerHTML = `<div class="section"><h2>Progression (ml_skills · lecture seule)</h2>
      <div class="cards">${Object.keys(levels).map((k) => `
        <div class="card"><div class="k">${esc(k)}</div>
        <div class="v">Niv. ${levels[k].level || 0}</div>
        <div class="k">Bonus ${levels[k].bonus || 0}%</div></div>`).join('')}
      </div>
      <p class="empty">Aucune donnée d'autrui. Pas de table XP craft.</p></div>`;
  }

  async function renderListModule(main, mod, title, rowFn) {
    const r = await loadModule(mod);
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>${esc(title)}</h2>
      <ul class="list">${arr.length ? arr.map(rowFn).join('') : '<li class="empty">Aucune entrée</li>'}</ul></div>`;
  }

  async function renderObjectives(main) {
    const r = await loadModule('objectives');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Objectifs</h2>
      <div class="row-actions">
        <input id="obj-title" type="text" placeholder="Nouvel objectif…" />
        <button type="button" class="primary" id="obj-add">Ajouter</button>
      </div>
      <ul class="list" id="obj-list"></ul></div>`;
    const list = $('#obj-list');
    list.innerHTML = arr.map((o) => `
      <li data-id="${o.id}">
        <span>${o.done ? '✓ ' : ''}${esc(o.title)} <span class="badge">${esc(o.kind)}</span></span>
        <span>
          ${!o.done ? `<button type="button" class="ghost small" data-act="done">OK</button>` : ''}
          <button type="button" class="ghost small" data-act="del">✕</button>
        </span>
      </li>`).join('') || '<li class="empty">Aucun objectif</li>';
    $('#obj-add').onclick = async () => {
      const title = $('#obj-title').value.trim();
      if (!title) return;
      await post('bookAction', { action: 'addObjective', payload: { title, kind: 'manual' } });
      navigate('objectives');
    };
    list.onclick = async (ev) => {
      const btn = ev.target.closest('button');
      if (!btn) return;
      const li = btn.closest('li');
      const id = Number(li.dataset.id);
      if (btn.dataset.act === 'done') await post('bookAction', { action: 'completeObjective', payload: { id } });
      if (btn.dataset.act === 'del') await post('bookAction', { action: 'removeObjective', payload: { id } });
      navigate('objectives');
    };
  }

  async function renderPins(main) {
    const r = await loadModule('pins');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Épingles + mini HUD</h2>
      <div class="row-actions"><button type="button" class="ghost" id="hud-toggle">Basculer mini HUD</button></div>
      <ul class="list">${arr.map((p) => `
        <li><span>${esc(p.label)}</span>
        <button type="button" class="ghost small" data-rid="${esc(p.recipeId)}">Retirer</button></li>`).join('') || '<li class="empty">Aucune épingle — utilisez le craft UI</li>'}
      </ul></div>`;
    main.querySelectorAll('button[data-rid]').forEach((b) => {
      b.onclick = async () => {
        await post('bookAction', { action: 'unpin', payload: { recipeId: b.dataset.rid } });
        navigate('pins');
      };
    });
    const ht = $('#hud-toggle');
    if (ht) ht.onclick = () => post('bookToggleHud', { enabled: true });
  }

  async function renderSuggestions(main) {
    const r = await loadModule('suggestions');
    const d = (r && r.data) || { almost: [], oneLevel: [] };
    main.innerHTML = `<div class="split">
      <div class="section"><h2>Presque craftable</h2>
        <ul class="list">${(d.almost || []).map((x) => `<li><span>${esc(x.label)}</span><span class="badge warn">manque ${(x.missing||[]).length}</span></li>`).join('') || '<li class="empty">—</li>'}</ul>
      </div>
      <div class="section"><h2>À un niveau</h2>
        <ul class="list">${(d.oneLevel || []).map((x) => `<li><span>${esc(x.label)}</span><span class="badge">+1</span></li>`).join('') || '<li class="empty">—</li>'}</ul>
      </div></div>`;
  }

  async function renderShopping(main) {
    main.innerHTML = `<div class="section"><h2>Liste courses intelligente</h2>
      <p class="empty">Récursive, sans double-compte si intermédiaire possédé. Garde anti-cycle.</p>
      <div class="row-actions">
        <input id="shop-rid" type="text" placeholder="recipeId (ex: ex_metal_plate)" />
        <input id="shop-batch" type="number" min="1" value="1" style="width:70px" />
        <button type="button" class="primary" id="shop-go">Calculer</button>
      </div>
      <ul class="list" id="shop-out"></ul></div>`;
    $('#shop-go').onclick = async () => {
      const recipeId = $('#shop-rid').value.trim();
      const batch = Number($('#shop-batch').value) || 1;
      const r = await loadModule('shopping', { recipeId, batch });
      const list = (r && r.data) || [];
      $('#shop-out').innerHTML = list.map((x) =>
        `<li><span>${itemLabel(x)} <span class="badge">x${x.count}</span></span><span class="badge">inv ${x.have||0}</span></li>`
      ).join('') || '<li class="empty">Rien à récupérer / recette invalide</li>';
    };
  }

  function treeText(node, indent) {
    if (!node) return '';
    indent = indent || '';
    if (node.type === 'raw') {
      const lab = node.known === false ? '???' : (node.label || node.item);
      return `${indent}- ${lab} x${node.count || 1}\n`;
    }
    let s = `${indent}* ${node.label || node.id}\n`;
    (node.children || []).forEach((c) => { s += treeText(c, indent + '  '); });
    return s;
  }

  async function renderTree(main) {
    main.innerHTML = `<div class="section"><h2>Arbre de craft</h2>
      <div class="row-actions">
        <input id="tree-rid" type="text" placeholder="recipeId" />
        <button type="button" class="primary" id="tree-go">Afficher</button>
      </div>
      <pre class="tree-pre" id="tree-out">—</pre></div>`;
    $('#tree-go').onclick = async () => {
      const recipeId = $('#tree-rid').value.trim();
      const r = await loadModule('tree', { recipeId, depth: 3 });
      $('#tree-out').textContent = r && r.ok ? treeText(r.data) : (r && r.reason) || 'Erreur';
    };
  }

  async function renderResources(main) {
    const r = await loadModule('resources');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Codex ressources (découvertes uniquement)</h2>
      <p class="empty">Les inconnues apparaissent comme ??? — pas de wiki omniscient, pas de GPS.</p>
      <ul class="list">${arr.map((x) => `<li><span>${esc(x.label || x.item)}</span><span class="badge">${esc(x.item)}</span></li>`).join('') || '<li class="empty">Aucune ressource découverte</li>'}
      </ul></div>`;
  }

  async function renderHistory(main, page) {
    const r = await loadModule(page === 'discoveries' ? 'discoveries' : 'history');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>${page === 'discoveries' ? 'Découvertes' : 'Historique'}</h2>
      <ul class="list">${arr.map((x) => `<li><span>${esc(x.type)}</span><span class="badge">${esc(JSON.stringify(x.payload || {}).slice(0, 48))}</span></li>`).join('') || '<li class="empty">Vide</li>'}
      </ul></div>`;
  }

  async function renderArtisans(main) {
    const r = await loadModule('artisans');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Artisans</h2>
      <p class="empty">Tiers qualitatifs uniquement — jamais niveaux/licences/inventaires exacts d'autrui. Rencontre via ox_target / carte / craft.</p>
      <ul class="list">${arr.map((a) => `
        <li><span>${esc(a.displayName)} <span class="badge">${esc(a.specialty || 'general')}</span></span>
        <span class="badge warn">${esc(a.tier || 'unknown')}</span></li>`).join('') || '<li class="empty">Aucun contact</li>'}
      </ul></div>`;
  }

  async function renderNetwork(main) {
    const r = await loadModule('network');
    const net = (r && r.data) || {};
    const keys = Object.keys(net);
    main.innerHTML = `<div class="section"><h2>Réseau par spécialité</h2>
      ${keys.length ? keys.map((k) => `
        <div class="section"><h2>${esc(k)}</h2>
          <ul class="list">${net[k].map((a) => `<li><span>${esc(a.displayName)}</span><span class="badge">${esc(a.tier)}</span></li>`).join('')}</ul>
        </div>`).join('') : '<p class="empty">Réseau vide</p>'}
      </div>`;
  }

  async function renderOrders(main) {
    const r = await loadModule('orders');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Commandes craft</h2>
      <p class="empty">Échange physique / RP uniquement — aucun téléport d'items.</p>
      <div class="row-actions">
        <input id="ord-note" type="text" placeholder="Note commande" />
        <input id="ord-rid" type="text" placeholder="recipeId optionnel" />
        <button type="button" class="primary" id="ord-add">Créer</button>
      </div>
      <ul class="list">${arr.map((o) => `
        <li><span>${esc(o.orderUid.slice(0, 8))}… ${esc(o.note || o.recipeId || '')}</span>
        <span class="badge">${esc(o.status)}</span></li>`).join('') || '<li class="empty">Aucune commande</li>'}
      </ul></div>`;
    $('#ord-add').onclick = async () => {
      await post('bookAction', {
        action: 'createOrder',
        payload: { note: $('#ord-note').value, recipeId: $('#ord-rid').value.trim() || null, items: [] },
      });
      navigate('orders');
    };
  }

  async function renderProductions(main) {
    const r = await loadModule('productions');
    const d = (r && r.data) || { queue: [], projects: [] };
    main.innerHTML = `<div class="split">
      <div class="section"><h2>File</h2>
        <ul class="list">${(d.queue||[]).map((q)=>`<li><span>${esc(q.label)}</span><span class="badge">x${q.batch||1}</span></li>`).join('') || '<li class="empty">Vide</li>'}</ul>
      </div>
      <div class="section"><h2>Projets</h2>
        <ul class="list">${(d.projects||[]).map((p)=>`<li><span>${esc(p.label)}</span><span class="badge">${p.isOwner?'owner':'contrib'}</span></li>`).join('') || '<li class="empty">Aucun</li>'}</ul>
      </div></div>`;
  }

  async function renderWorkshop(main) {
    const r = await loadModule('workshop');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Mon atelier</h2>
      <p class="empty">Pas de coordonnées GPS — catégorie / niveau / modules seulement.</p>
      <ul class="list">${arr.map((s) => `
        <li><span>${esc(s.category)} (${esc(s.kind)})</span>
        <span class="badge">L${s.stationLevel||1}${s.powered===false?' · OFF':''}</span></li>`).join('') || '<li class="empty">Aucun banc</li>'}
      </ul></div>`;
  }

  async function renderMaintenance(main) {
    const r = await loadModule('maintenance');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Maintenance</h2>
      <ul class="list">${arr.map((h) => `
        <li><span>${esc(h.kind)} ${esc(h.label || h.category || h.item || '')}</span>
        <span class="badge warn">${esc(h.hint || '')}</span></li>`).join('') || '<li class="empty">Rien à signaler</li>'}
      </ul></div>`;
  }

  async function renderNotes(main) {
    const r = await loadModule('notes');
    const arr = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Notes / checklists</h2>
      <input id="note-title" type="text" placeholder="Titre" />
      <textarea id="note-body" placeholder="Contenu…"></textarea>
      <div class="row-actions"><button type="button" class="primary" id="note-save">Enregistrer</button></div>
      <ul class="list" id="note-list"></ul></div>`;
    $('#note-list').innerHTML = arr.map((n) => `
      <li data-id="${n.id}"><span><strong>${esc(n.title)}</strong> — ${esc((n.body||'').slice(0,60))}</span>
      <button type="button" class="ghost small" data-act="del">✕</button></li>`).join('') || '<li class="empty">Aucune note</li>';
    $('#note-save').onclick = async () => {
      await post('bookAction', { action: 'saveNote', payload: { title: $('#note-title').value, body: $('#note-body').value } });
      navigate('notes');
    };
    $('#note-list').onclick = async (ev) => {
      const btn = ev.target.closest('button[data-act="del"]');
      if (!btn) return;
      await post('bookAction', { action: 'deleteNote', payload: { id: Number(btn.closest('li').dataset.id) } });
      navigate('notes');
    };
  }

  async function renderStats(main) {
    const r = await loadModule('stats');
    const st = (r && r.data) || {};
    main.innerHTML = `<div class="section"><h2>Stats (compteurs)</h2>
      <div class="cards">${Object.keys(st).map((k) => `
        <div class="card"><div class="k">${esc(k)}</div><div class="v">${st[k]}</div></div>`).join('')}
      </div></div>`;
  }

  async function doSearch(q) {
    if (!q || q.length < 2) return;
    state.page = 'search';
    renderNav();
    const main = $('#book-main');
    const r = await loadModule('search', { q });
    const hits = (r && r.data) || [];
    main.innerHTML = `<div class="section"><h2>Recherche — ${esc(q)}</h2>
      <ul class="list">${hits.map((h) => `<li><span>${esc(h.label)}</span><span class="badge">${esc(h.kind)}</span></li>`).join('') || '<li class="empty">Aucun résultat</li>'}
      </ul></div>`;
  }

  function openBook(msg) {
    state.open = true;
    state.meta = msg.meta || {};
    state.modules = (state.meta.modules) || {};
    if (state.meta.accent) {
      document.documentElement.style.setProperty('--book-accent', state.meta.accent);
      document.documentElement.style.setProperty('--accent', state.meta.accent);
    }
    $('#book-title').textContent = state.meta.title || 'Carnet de survie';
    $('#book-sub').textContent = state.meta.subtitle || 'Manuel de terrain';
    book.classList.remove('hidden');
    renderNav();
    navigate(msg.page || 'dashboard');
  }

  function closeBook() {
    state.open = false;
    book.classList.add('hidden');
    post('bookClose', {});
  }

  $('#book-btn-close').addEventListener('click', closeBook);
  $('#book-search').addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') doSearch(ev.target.value.trim());
  });

  window.addEventListener('message', (ev) => {
    const data = ev.data || {};
    if (data.action === 'bookOpen') openBook(data);
    if (data.action === 'bookClose') {
      state.open = false;
      book.classList.add('hidden');
    }
    if (data.action === 'bookPins') {
      // HUD handled in Lua; optional toast in book if open
    }
  });

  window.addEventListener('keydown', (ev) => {
    if (ev.key === 'Escape' && state.open) closeBook();
  });
})();
