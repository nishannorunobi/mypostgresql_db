// Thin health-panel shim — header badges only (server details handled by ServerPanel)
class HealthPanel {
  updateBadges(h) {
    const pgDot  = $id('pg-dot');
    const webDot = $id('pgweb-dot');
    if (pgDot)  pgDot.className  = 'dot ' + (h.postgres_running ? 'up' : 'down');
    if (webDot) webDot.className = 'dot ' + (h.pgweb_running    ? 'up' : 'down');
  }
}
window.HealthPanel = HealthPanel;
