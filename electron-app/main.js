const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');

// Web Bluetooth requestLEScan() 실험적 API 활성화 (BLE Scanner 창에서 사용)
app.commandLine.appendSwitch('enable-experimental-web-platform-features');

let mainWindow;
let scannerWindow = null;
let targetDeviceId = null;
let targetDeviceName = null;

// BocaRoast 보관함 폴더 경로 획득 (~/BocaRoast/)
function getStoragePath() {
  const homeDir = app.getPath('home');
  const bocaDir = path.join(homeDir, 'BocaRoast');
  if (!fs.existsSync(bocaDir)) {
    fs.mkdirSync(bocaDir, { recursive: true });
  }
  return bocaDir;
}

// ── 중복 실행 방지 및 기존 인스턴스 킬 기능 구현 ──
const pidFilePath = path.join(getStoragePath(), 'app.pid');

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1560,
    height: 970,
    minWidth: 1500,
    minHeight: 970,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    },
    title: "보카보카(BOCABOCA) 250/500BT 커피 로스터 프로파일러",
    titleBarStyle: 'hidden',
    icon: path.join(__dirname, 'AppIcon.png')
  });

  mainWindow.loadFile('index.html');
  // mainWindow.webContents.openDevTools();

  // Electron Web Bluetooth 기기 자동 선택기 연동
  mainWindow.webContents.on('select-bluetooth-device', (event, deviceList, callback) => {
    event.preventDefault();
    
    // 이미 이 요청에 대해 콜백이 처리되었으면 추가 실행 차단
    if (callback.called) return;
    
    console.log("Bluetooth devices discovered:", deviceList.map(d => ({ name: d.deviceName, id: d.deviceId })));
    
    if (targetDeviceId || targetDeviceName) {
      // 1. UUID 매칭 시도 (하이픈 제거 및 소문자 정규화 비교)
      let found = null;
      if (targetDeviceId) {
        found = deviceList.find(d => {
          const cleanId = d.deviceId.replace(/-/g, '').toLowerCase();
          return cleanId === targetDeviceId;
        });
      }
      
      // 2. ID 매칭 실패 시 블루투스 기기명 매칭 시도 (폴백)
      if (!found && targetDeviceName) {
        found = deviceList.find(d => d.deviceName === targetDeviceName);
      }
      
      if (found) {
        console.log("Connecting to selected target device:", found.deviceName, "(", found.deviceId, ")");
        callback.called = true;
        callback(found.deviceId);
        targetDeviceId = null;
        targetDeviceName = null;
        return;
      }
      console.log(`Target device (ID: ${targetDeviceId}, Name: ${targetDeviceName}) not found yet in list... waiting...`);
    } else {
      const target = deviceList.find(d => 
        d.deviceName.toLowerCase().includes('boca') || 
        d.deviceName.toLowerCase().includes('bt')
      );
      
      if (target) {
        callback.called = true;
        callback(target.deviceId);
      } else if (deviceList.length > 0) {
        callback.called = true;
        callback(deviceList[0].deviceId);
      }
    }
  });

  // 블루투스 기기 스캔 권한 자동 허용
  mainWindow.webContents.session.setPermissionCheckHandler((webContents, permission, requestingOrigin, details) => {
    if (permission === 'bluetooth') {
      return true;
    }
    return false;
  });

  mainWindow.webContents.session.setDevicePermissionHandler((details) => {
    if (details.deviceType === 'bluetooth') {
      return true;
    }
    return false;
  });
}

// MARK: - IPC 핸들러 등록

// 0. 완전 종료 시그널 수신
ipcMain.on('exit-app', () => {
  console.log("App exit requested via header button.");
  app.quit();
});

