// CloudPanel — rclone web UI start/stop
class CloudPanel {
  constructor(log) { this._log = log; }

  renderStatus(h) {
    const up  = h.rclone_ui_running;
    const dot = $id('rclone-dot');
    const badge = $id('rclone-status-badge');
    if (dot)   dot.className   = 'dot ' + (up ? 'up' : 'down');
    if (badge) {
      badge.className  = 'server-status-badge ' + (up ? 'up' : 'down');
      badge.textContent = up ? '● RUNNING' : '● STOPPED';
    }
    const startBtn = $id('rclone-start-btn');
    const stopBtn  = $id('rclone-stop-btn');
    if (startBtn && !startBtn._origHTML) startBtn.disabled = up;
    if (stopBtn  && !stopBtn._origHTML)  stopBtn.disabled  = !up;
  }

  async start(btn) {
    const ok = await this._log.run('/api/stream/cloud/ui/start', 'Start rclone UI', btn);
    if (ok) await window._app.refresh();
  }

  async stop(btn) {
    await this._log.run('/api/stream/cloud/ui/stop', 'Stop rclone UI', btn);
    await window._app.refresh();
  }
}

window.CloudPanel = CloudPanel;
