// DBApp — nav routing, panel wiring, auto-refresh
class DBApp {
  constructor() {
    this.log     = new LogPanel();
    this.server  = new ServerPanel(this.log);
    this.schemas = new SchemasPanel(this.log);
    this.browser = new BrowserPanel(this.log);
    this.backup  = new BackupPanel(this.log);
    this.cloud   = new CloudPanel(this.log);
    this.health  = new HealthPanel();
    this.chat    = new ChatPanel();
    window._app  = this;
  }

  // ── Nav ──────────────────────────────────────────────────────────────────

  switchSection(name) {
    document.querySelectorAll('.section-panel').forEach(el => {
      el.style.display = el.dataset.section === name ? '' : 'none';
    });
    document.querySelectorAll('.nav-item').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.section === name);
    });
    // Lazy-load on tab open
    if (name === 'schemas') this.schemas.load();
    if (name === 'backup')  this.backup.load();
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  async refresh() {
    try {
      const h = await Api.get('/health');
      this.health.updateBadges(h);
      this.server.render(h);
      this.browser.renderStatus(h);
      this.cloud.renderStatus(h);
    } catch (_) {}
  }

  start() {
    // Set first nav active
    this.switchSection('server');
    this.refresh();
    setInterval(() => this.refresh(), 15000);
    this.log._applyState(); // apply collapsed state
  }
}

document.addEventListener('DOMContentLoaded', () => new DBApp().start());
