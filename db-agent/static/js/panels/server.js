// ServerPanel — PostgreSQL health display + start/stop controls
class ServerPanel {
  constructor(log) { this._log = log; }

  render(h) {
    this._updateBadges(h);
    this._updateButtons(h);
    this._updateFields(h);
    this._updateIssues(h.issues || []);
  }

  _updateBadges(h) {
    const pgBadge  = $id('pg-badge');
    const pgDot    = $id('pg-dot');
    const webBadge = $id('pgweb-badge');
    const webDot   = $id('pgweb-dot');

    if (pgDot)    pgDot.className  = 'dot ' + (h.postgres_running ? 'up' : 'down');
    if (webDot)   webDot.className = 'dot ' + (h.pgweb_running ? 'up' : 'down');

    const pgCard = $id('server-status-badge');
    if (pgCard) {
      pgCard.className  = 'server-status-badge ' + (h.postgres_running ? 'up' : 'down');
      pgCard.textContent = h.postgres_running ? '● RUNNING' : '● STOPPED';
    }
  }

  _updateButtons(h) {
    const pg    = h.postgres_running;
    const web   = h.pgweb_running;
    this._btn('pg-start-btn',    pg);
    this._btn('pg-stop-btn',     !pg);
    this._btn('pgweb-start-btn', web);
    this._btn('pgweb-stop-btn',  !web);
  }

  _btn(id, disabled) {
    const b = $id(id);
    if (b && !b._origHTML) b.disabled = disabled;
  }

  _updateFields(h) {
    const skip = new Set(['status','issues','time','agent']);
    const el   = $id('health-fields');
    if (!el) return;
    const rows = Object.entries(h).filter(([k]) => !skip.has(k)).map(([k, v]) => {
      const s   = typeof v === 'boolean' ? (v ? 'Yes' : 'No') : String(v);
      const cls = typeof v === 'boolean' ? (v ? 'green' : 'red') : 'plain';
      return `<div class="field-row"><span class="field-key">${esc(k.replace(/_/g,' '))}</span>
        <span class="field-val ${cls}">${esc(s)}</span></div>`;
    });
    el.innerHTML = rows.join('') || '<div class="field-row" style="color:var(--text3)">No data</div>';
  }

  _updateIssues(issues) {
    const el = $id('issues-area');
    if (!el) return;
    if (issues.length) {
      el.innerHTML = `<div class="issues">${
        issues.map(i => `<div class="issue-item">⚠ ${esc(i)}</div>`).join('')
      }</div>`;
    } else {
      el.innerHTML = '<div class="no-issues"><span class="dot up"></span> No active issues</div>';
    }
  }

  async startPg(btn) {
    const ok = await this._log.run('/api/stream/db/start', 'Start PostgreSQL', btn);
    if (ok) await window._app.refresh();
  }

  async stopPg(btn) {
    const ok = await this._log.run('/api/stream/db/stop', 'Stop PostgreSQL', btn);
    await window._app.refresh();
  }
}

window.ServerPanel = ServerPanel;
