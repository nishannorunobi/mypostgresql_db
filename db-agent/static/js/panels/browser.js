// BrowserPanel — pgweb DB browser controls
class BrowserPanel {
  constructor(log) { this._log = log; }

  renderStatus(h) {
    const up  = h.pgweb_running;
    const el  = $id('pgweb-status-badge');
    if (el) {
      el.className  = 'server-status-badge ' + (up ? 'up' : 'down');
      el.textContent = up ? '● RUNNING' : '● STOPPED';
    }
    const startBtn = $id('pgweb-start-btn');
    const stopBtn  = $id('pgweb-stop-btn');
    if (startBtn && !startBtn._origHTML) startBtn.disabled = up;
    if (stopBtn  && !stopBtn._origHTML)  stopBtn.disabled  = !up;
  }

  async start(btn) {
    const ok = await this._log.run('/api/stream/dbui/start', 'Start pgweb', btn);
    if (ok) await window._app.refresh();
  }

  async stop(btn) {
    await this._log.run('/api/stream/dbui/stop', 'Stop pgweb', btn);
    await window._app.refresh();
  }
}

window.BrowserPanel = BrowserPanel;
