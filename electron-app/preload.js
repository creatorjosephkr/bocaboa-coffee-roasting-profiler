const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  loadSessions: () => ipcRenderer.invoke('load-sessions'),
  saveSession: (session) => ipcRenderer.invoke('save-session', session),
  deleteSession: (filename) => ipcRenderer.invoke('delete-session', filename),
  exportSession: (session) => ipcRenderer.invoke('export-session-panel', session),
  importSession: () => ipcRenderer.invoke('import-session-panel'),
  revealInFinder: () => ipcRenderer.invoke('reveal-in-finder'),
  exitApp: () => ipcRenderer.send('exit-app'),
  scanDevices: () => ipcRenderer.send('scan-devices'),
  loadRegisteredDevices: () => ipcRenderer.invoke('load-registered-devices'),
  setTargetDevice: (id, name) => ipcRenderer.send('set-target-device', { id, name }),
  saveChartImage: (opts) => ipcRenderer.invoke('save-chart-image', opts),
  saveChartPdf: (opts) => ipcRenderer.invoke('save-chart-pdf', opts),
  printChartImage: (opts) => ipcRenderer.invoke('print-chart-image', opts),
  saveReportPdf: (defaultName) => ipcRenderer.invoke('save-report-pdf', defaultName),
  // GitHub 연동
  githubSaveConfig: (config) => ipcRenderer.invoke('github-save-config', config),
  githubLoadConfig: () => ipcRenderer.invoke('github-load-config'),
  githubUploadSession: (opts) => ipcRenderer.invoke('github-upload-session', opts),
  githubListSessions: (config) => ipcRenderer.invoke('github-list-sessions', config),
  githubDownloadSession: (opts) => ipcRenderer.invoke('github-download-session', opts),
  openExternalLink: (url) => ipcRenderer.invoke('open-external-link', url)
});
