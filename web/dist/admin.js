(() => {
  const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sanctuary_crafting';
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const root = $('#craft-admin');
  if (!root) return;

  const IMG_BASE = 'nui://ox_inventory/web/images/';
  const state = {
    meta: { stations: [], categories: [], rarities: [], signatureModes: [] },
    list: [],
    selected: null,
    draft: emptyDraft(),
    oxTarget: null,
    previewTimer: null,
  };

  function emptyDraft() {
    return {
      id: '', result: '', qty: 1, oxLabel: '', description: '',
      station: '', category: '', rarity: 'common',
      requireSpec: '', requireSkill: '', requireLevel: '',
      duration: 5000, xp: 0, xpCategory: '',
      mastery: 0, ingredients: [], tools: [],
      energy: 0, noise: 0, heat: 0, blueprint: '',
      teachable: false, batchMax: 50, signatureMode: 'batch', discovery: false,
      _disabled: false,
    };
  }

  function post(name, data) {
    return fetch(`https://${res}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({ ok: false }));
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function status(msg, kind) {
    const el = $('#ca-status');
    if (!el) return;
    el.textContent = msg || '';
    el.className = 'ca-status' + (kind ? ' ' + kind : '');
  }

  function fillSelect(el, items, withBlank) {
    if (!el) return;
    const cur = el.value;
    el.innerHTML = withBlank ? '<option value="">—</option>' : '';
    (items || []).forEach((it) => {
      const id = typeof it === 'string' ? it : it.id;
      const label = typeof it === 'string' ? it : (it.label || it.id);
      const o = document.createElement('option');
      o.value = id; o.textContent = label;
      el.appendChild(o);
    });
    if (cur) el.value = cur;
  }

  function readDraft() {
    const d = state.draft;
    d.id = $('#ca-id').value.trim();
    d.result = $('#ca-result').value.trim();
    d.qty = Number($('#ca-qty').value) || 1;
    d.oxLabel = $('#ca-oxlabel').value.trim();
    d.description = $('#ca-desc').value.trim();
    d.station = $('#ca-station').value;
    d.category = $('#ca-category').value;
    d.rarity = $('#ca-rarity').value;
    d.requireSpec = $('#ca-spec').value.trim();
    d.requireSkill = $('#ca-skill').value.trim();
    d.requireLevel = $('#ca-level').value;
    d.duration = Number($('#ca-duration').value) || 5000;
    d.xp = Number($('#ca-xp').value) || 0;
    d.xpCategory = $('#ca-xpcat').value.trim();
    d.energy = Number($('#ca-energy').value) || 0;
    d.noise = Number($('#ca-noise').value) || 0;
    d.heat = Number($('#ca-heat').value) || 0;
    d.blueprint = $('#ca-blueprint').value.trim();
    d.teachable = $('#ca-teachable').checked;
    d.batchMax = Number($('#ca-batchmax').value) || 50;
    d.signatureMode = $('#ca-sig').value;
    d.discovery = $('#ca-discovery').checked;
    d.ingredients = $$('#ca-ings .ing-row').map((row) => ({
      item: $('.ing-item', row).value.trim(),
      count: Number($('.ing-qty', row).value) || 1,
      consumed: $('.ing-cons', row).checked,
      optional: $('.ing-opt', row).checked,
      altGroup: $('.ing-alt', row).value.trim(),
    })).filter((x) => x.item);
    d.tools = $$('#ca-tools .tool-row').map((row) => ({
      item: $('.tool-item', row).value.trim(),
      count: 1,
      consume: false,
    })).filter((x) => x.item);
    return d;
  }

  function writeDraft(d) {
    state.draft = Object.assign(emptyDraft(), d || {});
    const r = state.draft;
    const result = (r.result && typeof r.result === 'object' && !Array.isArray(r.result)) ? r.result.item : r.result;
    const qty = ((r.result && typeof r.result === 'object' && r.result.count) ? r.result.count : r.qty) || 1;
    $('#ca-id').value = r.id || '';
    $('#ca-result').value = result || '';
    $('#ca-qty').value = qty;
    $('#ca-oxlabel').value = r.oxLabel || r.label || '';
    $('#ca-desc').value = r.description || '';
    $('#ca-station').value = r.station || '';
    $('#ca-category').value = r.category || '';
    $('#ca-rarity').value = r.rarity || 'common';
    $('#ca-spec').value = r.requireSpec || '';
    $('#ca-skill').value = r.requireSkill || '';
    $('#ca-level').value = r.requireLevel || '';
    $('#ca-duration').value = r.duration || 5000;
    $('#ca-xp').value = (r.xp && r.xp.amount) || r.xp || 0;
    $('#ca-xpcat').value = (r.xp && r.xp.category) || r.xpCategory || r.requireSkill || '';
    $('#ca-energy').value = r.energy || r.powerCost || 0;
    $('#ca-noise').value = r.noise || r.noiseLevel || 0;
    $('#ca-heat').value = r.heat || 0;
    $('#ca-blueprint').value = r.blueprint || r.requireBlueprint || r.blueprintId || '';
    $('#ca-teachable').checked = !!r.teachable;
    $('#ca-batchmax').value = r.batchMax || r.maxQuantity || 50;
    $('#ca-sig').value = r.signatureMode || 'batch';
    $('#ca-discovery').checked = !!r.discovery || !!r.requiresLearn;
    renderIngRows(r.ingredients || []);
    renderToolRows(r.tools || []);
    schedulePreview();
  }

  function renderIngRows(list) {
    const host = $('#ca-ings');
    host.innerHTML = '';
    (list.length ? list : [{ item: '', count: 1 }]).forEach((ing) => host.appendChild(ingRow(ing)));
  }
  function renderToolRows(list) {
    const host = $('#ca-tools');
    host.innerHTML = '';
    (list.length ? list : [{ item: '' }]).forEach((t) => host.appendChild(toolRow(t)));
  }

  function ingRow(ing) {
    const row = document.createElement('div');
    row.className = 'ing-row';
    const item = (ing && (ing.item || ing)) || '';
    row.innerHTML = `
      <input class="ing-item" placeholder="item" value="${escapeHtml(item)}" />
      <input class="ing-qty" type="number" min="1" value="${escapeHtml(ing.count || 1)}" />
      <label class="ca-chk"><input class="ing-cons" type="checkbox" ${ing.consumed !== false ? 'checked' : ''}/>cons.</label>
      <label class="ca-chk"><input class="ing-opt" type="checkbox" ${ing.optional ? 'checked' : ''}/>opt.</label>
      <input class="ing-alt" placeholder="alt grp" value="${escapeHtml(ing.altGroup || '')}" />
      <button type="button" class="ghost ing-del" title="Retirer">×</button>`;
    $('.ing-del', row).addEventListener('click', () => { row.remove(); schedulePreview(); });
    $$('input', row).forEach((i) => i.addEventListener('input', schedulePreview));
    $('.ing-item', row).addEventListener('focus', () => bindOx($('.ing-item', row)));
    return row;
  }
  function toolRow(t) {
    const row = document.createElement('div');
    row.className = 'tool-row';
    const item = typeof t === 'string' ? t : (t && t.item) || '';
    row.innerHTML = `
      <input class="tool-item" placeholder="outil" value="${escapeHtml(item)}" />
      <span></span><span></span><span></span><span></span>
      <button type="button" class="ghost tool-del">×</button>`;
    $('.tool-del', row).addEventListener('click', () => { row.remove(); schedulePreview(); });
    $('.tool-item', row).addEventListener('input', schedulePreview);
    $('.tool-item', row).addEventListener('focus', () => bindOx($('.tool-item', row)));
    return row;
  }

  function bindOx(input) {
    state.oxTarget = input;
    const box = $('#ca-oxbox');
    if (box) box.style.display = 'block';
    $('#ca-oxq').value = input.value || '';
    $('#ca-oxq').focus();
    searchOx();
  }

  let oxTimer = null;
  function searchOx() {
    clearTimeout(oxTimer);
    oxTimer = setTimeout(async () => {
      const q = $('#ca-oxq').value.trim();
      const r = await post('craftadminSearchOx', { q, limit: 20 });
      const host = $('#ca-oxresults');
      host.innerHTML = '';
      (r.items || []).forEach((it) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.textContent = `${it.label}  ·  ${it.spawn || it.name}`;
        b.addEventListener('click', () => {
          if (state.oxTarget) {
            state.oxTarget.value = it.name || it.spawn;
            if (state.oxTarget.id === 'ca-result') {
              $('#ca-oxlabel').value = it.label || '';
              if (it.description && !$('#ca-desc').value) $('#ca-desc').value = it.description;
            }
          }
          host.innerHTML = '';
          schedulePreview();
        });
        host.appendChild(b);
      });
    }, 180);
  }

  function schedulePreview() {
    clearTimeout(state.previewTimer);
    state.previewTimer = setTimeout(runPreview, 220);
  }

  async function runPreview() {
    const draft = readDraft();
    if (!draft.id && !draft.result) {
      renderPreview(null, null);
      return;
    }
    const r = await post('craftadminPreview', draft);
    renderPreview(r && r.entry, r && r.ox, r && r.valid);
  }

  function renderPreview(entry, ox, valid) {
    const host = $('#admin-preview-app');
    if (!host) return;
    if (!entry) {
      host.innerHTML = '<p class="ca-status">Aperçu live — remplissez id + résultat</p>';
      return;
    }
    const item = (entry.result && entry.result.item) || entry.id;
    const label = entry.label || (ox && ox.label) || item;
    const desc = entry.description || (ox && ox.description) || '';
    const ings = (entry.ingredients || []).map((ing) => {
      const need = ing.count || 1;
      const owned = typeof ing.owned === 'number' ? ing.owned : '?';
      return `<li><span>${escapeHtml(ing.label || ing.item)}</span><span>${owned}/${need}</span></li>`;
    }).join('');
    const st = entry.locked ? 'VERROUILLÉ' : (entry.missingItems ? 'MANQUANT' : 'OPÉRATIONNEL');
    host.innerHTML = `
      <article class="recipe-card selected state-${entry.locked ? 'bad' : 'ok'}">
        <div class="card-img-zone">
          <img src="${IMG_BASE}${encodeURIComponent(item)}.png" alt="" onerror="this.style.display='none'"/>
          <span class="card-state-badge">${st}</span>
        </div>
        <div class="card-body">
          <div class="card-identity">
            <div class="card-title">${escapeHtml(label)}</div>
            <div class="card-meta-line">
              <span class="card-cat">${escapeHtml(entry.category || '')}</span>
              <span class="card-code">${escapeHtml(entry.id || '')}</span>
            </div>
          </div>
        </div>
      </article>
      <div class="detail-fiche">
        <div class="fiche-hero">
          <p class="fiche-l1-label">Fiche · Identité (preview)</p>
          <div class="fiche-identity">
            <div class="fiche-img"><img src="${IMG_BASE}${encodeURIComponent(item)}.png" alt="" onerror="this.style.display='none'"/></div>
            <div>
              <span class="badge">${escapeHtml(entry.category || '')}</span>
              <span class="badge">${escapeHtml(entry.rarity || '')}</span>
              <h2 class="t-l2">${escapeHtml(label)}</h2>
              <p class="t-l6">${escapeHtml(desc)}</p>
            </div>
          </div>
        </div>
        <p class="fiche-section-label">Paramètres</p>
        <div class="kv-row"><span>Résultat</span><span>${escapeHtml(item)} ×${(entry.result && entry.result.count) || 1}</span></div>
        <div class="kv-row"><span>Durée</span><span>${Math.round((entry.duration || 0)/1000)}s</span></div>
        <div class="kv-row"><span>Station</span><span>${escapeHtml(entry.station || '')}</span></div>
        <div class="kv-row"><span>Skill</span><span>${escapeHtml(entry.requireSkill || '—')} ${entry.requireLevel || ''}</span></div>
        <div class="kv-row"><span>XP</span><span>${entry.xp ? (entry.xp.amount + ' ' + (entry.xp.category || '')) : '—'}</span></div>
        <div class="kv-row"><span>Batch max</span><span>${entry.batchMax || entry.maxQuantity || '—'}</span></div>
        <div class="kv-row"><span>Signature</span><span>${escapeHtml(entry.signatureMode || '')}</span></div>
        <div class="kv-row"><span>Validité schéma</span><span>${valid === false ? 'INVALIDE' : 'OK'}</span></div>
        <h3 class="t-l3">Matériaux</h3>
        <ul class="ing-list">${ings || '<li>—</li>'}</ul>
      </div>`;
  }

  async function loadList() {
    const r = await post('craftadminList', {
      q: $('#ca-search').value.trim(),
      station: $('#ca-f-station').value,
      category: $('#ca-f-category').value,
      rarity: $('#ca-f-rarity').value,
    });
    state.list = (r && r.recipes) || [];
    const ul = $('#ca-list');
    ul.innerHTML = '';
    state.list.forEach((rec) => {
      const li = document.createElement('li');
      if (rec._disabled) li.classList.add('disabled');
      if (state.selected && state.selected.id === rec.id) li.classList.add('on');
      li.innerHTML = `<div class="id">${escapeHtml(rec.id)}</div>
        <div class="lbl">${escapeHtml(rec.label || rec.id)}</div>
        <div class="meta">${escapeHtml(rec.station || '')} · v${rec._version || 0}${rec._disabled ? ' · OFF' : ''}</div>`;
      li.addEventListener('click', () => select(rec.id));
      ul.appendChild(li);
    });
  }

  async function select(id) {
    const r = await post('craftadminGet', { recipeId: id });
    if (!r || !r.ok) { status('Recette introuvable', 'err'); return; }
    state.selected = r.recipe;
    writeDraft(r.recipe);
    loadList();
  }

  function confirmModal(title, body, onYes) {
    $('#ca-modal-title').textContent = title;
    $('#ca-modal-body').textContent = body;
    $('#ca-modal').classList.remove('hidden');
    const yes = $('#ca-modal-yes');
    const no = $('#ca-modal-no');
    const done = () => $('#ca-modal').classList.add('hidden');
    yes.onclick = async () => { done(); await onYes(); };
    no.onclick = done;
  }

  async function save(create) {
    const draft = readDraft();
    const v = await post('craftadminValidate', draft);
    if (!v || !v.ok) { status('Validation échouée — corrigez le schéma', 'err'); return; }
    confirmModal('Confirmer l’enregistrement', `Version += 1 pour « ${draft.id} ». Continuer ?`, async () => {
      const endpoint = create ? 'craftadminCreate' : 'craftadminSave';
      const r = await post(endpoint, Object.assign({}, draft, { confirm: true }));
      if (!r || !r.ok) { status(r && r.reason || 'Échec save', 'err'); return; }
      status(`Enregistré · version ${r.version}`, 'ok');
      await loadList();
    });
  }

  function wire() {
    $('#ca-close').addEventListener('click', () => post('craftadminClose', {}));
    $('#ca-search').addEventListener('input', () => loadList());
    $('#ca-f-station').addEventListener('change', () => loadList());
    $('#ca-f-category').addEventListener('change', () => loadList());
    $('#ca-f-rarity').addEventListener('change', () => loadList());
    $('#ca-new').addEventListener('click', () => { state.selected = null; writeDraft(emptyDraft()); });
    $('#ca-add-ing').addEventListener('click', () => { $('#ca-ings').appendChild(ingRow({ item: '', count: 1 })); });
    $('#ca-add-tool').addEventListener('click', () => { $('#ca-tools').appendChild(toolRow({ item: '' })); });
    $('#ca-save').addEventListener('click', () => save(false));
    $('#ca-create').addEventListener('click', () => save(true));
    $('#ca-dup').addEventListener('click', async () => {
      if (!state.selected) return;
      const newId = prompt('Nouvel id ?', state.selected.id + '_copy');
      if (!newId) return;
      const r = await post('craftadminDuplicate', { recipeId: state.selected.id, newId });
      if (r && r.ok) { status('Dupliqué', 'ok'); await loadList(); select(newId); }
      else status(r && r.reason || 'Échec', 'err');
    });
    $('#ca-disable').addEventListener('click', async () => {
      if (!state.selected) return;
      const r = await post('craftadminDisable', { recipeId: state.selected.id, disabled: true });
      if (r && r.ok) { status('Désactivé (soft)', 'ok'); loadList(); }
    });
    $('#ca-enable').addEventListener('click', async () => {
      if (!state.selected) return;
      const r = await post('craftadminDisable', { recipeId: state.selected.id, disabled: false });
      if (r && r.ok) { status('Réactivé', 'ok'); loadList(); }
    });
    $('#ca-delete').addEventListener('click', () => {
      if (!state.selected) return;
      confirmModal('Soft-delete', `Désactiver ${state.selected.id} ?`, async () => {
        const r = await post('craftadminDelete', { recipeId: state.selected.id });
        if (r && r.ok) { status('Soft-delete OK', 'ok'); state.selected = null; loadList(); }
      });
    });
    $('#ca-test').addEventListener('click', async () => {
      const d = readDraft();
      const r = await post('craftadminTest', { recipeId: d.id, benchKey: $('#ca-test-bench').value, batch: 1, real: false });
      if (r && r.ok) status(`Dry-run OK · batch ${r.batch || 1} (aucun item retiré)`, 'ok');
      else status(`Dry-run: ${r && r.reason || 'échec'}`, 'err');
    });
    $('#ca-test-real').addEventListener('click', () => {
      confirmModal('TEST RÉEL', 'Consomme les items. Continuer ?', async () => {
        const d = readDraft();
        const r = await post('craftadminTest', { recipeId: d.id, benchKey: $('#ca-test-bench').value, batch: 1, real: true });
        status((r && r.ok) ? 'Test réel lancé' : ((r && r.reason) || 'échec'), r && r.ok ? 'ok' : 'err');
      });
    });
    $('#ca-restore').addEventListener('click', async () => {
      if (!state.selected) return;
      const vs = await post('craftadminVersions', { recipeId: state.selected.id });
      const list = (vs && vs.versions) || [];
      if (!list.length) { status('Pas d’historique', 'err'); return; }
      const ver = Number(prompt('Version à restaurer ?\n' + list.map((v) => `v${v.version} ${v.updated_at || ''}`).join('\n'), list[0].version));
      if (!ver) return;
      confirmModal('RESTORE', `Restaurer v${ver} (nouveau version++) ?`, async () => {
        const r = await post('craftadminRestore', { recipeId: state.selected.id, version: ver });
        status((r && r.ok) ? `Restauré → v${r.version}` : (r && r.reason || 'échec'), r && r.ok ? 'ok' : 'err');
        if (r && r.ok) select(state.selected.id);
      });
    });
    $('#ca-oxq').addEventListener('input', searchOx);
    $$('#ca-form input, #ca-form select, #ca-form textarea').forEach((el) => {
      el.addEventListener('input', schedulePreview);
      el.addEventListener('change', schedulePreview);
    });
  }

  function applyMeta(meta) {
    state.meta = meta || state.meta;
    fillSelect($('#ca-station'), state.meta.stations, true);
    fillSelect($('#ca-f-station'), state.meta.stations, true);
    fillSelect($('#ca-category'), state.meta.categories, true);
    fillSelect($('#ca-f-category'), state.meta.categories, true);
    fillSelect($('#ca-rarity'), state.meta.rarities, true);
    fillSelect($('#ca-f-rarity'), state.meta.rarities, true);
    fillSelect($('#ca-sig'), state.meta.signatureModes, false);
  }

  window.addEventListener('message', (ev) => {
    const msg = ev.data || {};
    if (msg.action === 'craftadminOpen') {
      root.classList.remove('hidden');
      applyMeta(msg.meta);
      loadList();
      writeDraft(emptyDraft());
    } else if (msg.action === 'craftadminClose') {
      root.classList.add('hidden');
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !root.classList.contains('hidden')) {
      post('craftadminClose', {});
    }
  });

  wire();
})();
