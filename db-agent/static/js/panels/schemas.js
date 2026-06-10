// SchemasPanel — dynamic database schema cards loaded from /api/schemas
class SchemasPanel {
  constructor(log) { this._log = log; }

  async load() {
    const wrap = $id('schemas-wrap');
    if (!wrap) return;
    wrap.innerHTML = '<div style="color:var(--text3);font-size:13px">Loading schemas…</div>';
    try {
      const data = await Api.get('/api/schemas');
      this._render(wrap, data.schemas || []);
    } catch (e) {
      wrap.innerHTML = `<div style="color:var(--red);font-size:13px">Failed to load schemas: ${esc(String(e))}</div>`;
    }
  }

  _render(wrap, schemas) {
    if (!schemas.length) {
      wrap.innerHTML = '<div style="color:var(--text3);font-size:13px">No schemas configured.</div>';
      return;
    }
    wrap.innerHTML = '';
    schemas.forEach(s => wrap.appendChild(this._card(s)));
  }

  _card(s) {
    const card = document.createElement('div');
    card.className = 'schema-card fade-in';

    const statusCls  = s.initialized === true ? 'yes' : s.initialized === false ? 'no' : 'unknown';
    const statusText = s.initialized === true
      ? '● Initialized'
      : s.initialized === false
        ? '○ Not initialized'
        : '? Unknown (PostgreSQL offline)';

    const initDis  = !s.script_exists ? 'disabled title="Script not found"' : '';
    const cleanDis = s.initialized !== true ? 'disabled title="Database not initialized"' : '';

    card.innerHTML = `
      <div class="schema-card-inner">
        <div class="schema-card-accent" style="background:${esc(s.color)}"></div>
        <div class="schema-card-body">
          <div class="schema-card-head">
            <span class="schema-icon">${s.icon}</span>
            <span class="schema-name">${esc(s.label)}</span>
            <span class="schema-label">${esc(s.name)}</span>
          </div>
          <div class="schema-desc">${esc(s.description)}</div>
          <div class="schema-status ${statusCls}">${statusText}</div>
          <div class="schema-actions">
            <button class="btn btn-init btn-sm" ${initDis}
              onclick="window._app.schemas.initSchema('${esc(s.name)}','${esc(s.label)}',this)">
              ⚙ Initialize
            </button>
            <button class="btn btn-danger btn-sm" ${cleanDis}
              onclick="window._app.schemas.cleanSchema('${esc(s.name)}','${esc(s.label)}',this)">
              🗑 Clean
            </button>
            <button class="btn btn-ghost btn-sm"
              onclick="window._app.schemas.load()">
              ↺ Refresh
            </button>
          </div>
        </div>
      </div>`;
    return card;
  }

  async initSchema(name, label, btn) {
    const ok = await this._log.run(`/api/stream/initdb/${name}`, `Initialize ${label}`, btn);
    if (ok) await this.load();
  }

  async cleanSchema(name, label, btn) {
    const confirmed = confirm(
      `⚠ Clean "${label}"?\n\nThis will DROP the database and its user.\nALL DATA WILL BE LOST and nothing will be recreated.\n\nThis cannot be undone.`
    );
    if (!confirmed) return;
    const ok = await this._log.run(`/api/stream/cleandb/${name}`, `Clean ${label}`, btn);
    if (ok) await this.load();
  }

  async cleanAll(btn) {
    const confirmed = confirm(
      `⚠ Clean ALL databases?\n\nThis will DROP all databases and all users.\nALL DATA WILL BE LOST and nothing will be recreated.\n\nThis cannot be undone.`
    );
    if (!confirmed) return;
    const ok = await this._log.run('/api/stream/cleandb/all', 'Clean All Databases', btn);
    if (ok) await this.load();
  }
}

window.SchemasPanel = SchemasPanel;
