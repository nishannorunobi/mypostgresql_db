// BackupPanel — per-database backup and restore controls
class BackupPanel {
  constructor(log) {
    this._log = log;
    this._files = { ums: [], mydocs: [], wholedb: [] };
  }

  async load() {
    await Promise.all(
      ['ums', 'mydocs', 'wholedb'].map(db => this._loadFiles(db))
    );
  }

  async _loadFiles(db) {
    try {
      const r = await Api.get(`/api/backup/files/${db}`);
      this._files[db] = r.files || [];
      this._renderFiles(db);
    } catch (_) {}
  }

  _renderFiles(db) {
    const el = $id(`backup-files-${db}`);
    if (!el) return;
    const files = this._files[db];
    if (!files.length) {
      el.innerHTML = '<span class="backup-no-files">No backups yet</span>';
      return;
    }
    el.innerHTML = files.map(f => `
      <div class="backup-file-row">
        <span class="backup-file-name">${esc(f)}</span>
        <button class="btn btn-secondary btn-sm" onclick="window._app.backup._restore('${db}','${esc(f)}',this)">
          ⬇ Restore
        </button>
      </div>`).join('');
  }

  async backup(db, btn) {
    const labels = { ums: 'UMS', mydocs: 'Docs', wholedb: 'Whole DB' };
    const ok = await this._log.run(`/api/stream/backup/${db}`, `Backup ${labels[db]}`, btn);
    if (ok) await this._loadFiles(db);
  }

  async _restore(db, file, btn) {
    const labels = { ums: 'UMS', mydocs: 'Docs', wholedb: 'Whole DB' };
    const ok = await this._log.run(
      `/api/stream/restore/${db}?file=${encodeURIComponent(file)}`,
      `Restore ${labels[db]} — ${file}`, btn
    );
    return ok;
  }
}

window.BackupPanel = BackupPanel;