// 1. 모든 세션 파일 읽기
ipcMain.handle('load-sessions', async () => {
  try {
    const dir = getStoragePath();
    const files = fs.readdirSync(dir);
    const sessions = [];
    
    for (const file of files) {
      if (path.extname(file).toLowerCase() === '.json' && file !== 'registered_devices.json') {
        const filePath = path.join(dir, file);
        const data = fs.readFileSync(filePath, 'utf-8');
        try {
          const session = JSON.parse(data);
          // 단일 세션 객체 형식(id 필드가 존재하고 배열이 아님)인지 추가 검증
          if (session && typeof session === 'object' && !Array.isArray(session) && session.id) {
            session.filename = file;
            sessions.push(session);
          }
        } catch (e) {
          console.error(`Error parsing JSON from ${file}:`, e);
        }
      }
    }
    
    sessions.sort((a, b) => new Date(b.date) - new Date(a.date));
    return sessions;
  } catch (err) {
    console.error('Failed to load sessions:', err);
    return [];
  }
});

// 2. 단일 세션 파일 저장
ipcMain.handle('save-session', async (event, session) => {
  try {
    const dir = getStoragePath();
    const dateStr = session.date.replace(/[-T:.Z]/g, '').substring(0, 12);
    const safeBeanName = (session.beanName || 'unnamed').replace(/\s+/g, '_');
    const fileName = `${dateStr}_${safeBeanName}.json`;
    const filePath = path.join(dir, fileName);
    
    fs.writeFileSync(filePath, JSON.stringify(session, null, 2), 'utf-8');
    return { success: true, fileName };
  } catch (err) {
    console.error('Failed to save session:', err);
    return { success: false, error: err.message };
  }
});

// 3. 세션 파일 삭제
ipcMain.handle('delete-session', async (event, filename) => {
  try {
    const dir = getStoragePath();
    const filePath = path.join(dir, filename);
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
      return { success: true };
    }
    return { success: false, error: 'File not found' };
  } catch (err) {
    console.error('Failed to delete session:', err);
    return { success: false, error: err.message };
  }
});

// 4. 외부 프로파일 내보내기 (Export)
ipcMain.handle('export-session-panel', async (event, session) => {
  try {
    const dateStr = session.date.replace(/[-T:.Z]/g, '').substring(0, 12);
    const safeBeanName = (session.beanName || 'unnamed').replace(/\s+/g, '_');
    const defaultName = `${dateStr}_${safeBeanName}.json`;
    
    const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, {
      title: '로스팅 프로파일 내보내기',
      defaultPath: path.join(app.getPath('downloads'), defaultName),
      filters: [{ name: 'JSON 파일', extensions: ['json'] }]
    });
    
    if (!canceled && filePath) {
      fs.writeFileSync(filePath, JSON.stringify(session, null, 2), 'utf-8');
      return { success: true };
    }
    return { success: false, reason: 'canceled' };
  } catch (err) {
    console.error('Export panel error:', err);
    return { success: false, error: err.message };
  }
});

// 4.1 그래프 이미지 저장 (PNG/JPG)
ipcMain.handle('save-chart-image', async (event, { base64Data, format, defaultName }) => {
  try {
    const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, {
      title: '그래프 이미지 저장',
      defaultPath: path.join(app.getPath('downloads'), defaultName),
      filters: [
        { name: format.toUpperCase() + ' 이미지', extensions: [format.toLowerCase()] }
      ]
    });
    
    if (!canceled && filePath) {
      const data = base64Data.replace(/^data:image\/\w+;base64,/, "");
      const buf = Buffer.from(data, 'base64');
      fs.writeFileSync(filePath, buf);
      return { success: true };
    }
    return { success: false, reason: 'canceled' };
  } catch (err) {
    console.error('Save chart image error:', err);
    return { success: false, error: err.message };
  }
});

// 4.2 그래프 PDF 저장
ipcMain.handle('save-chart-pdf', async (event, { base64Data, defaultName }) => {
  try {
    const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, {
      title: 'PDF 파일로 저장',
      defaultPath: path.join(app.getPath('downloads'), defaultName),
      filters: [{ name: 'PDF 파일', extensions: ['pdf'] }]
    });
    
    if (canceled || !filePath) {
      return { success: false, reason: 'canceled' };
    }
    
    const win = new BrowserWindow({
      show: false,
      webPreferences: {
        nodeIntegration: false
      }
    });
    
    const htmlContent = `
      <html>
        <body style="margin: 0; display: flex; align-items: center; justify-content: center; height: 100vh;">
          <img src="${base64Data}" style="max-width: 100%; max-height: 100%; object-fit: contain;" />
        </body>
      </html>
    `;
    
    await win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(htmlContent)}`);
    
    const pdfBuffer = await win.webContents.printToPDF({
      margins: { top: 0, bottom: 0, left: 0, right: 0 },
      pageSize: 'A4',
      landscape: true
    });
    
    fs.writeFileSync(filePath, pdfBuffer);
    win.destroy();
    
    return { success: true };
  } catch (err) {
    console.error('Save PDF error:', err);
    return { success: false, error: err.message };
  }
});

// 4.2.5 상세 리포트 모달 전체 PDF 저장
ipcMain.handle('save-report-pdf', async (event, defaultName) => {
  try {
    const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, {
      title: '상세 리포트 PDF 저장',
      defaultPath: path.join(app.getPath('downloads'), defaultName || 'Roasting-Report.pdf'),
      filters: [{ name: 'PDF Document', extensions: ['pdf'] }]
    });
    
    if (canceled || !filePath) {
      return { success: false, reason: 'canceled' };
    }
    
    // printToPDF options: format A4, default portrait, print background
    const pdfBuffer = await event.sender.printToPDF({
      margins: { top: 0, bottom: 0, left: 0, right: 0 },
      printBackground: true,
      pageSize: 'A4',
      landscape: false
    });
    
    fs.writeFileSync(filePath, pdfBuffer);
    return { success: true };
  } catch (err) {
    console.error('Save report PDF error:', err);
    return { success: false, error: err.message };
  }
});

// 4.3 그래프 인쇄
ipcMain.handle('print-chart-image', async (event, { base64Data }) => {
  try {
    const win = new BrowserWindow({
      width: 900,
      height: 650,
      show: true,
      title: '인쇄 미리보기',
      webPreferences: {
        nodeIntegration: false
      }
    });
    
    win.setMenu(null);
    
    const htmlContent = `
      <html>
        <head>
          <title>인쇄 미리보기</title>
          <style>
            @media print {
              body { margin: 0; }
              img { max-width: 100%; max-height: 100%; object-fit: contain; }
            }
          </style>
        </head>
        <body style="margin: 0; display: flex; align-items: center; justify-content: center; height: 100vh; background-color: #f7fafc;">
          <img src="${base64Data}" style="max-width: 95%; max-height: 95%; object-fit: contain; box-shadow: 0 4px 12px rgba(0,0,0,0.1); border-radius: 4px; background: white;" />
          <script>
            window.onload = () => {
              setTimeout(() => {
                window.print();
                window.close();
              }, 300);
            }
          </script>
        </body>
      </html>
    `;
    
    await win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(htmlContent)}`);
    return { success: true };
  } catch (err) {
    console.error('Print error:', err);
    return { success: false, error: err.message };
  }
});

// 5. 외부 프로파일 가져오기 (Import)
ipcMain.handle('import-session-panel', async () => {
  try {
    const { canceled, filePaths } = await dialog.showOpenDialog(mainWindow, {
      title: '외부 로스팅 프로파일 가져오기',
      properties: ['openFile'],
      filters: [{ name: 'JSON 파일', extensions: ['json'] }]
    });
    
    if (!canceled && filePaths.length > 0) {
      const srcPath = filePaths[0];
      const rawData = fs.readFileSync(srcPath, 'utf-8');
      const session = JSON.parse(rawData);
      
      if (!session.id || !Array.isArray(session.events) || !Array.isArray(session.graphPoints)) {
        throw new Error('올바른 로스팅 프로파일 파일이 아닙니다.');
      }
      
      const dir = getStoragePath();
      const dateStr = (session.date || new Date().toISOString()).replace(/[-T:.Z]/g, '').substring(0, 12);
      const safeBeanName = (session.beanName || 'unnamed').replace(/\s+/g, '_');
      const destName = `${dateStr}_${safeBeanName}.json`;
      const destPath = path.join(dir, destName);
      
      fs.writeFileSync(destPath, JSON.stringify(session, null, 2), 'utf-8');
      return { success: true, session };
    }
    return { success: false, reason: 'canceled' };
  } catch (err) {
    console.error('Import panel error:', err);
    return { success: false, error: err.message };
  }
});

// 6. 폴더 열기 (Reveal in Finder/Explorer)
ipcMain.handle('reveal-in-finder', async () => {
  const dir = getStoragePath();
  const { shell } = require('electron');
  shell.openPath(dir);
  return true;
});

// ── GitHub 연동 ──────────────────────────────────────────────────────────────

// 6-G1. 설정 저장
ipcMain.handle('github-save-config', async (event, config) => {
  try {
    const filePath = path.join(getStoragePath(), 'github_config.json');
    fs.writeFileSync(filePath, JSON.stringify(config, null, 2), 'utf-8');
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// 6-G2. 설정 불러오기
ipcMain.handle('github-load-config', async () => {
  try {
    const filePath = path.join(getStoragePath(), 'github_config.json');
    if (!fs.existsSync(filePath)) {
      return {
        success: true,
        config: {
          publicPat: '',
          privatePat: '',
          repoType: 'public', // 'public' | 'private'
          userName: '',
          privateOwner: '',
          privateRepo: ''
        }
      };
    }
    const data = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    // 호환성 처리 (이전 config에 pat가 있는 경우 적절히 배분)
    if (data.pat && !data.publicPat && !data.privatePat) {
      if (data.repoType === 'private') {
        data.privatePat = data.pat;
        data.publicPat = '';
      } else {
        data.publicPat = data.pat;
        data.privatePat = '';
      }
    }
    return { success: true, config: data };
  } catch (err) {
    return {
      success: true,
      config: {
        publicPat: '',
        privatePat: '',
        repoType: 'public',
        userName: '',
        privateOwner: '',
        privateRepo: ''
      }
    };
  }
});

// 6-G3. GitHub에 세션 업로드 (PUT)
ipcMain.handle('github-upload-session', async (event, { session, config }) => {
  try {
    const dateStr = session.date.replace(/[-T:.Z]/g, '').substring(0, 12);
    const safeName = (session.beanName || 'unnamed').replace(/\s+/g, '_');
    const fileName = `${dateStr}_${safeName}.json`;
    const content = Buffer.from(JSON.stringify(session, null, 2), 'utf-8').toString('base64');

    let owner = 'creatorjosephkr';
    let repo = 'bocaboa-profile';
    let pathPrefix = 'logs';
    const pat = config.repoType === 'public' ? config.publicPat : config.privatePat;

    if (config.repoType === 'public') {
      pathPrefix = `logs/${config.userName || 'unknown'}`;
    } else {
      owner = config.privateOwner;
      repo = config.privateRepo;
      if (config.userName) {
        pathPrefix = `logs/${config.userName}`;
      } else {
        pathPrefix = `logs`;
      }
    }

    const apiUrl = `https://api.github.com/repos/${owner}/${repo}/contents/${pathPrefix}/${fileName}`;

    // SHA 조회 (파일 업데이트 시 필요)
    let sha = undefined;
    const checkRes = await fetch(apiUrl, {
      headers: {
        Authorization: `Bearer ${pat}`,
        Accept: 'application/vnd.github+json',
        'User-Agent': 'bocaboa-profiler'
      }
    });
    if (checkRes.ok) {
      const existing = await checkRes.json();
      sha = existing.sha;
    }

    const body = { message: `Upload log: ${fileName}`, content };
    if (sha) body.sha = sha;

    const res = await fetch(apiUrl, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${pat}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'User-Agent': 'bocaboa-profiler'
      },
      body: JSON.stringify(body)
    });

    if (res.ok) {
      return { success: true, fileName };
    } else {
      const err = await res.json();
      return { success: false, error: err.message || res.statusText };
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// 6-G4. GitHub에서 세션 목록 불러오기
ipcMain.handle('github-list-sessions', async (event, config) => {
  try {
    let owner = 'creatorjosephkr';
    let repo = 'bocaboa-profile';
    const pat = config.repoType === 'public' ? config.publicPat : config.privatePat;

    if (config.repoType === 'private') {
      owner = config.privateOwner;
      repo = config.privateRepo;
    }

    // 1. Repository 정보를 조회해서 default_branch 획득
    const repoInfoUrl = `https://api.github.com/repos/${owner}/${repo}`;
    const headers = {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'bocaboa-profiler'
    };
    if (pat) headers.Authorization = `Bearer ${pat}`;

    const repoRes = await fetch(repoInfoUrl, { headers });
    if (!repoRes.ok) {
      const err = await repoRes.json();
      return { success: false, error: `저장소 접근 실패: ${err.message || repoRes.statusText}` };
    }
    const repoInfo = await repoRes.json();
    const defaultBranch = repoInfo.default_branch || 'main';

    // 2. recursive tree 조회 API 호출하여 logs/ 내의 모든 json 조회
    const treeUrl = `https://api.github.com/repos/${owner}/${repo}/git/trees/${defaultBranch}?recursive=1`;
    const treeRes = await fetch(treeUrl, { headers });
    if (!treeRes.ok) {
      const err = await treeRes.json();
      return { success: false, error: `파일 트리 조회 실패: ${err.message || treeRes.statusText}` };
    }
    const treeData = await treeRes.json();
    if (!treeData || !treeData.tree) {
      return { success: true, files: [] };
    }

    const files = treeData.tree
      .filter(item => item.type === 'blob' && item.path.startsWith('logs/') && item.path.endsWith('.json'))
      .map(item => {
        const parts = item.path.split('/');
        let fileUserName = '';
        let fileName = parts[parts.length - 1];

        if (parts.length > 2) {
          fileUserName = parts[1];
        }

        const downloadUrl = `https://raw.githubusercontent.com/${owner}/${repo}/${defaultBranch}/${item.path}`;

        return {
          name: fileName,
          path: item.path,
          userName: fileUserName,
          downloadUrl: downloadUrl,
          sha: item.sha,
          size: item.size
        };
      });

    return { success: true, files };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// 6-G5. GitHub에서 세션 파일 다운로드 및 로컬 저장
ipcMain.handle('github-download-session', async (event, { downloadUrl, fileName, pat }) => {
  try {
    const headers = { 'User-Agent': 'bocaboa-profiler' };
    if (pat) headers.Authorization = `Bearer ${pat}`;
    const res = await fetch(downloadUrl, { headers });
    if (!res.ok) return { success: false, error: res.statusText };
    const text = await res.text();
    const session = JSON.parse(text);
    const localPath = path.join(getStoragePath(), fileName);
    fs.writeFileSync(localPath, JSON.stringify(session, null, 2), 'utf-8');
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// 6-G6. 외부 브라우저 링크 열기
ipcMain.handle('open-external-link', async (event, url) => {
  try {
    const { shell } = require('electron');
    await shell.openExternal(url);
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
});

// 7. 등록된 블루투스 장치 목록 불러오기
ipcMain.handle('load-registered-devices', async () => {
  try {
    const filePath = path.join(getStoragePath(), 'registered_devices.json');
    if (fs.existsSync(filePath)) {
      const data = fs.readFileSync(filePath, 'utf-8');
      return JSON.parse(data);
    }
    return [];
  } catch (err) {
    console.error('Failed to load registered devices:', err);
    return [];
  }
});

// 8. 블루투스 장치 등록하기
ipcMain.handle('register-device', async (event, { id, name, nickname }) => {
  try {
    const filePath = path.join(getStoragePath(), 'registered_devices.json');
    let list = [];
    if (fs.existsSync(filePath)) {
      list = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    }
    list = list.filter(d => d.id !== id);
    list.push({ id, name, nickname, registeredAt: new Date().toISOString() });
    fs.writeFileSync(filePath, JSON.stringify(list, null, 2), 'utf-8');
    return { success: true };
  } catch (err) {
    console.error('Failed to register device:', err);
    return { success: false, error: err.message };
  }
});

// 9. 블루투스 장치 등록 해제하기
ipcMain.handle('deregister-device', async (event, id) => {
  try {
    const filePath = path.join(getStoragePath(), 'registered_devices.json');
    if (fs.existsSync(filePath)) {
      let list = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
      list = list.filter(d => d.id !== id);
      fs.writeFileSync(filePath, JSON.stringify(list, null, 2), 'utf-8');
    }
    return { success: true };
  } catch (err) {
    console.error('Failed to deregister device:', err);
    return { success: false, error: err.message };
  }
});

// 10. 대상 장치 ID 및 이름 저장하기 (연결 시 자동 선택용)
ipcMain.on('set-target-device', (event, { id, name }) => {
  targetDeviceId = id ? id.replace(/-/g, '').toLowerCase() : null;
  targetDeviceName = name;
  console.log('Target device set to:', { id: targetDeviceId, name: targetDeviceName });
  
  // 보조 조치: 메인 창에서 연결을 개시하므로 noble의 스캔 및 기존 모든 연결을 강제 종료하여 무선 채널 점유 해제
  try {
    stopNobleScan();
    for (const [pId, peripheral] of discoveredPeripherals.entries()) {
      if (peripheral.state === 'connected') {
        console.log(`Disconnecting noble peripheral ${peripheral.advertisement.localName || pId} to free connection slot for Web Bluetooth...`);
        peripheral.disconnect();
      }
    }
  } catch (err) {
    console.error('Failed to clean up noble state:', err);
  }
});


// 두 번째 인스턴스가 켜질 때의 중복 윈도우 포커싱 보조
app.on('second-instance', (event, commandLine, workingDirectory) => {
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  }
});

// ── noble 네이티브 BLE 스캐너 및 연결 관리 ──────────────────────────────
let noble = null;
let nobleScanning = false;
const discoveredPeripherals = new Map();

function getNoble() {
  if (!noble) {
    noble = require('@abandonware/noble');
  }
  return noble;
}

// Known GATT UUIDs
const SERVICE_NAMES = {
  '180a': 'Device Information',
  '180d': 'Heart Rate',
  'ffe0': 'Serial (Custom)',
  '1800': 'Generic Access',
  '1801': 'Generic Attribute',
};
const CHAR_NAMES = {
  '2a00': 'Device Name',
  '2a24': 'Model Number String',
  '2a25': 'Serial Number String',
  '2a29': 'Manufacturer Name',
  '2a23': 'System ID',
  'ffe1': 'Data (Custom)',
};

function getServiceName(uuid) {
  const clean = uuid.replace(/-/g, '').toLowerCase();
  const short = clean.length === 32 ? clean.substring(4, 8) : clean;
  return SERVICE_NAMES[clean] || SERVICE_NAMES[short] || 'Custom Service';
}

function getCharName(uuid) {
  const clean = uuid.replace(/-/g, '').toLowerCase();
  const short = clean.length === 32 ? clean.substring(4, 8) : clean;
  return CHAR_NAMES[clean] || CHAR_NAMES[short] || 'Custom Characteristic';
}

// BLE Scanner 새 창 열기 IPC 채널
ipcMain.on('scan-devices', () => {
  if (scannerWindow && !scannerWindow.isDestroyed()) {
    scannerWindow.focus();
    return;
  }
  scannerWindow = new BrowserWindow({
    width: 1100, height: 780, minWidth: 800, minHeight: 600,
    title: 'BLE Scanner', titleBarStyle: 'hiddenInset',
    backgroundColor: '#23232c',
    webPreferences: { contextIsolation: false, nodeIntegration: true }
  });
  scannerWindow.loadFile(path.join(__dirname, 'ble-scanner.html'));
  scannerWindow.on('closed', () => {
    stopNobleScan();
    // 창이 닫힐 때 기전 연결된 장치들도 해제
    for (const peripheral of discoveredPeripherals.values()) {
      if (peripheral.state === 'connected') {
        peripheral.disconnect();
      }
    }
    scannerWindow = null;
  });
});

// noble 스캔 시작 IPC
ipcMain.on('ble-start-scan', () => {
  const n = getNoble();

  const startScan = () => {
    if (nobleScanning) return;
    nobleScanning = true;
    n.startScanning([], true, (err) => {
      if (err) {
        console.error('Noble scan error:', err);
        nobleScanning = false;
        if (scannerWindow && !scannerWindow.isDestroyed()) {
          scannerWindow.webContents.send('ble-scan-error', err.message);
        }
      }
    });
  };

  if (n.state === 'poweredOn') {
    startScan();
  } else {
    n.once('stateChange', (state) => {
      if (state === 'poweredOn') startScan();
      else {
        if (scannerWindow && !scannerWindow.isDestroyed()) {
          scannerWindow.webContents.send('ble-scan-error', `Bluetooth 상태: ${state}`);
        }
      }
    });
  }

  // 기기 발견 시 렌더러로 전송 및 맵에 누적 보관
  n.removeAllListeners('discover');
  n.on('discover', (peripheral) => {
    discoveredPeripherals.set(peripheral.id, peripheral);
    if (!scannerWindow || scannerWindow.isDestroyed()) return;
    const adv = peripheral.advertisement || {};
    const device = {
      id:        peripheral.id,
      name:      adv.localName || peripheral.id.substring(0, 8).toUpperCase() || '알 수 없는 기기',
      rssi:      peripheral.rssi,
      uuids:     (adv.serviceUuids || []).map(u => u.toUpperCase()),
      connectable: peripheral.connectable,
      txPower:   adv.txPowerLevel,
      manufacturerData: adv.manufacturerData ? adv.manufacturerData.toString('hex').toUpperCase() : null,
    };
    scannerWindow.webContents.send('ble-device-discovered', device);
  });
});

// noble 스캔 중지 IPC
ipcMain.on('ble-stop-scan', () => stopNobleScan());

function stopNobleScan() {
  if (noble && nobleScanning) {
    noble.stopScanning();
    nobleScanning = false;
    noble.removeAllListeners('discover');
  }
}

// noble 기기 연결 IPC
ipcMain.on('ble-connect-device', (event, deviceId) => {
  const peripheral = discoveredPeripherals.get(deviceId);
  if (!peripheral) {
    if (scannerWindow && !scannerWindow.isDestroyed()) {
      scannerWindow.webContents.send('ble-connection-failed', { id: deviceId, message: '기기를 발견 맵에서 찾을 수 없습니다. 다시 스캔해 주세요.' });
    }
    return;
  }

  peripheral.connect((err) => {
    if (err) {
      console.error('BLE connection error:', err);
      if (scannerWindow && !scannerWindow.isDestroyed()) {
        scannerWindow.webContents.send('ble-connection-failed', { id: deviceId, message: err.message });
      }
      return;
    }

    if (scannerWindow && !scannerWindow.isDestroyed()) {
      scannerWindow.webContents.send('ble-connected', { id: deviceId });
    }

    // 서비스 및 특성 탐색 진행
    peripheral.discoverServices([], (err2, services) => {
      if (err2) {
        console.error('BLE service discovery error:', err2);
        return;
      }

      let completed = 0;
      const servicesInfo = [];

      if (services.length === 0) {
        if (scannerWindow && !scannerWindow.isDestroyed()) {
          scannerWindow.webContents.send('ble-services-discovered', { id: deviceId, services: [] });
        }
        return;
      }

      services.forEach(service => {
        service.discoverCharacteristics([], (err3, characteristics) => {
          completed++;
          const charsInfo = [];
          if (!err3 && characteristics) {
            characteristics.forEach(ch => {
              const props = [];
              if (ch.properties.includes('read')) props.push('READ');
              if (ch.properties.includes('write')) props.push('WRITE');
              if (ch.properties.includes('writeWithoutResponse')) props.push('WRITE_NR');
              if (ch.properties.includes('notify')) props.push('NOTIFY');
              if (ch.properties.includes('indicate')) props.push('INDICATE');

              // 기존 수신 리스너들 정리 후 등록
              ch.removeAllListeners('data');
              ch.on('data', (data, isNotification) => {
                if (scannerWindow && !scannerWindow.isDestroyed()) {
                  scannerWindow.webContents.send('ble-char-data', {
                    deviceId: deviceId,
                    serviceUuid: service.uuid,
                    charUuid: ch.uuid,
                    value: data.toString('hex').toUpperCase(),
                    isNotification: isNotification
                  });
                }
              });

              // 알림 특성 자동 구독 설정
              if (ch.properties.includes('notify') || ch.properties.includes('indicate')) {
                ch.subscribe((errSub) => {
                  if (errSub) console.error('BLE characteristic notify subscribe error:', errSub);
                });
              }

              // 읽기 특성 초깃값 조회
              if (ch.properties.includes('read')) {
                ch.read((errRead, data) => {
                  if (!errRead && data) {
                    if (scannerWindow && !scannerWindow.isDestroyed()) {
                      scannerWindow.webContents.send('ble-char-data', {
                        deviceId: deviceId,
                        serviceUuid: service.uuid,
                        charUuid: ch.uuid,
                        value: data.toString('hex').toUpperCase()
                      });
                    }
                  }
                });
              }

              charsInfo.push({
                uuid: ch.uuid,
                name: getCharName(ch.uuid),
                props: props,
                value: null
              });
            });
          }

          servicesInfo.push({
            uuid: service.uuid,
            name: getServiceName(service.uuid),
            chars: charsInfo
          });

          if (completed === services.length) {
            if (scannerWindow && !scannerWindow.isDestroyed()) {
              scannerWindow.webContents.send('ble-services-discovered', {
                id: deviceId,
                services: servicesInfo
              });
            }
          }
        });
      });
    });

    // 연결 해제 이벤트 바인딩
    peripheral.once('disconnect', () => {
      if (scannerWindow && !scannerWindow.isDestroyed()) {
        scannerWindow.webContents.send('ble-disconnected', { id: deviceId });
      }
    });
  });
});

// noble 기기 해제 IPC
ipcMain.on('ble-disconnect-device', (event, deviceId) => {
  const peripheral = discoveredPeripherals.get(deviceId);
  if (peripheral) {
    peripheral.disconnect();
  }
});



app.whenReady().then(() => {
  let gotTheLock = app.requestSingleInstanceLock();
  
  if (!gotTheLock) {
    const choice = dialog.showMessageBoxSync({
      type: 'warning',
      buttons: ['기존 앱 종료 후 실행', '실행 취소'],
      defaultId: 0,
      cancelId: 1,
      title: '보카보카 - 중복 실행 감지',
      message: '보카보카 프로파일러가 이미 실행 중입니다.',
      detail: '기존에 실행 중인 앱을 완전히 종료하고 새로 시작하시겠습니까, 아니면 실행을 취소하시겠습니까?'
    });

    if (choice === 0) {
      if (fs.existsSync(pidFilePath)) {
        try {
          const oldPid = parseInt(fs.readFileSync(pidFilePath, 'utf-8').trim(), 10);
          if (!isNaN(oldPid)) {
            console.log(`Killing old instance with PID: ${oldPid}`);
            process.kill(oldPid, 'SIGTERM');
          }
        } catch (err) {
          console.error('Failed to kill previous instance:', err);
        }
      }
      setTimeout(() => {
        fs.writeFileSync(pidFilePath, process.pid.toString(), 'utf-8');
        createWindow();
      }, 800);
    } else {
      app.quit();
      process.exit(0);
    }
  } else {
    fs.writeFileSync(pidFilePath, process.pid.toString(), 'utf-8');
    createWindow();
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
