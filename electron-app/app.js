// ──────────────────────────────────────────────────────────
// BocaBoa Electron App.js - Core Profiler Engine (v2.0)
// ──────────────────────────────────────────────────────────

// IPC 및 전역 상태 관리
window.onerror = function(message, source, lineno, colno, error) {
  console.error("UNCAUGHT RENDERER ERROR:", message, "at", source, ":", lineno, ":", colno, error);
};

let sessionsList = [];
let activeSession = {
  id: null,
  date: null,
  beanName: '',
  beanWeight: '',
  preheatTemp: '',
  targetDTR: '',
  events: [],
  graphPoints: [],
  memo: '',
  processing: 'washed',
  purpose: 'hand-drip'
};
let guideSession = null;

// 블루투스 변수
let bluetoothDevice = null;
let bluetoothCharacteristic = null;
let lastReceivedTemp = 0.0;

// 로스팅 상태 관리 플래그
let isPreheating = false;
let isRoasting = false;
let elapsedSeconds = 0; // 예열 시작 기준 흐른 총 초
let chargeTimeOffset = 0; // 생두 투입 시점 경과초
let currentHeat = 12;
let pendingHeat = 12;
let isSaved = false;

// 5가지 개선 기능 추가 상태 변수
let preheatAlertPlay = false;
let tpDetected = false;
let minTempAfterCharge = 999;
let minTempTime = 0;
let tempRiseCount = 0;
let lastTemp = 999;
let dtrAlertPlay = false;
let currentAudio = null;

// 모의 로스팅 관련 상태 변수
let isMockRoasting = false;
let mockInterval = null;
let mockTemperature = 25.0;
let mockRoastingSeconds = 0;
let mockSelectedSession = null;
let tempSelectedSession = null;
let mockSpeedMultiplier = 1;
let isMockPaused = false;

// 보정 필터 슬라이더 값
let filterWindow = 30;
let filterStrength = 95;

// GitHub 연동 전역 설정 객체
let githubConfig = {
  publicPat: '',
  privatePat: '',
  repoType: 'public', // 'public' | 'private'
  userName: '',
  privateOwner: '',
  privateRepo: ''
};

// Chart.js 인스턴스
let mainChart = null;
let modalChart = null;
let zoomChart = null;
let verticalLinesPlugin = null;

// 실시간 패킷 수집 타이머
let mainTimerInterval = null;

// 그래프 확대/축소 및 이동 관련 상태 변수
let zoomPercent = 100;
let absoluteMaxX = 900;

// DOM 로딩 시 초기화
document.addEventListener('DOMContentLoaded', () => {
  initUI();
  initCharts();
  loadSavedSessions();
  setupKeyboardShortcuts();
  resetTimetable();
  
  // DTR 및 Agtron 초기 매핑 실행
  updateAgtronMapping();
  
  // 모달 드래그 가능하도록 설정
  makeModalDraggable('report-modal');
  makeModalDraggable('device-select-modal');
  makeModalDraggable('mock-session-select-modal');
  makeModalDraggable('mock-start-modal');
  makeModalDraggable('donation-modal');
  makeModalDraggable('chart-zoom-modal');
  makeModalDraggable('github-settings-modal');
  makeModalDraggable('github-sessions-modal');
  makeModalDraggable('import-source-modal');
  makeModalDraggable('github-guide-modal');

  // GitHub 설정 사전 로딩
  if (window.api && window.api.githubLoadConfig) {
    window.api.githubLoadConfig().then(res => {
      if (res && res.success && res.config) {
        githubConfig = { ...githubConfig, ...res.config };
      }
    });
  }
});

// MARK: - UI 요소 이벤트 매핑
function initUI() {
  document.fonts.ready.then(() => {
    document.fonts.load("12px 'LCDPhone'").then(() => {
      updateHeatDisplay(pendingHeat || 12);
    }).catch(() => {
      updateHeatDisplay(pendingHeat || 12);
    });
  });

  // BLE 기기 찾기
  document.getElementById('btn-connect').addEventListener('click', connectBluetooth);
  document.getElementById('btn-scan-devices').addEventListener('click', () => {
    window.api.scanDevices();
  });
  document.getElementById('btn-mock-roast').addEventListener('click', toggleMockRoasting);
  document.getElementById('btn-mock-pause').addEventListener('click', toggleMockPause);

  // 모의 로스팅 모달 닫기/확인 연동
  const mockModal = document.getElementById('mock-session-select-modal');
  document.getElementById('btn-close-mock-select').addEventListener('click', () => {
    mockModal.classList.remove('active');
  });
  document.getElementById('btn-close-mock-select-confirm').addEventListener('click', () => {
    mockModal.classList.remove('active');
  });

  // 모의 로스팅 시작 컨펌 모달 연동
  const startModal = document.getElementById('mock-start-modal');
  document.getElementById('btn-close-mock-start').addEventListener('click', () => {
    startModal.classList.remove('active');
  });
  document.getElementById('btn-mock-start-cancel').addEventListener('click', () => {
    startModal.classList.remove('active');
  });
  document.getElementById('btn-mock-start-execute').addEventListener('click', () => {
    startModal.classList.remove('active');
    startMockRoasting(tempSelectedSession);
  });

  // 헤더 완전히 종료 버튼
  document.getElementById('btn-force-stop').addEventListener('click', () => {
    if (confirm('보카보카 프로파일러 앱을 완전히 종료하시겠습니까?')) {
      window.api.exitApp();
    }
  });
  
  // 음성 설정 로드 및 연동
  const voiceEnabled = localStorage.getItem('voiceEnabled') !== 'false';
  document.getElementById('chk-voice-enable').checked = voiceEnabled;
  
  const voiceVolume = localStorage.getItem('voiceVolume') || '7';
  document.getElementById('rng-voice-volume').value = voiceVolume;
  document.getElementById('lbl-voice-volume').innerText = voiceVolume;
  
  document.getElementById('chk-voice-enable').addEventListener('change', (e) => {
    localStorage.setItem('voiceEnabled', e.target.checked);
  });
  document.getElementById('rng-voice-volume').addEventListener('input', (e) => {
    document.getElementById('lbl-voice-volume').innerText = e.target.value;
    localStorage.setItem('voiceVolume', e.target.value);
  });
  
  // 모의 로스팅 배속 변경 이벤트 연동
  document.getElementById('sel-mock-speed').addEventListener('change', (e) => {
    mockSpeedMultiplier = parseInt(e.target.value) || 1;
    if (isMockRoasting) {
      if (mockInterval) clearInterval(mockInterval);
      mockInterval = setInterval(simulateMockData, 1000 / mockSpeedMultiplier);
    }
    // 선택 후 포커스 해제 → 스페이스키가 드롭다운을 열지 않도록 방지
    e.target.blur();
  });
  // 개발자 후원 모달 연동
  const donationModal = document.getElementById('donation-modal');
  document.getElementById('btn-support').addEventListener('click', () => {
    openModal(donationModal);
  });
  document.getElementById('btn-close-donation').addEventListener('click', () => {
    donationModal.classList.remove('active');
  });
  document.getElementById('btn-close-donation-confirm').addEventListener('click', () => {
    donationModal.classList.remove('active');
  });

  // 블루투스 장치 선택 모달 연동
  const deviceSelectModal = document.getElementById('device-select-modal');
  document.getElementById('btn-close-device-select').addEventListener('click', () => {
    deviceSelectModal.classList.remove('active');
  });
  document.getElementById('btn-close-device-select-confirm').addEventListener('click', () => {
    deviceSelectModal.classList.remove('active');
  });
  document.getElementById('btn-open-scanner-from-select').addEventListener('click', () => {
    deviceSelectModal.classList.remove('active');
    window.api.scanDevices();
  });

  // 보정 값 슬라이더 연동
  const rangeWindow = document.getElementById('range-window');
  const rangeFilter = document.getElementById('range-filter');
  
  rangeWindow.addEventListener('input', (e) => {
    filterWindow = parseInt(e.target.value);
    document.getElementById('val-window').innerText = `${filterWindow}초`;
    recalculateAllRoR();
  });
  
  rangeFilter.addEventListener('input', (e) => {
    filterStrength = parseInt(e.target.value);
    document.getElementById('val-filter').innerText = `${filterStrength}%`;
    recalculateAllRoR();
  });

  document.getElementById('btn-reset-filters').addEventListener('click', () => {
    filterWindow = 30;
    filterStrength = 95;
    rangeWindow.value = 30;
    rangeFilter.value = 95;
    document.getElementById('val-window').innerText = '30초';
    document.getElementById('val-filter').innerText = '95%';
    recalculateAllRoR();
  });

  // 가져오기 (Import) 버튼 - 원본 선택 모달 오픈
  document.getElementById('btn-import').addEventListener('click', () => {
    document.getElementById('import-source-modal').classList.add('active');
  });

  // 가져오기 모달 닫기
  document.getElementById('btn-close-import-source').addEventListener('click', () => {
    document.getElementById('import-source-modal').classList.remove('active');
  });
  document.getElementById('btn-close-import-source-cancel').addEventListener('click', () => {
    document.getElementById('import-source-modal').classList.remove('active');
  });

  // 로컬 파일 가져오기 선택
  document.getElementById('btn-import-local').addEventListener('click', async () => {
    document.getElementById('import-source-modal').classList.remove('active');
    const res = await window.api.importSession();
    if (res.success) {
      loadSavedSessions();
      alert(`성공적으로 '${res.session.beanName}' 프로파일을 가져왔습니다.`);
    }
  });

  // GitHub 저장소 가져오기 선택
  document.getElementById('btn-import-github').addEventListener('click', () => {
    document.getElementById('import-source-modal').classList.remove('active');
    const pat = githubConfig.repoType === 'public' ? githubConfig.publicPat : githubConfig.privatePat;
    if (!pat) {
      alert('GitHub 설정이 완료되지 않았습니다. 설정 창에서 설정을 완료해 주세요.');
      openGithubSettingsModal();
      return;
    }
    openGithubSessionsModal();
  });

  // 로스팅 조작 컨트롤 버튼
  document.getElementById('btn-preheat').addEventListener('click', triggerPreheating);
  document.getElementById('btn-charge').addEventListener('click', triggerCharging);
  document.getElementById('btn-pop1').addEventListener('click', () => addEvent('1차 팝'));
  document.getElementById('btn-pop2').addEventListener('click', () => addEvent('2차 팝'));
  document.getElementById('btn-finish').addEventListener('click', triggerFinishing);

  // 다시 시작 & 로스팅 취소 버튼 복구
  document.getElementById('btn-reset-session').addEventListener('click', triggerResetSession);
  document.getElementById('btn-cancel-roast').addEventListener('click', triggerCancelRoast);

  // 열량 조절 슬라이더
  const rangeHeat = document.getElementById('range-heat');
  rangeHeat.addEventListener('input', (e) => {
    pendingHeat = parseInt(e.target.value);
    updateHeatDisplay(pendingHeat);
  });
  document.getElementById('btn-confirm-heat').addEventListener('click', confirmHeatChange);
  
  // 수동 열량 조절 단축키 마우스 클릭 바인딩
  document.getElementById('btn-heat-up').addEventListener('click', () => adjustHeatSlider(1));
  document.getElementById('btn-heat-down').addEventListener('click', () => adjustHeatSlider(-1));

  // 가공 방식 드롭다운 변경 리스너
  document.getElementById('select-processing').addEventListener('change', (e) => {
    const proc = e.target.value;
    let temp = 220;
    
    if (proc === 'washed') temp = 220;
    else if (proc === 'natural') temp = 205;
    else if (proc === 'honey') temp = 210;
    else if (proc === 'decaf') temp = 195;
    
    document.getElementById('recommend-temp').innerText = `권장 ${temp}°C`;
    document.getElementById('input-preheat-temp').value = temp;
    updateProcessingAndPurposeLimits();
  });

  // 로스팅 목적 드롭다운 변경 리스너
  document.getElementById('select-purpose').addEventListener('change', () => {
    updateProcessingAndPurposeLimits();
  });

  // DTR 슬라이더 및 입력 필드 상호 연동
  const rangeDtr = document.getElementById('range-dtr');
  const inputDtr = document.getElementById('val-target-dtr');
  
  function updateDTRComponents(val, source) {
    const num = parseFloat(val);
    if (isNaN(num)) return;
    
    // 값 범위 제한 (10.0 ~ 25.0)
    let clamped = num;
    if (source === 'input-blur') {
      if (num < 10.0) clamped = 10.0;
      if (num > 25.0) clamped = 25.0;
    }
    
    const formatted = clamped.toFixed(1);
    
    if (source !== 'slider') {
      rangeDtr.value = formatted;
    }
    if (source !== 'input') {
      inputDtr.value = formatted;
    }
    
    if (activeSession) {
      activeSession.targetDTR = formatted;
    }
    
    updateAgtronMapping();
    updateExpectedEtaTime();
  }

  rangeDtr.addEventListener('input', (e) => {
    updateDTRComponents(e.target.value, 'slider');
  });

  inputDtr.addEventListener('input', (e) => {
    updateDTRComponents(e.target.value, 'input');
  });

  inputDtr.addEventListener('blur', (e) => {
    updateDTRComponents(e.target.value, 'input-blur');
  });

  inputDtr.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      inputDtr.blur();
    }
  });

  // 모달 닫기
  document.getElementById('btn-close-modal').addEventListener('click', closeModal);
  
  // 모달 메모 저장
  document.getElementById('btn-save-memo').addEventListener('click', saveModalMemo);
  
  // 모달 내부 파일/출력 제어
  document.getElementById('btn-save-session').addEventListener('click', saveActiveSessionToDisk);
  document.getElementById('btn-github-upload').addEventListener('click', uploadActiveSessionToGithub);

  // GitHub 설정 열기 및 제어 연동
  document.getElementById('btn-github-settings-open').addEventListener('click', openGithubSettingsModal);
  document.getElementById('btn-close-github-settings').addEventListener('click', closeGithubSettingsModal);
  document.getElementById('btn-close-github-settings-cancel').addEventListener('click', closeGithubSettingsModal);
  document.getElementById('btn-save-github-pat').addEventListener('click', saveGithubConfig);
  
  // PAT 토큰 보이기/가리기 버튼 클릭시 토글 연동
  document.getElementById('btn-toggle-pat-visibility').addEventListener('click', togglePatVisibility);

  // 설정값 실시간 상태 텍스트 갱신을 위한 input 이벤트 바인딩
  document.getElementById('input-github-private-owner').addEventListener('input', updateGithubConfigStatus);
  document.getElementById('input-github-private-repo').addEventListener('input', updateGithubConfigStatus);
  document.getElementById('input-github-pat').addEventListener('input', updateGithubConfigStatus);
  document.getElementById('input-github-user-name').addEventListener('input', updateGithubConfigStatus);

  // 저장소 구분 변경 라디오 버튼 이벤트 연동
  document.querySelectorAll('input[name="github-repo-type"]').forEach(radio => {
    radio.addEventListener('change', (e) => {
      toggleGithubRepoFields(e.target.value);
    });
  });

  // GitHub 가이드 모달 연동 및 내부 링크 외부 브라우저 오픈 처리
  document.getElementById('btn-github-show-guide').addEventListener('click', () => {
    document.getElementById('github-guide-modal').classList.add('active');
  });
  document.getElementById('btn-close-github-guide').addEventListener('click', () => {
    document.getElementById('github-guide-modal').classList.remove('active');
  });
  document.getElementById('btn-close-github-guide-cancel').addEventListener('click', () => {
    document.getElementById('github-guide-modal').classList.remove('active');
  });

  document.querySelectorAll('#github-guide-modal a').forEach(link => {
    link.addEventListener('click', (e) => {
      e.preventDefault();
      const url = link.getAttribute('href');
      if (window.api && window.api.openExternalLink) {
        window.api.openExternalLink(url);
      }
    });
  });

  // GitHub 기록 리스트 브라우저 연동
  document.getElementById('btn-github-browse').addEventListener('click', openGithubSessionsModal);
  document.getElementById('btn-close-github-sessions').addEventListener('click', closeGithubSessionsModal);
  document.getElementById('btn-close-github-sessions-cancel').addEventListener('click', closeGithubSessionsModal);
  document.getElementById('btn-github-sessions-refresh').addEventListener('click', loadGithubSessionsList);

  // GitHub 기록 검색 리스너 연동
  document.getElementById('github-search-input').addEventListener('input', renderGithubSessionsList);
  document.getElementById('github-search-target').addEventListener('change', renderGithubSessionsList);
  document.getElementById('github-search-input').addEventListener('keydown', (e) => {
    if (e.isComposing) return; // IME 입력 완료 전 이벤트 처리 방지
    if (e.key === 'Enter') {
      renderGithubSessionsList();
      e.target.blur();
    }
  });
  document.getElementById('btn-export-session').addEventListener('click', exportActiveSession);
  document.getElementById('btn-set-guide').addEventListener('click', setAsGuide);
  document.getElementById('btn-print-report').addEventListener('click', () => {
    window.print();
  });
  document.getElementById('btn-save-pdf-report').addEventListener('click', async () => {
    try {
      let defaultName = 'Roasting-Report.pdf';
      if (activeSession) {
        const safeBeanName = (activeSession.beanName || '미지정_프로파일')
          .replace(/[\\/:*?"<>|]/g, '_')
          .trim();
        const dateStr = formatDateForFilename(activeSession.date);
        defaultName = `${safeBeanName}_${dateStr}.pdf`;
      }
      
      const res = await window.api.saveReportPdf(defaultName);
      if (res && res.success) {
        alert('PDF 리포트가 성공적으로 저장되었습니다.');
      } else if (res && res.error && res.error !== 'Cancelled') {
        alert('PDF 저장 중 오류가 발생했습니다: ' + res.error);
      }
    } catch (err) {
      console.error(err);
      alert('PDF 저장 실행 중 시스템 오류가 발생했습니다.');
    }
  });

  // 모달 차트 확대 이벤트 연동
  document.querySelector('.modal-chart-wrapper').addEventListener('click', openZoomModal);
  
  // 줌 모달 닫기
  document.getElementById('btn-close-zoom-modal').addEventListener('click', () => {
    document.getElementById('chart-zoom-modal').classList.remove('active');
  });
  
  // 줌 모달 차트 파일 내보내기/저장/인쇄 연동
  document.getElementById('btn-export-png').addEventListener('click', () => exportZoomChart('png'));
  document.getElementById('btn-export-jpg').addEventListener('click', () => exportZoomChart('jpg'));
  document.getElementById('btn-export-pdf').addEventListener('click', exportZoomChartPdf);
  document.getElementById('btn-zoom-print').addEventListener('click', printZoomChart);

  // ── 입력 필드 엔터키 처리 및 데이터 동적 매핑 ──
  const inputFields = [
    { id: 'input-bean-name', field: 'beanName' },
    { id: 'input-bean-weight', field: 'beanWeight' },
    { id: 'input-preheat-temp', field: 'preheatTemp' }
  ];

  inputFields.forEach(item => {
    const el = document.getElementById(item.id);
    if (el) {
      // 엔터키 누르면 포커스 해제 (입력 완료 피드백)
      el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          el.blur();
        }
      });
      // 입력값 변경 시 실시간 세션 오브젝트에 동적 동기화
      el.addEventListener('input', (e) => {
        if (activeSession) {
          activeSession[item.field] = e.target.value;
        }
      });
    }
  });

  // 드롭다운 및 슬라이더 실시간 연동
  document.getElementById('select-processing').addEventListener('change', (e) => {
    if (activeSession) activeSession.processing = e.target.value;
  });
  document.getElementById('select-purpose').addEventListener('change', (e) => {
    if (activeSession) activeSession.purpose = e.target.value;
  });
  updateHeatDisplay(12);
}

// MARK: - 차트 초기화 (Chart.js)
function initCharts() {
  // Chart.js 커스텀 툴팁 포지셔너 등록: 온도가 표시되는 그래프 선 상에 상태표시창(툴팁) 고정
  if (typeof Chart !== 'undefined' && Chart.Tooltip && Chart.Tooltip.positioners) {
    Chart.Tooltip.positioners.fixedTemp = function(items, eventPosition) {
      if (items.length === 0) return false;
      const chart = this.chart;
      const chartArea = chart && chart.chartArea;
      
      // dataset 0(온도) 또는 2(가이드 온도) 우선 — 예상 온도선(4) 제외
      const tempItem = items.find(item =>
        (item.datasetIndex === 0 || item.datasetIndex === 2) && !!item.element
      );
      
      if (chartArea) {
        let x, y;
        
        if (tempItem) {
          // x: 온도 그래프 element 위치 (그래프를 따라다님)
          x = tempItem.element.x;
          // y: 온도 element y픽셀, 차트 범위 안으로 클램핑
          const rawY = tempItem.element.y;
          y = Math.max(chartArea.top + 20, Math.min(chartArea.bottom - 20, rawY));
        } else {
          // 예상 온도선 구간 — dataset 0 마지막 포인트 위치 사용
          const ds0 = chart.getDatasetMeta(0);
          if (ds0 && ds0.data && ds0.data.length > 0) {
            const lastEl = ds0.data[ds0.data.length - 1];
            x = lastEl.x;
            const rawY = lastEl.y != null ? lastEl.y : null;
            y = rawY != null
              ? Math.max(chartArea.top + 20, Math.min(chartArea.bottom - 20, rawY))
              : chartArea.top + (chartArea.bottom - chartArea.top) * 0.25;
          } else {
            x = eventPosition ? eventPosition.x : chartArea.right;
            y = chartArea.top + (chartArea.bottom - chartArea.top) * 0.25;
          }
        }
        return { x, y };
      }
      
      if (tempItem) {
        return { x: tempItem.element.x, y: tempItem.element.y };
      }
      return eventPosition || false;
    };
  }

  const ctx = document.getElementById('profiler-chart').getContext('2d');
  
  verticalLinesPlugin = {
    id: 'verticalLines',
    beforeDatasetsDraw(chart) {
      if (!chart.scales || !chart.scales.x || !chart.chartArea) return;
      const { ctx, chartArea: { top, bottom, left, right } } = chart;
      const x = chart.scales.x;
      const canvasId = (chart.canvas && chart.canvas.id) || (chart.ctx && chart.ctx.canvas && chart.ctx.canvas.id) || '';
      ctx.save();
      
      // 1. 모달 상세 분석 차트 또는 줌 차트인 경우
      if (canvasId === 'modal-analysis-chart' || canvasId === 'zoom-analysis-chart') {
        // openReportModal에서 x.min = -sessionChargeOffset 으로 이미 설정됨
        // x.min < 0 이면 예열 구간이 존재하므로 배경색 적용
        const xMin = x.min;
        if (xMin < 0) {
          ctx.save();
          const startX = Math.max(left, x.getPixelForValue(xMin));
          const endX   = Math.min(right, x.getPixelForValue(0));
          if (startX < endX) {
            ctx.fillStyle = 'rgba(254, 215, 215, 0.45)';
            ctx.fillRect(startX, top, endX - startX, bottom - top);
          }
          ctx.restore();
        }
      } 
      // 2. 메인 대시보드 차트인 경우
      else {
        // chargeTimeOffset > 0이면 투입이 발생했다는 의미 → 예열 영역을 항상 표시
        // (투입 이벤트의 elapsedSeconds는 상대시간 기준 0이므로 전역 chargeTimeOffset 사용)
        if (chargeTimeOffset > 0 && activeSession && (activeSession.events || []).some(e => e.type === '투입')) {
          ctx.save();
          const startX = Math.max(left, x.getPixelForValue(-chargeTimeOffset));
          const endX   = Math.min(right, x.getPixelForValue(0));
          if (startX < endX) {
            ctx.fillStyle = 'rgba(254, 215, 215, 0.45)';
            ctx.fillRect(startX, top, endX - startX, bottom - top);
          }
          ctx.restore();
        } else if (isPreheating && preheatAlertPlay) {
          // 예열 완료 대기 중 (아직 투입 전): 전체 차트 영역을 연한 붉은색으로
          ctx.save();
          ctx.fillStyle = 'rgba(254, 215, 215, 0.45)';
          ctx.fillRect(left, top, right - left, bottom - top);
          ctx.restore();
        } else if (!isPreheating && !isRoasting && guideSession) {
          // 대기 상태에서 가이드 세션만 있는 경우
          const guideChargeEv = (guideSession.events || []).find(e => e.type === '투입');
          if (guideChargeEv) {
            // 가이드 세션의 투입 시각(절대 elapsed)을 기준으로 음수 영역 계산
            const guideChargeAbsSec = guideChargeEv.elapsedSeconds; // 가이드는 원본 세션이라 절대값
            const guideChargeTime   = guideChargeAbsSec; // X축상 투입 전 preheat 구간 (shifted)
            if (guideChargeTime > 0) {
              ctx.save();
              const startX = Math.max(left, x.getPixelForValue(-guideChargeTime));
              const endX   = Math.min(right, x.getPixelForValue(0));
              if (startX < endX) {
                ctx.fillStyle = 'rgba(254, 215, 215, 0.45)';
                ctx.fillRect(startX, top, endX - startX, bottom - top);
              }
              ctx.restore();
            }
          }
        }
      }
    },
    afterDraw(chart) {
      if (!chart.scales || !chart.scales.x) return;
      const { ctx, chartArea: { top, bottom } } = chart;
      const x = chart.scales.x;
      const canvasId = (chart.canvas && chart.canvas.id) || (chart.ctx && chart.ctx.canvas && chart.ctx.canvas.id) || '';
      ctx.save();
      
      // 1. 모달 상세 분석 차트 또는 줌 차트인 경우, 투입 이후 이벤트만 그립니다.
      if (canvasId === 'modal-analysis-chart' || canvasId === 'zoom-analysis-chart') {
        if (activeSession && activeSession.events) {
          // ev.elapsedSeconds는 상대시간: 0 = 투입, 양수 = 로스팅, 음수 = 예열
          // graphPoints도 relativeTime을 X 좌표로 쓰므로 그대로 사용
          
          // Pass 1: 투입 이후 이벤트 세로선 그리기
          activeSession.events.forEach(ev => {
            if (ev.type === '열량 조절' || ev.type === '예열 시작') return;
            if (ev.elapsedSeconds < 0) return; // 예열 구간(음수 상대시간) 이벤트 제외
            
            const xPos = x.getPixelForValue(ev.elapsedSeconds); // relativeTime = elapsedSeconds (상대)
            
            if (xPos >= chart.chartArea.left && xPos <= chart.chartArea.right) {
              ctx.strokeStyle = getEventColor(ev.type);
              if (ev.type === '투입') {
                ctx.lineWidth = 3;
                ctx.setLineDash([]);
              } else {
                ctx.lineWidth = 1.5;
                ctx.setLineDash([4, 4]);
              }
              ctx.beginPath();
              ctx.moveTo(xPos, top);
              ctx.lineTo(xPos, bottom);
              ctx.stroke();
            }
          });
          
          // Pass 2: 투입 이후 이벤트 배지 그리기
          const drawnBadges = [];
          activeSession.events.forEach(ev => {
            if (ev.type === '열량 조절' || ev.type === '예열 시작') return;
            if (ev.elapsedSeconds < 0) return; // 예열 구간 이벤트 제외
            
            const xPos = x.getPixelForValue(ev.elapsedSeconds);
            
            if (xPos >= chart.chartArea.left && xPos <= chart.chartArea.right) {
              const isZoom = canvasId === 'zoom-analysis-chart';
              ctx.setLineDash([]);
              
              let level = 0;
              while (true) {
                const hasConflict = drawnBadges.some(b => Math.abs(b.x - xPos) < 55 && b.level === level);
                if (!hasConflict) break;
                level++;
              }
              drawnBadges.push({ x: xPos, level: level });
              
              const offsetShift = isZoom ? 45 : 36;
              const adjustedTop = top + (level * offsetShift);
              
              const times = getEventTimes(ev, activeSession.events);
              drawEventBadge(ctx, ev.type, times.process, ev.temperature, xPos, adjustedTop, getEventColor(ev.type), isZoom);
            }
          });
        }
      }
      // 2. 메인 대시보드 차트인 경우
      else {
        // (1) activeSession 이벤트 그리기
        if (activeSession && activeSession.events && activeSession.events.length > 0) {
          const hasCharge = activeSession.events.some(e => e.type === '투입');
          
          // Pass 1: 세로선
          activeSession.events.forEach(ev => {
            if (ev.type === '열량 조절' || ev.type === '예열 시작') return;
            if (hasCharge) {
              const chargeEv = activeSession.events.find(e => e.type === '투입');
              if (ev.elapsedSeconds < chargeEv.elapsedSeconds) return;
            }
            
            const xPos = x.getPixelForValue(ev.elapsedSeconds);
            if (xPos >= chart.chartArea.left && xPos <= chart.chartArea.right) {
              ctx.strokeStyle = getEventColor(ev.type);
              if (ev.type === '투입') {
                ctx.lineWidth = 3;
                ctx.setLineDash([]);
              } else {
                ctx.lineWidth = 1.5;
                ctx.setLineDash([4, 4]);
              }
              ctx.beginPath();
              ctx.moveTo(xPos, top);
              ctx.lineTo(xPos, bottom);
              ctx.stroke();
            }
          });
          
          // Pass 2: 배지
          const drawnBadges = [];
          activeSession.events.forEach(ev => {
            if (ev.type === '열량 조절' || ev.type === '예열 시작') return;
            if (hasCharge) {
              const chargeEv = activeSession.events.find(e => e.type === '투입');
              if (ev.elapsedSeconds < chargeEv.elapsedSeconds) return;
            }
            
            const xPos = x.getPixelForValue(ev.elapsedSeconds);
            if (xPos >= chart.chartArea.left && xPos <= chart.chartArea.right) {
              ctx.setLineDash([]);
              
              let level = 0;
              while (true) {
                const hasConflict = drawnBadges.some(b => Math.abs(b.x - xPos) < 55 && b.level === level);
                if (!hasConflict) break;
                level++;
              }
              drawnBadges.push({ x: xPos, level: level });
              
              const adjustedTop = top + (level * 36);
              const times = getEventTimes(ev, activeSession.events);
              drawEventBadge(ctx, ev.type, times.process, ev.temperature, xPos, adjustedTop, getEventColor(ev.type), false);
            }
          });
        }
        
        // (2) 가이드 세션 이벤트 그리기
        if (guideSession && guideSession.events && guideSession.events.length > 0) {
          const guideChargeEv = (guideSession.events || []).find(e => e.type === '투입');
          const guideChargeTime = guideChargeEv ? guideChargeEv.elapsedSeconds : 0;
          
          // Pass 1: 세로선
          guideSession.events.forEach(ev => {
            if (ev.type === '열량 조절' || ev.type === '예열 시작') return;
            if (ev.elapsedSeconds < guideChargeTime) return;
            
            const shiftedSec = ev.elapsedSeconds - guideChargeTime;
            const xPos = x.getPixelForValue(shiftedSec);
            
            if (xPos >= chart.chartArea.left && xPos <= chart.chartArea.right) {
              ctx.strokeStyle = 'rgba(160, 174, 192, 0.6)';
              if (ev.type === '투입') {
                ctx.lineWidth = 3;
                ctx.setLineDash([]);
              } else {
                ctx.lineWidth = 1.2;
                ctx.setLineDash([3, 3]);
              }
              ctx.beginPath();
              ctx.moveTo(xPos, top);
              ctx.lineTo(xPos, bottom);
              ctx.stroke();
            }
          });
          
          // Pass 2: 배지
          const drawnBadges = [];
          guideSession.events.forEach(ev => {
            if (ev.type === '열량 조절' || ev.type === '예열 시작') return;
            if (ev.elapsedSeconds < guideChargeTime) return;
            
            const shiftedSec = ev.elapsedSeconds - guideChargeTime;
            const xPos = x.getPixelForValue(shiftedSec);
            
            if (xPos >= chart.chartArea.left && xPos <= chart.chartArea.right) {
              ctx.setLineDash([]);
              
              let level = 0;
              while (true) {
                const hasConflict = drawnBadges.some(b => Math.abs(b.x - xPos) < 55 && b.level === level);
                if (!hasConflict) break;
                level++;
              }
              drawnBadges.push({ x: xPos, level: level });
              
              const adjustedTop = top + (level * 36);
              const times = getEventTimes(ev, guideSession.events);
              drawEventBadge(ctx, ev.type, times.process, ev.temperature, xPos, adjustedTop, 'rgba(113, 128, 150, 0.8)', false);
            }
          });
        }
      }
      ctx.restore();
    }
  };

  const commonOptions = (yAxisMaxTemp = 240) => ({
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        labels: {
          color: '#2d3748',
          font: { size: 10 },
          usePointStyle: true,
          pointStyle: 'line',
          pointStyleWidth: 40,
          boxWidth: 40
        }
      },
      tooltip: {
        enabled: false
      }
    },
    scales: {
      x: {
        type: 'linear',
        min: 0, // 항상 0부터 시작
        max: 900,  // 기본 15분
        ticks: {
          color: '#4a5568',
          font: { size: 9 },
          callback: (value) => {
            const events = (activeSession && activeSession.events) || (guideSession && guideSession.events) || [];
            return formatXAxisTick(value, events);
          }
        },
        grid: { color: 'rgba(0,0,0,0.04)' }
      },
      y: {
        type: 'linear',
        position: 'left',
        min: 0,
        max: yAxisMaxTemp,
        title: { display: true, text: '온도 (°C)', color: '#e53e3e' },
        ticks: { color: '#e53e3e', stepSize: 20 },
        grid: { color: 'rgba(0,0,0,0.06)' }
      },
      y1: {
        type: 'linear',
        position: 'right',
        min: -15,
        max: 40,
        title: { display: true, text: 'RoR (°C/min)', color: '#38a169' },
        ticks: { color: '#38a169', stepSize: 8 },
        grid: { drawOnChartArea: false }
      }
    }
  });

  // 메인 대시보드 차트 생성
  mainChart = new Chart(ctx, {
    type: 'line',
    data: {
      datasets: [
        {
          label: '예열 온도',
          borderColor: '#e53e3e',
          backgroundColor: 'rgba(229, 62, 98, 0.1)',
          borderWidth: 2.5,
          pointRadius: 0,
          data: [],
          yAxisID: 'y'
        },
        {
          label: '실시간 RoR',
          borderColor: '#38a169',
          segment: {
            borderColor: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? '#3182ce' : '#38a169';
            },
            borderWidth: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? 1.2 : 2.5;
            },
            borderDash: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? [4, 4] : [];
            }
          },
          borderWidth: 2.5,
          pointRadius: 0,
          data: [],
          yAxisID: 'y1'
        },
        {
          label: '가이드 온도',
          borderColor: 'rgba(160, 174, 192, 0.5)',
          borderWidth: 3.5,
          borderDash: [10, 8],
          pointRadius: 0,
          data: [],
          yAxisID: 'y'
        },
        {
          label: '가이드 RoR',
          borderColor: 'rgba(56, 161, 105, 0.4)',
          segment: {
            borderColor: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? 'rgba(49, 130, 206, 0.4)' : 'rgba(56, 161, 105, 0.4)';
            },
            borderWidth: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? 1.5 : 3.5;
            },
            borderDash: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? [4, 4] : [8, 6];
            }
          },
          borderWidth: 3.5,
          borderDash: [8, 6],
          pointRadius: 0,
          data: [],
          yAxisID: 'y1'
        },
        {
          label: '예상 온도선',
          borderColor: '#fc8181',
          borderWidth: 1.5,
          borderDash: [6, 4],
          pointRadius: 0,
          data: [],
          yAxisID: 'y',
          fill: false,
          spanGaps: true
        }
      ]
    },
    options: commonOptions(240),
    plugins: [verticalLinesPlugin]
  });
  
  // 모달 상세 분석 차트 생성
  const modalCtx = document.getElementById('modal-analysis-chart').getContext('2d');
  modalChart = new Chart(modalCtx, {
    type: 'line',
    data: {
      datasets: [
        {
          label: '온도',
          borderColor: '#e53e3e',
          borderWidth: 2.5,
          pointRadius: 0,
          data: [],
          yAxisID: 'y'
        },
        {
          label: 'RoR',
          borderColor: '#38a169',
          segment: {
            borderColor: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? '#3182ce' : '#38a169';
            },
            borderWidth: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? 1.2 : 2.5;
            },
            borderDash: ctx => {
              const y0 = ctx.p0.parsed.y;
              const y1 = ctx.p1.parsed.y;
              return (y0 < 0 || y1 < 0) ? [4, 4] : [];
            }
          },
          borderWidth: 2.5,
          pointRadius: 0,
          data: [],
          yAxisID: 'y1'
        }
      ]
    },
    options: commonOptions(240),
    plugins: [verticalLinesPlugin]
  });
  modalChart.id = 'modal-chart';

  // ── 그래프 확대/축소 및 드래그 스크롤 연동 ──
  const canvas = document.getElementById('profiler-chart');
  
  // 마우스 휠 이벤트 (확대/축소)
  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    const chartArea = mainChart.chartArea;
    if (!chartArea) return;
    
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    if (mouseX < chartArea.left || mouseX > chartArea.right) return;
    
    const pointerXVal = mainChart.scales.x.getValueForPixel(mouseX);
    const delta = e.deltaY;
    
    if (delta < 0) {
      // 확대
      if (zoomPercent < 800) {
        zoomPercent = Math.min(800, zoomPercent + 10);
        applyZoom(pointerXVal);
      }
    } else {
      // 축소
      if (zoomPercent > 100) {
        zoomPercent = Math.max(100, zoomPercent - 10);
        applyZoom(pointerXVal);
      }
    }
  });

  // 드래그 스크롤 (이동) 이벤트
  let isDragging = false;
  let dragStartX = 0;
  let dragStartMin = 0;
  let dragStartMax = 0;

  canvas.addEventListener('mousedown', (e) => {
    if (zoomPercent <= 100) return;
    const chartArea = mainChart.chartArea;
    if (!chartArea) return;
    
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    if (mouseX < chartArea.left || mouseX > chartArea.right) return;
    
    isDragging = true;
    dragStartX = e.clientX;
    dragStartMin = mainChart.options.scales.x.min;
    dragStartMax = mainChart.options.scales.x.max;
    canvas.style.cursor = 'grabbing';
  });

  canvas.addEventListener('mousemove', (e) => {
    const chartArea = mainChart.chartArea;
    if (!chartArea) return;
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    
    if (!isDragging) {
      if (zoomPercent > 100 && mouseX >= chartArea.left && mouseX <= chartArea.right) {
        canvas.style.cursor = 'grab';
      } else {
        canvas.style.cursor = 'default';
      }
      return;
    }
    
    const pixelDiff = e.clientX - dragStartX;
    const chartWidth = mainChart.scales.x.width;
    const valueSpan = dragStartMax - dragStartMin;
    const valueDiff = (pixelDiff / chartWidth) * valueSpan;
    
    const minBound = (isRoasting || chargeTimeOffset > 0) ? -chargeTimeOffset : 0;
    const maxBound = absoluteMaxX;
    
    let newMin = dragStartMin - valueDiff;
    let newMax = dragStartMax - valueDiff;
    
    if (newMin < minBound) {
      newMin = minBound;
      newMax = minBound + valueSpan;
    }
    if (newMax > maxBound) {
      newMax = maxBound;
      newMin = maxBound - valueSpan;
    }
    
    mainChart.options.scales.x.min = newMin;
    mainChart.options.scales.x.max = newMax;
    mainChart.update('none');
  });

  const stopDragging = () => {
    if (isDragging) {
      isDragging = false;
      canvas.style.cursor = zoomPercent > 100 ? 'grab' : 'default';
    }
  };

  canvas.addEventListener('mouseup', stopDragging);
  canvas.addEventListener('mouseleave', stopDragging);

  // 수동 툴바 버튼 이벤트
  document.getElementById('btn-zoom-in').addEventListener('click', () => {
    if (zoomPercent < 800) {
      zoomPercent = Math.min(800, zoomPercent + 10);
      applyZoom();
    }
  });

  document.getElementById('btn-zoom-out').addEventListener('click', () => {
    if (zoomPercent > 100) {
      zoomPercent = Math.max(100, zoomPercent - 10);
      applyZoom();
    }
  });

  document.getElementById('btn-zoom-fit').addEventListener('click', () => {
    zoomPercent = 100;
    applyZoom();
  });
}

// 그래프 확대/축소 핵심 처리 함수
function applyZoom(centerX = null) {
  if (!mainChart) return;
  
  const minBound = (isRoasting || chargeTimeOffset > 0) ? -chargeTimeOffset : 0;
  const maxBound = absoluteMaxX;
  const totalSpan = maxBound - minBound;
  
  if (zoomPercent === 100) {
    mainChart.options.scales.x.min = minBound;
    mainChart.options.scales.x.max = maxBound;
    document.getElementById('lbl-zoom-percent').innerText = '100% (Fit)';
    mainChart.update('none');
    return;
  }
  
  const currentMin = mainChart.options.scales.x.min;
  const currentMax = mainChart.options.scales.x.max;
  const currentSpan = currentMax - currentMin;
  const newSpan = totalSpan / (zoomPercent / 100);
  
  if (centerX === null) {
    centerX = currentMin + currentSpan / 2;
  }
  
  const ratio = currentSpan > 0 ? (centerX - currentMin) / currentSpan : 0.5;
  let newMin = centerX - ratio * newSpan;
  let newMax = centerX + (1 - ratio) * newSpan;
  
  if (newMin < minBound) {
    newMin = minBound;
    newMax = minBound + newSpan;
  }
  if (newMax > maxBound) {
    newMax = maxBound;
    newMin = maxBound - newSpan;
  }
  
  mainChart.options.scales.x.min = newMin;
  mainChart.options.scales.x.max = newMax;
  document.getElementById('lbl-zoom-percent').innerText = `${zoomPercent}%`;
  mainChart.update('none');
}

// MARK: - 가공 방식 및 로스팅 목적 변경 시 권장 DTR 업데이트
function updateProcessingAndPurposeLimits() {
  const proc = document.getElementById('select-processing').value;
  const purp = document.getElementById('select-purpose').value;
  
  let dtrMin = 14;
  let dtrMax = 18;
  let defaultDtr = 15.0;

  if (purp === 'hand-drip') {
    if (proc === 'washed') { dtrMin = 14; dtrMax = 18; defaultDtr = 15.0; }
    else if (proc === 'natural') { dtrMin = 13; dtrMax = 16; defaultDtr = 14.5; }
    else if (proc === 'honey') { dtrMin = 14; dtrMax = 17; defaultDtr = 15.0; }
    else if (proc === 'decaf') { dtrMin = 12; dtrMax = 15; defaultDtr = 13.5; }
  } else {
    // 에스프레소 목적
    if (proc === 'washed') { dtrMin = 18; dtrMax = 22; defaultDtr = 19.0; }
    else if (proc === 'natural') { dtrMin = 16; dtrMax = 20; defaultDtr = 18.0; }
    else if (proc === 'honey') { dtrMin = 17; dtrMax = 21; defaultDtr = 18.5; }
    else if (proc === 'decaf') { dtrMin = 15; dtrMax = 18; defaultDtr = 16.5; }
  }

  document.getElementById('recommend-dtr').innerText = `권장 ${dtrMin}-${dtrMax}%`;
  document.getElementById('range-dtr').value = defaultDtr;
  document.getElementById('val-target-dtr').value = defaultDtr.toFixed(1);
  updateAgtronMapping();
}

// MARK: - DTR 수치에 따른 Agtron 매핑 및 표시기 이동
function updateAgtronMapping() {
  const dtr = parseFloat(document.getElementById('range-dtr').value);
  
  // DTR에 반비례하는 Agtron 수치 산출 (DTR 10% -> Agtron 95, DTR 25% -> Agtron 35)
  // Agtron = 95 - (DTR - 10.0) * 4.0
  const agtron = Math.max(35, Math.min(95, Math.round(95 - (dtr - 10.0) * 4.0)));
  
  let rangeStr = "";
  let commonStr = "";
  let scaStr = "";

  if (agtron >= 90) {
    rangeStr = "95-90";
    commonStr = "Light";
    scaStr = "Very Light";
  } else if (agtron >= 80) {
    rangeStr = "89-80";
    commonStr = "Medium Light";
    scaStr = "Light";
  } else if (agtron >= 70) {
    rangeStr = "79-70";
    commonStr = "Light Medium";
    scaStr = "Medium Light";
  } else if (agtron >= 60) {
    rangeStr = "69-60";
    commonStr = "Medium";
    scaStr = "Medium";
  } else if (agtron >= 50) {
    rangeStr = "59-50";
    commonStr = "Medium Dark";
    scaStr = "Medium Dark";
  } else {
    rangeStr = "49-35";
    commonStr = "Dark";
    scaStr = "Dark";
  }

  // 텍스트 업데이트
  document.getElementById('agtron-value-text').innerText = `Agtron: #${agtron}`;
  document.getElementById('agtron-range-val').innerText = rangeStr;
  document.getElementById('agtron-common-val').innerText = commonStr;
  document.getElementById('agtron-sca-val').innerText = scaStr;

  // 포인터 삼각 기호 위치 이동 (10% ~ 25% 범위를 0% ~ 100%로 환산)
  const leftPercent = ((dtr - 10.0) / 15.0) * 100;
  document.getElementById('agtron-pointer').style.left = `${leftPercent}%`;
}

// 이전 사용했던 커피 품종 목록 자동 수집 및 datalist 갱신
function updateBeanNameDatalist() {
  const datalist = document.getElementById('datalist-bean-names');
  if (!datalist) return;
  
  const names = new Set();
  if (Array.isArray(sessionsList)) {
    sessionsList.forEach(s => {
      if (s.beanName && s.beanName.trim() !== '') {
        names.add(s.beanName.trim());
      }
    });
  }
  
  datalist.innerHTML = '';
  Array.from(names).sort().forEach(name => {
    const opt = document.createElement('option');
    opt.value = name;
    datalist.appendChild(opt);
  });
}

// MARK: - 로컬 파일 보관함 연동 (저장 목록 로드)
async function loadSavedSessions() {
  sessionsList = await window.api.loadSessions();
  updateBeanNameDatalist();
  const listContainer = document.getElementById('session-list');
  listContainer.innerHTML = '';
  
  if (sessionsList.length === 0) {
    listContainer.innerHTML = '<div class="empty-list">저장된 기록이 없습니다.</div>';
    return;
  }
  
  sessionsList.forEach(session => {
    const item = document.createElement('div');
    item.className = 'session-item';
    
    const displayDate = formatDate(session.date);
    
    item.innerHTML = `
      <div class="session-info">
        <span class="session-bean">${session.beanName || '원두명 미입력'} (${session.beanWeight || '0'}g)</span>
        <span class="session-date">${displayDate}</span>
      </div>
      <div class="session-actions">
        <button class="btn-icon btn-rename" title="이름 변경">
          <svg class="action-svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 1 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
        </button>
        <button class="btn-icon btn-delete" title="삭제">
          <svg class="action-svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
        </button>
      </div>
    `;
    
    item.addEventListener('click', (e) => {
      if (e.target.closest('.btn-rename') || e.target.closest('.btn-delete')) return;
      openReportModal(session);
    });
    
    item.querySelector('.btn-rename').addEventListener('click', (e) => {
      e.stopPropagation();
      const newName = prompt('새로운 원두명 입력:', session.beanName);
      if (newName !== null) {
        const updated = { ...session, beanName: newName };
        const oldFileName = session.filename || getFileNameForSession(session);
        window.api.deleteSession(oldFileName).then((delRes) => {
          if (delRes && delRes.success) {
            window.api.saveSession(updated).then((saveRes) => {
              if (saveRes && saveRes.success) {
                loadSavedSessions();
              } else {
                alert('원두명 저장 실패: ' + (saveRes ? saveRes.error : '알 수 없는 오류'));
              }
            });
          } else {
            alert('이전 기록 수정 대기 실패: ' + (delRes ? delRes.error : '알 수 없는 오류'));
          }
        });
      }
    });

    item.querySelector('.btn-delete').addEventListener('click', (e) => {
      e.stopPropagation();
      if (confirm(`'${session.beanName}' 기록을 영구 삭제하시겠습니까?`)) {
        const filename = session.filename || getFileNameForSession(session);
        window.api.deleteSession(filename).then((res) => {
          if (res && res.success) {
            loadSavedSessions();
          } else {
            alert('기록 삭제 실패: ' + (res ? res.error : '알 수 없는 오류'));
          }
        });
      }
    });
    
    listContainer.appendChild(item);
  });
}

function getFileNameForSession(session) {
  const dateStr = session.date.replace(/[-T:.Z]/g, '').substring(0, 12);
  const safeBeanName = (session.beanName || 'unnamed').replace(/\s+/g, '_');
  return `${dateStr}_${safeBeanName}.json`;
}

// MARK: - 블루투스 연결 (Web Bluetooth API)
// MARK: - 블루투스 연결 (Web Bluetooth API)
async function connectBluetooth() {
  if (isMockRoasting) {
    alert("모의 로스팅 모드가 활성화되어 있습니다. 먼저 모의 종료를 진행해 주세요.");
    return;
  }
  const btn = document.getElementById('btn-connect');
  
  // 이미 연결된 상태라면 연결 해제 수행
  if (bluetoothDevice) {
    disconnectBluetooth();
    return;
  }

  try {
    const list = await window.api.loadRegisteredDevices();
    if (!list || list.length === 0) {
      alert("등록된 보카보카 장치가 없습니다.\n우측의 '블루투스 장치 검색' 버튼을 눌러 검색기 창에서 장치를 먼저 검색하고 보카보카 장치로 등록해 주세요.");
      return;
    }
    
    showDeviceSelectModal(list);
  } catch (err) {
    console.error('Failed to load registered devices:', err);
    // 폴백: 리스트 로드에 실패 시 기본 무조건 연결 시도
    startWebBluetoothConnection(null);
  }
}

// 등록 장치 선택 모달 출력
function showDeviceSelectModal(list) {
  const modal = document.getElementById('device-select-modal');
  const container = document.getElementById('device-select-list');
  container.innerHTML = '';
  
  list.forEach(device => {
    const item = document.createElement('div');
    item.className = 'device-select-item';
    item.innerHTML = `
      <div class="device-select-info">
        <span class="device-select-nickname">${device.nickname}</span>
        <span class="device-select-name">${device.name} (${device.id})</span>
      </div>
      <button class="btn-device-connect-pill">연결</button>
    `;
    
    // 버튼 클릭 핸들러
    item.querySelector('.btn-device-connect-pill').addEventListener('click', (e) => {
      e.stopPropagation();
      modal.classList.remove('active');
      startWebBluetoothConnection(device);
    });
    
    // 카드 자체 클릭 핸들러
    item.addEventListener('click', () => {
      modal.classList.remove('active');
      startWebBluetoothConnection(device);
    });
    
    container.appendChild(item);
  });
  
  openModal(modal);
}

// 실제 Web Bluetooth API 기반 연결 개시
async function startWebBluetoothConnection(device) {
  const btn = document.getElementById('btn-connect');
  const indicator = document.getElementById('connection-status');
  const statusLabel = document.getElementById('device-status-text');
  
  btn.innerText = "연결 중...";
  statusLabel.innerText = `${device ? device.nickname : '장치'} 연결 중...`;
  
  try {
    if (device) {
      // 메인 프로세스에 타겟 기기 ID 및 이름 세팅하고 noble 리소스 강제 해제 요청
      window.api.setTargetDevice(device.id, device.name);
      // noble 연결이 안전하게 해제되고 기기가 다시 광고 방송을 시작할 수 있도록 1.5초 대기
      await new Promise(resolve => setTimeout(resolve, 1500));
    }
    
    const requestOptions = {
      optionalServices: [
        '0000ffe0-0000-1000-8000-00805f9b34fb',
        '6e400001-b5a3-f393-e0a9-e50e24dcca9e'
      ]
    };
    
    if (device && device.name) {
      requestOptions.filters = [
        { name: device.name }
      ];
    } else {
      requestOptions.filters = [
        { namePrefix: 'Boca' },
        { namePrefix: 'BT' },
        { namePrefix: 'PRL' }
      ];
    }

    bluetoothDevice = await navigator.bluetooth.requestDevice(requestOptions);

    const server = await bluetoothDevice.gatt.connect();
    
    let service = null;
    let charUuid = null;
    
    // 1. Nordic UART Service (NUS) 시도
    try {
      service = await server.getPrimaryService('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
      charUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
      console.log('Nordic UART Service (NUS) 서비스 획득 성공');
    } catch (nusErr) {
      // 2. 실패 시 기존 Custom Serial Service (ffe0) 시도
      try {
        service = await server.getPrimaryService('0000ffe0-0000-1000-8000-00805f9b34fb');
        charUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
        console.log('Custom Serial Service (ffe0) 서비스 획득 성공');
      } catch (ffeErr) {
        throw new Error('호환되는 블루투스 서비스(Nordic NUS 또는 Custom Serial ffe0)를 찾을 수 없습니다.');
      }
    }
    
    bluetoothCharacteristic = await service.getCharacteristic(charUuid);
    
    await bluetoothCharacteristic.startNotifications();
    bluetoothCharacteristic.addEventListener('characteristicvaluechanged', handleBluetoothData);
    
    bluetoothDevice.addEventListener('gattserverdisconnected', onBluetoothDisconnected);

    // 모든 GATT 서비스 및 알림 구독이 완결된 후에 UI를 성공으로 변경
    indicator.className = "status-indicator connected";
    statusLabel.innerText = `${device ? device.nickname : bluetoothDevice.name} 연결 성공 (실시간 데이터 대기 중)`;
    btn.innerText = "연결 해제";

  } catch (err) {
    console.error('BLE connection failed:', err);
    alert('블루투스 연결에 실패했습니다: ' + err.message + '\n\n장치가 켜져 있는지, 혹은 다른 앱에 연결되어 있지 않은지 확인해 주세요.');
    bluetoothDevice = null;
    bluetoothCharacteristic = null;
    onBluetoothDisconnected();
  }
}

function disconnectBluetooth() {
  if (bluetoothDevice) {
    if (bluetoothDevice.gatt && bluetoothDevice.gatt.connected) {
      bluetoothDevice.gatt.disconnect();
    }
    bluetoothDevice = null;
  }
  bluetoothCharacteristic = null;
  onBluetoothDisconnected();
}

function handleBluetoothData(event) {
  const value = event.target.value;
  if (value.byteLength === 10) {
    const head0 = value.getUint8(0);
    const head1 = value.getUint8(1);
    const foot8 = value.getUint8(8);
    const foot9 = value.getUint8(9);
    
    if (head0 === 0xFE && head1 === 0xEF && foot8 === 0xEF && foot9 === 0xFE) {
      const rawVal = (value.getUint8(4) << 8) | value.getUint8(5);
      const tempCelsius = (rawVal - 42.0) / 32.0;
      onTemperatureUpdate(parseFloat(tempCelsius.toFixed(1)));
    }
  }
}

function onBluetoothDisconnected() {
  const btn = document.getElementById('btn-connect');
  const indicator = document.getElementById('connection-status');
  const statusLabel = document.getElementById('device-status-text');
  
  indicator.className = "status-indicator disconnected";
  statusLabel.innerText = "BocaBoca250BT 연결 대기 중 ('연결하기' 버튼 누르세요)";
  btn.innerText = "연결하기";
  
  bluetoothDevice = null;
  bluetoothCharacteristic = null;
}

// MARK: - 모의 로스팅 시뮬레이터 엔진
function toggleMockRoasting() {
  if (isMockRoasting) {
    stopMockRoasting();
  } else {
    openMockSessionSelectModal();
  }
}

function openMockSessionSelectModal() {
  const modal = document.getElementById('mock-session-select-modal');
  const container = document.getElementById('mock-session-select-list');
  container.innerHTML = '';
  
  if (!sessionsList || sessionsList.length === 0) {
    const noData = document.createElement('div');
    noData.style.padding = '20px';
    noData.style.textAlign = 'center';
    noData.style.color = 'var(--text-tertiary)';
    noData.style.fontSize = '12px';
    noData.style.lineHeight = '1.6';
    noData.innerText = '저장된 이전 로스팅 기록이 없습니다.\n모의 로스팅을 진행하려면 실제 로스팅 기록이 1개 이상 필요합니다.';
    container.appendChild(noData);
  } else {
    sessionsList.forEach(session => {
      const item = document.createElement('div');
      item.className = 'device-select-item';
      
      const displayDate = formatDate(session.date);
      item.innerHTML = `
        <div class="device-select-info" style="text-align: left;">
          <span class="device-select-nickname" style="font-weight: 700;">${session.beanName || '원두명 미입력'}</span>
          <span class="device-select-name" style="font-size: 11px; color: var(--text-tertiary);">${displayDate} (${session.beanWeight || 0}g, DTR: ${session.finalDTR ? session.finalDTR.toFixed(1) : 0}%)</span>
        </div>
        <button class="btn-device-connect-pill">선택</button>
      `;
      
      item.querySelector('.btn-device-connect-pill').addEventListener('click', (e) => {
        e.stopPropagation();
        modal.classList.remove('active');
        openMockStartConfirmModal(session);
      });
      
      item.addEventListener('click', () => {
        modal.classList.remove('active');
        openMockStartConfirmModal(session);
      });
      
      container.appendChild(item);
    });
  }
  
  openModal(modal);
}

function openMockStartConfirmModal(session) {
  if (!session) return;
  tempSelectedSession = session;
  
  const modal = document.getElementById('mock-start-modal');
  
  document.getElementById('mock-start-bean-name').innerText = session.beanName || '원두명 미입력';
  document.getElementById('mock-start-bean-weight').innerText = session.beanWeight ? `${session.beanWeight}g` : '미입력';
  document.getElementById('mock-start-preheat-temp').innerText = session.preheatTemp ? `${session.preheatTemp}°C` : '미입력';
  
  const roastPoints = (session.graphPoints || []).filter(p => p.relativeTime >= 0);
  if (roastPoints.length > 0) {
    const maxTime = roastPoints[roastPoints.length - 1].relativeTime;
    document.getElementById('mock-start-duration').innerText = formatTime(maxTime);
  } else {
    document.getElementById('mock-start-duration').innerText = '알 수 없음';
  }
  
  openModal(modal);
}

function startMockRoasting(session) {
  if (!session) return;
  if (bluetoothDevice) {
    disconnectBluetooth();
  }
  
  isMockRoasting = true;
  mockSelectedSession = session;
  mockRoastingSeconds = 0;
  
  // 시작 온도 부드러운 전이 세팅 ( jump 방지 )
  mockTemperature = 25.0;
  if (session.graphPoints) {
    const chargeEvent = (session.events || []).find(e => e.type === '투입');
    const originalChargeTime = chargeEvent ? chargeEvent.elapsedSeconds : 0;
    
    const preheatPoints = session.graphPoints.filter(p => p.relativeTime < originalChargeTime).sort((a, b) => a.relativeTime - b.relativeTime);
    if (preheatPoints.length > 0) {
      mockTemperature = preheatPoints[0].temperature;
    } else {
      const roastPoints = session.graphPoints.filter(p => p.relativeTime >= originalChargeTime).sort((a, b) => a.relativeTime - b.relativeTime);
      if (roastPoints.length > 0) {
        mockTemperature = roastPoints[0].temperature;
      }
    }
  }
  
  const indicator = document.getElementById('connection-status');
  const statusLabel = document.getElementById('device-status-text');
  const btnConnect = document.getElementById('btn-connect');
  const btnMock = document.getElementById('btn-mock-roast');
  
  indicator.className = "status-indicator connected";
  
  statusLabel.innerText = `[모의 로스팅: ${session.beanName || '기록'}] 재생 중`;
  
  if (session.beanName) document.getElementById('input-bean-name').value = session.beanName;
  if (session.beanWeight) document.getElementById('input-bean-weight').value = session.beanWeight;
  if (session.preheatTemp) document.getElementById('input-preheat-temp').value = session.preheatTemp;
  if (session.targetDTR) {
    document.getElementById('range-dtr').value = session.targetDTR;
    document.getElementById('val-target-dtr').value = parseFloat(session.targetDTR).toFixed(1);
  }
  
  btnConnect.innerText = "연결하기";
  btnConnect.classList.add('disabled');
  btnMock.innerText = "모의 종료";
  btnMock.classList.add('btn-connect-pill');
  btnMock.classList.remove('btn-outline-pill');
  
  // 배속UI 노출, 일시정지 버튼 노출 및 값 셋팅
  const speedGroup = document.getElementById('mock-speed-group');
  if (speedGroup) speedGroup.style.display = 'inline-flex';
  const pauseBtn = document.getElementById('btn-mock-pause');
  if (pauseBtn) pauseBtn.style.display = 'inline-block';
  isMockPaused = false;
  mockSpeedMultiplier = parseInt(document.getElementById('sel-mock-speed').value) || 1;
  
  if (mockInterval) clearInterval(mockInterval);
  mockInterval = setInterval(simulateMockData, 1000 / mockSpeedMultiplier);
  
  // 모의 로스팅 시작 버튼 클릭 시 예열 자동 시작
  triggerPreheating();
}

function stopMockRoasting() {
  isMockRoasting = false;
  isMockPaused = false;
  mockSelectedSession = null;
  tempSelectedSession = null;
  if (mockInterval) {
    clearInterval(mockInterval);
    mockInterval = null;
  }
  
  // 배속UI, 일시정지 버튼 미노출
  const speedGroup = document.getElementById('mock-speed-group');
  if (speedGroup) speedGroup.style.display = 'none';
  const pauseBtn = document.getElementById('btn-mock-pause');
  if (pauseBtn) { pauseBtn.style.display = 'none'; pauseBtn.textContent = '일시정지'; }
  
  const indicator = document.getElementById('connection-status');
  const statusLabel = document.getElementById('device-status-text');
  const btnConnect = document.getElementById('btn-connect');
  const btnMock = document.getElementById('btn-mock-roast');
  
  indicator.className = "status-indicator disconnected";
  statusLabel.innerText = "BocaBoca250BT 연결 대기 중 ('연결하기' 버튼 누르세요)";
  btnConnect.innerText = "연결하기";
  btnConnect.classList.remove('disabled');
  btnMock.innerText = "모의 로스팅";
  btnMock.classList.remove('btn-connect-pill');
  btnMock.classList.add('btn-outline-pill');
  
  if (isPreheating || isRoasting) {
    triggerCancelRoast();
  }
}

function toggleMockPause() {
  if (!isMockRoasting) return;
  isMockPaused = !isMockPaused;
  const pauseBtn = document.getElementById('btn-mock-pause');
  if (isMockPaused) {
    if (pauseBtn) { pauseBtn.textContent = '▶ 재개'; pauseBtn.style.background = '#c6f6d5'; pauseBtn.style.borderColor = '#9ae6b4'; pauseBtn.style.color = '#276749'; }
    document.getElementById('lbl-roast-state').innerText = (document.getElementById('lbl-roast-state').innerText || '') + ' (일시정지)';
  } else {
    if (pauseBtn) { pauseBtn.textContent = '일시정지'; pauseBtn.style.background = '#edf2f7'; pauseBtn.style.borderColor = '#cbd5e0'; pauseBtn.style.color = '#4a5568'; }
    const lbl = document.getElementById('lbl-roast-state');
    lbl.innerText = lbl.innerText.replace(' (일시정지)', '');
  }
}

function simulateMockData() {
  if (!isMockRoasting) return;
  if (isMockPaused) return;
  if (!mockSelectedSession) return;
  
  if (elapsedSeconds % 10 === 0) {
    console.log(`[Mock Sim] elapsedSeconds:${elapsedSeconds} isPreheating:${isPreheating} isRoasting:${isRoasting}`);
  }
  
  const pts = mockSelectedSession.graphPoints || [];
  
  // 이전 기록에서 실제 생두 투입 시각(초) 찾기
  const chargeEvent = (mockSelectedSession.events || []).find(e => e.type === '투입');
  const isShifted = pts.some(p => p.relativeTime < 0);
  
  // preheatDuration (예열 기간) 계산
  let preheatDuration = 0;
  if (isShifted) {
    const minRel = Math.min(...pts.map(p => p.relativeTime));
    preheatDuration = minRel < 0 ? Math.abs(minRel) : 0;
  } else {
    preheatDuration = chargeEvent ? chargeEvent.elapsedSeconds : 0;
  }
  
  // 시뮬레이터 elapsedSeconds(0부터 증가)를 세션의 relativeTime 스케일로 매핑
  let targetSessionTime = 0;
  if (isShifted) {
    // 예열은 -preheatDuration ~ 0, 로스팅은 0 ~ max
    targetSessionTime = elapsedSeconds - preheatDuration;
  } else {
    // 예열은 0 ~ preheatDuration, 로스팅은 preheatDuration ~ max
    targetSessionTime = elapsedSeconds;
  }

  // 예열 단계
  if (isPreheating && !isRoasting) {
    // 투입 시각 이전의 포인트들만 추출하여 예열 단계 재생
    const preheatPoints = isShifted 
      ? pts.filter(p => p.relativeTime < 0).sort((a, b) => a.relativeTime - b.relativeTime)
      : pts.filter(p => p.relativeTime < preheatDuration).sort((a, b) => a.relativeTime - b.relativeTime);
      
    if (preheatPoints.length > 0) {
      // targetSessionTime에 가장 가까운 예열 포인트 매핑
      const closestPt = preheatPoints.reduce((prev, curr) => 
        Math.abs(curr.relativeTime - targetSessionTime) < Math.abs(prev.relativeTime - targetSessionTime) ? curr : prev
      );
      mockTemperature = closestPt.temperature;
      
      // 원본 예열 완료 시각(preheatDuration)에 도달하면 자동으로 생두 투입 트리거
      if (elapsedSeconds >= preheatDuration) {
        triggerCharging();
      }
    }
  }
  
  // 로스팅 단계
  else if (isRoasting) {
    // 투입 시각 이후의 포인트들만 추출하여 로스팅 단계 재생
    const roastPoints = isShifted
      ? pts.filter(p => p.relativeTime >= 0).sort((a, b) => a.relativeTime - b.relativeTime)
      : pts.filter(p => p.relativeTime >= preheatDuration).sort((a, b) => a.relativeTime - b.relativeTime);
    
    if (roastPoints.length > 0) {
      // targetSessionTime에 매핑되는 포인트 매칭
      const closestPt = roastPoints.reduce((prev, curr) => 
        Math.abs(curr.relativeTime - targetSessionTime) < Math.abs(prev.relativeTime - targetSessionTime) ? curr : prev
      );
      mockTemperature = closestPt.temperature;
      
      // 열량(Heat) 조절 상태 동기화 및 UI 갱신
      if (closestPt.heat !== undefined && closestPt.heat !== null) {
        const originalHeat = parseInt(closestPt.heat);
        if (!isNaN(originalHeat) && originalHeat !== currentHeat) {
          currentHeat = originalHeat;
          pendingHeat = originalHeat;
          document.getElementById('range-heat').value = originalHeat;
          updateHeatDisplay(originalHeat);
          addEvent('열량 조절');
        }
      }
      
      // 1차 팝 / 2차 팝 자동 이벤트 재생 트리거 (보정/정렬된 경과시간 기준)
      const mockEvents = mockSelectedSession.events || [];
      
      const pop1Ev = mockEvents.find(e => e.type === '1차 팝');
      if (pop1Ev && Math.round(pop1Ev.elapsedSeconds) === Math.round(targetSessionTime)) {
        const btnPop1 = document.getElementById('btn-pop1');
        if (btnPop1 && !btnPop1.classList.contains('disabled')) {
          addEvent('1차 팝');
        }
      }
      
      const pop2Ev = mockEvents.find(e => e.type === '2차 팝');
      if (pop2Ev && Math.round(pop2Ev.elapsedSeconds) === Math.round(targetSessionTime)) {
        const btnPop2 = document.getElementById('btn-pop2');
        if (btnPop2 && !btnPop2.classList.contains('disabled')) {
          addEvent('2차 팝');
        }
      }
      
      // 기록된 최대 로스팅 시간에 도달하면 자동으로 배출(로스팅 종료) 처리
      const maxSavedRoastTime = roastPoints[roastPoints.length - 1].relativeTime;
      if (targetSessionTime >= maxSavedRoastTime) {
        triggerFinishing();
      }
    }
  }
  
  onTemperatureUpdate(parseFloat(mockTemperature.toFixed(1)));
}

// MARK: - 실시간 로스팅 제어 및 데이터 기록 연동
function triggerPreheating() {
  // 기기 연결 미완료 상태인 경우 예열 차단 (모의 로스팅 모드 제외)
  if (!bluetoothDevice && !isMockRoasting) {
    alert("기기 연결을 먼저 완료해 주세요.");
    return;
  }

  if (isPreheating) return;
  isPreheating = true;
  isRoasting = false;
  elapsedSeconds = 0;
  chargeTimeOffset = 0;
  isSaved = false;
  preheatAlertPlay = false;
  dtrAlertPlay = false;
  
  resetTimetable();
  
  // 차트 X축 리셋
  mainChart.options.scales.x.min = 0;
  mainChart.options.scales.x.max = 900;
  absoluteMaxX = 900;
  zoomPercent = 100;
  document.getElementById('lbl-zoom-percent').innerText = '100% (Fit)';
  
  activeSession.id = generateUUID();
  activeSession.date = new Date().toISOString();
  activeSession.events = [];
  activeSession.graphPoints = [];
  activeSession.memo = '';
  activeSession.processing = document.getElementById('select-processing').value;
  activeSession.purpose = document.getElementById('select-purpose').value;
  
  // 사용자 설정
  activeSession.beanName = document.getElementById('input-bean-name').value;
  activeSession.beanWeight = document.getElementById('input-bean-weight').value;
  activeSession.preheatTemp = document.getElementById('input-preheat-temp').value;
  activeSession.targetDTR = document.getElementById('range-dtr').value;

  // 차트 데이터 리셋
  mainChart.data.datasets[0].label = '예열 온도';
  mainChart.data.datasets[0].data = [];
  mainChart.data.datasets[1].data = [];
  mainChart.data.datasets[4].data = [];
  mainChart.update();
  
  document.getElementById('log-list').innerHTML = '';
  
  addEvent('예열 시작');
  
  // UI 비활성화/활성화 토글
  document.getElementById('btn-preheat').classList.add('disabled');
  document.getElementById('btn-charge').classList.remove('disabled');
  document.getElementById('btn-finish').classList.remove('disabled');
  document.getElementById('lbl-roast-state').innerText = "예열 중";
  
  // 다시 시작 / 취소 버튼 상태 해제
  document.getElementById('btn-reset-session').classList.remove('disabled');
  document.getElementById('btn-cancel-roast').classList.remove('disabled');
  
  updateShortcutHints();
}

function triggerCharging() {
  if (!isPreheating || isRoasting) return;
  isRoasting = true;
  
  // 생두 투입 시점 0초로 보정
  chargeTimeOffset = elapsedSeconds;
  
  // X축 최소값 보정 (예열 그래프가 좌측 음수 영역에 표시되도록 설정)
  mainChart.options.scales.x.min = -chargeTimeOffset;
  mainChart.options.scales.x.max = 600;
  absoluteMaxX = 600;
  zoomPercent = 100;
  document.getElementById('lbl-zoom-percent').innerText = '100% (Fit)';
  mainChart.data.datasets[0].label = '온도';
  
  // TP 감지용 변수 초기화
  tpDetected = false;
  minTempAfterCharge = parseFloat(document.getElementById('metric-temp').innerText) || 999;
  minTempTime = 0;
  tempRiseCount = 0;
  lastTemp = minTempAfterCharge;
  dtrAlertPlay = false;
  
  if (isMockRoasting) {
    mockRoastingSeconds = 0;
    mockTemperature = parseFloat(document.getElementById('metric-temp').innerText) || 200.0;
  }
  
  activeSession.graphPoints = activeSession.graphPoints.map(pt => {
    pt.relativeTime = pt.relativeTime - chargeTimeOffset;
    return pt;
  });
  
  activeSession.events = activeSession.events.map(ev => {
    ev.elapsedSeconds = ev.elapsedSeconds - chargeTimeOffset;
    return ev;
  });
  
  recalculateAllRoR();
  
  addEvent('투입');
  
  document.getElementById('btn-charge').classList.add('disabled');
  document.getElementById('btn-pop1').classList.remove('disabled');
  document.getElementById('lbl-roast-state').innerText = "로스팅 중";
  
  updateShortcutHints();
}

function triggerFinishing() {
  if (!isPreheating) return;
  addEvent('종료');
  
  isPreheating = false;
  isRoasting = false;
  
  mainChart.data.datasets[0].label = '예열 온도';
  mainChart.data.datasets[4].data = [];
  mainChart.update();
  
  document.getElementById('btn-preheat').classList.remove('disabled');
  document.getElementById('btn-charge').classList.add('disabled');
  document.getElementById('btn-pop1').classList.add('disabled');
  document.getElementById('btn-pop2').classList.add('disabled');
  document.getElementById('btn-finish').classList.add('disabled');
  document.getElementById('lbl-roast-state').innerText = "대기";
  
  document.getElementById('btn-reset-session').classList.add('disabled');
  document.getElementById('btn-cancel-roast').classList.add('disabled');
  
  calculateSessionSummary();
  openReportModal(activeSession);
  
  updateShortcutHints();
}

// 다시 시작 버튼 복구
function triggerResetSession() {
  if (!confirm('현재 로스팅 데이터를 지우고 예열 단계부터 다시 시작하시겠습니까?')) return;
  
  isPreheating = false;
  isRoasting = false;
  
  document.getElementById('btn-preheat').classList.remove('disabled');
  document.getElementById('btn-charge').classList.add('disabled');
  document.getElementById('btn-pop1').classList.add('disabled');
  document.getElementById('btn-pop2').classList.add('disabled');
  document.getElementById('btn-finish').classList.add('disabled');
  document.getElementById('lbl-roast-state').innerText = "대기";
  
  updateShortcutHints();
  triggerPreheating();
}

// 로스팅 취소 버튼 복구
function triggerCancelRoast() {
  if (!confirm('진행 중인 로스팅 세션 또는 가이드를 취소하고 대기 상태로 되돌아가시겠습니까?')) return;
  
  isPreheating = false;
  isRoasting = false;
  elapsedSeconds = 0;
  chargeTimeOffset = 0;
  preheatAlertPlay = false;
  tpDetected = false;
  dtrAlertPlay = false;
  
  // 차트 X축 리셋
  mainChart.options.scales.x.min = 0;
  mainChart.options.scales.x.max = 900;
  absoluteMaxX = 900;
  zoomPercent = 100;
  document.getElementById('lbl-zoom-percent').innerText = '100% (Fit)';
  
  mainChart.data.datasets[0].label = '예열 온도';
  
  document.getElementById('btn-preheat').classList.remove('disabled');
  document.getElementById('btn-charge').classList.add('disabled');
  document.getElementById('btn-pop1').classList.add('disabled');
  document.getElementById('btn-pop2').classList.add('disabled');
  document.getElementById('btn-finish').classList.add('disabled');
  document.getElementById('lbl-roast-state').innerText = "대기";
  
  document.getElementById('btn-reset-session').classList.add('disabled');
  document.getElementById('btn-cancel-roast').classList.add('disabled');
  
  // 차트 및 가이드 초기화
  mainChart.data.datasets[0].data = [];
  mainChart.data.datasets[1].data = [];
  mainChart.data.datasets[4].data = [];
  
  if (guideSession) {
    guideSession = null;
    mainChart.data.datasets[2].data = [];
    mainChart.data.datasets[3].data = [];
    mainChart.options.scales.x.max = 900; // 기본 15분 복원
    absoluteMaxX = 900;
  }
  
  mainChart.update();
  resetTimetable();
  
  document.getElementById('log-list').innerHTML = '<div class="log-placeholder">진행 중인 로그가 없습니다. 예열 시작 버튼을 누르면 기록이 시작됩니다.</div>';
  
  // ETA 리셋
  document.getElementById('lbl-eta-time').innerText = '--:--';
  
  updateShortcutHints();
}

// 실시간 패킷 온도 수신 콜백
function onTemperatureUpdate(temp) {
  document.getElementById('metric-temp').innerHTML = `${temp.toFixed(1)}<span class="unit">°C</span>`;
  
  if (isPreheating) {
    elapsedSeconds++;
    const relativeSec = elapsedSeconds - chargeTimeOffset;
    
    // 예열 시간 vs 로스팅 시간 분류 계산
    if (!isRoasting) {
      document.getElementById('metric-preheat-time').innerText = formatTime(elapsedSeconds);
      
      // 예열 완료 감지 및 알림음 재생
      const targetPreheat = parseFloat(activeSession.preheatTemp);
      if (!isNaN(targetPreheat) && temp >= targetPreheat && !preheatAlertPlay) {
        preheatAlertPlay = true;
        playVoice('Voices/02.wav', 'Sound/alert02.mp3');
        document.getElementById('lbl-roast-state').innerText = "예열 완료";
      }
    } else {
      document.getElementById('metric-preheat-time').innerText = formatTime(chargeTimeOffset);
    }
    
    // Turning Point (TP) 감지 및 보정 로직
    if (isRoasting && !tpDetected && relativeSec >= 0) {
      if (temp < minTempAfterCharge) {
        minTempAfterCharge = temp;
        minTempTime = relativeSec;
        tempRiseCount = 0;
      } else if (temp > lastTemp) {
        if (relativeSec > 15) {
          tempRiseCount++;
          
          // 1. 처음 온도 상승 감지 시 측정치 임시 표시
          if (tempRiseCount === 1) {
            if (!activeSession.events.some(e => e.type === 'TP')) {
              addEvent('TP', minTempTime, minTempAfterCharge);
            }
          }
          
          // 2. 온도가 본격적으로 상승 시 보정 터닝 포인트로 확정
          if (tempRiseCount >= 6 || (temp - minTempAfterCharge) >= 1.5) {
            tpDetected = true;
            
            // 기존 TP 이벤트를 보정 터닝 포인트로 수정
            const tpEv = activeSession.events.find(e => e.type === 'TP');
            if (tpEv) {
              tpEv.elapsedSeconds = minTempTime;
              tpEv.temperature = minTempAfterCharge;
              tpEv.description = `보정 터닝 포인트: ${minTempAfterCharge.toFixed(1)}°C`;
              updateLiveLogTable();
              
              // 확정 시 음성 안내 재생
              playVoice('Voices/03.wav', 'Sound/alarm01.mp3');
            }
          }
        }
      } else if (temp < lastTemp) {
        tempRiseCount = 0;
      }
      lastTemp = temp;
    }
    
    // RoR 실시간 계산 (생두 투입 후 1분(60초)부터 계산 시작, 마이너스 값 포함)
    let calculatedRoR = null;
    if (isRoasting && relativeSec >= 60) {
      const targetTime = relativeSec - filterWindow;
      const prevPoint = activeSession.graphPoints.find(pt => pt.relativeTime >= targetTime);
      if (prevPoint) {
        const tempDiff = temp - prevPoint.temperature;
        const timeDiff = relativeSec - prevPoint.relativeTime;
        const rawRoR = (tempDiff / (timeDiff || 1)) * 60;
        
        // EMA 필터
        const lastPt = activeSession.graphPoints[activeSession.graphPoints.length - 1];
        const lastRor = (lastPt && lastPt.ror !== null) ? lastPt.ror : 0;
        const smoothed = (lastRor * filterStrength / 100.0) + (rawRoR * (1 - filterStrength / 100.0));
        calculatedRoR = parseFloat(smoothed.toFixed(2));
      }
    }
    
    // RoR 표시
    document.getElementById('metric-ror').innerHTML = `${calculatedRoR !== null ? (calculatedRoR >= 0 ? '+' : '') + calculatedRoR.toFixed(1) : '—'}<span class="unit">°C/min</span>`;
    
    // 실시간 DTR 계산 및 갱신
    let calculatedDTR = 0.0;
    if (isRoasting) {
      const firstPop = activeSession.events.find(e => e.type === '1차 팝');
      if (firstPop) {
        const devSec = relativeSec - firstPop.elapsedSeconds;
        const totalSec = relativeSec; // 투입 시점 0초 기준 누적 시간
        if (totalSec > 0 && devSec > 0) {
          calculatedDTR = (devSec / totalSec) * 100.0;
        }
      }
    }
    document.getElementById('metric-dtr').innerHTML = `${calculatedDTR.toFixed(1)}<span class="unit">%</span>`;

    // 목표 DTR 도달 알림음 재생 (Voices/08.wav)
    if (isRoasting && calculatedDTR > 0) {
      const targetDtrVal = parseFloat(activeSession.targetDTR);
      if (!isNaN(targetDtrVal) && calculatedDTR >= targetDtrVal && !dtrAlertPlay) {
        dtrAlertPlay = true;
        playVoice('Voices/08.wav', 'Sound/alert03.mp3');
      }
    }

    // 포인트 수집
    activeSession.graphPoints.push({
      id: generateUUID(),
      relativeTime: relativeSec,
      temperature: temp,
      heat: currentHeat,
      ror: calculatedRoR
    });
    
    // 차트 실시간 갱신
    mainChart.data.datasets[0].data.push({ x: relativeSec, y: temp });
    mainChart.data.datasets[1].data.push({ x: relativeSec, y: calculatedRoR });
    
    // 예상 온도선 점선 데이터 갱신
    if (isRoasting && tpDetected && calculatedRoR !== null) {
      const futureTime = Math.max(relativeSec + 120, absoluteMaxX);
      const predictedTemp = temp + (calculatedRoR / 60) * (futureTime - relativeSec);
      mainChart.data.datasets[4].data = [
        { x: relativeSec, y: temp },
        { x: futureTime, y: predictedTemp }
      ];
    } else {
      mainChart.data.datasets[4].data = [];
    }
    
    // X축 자동 핏 (상태창/툴팁이 가림 없이 우측에 넉넉히 그려지도록 최소 90초 여백 버퍼 확보)
    const requiredMax = relativeSec + 90;
    const computedMax = Math.ceil(requiredMax / 60) * 60;
    if (computedMax > absoluteMaxX) {
      absoluteMaxX = computedMax;
      if (zoomPercent === 100) {
        mainChart.options.scales.x.max = absoluteMaxX;
      }
    }
    
    if (isRoasting) {
      updateTimetableFromPoints(activeSession.graphPoints);
    }
    
    updateY1AxisMax(mainChart);
    mainChart.update('none');
    
    // 실시간 ETA 갱신
    updateExpectedEtaTime();
    
    // 로스팅 시간 표시 및 예상 종료시간 결합 표기
    if (isRoasting) {
      const etaText = document.getElementById('lbl-eta-time').innerText;
      document.getElementById('metric-roast-time').innerHTML = `${formatTime(relativeSec)} <span class="eta-small" style="font-size: 0.6em; color: #a0aec0; margin-left: 6px; font-weight: normal;">(예상: ${etaText})</span>`;
    } else {
      document.getElementById('metric-roast-time').innerHTML = '00:00 <span class="eta-small" style="font-size: 0.6em; color: #a0aec0; margin-left: 6px; font-weight: normal;">(예상: --:--)</span>';
    }
  }
}

// 1차 팝 기준 ETA 예상 완료 시간 공식
function updateExpectedEtaTime() {
  if (!isRoasting) return;
  const firstPop = activeSession.events.find(e => e.type === '1차 팝');
  if (!firstPop) {
    document.getElementById('lbl-eta-time').innerText = '--:--';
    return;
  }
  
  const targetDtrVal = parseFloat(document.getElementById('range-dtr').value) / 100.0;
  const firstPopSeconds = firstPop.elapsedSeconds; // 1차 팝 도달 시간
  
  if (targetDtrVal < 1.0) {
    // 총 예상 로스팅 초 = 1차 팝 초 / (1 - 목표 DTR)
    const totalRoastSeconds = firstPopSeconds / (1 - targetDtrVal);
    document.getElementById('lbl-eta-time').innerText = formatTime(totalRoastSeconds);
    document.getElementById('lbl-eta-dtr').innerText = `목표 DTR ${(targetDtrVal * 100).toFixed(1)}%`;
  }
}

function playVoice(voiceFile, effectFile = null) {
  const isVoiceEnabled = document.getElementById('chk-voice-enable').checked;
  const fileToPlay = isVoiceEnabled ? voiceFile : effectFile;
  
  if (!fileToPlay) return;
  
  if (currentAudio) {
    try {
      currentAudio.pause();
      currentAudio.currentTime = 0;
    } catch (e) {
      console.error("Failed to pause current audio:", e);
    }
  }
  
  const volumeStep = parseInt(document.getElementById('rng-voice-volume').value);
  currentAudio = new Audio(fileToPlay);
  currentAudio.volume = volumeStep / 10.0;
  currentAudio.play().catch(err => console.error(`Audio play failed for ${fileToPlay}:`, err));
}

// 이벤트 추가 엔진
function addEvent(type, customSeconds = null, customTemp = null) {
  if (!isPreheating) return;
  
  const relativeSec = customSeconds !== null ? customSeconds : (elapsedSeconds - chargeTimeOffset);
  let temp = customTemp !== null ? customTemp : parseFloat(document.getElementById('metric-temp').innerText);
  if (isNaN(temp)) {
    temp = lastReceivedTemp || mockTemperature || 25.0;
  }
  
  let desc = "";
  if (type === '예열 시작') desc = "예열 시작 관련 내용 기록";
  else if (type === '투입') desc = "생두 투입 완료";
  else if (type === 'TP') desc = `터닝포인트(측정치): ${temp.toFixed(1)}°C`;
  else if (type === '1차 팝') desc = "1차 크랙 진행 감지";
  else if (type === '2차 팝') desc = "2차 크랙 진행 감지";
  else if (type === '종료') desc = "배출 및 로스팅 종료";
  else if (type === '열량 조절') desc = `열량 변경: ${currentHeat}단계`;

  const newEvent = {
    id: generateUUID(),
    elapsedSeconds: relativeSec,
    temperature: temp,
    heatValue: currentHeat,
    type,
    description: desc
  };
  
  activeSession.events.push(newEvent);
  
  // 소급 적용 이벤트(예: TP) 등으로 순서가 섞이지 않도록 정렬
  activeSession.events.sort((a, b) => a.elapsedSeconds - b.elapsedSeconds);
  
  updateLiveLogTable();
  
  // 상황별 음성 알림 연동
  if (type === '예열 시작') playVoice('Voices/01.wav', 'Sound/alert01.mp3');
  else if (type === 'TP') {
    if (tpDetected) {
      playVoice('Voices/03.wav', 'Sound/alarm01.mp3');
    }
  }
  else if (type === '투입') playVoice('Voices/04.wav');
  else if (type === '1차 팝') playVoice('Voices/05.wav', 'Sound/alarm02.mp3');
  else if (type === '2차 팝') playVoice('Voices/06.wav', 'Sound/alarm02.mp3');
  else if (type === '종료') playVoice('Voices/07.wav', 'Sound/alert04.mp3');
  
  // 1차 팝 시 2차 팝 버튼 해제
  if (type === '1차 팝') {
    document.getElementById('btn-pop1').classList.add('disabled');
    document.getElementById('btn-pop2').classList.remove('disabled');
    updateExpectedEtaTime();
  } else if (type === '2차 팝') {
    document.getElementById('btn-pop2').classList.add('disabled');
  }
  
  mainChart.update();
}

function updateLiveLogTable() {
  const container = document.getElementById('log-list');
  container.innerHTML = '';
  
  activeSession.events.forEach(ev => {
    const row = document.createElement('div');
    row.className = 'log-row';
    const times = getEventTimes(ev, activeSession.events);
    
    const tempStr = (ev.temperature !== null && ev.temperature !== undefined && !isNaN(ev.temperature))
      ? `${ev.temperature.toFixed(1)}°C`
      : '—';
    
    row.innerHTML = `
      <span>${times.total}</span>
      <span>${times.process}</span>
      <span><span class="event-badge ${getEventBadgeClass(ev.type)}">${ev.type}</span></span>
      <span>${tempStr}</span>
      <span>${ev.heatValue}</span>
      <span>${ev.description}</span>
    `;
    container.appendChild(row);
  });
  container.scrollTop = container.scrollHeight;
}

// MARK: - 2단계 안전제어식 열량 제어
function confirmHeatChange() {
  currentHeat = pendingHeat;
  
  if (bluetoothCharacteristic) {
    const packet = new Uint8Array([0xFE, 0xEF, 0x02, currentHeat, 0xEF, 0xFE]);
    bluetoothCharacteristic.writeValue(packet).catch(err => console.error(err));
  }
  
  addEvent('열량 조절');
}

// ROR Y축 최댓값/최솟값 동적 조절 함수
function updateY1AxisMax(chart) {
  if (!chart || !chart.data || !chart.data.datasets) return;
  
  let rorValues = [];
  chart.data.datasets.forEach(dataset => {
    if ((dataset.yAxisID === 'y1' || dataset.label === 'RoR' || dataset.label === '실시간 RoR' || dataset.label === '가이드 RoR') && dataset.data) {
      dataset.data.forEach(pt => {
        const yVal = (typeof pt === 'object' && pt !== null) ? pt.y : pt;
        if (yVal !== null && yVal !== undefined && !isNaN(yVal)) {
          // 비정상적인 노이즈 값(|y| > 60)은 제외
          if (Math.abs(yVal) <= 60) {
            rorValues.push(yVal);
          }
        }
      });
    }
  });
  
  let maxRor = rorValues.length > 0 ? Math.max(...rorValues) : 0;
  let minRor = rorValues.length > 0 ? Math.min(...rorValues) : 0;
  
  // ROR 최댓값: 기본 최소 40 유지, 초과 시 5단위 올림
  const calculatedMax = Math.max(40, Math.ceil(maxRor / 5) * 5);
  // ROR 최솟값: 기본 최대 0으로 두며, 마이너스 값 존재 시 5단위 내림 (최대 -15 기본 마진 설정)
  const calculatedMin = Math.min(0, Math.floor(minRor / 5) * 5);
  
  if (chart.options.scales && chart.options.scales.y1) {
    chart.options.scales.y1.min = calculatedMin;
    chart.options.scales.y1.max = calculatedMax;
    if (chart.options.scales.y1.ticks) {
      chart.options.scales.y1.ticks.stepSize = (calculatedMax - calculatedMin) / 5;
    }
  }
}

// 로스팅 타임테이블 초기화
function resetTimetable() {
  for (let s = 0; s <= 750; s += 30) {
    const el = document.getElementById(`tt-val-${s}`);
    if (el) el.innerText = '—';
  }
}

// 로스팅 타임테이블 데이터 적용
function updateTimetableFromPoints(points) {
  if (!points || points.length === 0) return;
  for (let s = 0; s <= 750; s += 30) {
    const el = document.getElementById(`tt-val-${s}`);
    if (!el) continue;
    
    // relativeTime이 s에 가장 가까운 포인트(1초 미만 오차)를 찾습니다.
    const pt = points.find(p => Math.abs(p.relativeTime - s) < 1);
    if (pt && pt.temperature !== undefined && pt.temperature !== null) {
      el.innerText = pt.temperature.toFixed(1);
    }
  }
}

// 상세 리포트 모달 타임테이블 데이터 적용 및 초기화
function updateModalTimetable(points) {
  for (let s = 0; s <= 750; s += 30) {
    const el = document.getElementById(`modal-tt-val-${s}`);
    if (el) el.innerText = '—';
  }
  if (!points || points.length === 0) return;
  for (let s = 0; s <= 750; s += 30) {
    const el = document.getElementById(`modal-tt-val-${s}`);
    if (!el) continue;
    const pt = points.find(p => Math.abs(p.relativeTime - s) < 1);
    if (pt && pt.temperature !== undefined && pt.temperature !== null) {
      el.innerText = pt.temperature.toFixed(1);
    }
  }
}

// MARK: - RoR 전체 재계산 필터 엔진
function recalculateAllRoR() {
  const pts = activeSession.graphPoints;
  if (pts.length === 0) return;
  
  let lastRor = 0.0;
  for (let i = 0; i < pts.length; i++) {
    const pt = pts[i];
    
    // 액티브 세션 진행 중인 경우, 예열 단계에서는 RoR 계산 제외
    if (isPreheating && !isRoasting) {
      pt.ror = null;
      continue;
    }
    // 생두 투입 후 1분이 경과하지 않은 포인트는 계산 제외 (60초부터 계산 시작)
    if (pt.relativeTime < 60) {
      pt.ror = null;
      continue;
    }
    
    const targetTime = pt.relativeTime - filterWindow;
    let prevPt = null;
    for (let j = i - 1; j >= 0; j--) {
      if (pts[j].relativeTime >= targetTime) {
        prevPt = pts[j];
      } else {
        break;
      }
    }
    
    if (prevPt) {
      const tempDiff = pt.temperature - prevPt.temperature;
      const timeDiff = pt.relativeTime - prevPt.relativeTime;
      const rawRoR = (tempDiff / (timeDiff || 1)) * 60;
      const smoothed = (lastRor * filterStrength / 100.0) + (rawRoR * (1 - filterStrength / 100.0));
      pt.ror = parseFloat(smoothed.toFixed(2));
      lastRor = pt.ror;
    } else {
      pt.ror = null;
    }
  }
  
  mainChart.data.datasets[0].data = pts.map(p => ({ x: p.relativeTime, y: p.temperature }));
  mainChart.data.datasets[1].data = pts.map(p => ({ x: p.relativeTime, y: p.ror }));
  updateY1AxisMax(mainChart);
  mainChart.update();
  
  if (document.getElementById('report-modal').classList.contains('active')) {
    modalChart.data.datasets[0].data = pts.map(p => ({ x: p.relativeTime, y: p.temperature }));
    modalChart.data.datasets[1].data = pts.map(p => ({ x: p.relativeTime, y: p.ror }));
    updateY1AxisMax(modalChart);
    modalChart.update();
    updateModalTimetable(pts);
  }
}

function calculateSessionSummary() {
  const chargeEvent = activeSession.events.find(e => e.type === '투입');
  const firstPop = activeSession.events.find(e => e.type === '1차 팝');
  const finishEvent = activeSession.events.find(e => e.type === '종료');
  
  activeSession.chargeTemp = chargeEvent ? chargeEvent.temperature : null;
  activeSession.firstPopTemp = firstPop ? firstPop.temperature : null;
  activeSession.finishTemp = finishEvent ? finishEvent.temperature : null;
  
  if (chargeEvent && finishEvent) {
    activeSession.totalRoastSeconds = finishEvent.elapsedSeconds - chargeEvent.elapsedSeconds;
  } else {
    activeSession.totalRoastSeconds = null;
  }
  
  if (firstPop && finishEvent) {
    activeSession.devTimeSeconds = finishEvent.elapsedSeconds - firstPop.elapsedSeconds;
  } else {
    activeSession.devTimeSeconds = null;
  }
  
  if (activeSession.totalRoastSeconds && activeSession.devTimeSeconds) {
    activeSession.finalDTR = (activeSession.devTimeSeconds / activeSession.totalRoastSeconds) * 100.0;
  } else {
    activeSession.finalDTR = null;
  }
  
  // 예열 구간 복원을 위해 chargeTimeOffset(생두 투입 시점의 절대 경과 초)도 세션에 저장
  activeSession.chargeTimeOffset = chargeTimeOffset;
}

// MARK: - 모달 창 (리포트/상세 분석) 활성화
function openReportModal(sessionData) {
  activeSession = JSON.parse(JSON.stringify(sessionData));
  
  // 절대시간 형태(예열 시작=0, 투입=양수)로 저장된 구버전 데이터 호환:
  // 투입 시점을 0초로 강제 shift(보정)하여 예열 영역을 음수 시간대로 재구성합니다.
  const chargeEv = (activeSession.events || []).find(e => e.type === '투입');
  const isShifted = activeSession.graphPoints && activeSession.graphPoints.some(p => p.relativeTime < 0);
  const shiftOffset = (!isShifted && chargeEv) ? chargeEv.elapsedSeconds : 0;
  
  if (shiftOffset > 0) {
    activeSession.graphPoints = activeSession.graphPoints.map(pt => {
      pt.relativeTime = pt.relativeTime - shiftOffset;
      return pt;
    });
    activeSession.events = activeSession.events.map(ev => {
      ev.elapsedSeconds = ev.elapsedSeconds - shiftOffset;
      return ev;
    });
  }
  
  const modal = document.getElementById('report-modal');
  openModal(modal);
  
  document.getElementById('modal-date').innerText = formatDate(activeSession.date);
  document.getElementById('modal-title').innerHTML = `
    <svg class="inline-header-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 20V10"/><path d="M12 20V4"/><path d="M6 20v-6"/></svg>
    <span>리포트 상세: ${activeSession.beanName || '원두명 미입력'}</span>
  `;
  
  document.getElementById('modal-info-row').innerHTML = `
    <span><strong>투입량:</strong> ${activeSession.beanWeight || '0'}g</span> &nbsp;·&nbsp;
    <span><strong>예열 온도:</strong> ${activeSession.preheatTemp || '0'}°C</span> &nbsp;·&nbsp;
    <span><strong>목표 DTR:</strong> ${activeSession.targetDTR || '0'}%</span>
  `;
  
  document.getElementById('modal-metric-dtr').innerText = activeSession.finalDTR ? `${activeSession.finalDTR.toFixed(1)}%` : '—';
  document.getElementById('modal-metric-total').innerText = activeSession.totalRoastSeconds ? formatTime(activeSession.totalRoastSeconds) : '—';
  document.getElementById('modal-metric-dev').innerText = activeSession.devTimeSeconds ? formatTime(activeSession.devTimeSeconds) : '—';
  document.getElementById('modal-metric-finish').innerText = activeSession.finishTemp ? `${activeSession.finishTemp.toFixed(1)}°C` : '—';
  
  document.getElementById('modal-memo-text').value = activeSession.memo || '';
  
  // 세션에 chargeTimeOffset이 저장돼 있으면 그대로 사용,
  // 예열 구간 오프셋 결정 (우선순위: 세션 저장값 → graphPoints 최소 relativeTime 역산)
  const sessionChargeOffset =
    sessionData.chargeTimeOffset ||          // 새 형식 세션: calculateSessionSummary가 저장
    activeSession.chargeTimeOffset ||        // 같은 값이지만 JSON.parse 복사본에서 확인
    (() => {
      if (!activeSession.graphPoints || activeSession.graphPoints.length === 0) return 0;
      const minRel = Math.min(...activeSession.graphPoints.map(p => p.relativeTime));
      return minRel < 0 ? Math.abs(minRel) : 0; // 음수 relativeTime이 있으면 예열 구간 존재
    })();

  modalChart.data.datasets[0].data = activeSession.graphPoints.map(p => ({ x: p.relativeTime, y: p.temperature }));
  modalChart.data.datasets[1].data = activeSession.graphPoints.map(p => ({ x: p.relativeTime, y: p.ror }));
  
  modalChart.options.scales.x.min = sessionChargeOffset > 0 ? -sessionChargeOffset : 0;
  const maxTime = activeSession.graphPoints.length > 0 ? activeSession.graphPoints[activeSession.graphPoints.length - 1].relativeTime : 600;
  modalChart.options.scales.x.max = Math.max(600, Math.ceil(maxTime / 60) * 60);
  modalChart.update();
  
  // 모달 상세 리포트 내 타임테이블 데이터 반영
  updateModalTimetable(activeSession.graphPoints);
  
  const tableBody = document.getElementById('modal-log-list');
  tableBody.innerHTML = '';
  activeSession.events.forEach(ev => {
    const row = document.createElement('div');
    row.className = 'table-row';
    const times = getEventTimes(ev, activeSession.events);
    const tempStr = (ev.temperature !== null && ev.temperature !== undefined && !isNaN(ev.temperature))
      ? `${ev.temperature.toFixed(1)}°C`
      : '—';
    
    row.innerHTML = `
      <span>${times.total}</span>
      <span>${times.process}</span>
      <span><span class="event-badge ${getEventBadgeClass(ev.type)}">${ev.type}</span></span>
      <span>${tempStr}</span>
      <span>${ev.heatValue}</span>
      <span>${ev.description}</span>
    `;
    tableBody.appendChild(row);
  });

  isSaved = sessionsList.some(s => s.id === activeSession.id);
  const saveBtn = document.getElementById('btn-save-session');
  if (isSaved) {
    saveBtn.innerHTML = `
      <svg class="btn-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
      <span>저장 완료</span>
    `;
    saveBtn.classList.add('disabled');
  } else {
    saveBtn.innerHTML = `
      <svg class="btn-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/></svg>
      <span>기록 저장 (자동경로)</span>
    `;
    saveBtn.classList.remove('disabled');
  }

  // GitHub 업로드 버튼 상태 초기화
  const githubBtn = document.getElementById('btn-github-upload');
  githubBtn.innerHTML = `
    <svg class="btn-svg" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0C5.37 0 0 5.37 0 12c0 5.3 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61-.546-1.385-1.335-1.755-1.335-1.755-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.418-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23a11.5 11.5 0 0 1 3-.405c1.02.005 2.045.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 21.795 24 17.295 24 12c0-6.63-5.37-12-12-12"/></svg>
    <span>GitHub에 저장</span>
  `;
  githubBtn.classList.remove('disabled');
}

function closeModal() {
  document.getElementById('report-modal').classList.remove('active');
  loadSavedSessions();
}

async function saveModalMemo() {
  const memoText = document.getElementById('modal-memo-text').value;
  activeSession.memo = memoText;
  
  const res = await window.api.saveSession(activeSession);
  if (res.success) {
    const toast = document.getElementById('memo-toast');
    toast.className = "toast-message show";
    setTimeout(() => {
      toast.className = "toast-message";
    }, 1500);
  }
}

async function saveActiveSessionToDisk() {
  const saveBtn = document.getElementById('btn-save-session');
  if (saveBtn.classList.contains('disabled')) return;
  
  activeSession.memo = document.getElementById('modal-memo-text').value;
  const res = await window.api.saveSession(activeSession);
  if (res.success) {
    saveBtn.innerHTML = `
      <svg class="btn-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
      <span>저장 완료</span>
    `;
    saveBtn.classList.add('disabled');
    loadSavedSessions();
  }
}

async function exportActiveSession() {
  activeSession.memo = document.getElementById('modal-memo-text').value;
  const res = await window.api.exportSession(activeSession);
  if (res.success) {
    alert('프로파일 파일이 정상적으로 저장되었습니다.');
  }
}

function setAsGuide() {
  guideSession = JSON.parse(JSON.stringify(activeSession));
  
  // 음수 시간대 데이터 제외하고 0초 이상인 부분만 가이드 라인 맵핑
  const positivePoints = guideSession.graphPoints.filter(p => p.relativeTime >= 0);
  
  mainChart.data.datasets[2].data = positivePoints.map(p => ({ x: p.relativeTime, y: p.temperature }));
  mainChart.data.datasets[3].data = positivePoints.map(p => ({ x: p.relativeTime, y: p.ror }));
  
  const maxGuideTime = positivePoints.length > 0 ? positivePoints[positivePoints.length - 1].relativeTime : 900;
  absoluteMaxX = Math.max(900, Math.ceil(maxGuideTime / 60) * 60);
  mainChart.options.scales.x.max = absoluteMaxX;
  mainChart.options.scales.x.min = 0; // 항상 0부터 기점
  zoomPercent = 100;
  document.getElementById('lbl-zoom-percent').innerText = '100% (Fit)';
  
  mainChart.update();
  
  // 가이드 적재 시, 대기 상태이더라도 취소(가이드 해제)할 수 있도록 취소 버튼 활성화
  document.getElementById('btn-cancel-roast').classList.remove('disabled');
  
  alert(`'${guideSession.beanName}' 가이드라인이 배경에 탑재되었습니다!`);
  closeModal();
}

// MARK: - 헬퍼 및 기타 유틸 함수
function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    const r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

function formatTime(sec) {
  const sign = sec < 0 ? "-" : "";
  const absSec = Math.abs(Math.round(sec));
  const m = Math.floor(absSec / 60);
  const s = absSec % 60;
  return `${sign}${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

function formatDate(isoString) {
  if (!isoString) return '';
  const d = new Date(isoString);
  return `${d.getFullYear()}.${(d.getMonth()+1).toString().padStart(2,'0')}.${d.getDate().toString().padStart(2,'0')} ${d.getHours().toString().padStart(2,'0')}:${d.getMinutes().toString().padStart(2,'0')}`;
}

function getEventBadgeClass(type) {
  switch (type) {
    case '예열 시작': return 'badge-preheat';
    case '투입': return 'badge-charge';
    case 'TP': return 'badge-tp';
    case '1차 팝': return 'badge-pop1';
    case '2차 팝': return 'badge-pop2';
    case '종료': return 'badge-finish';
    default: return 'badge-default';
  }
}

function getEventColor(type) {
  switch (type) {
    case '예열 시작': return '#dd6b20';
    case '투입': return '#3182ce';
    case 'TP': return '#319795';
    case '1차 팝': return '#b7791f';
    case '2차 팝': return '#8c520a';
    case '종료': return '#e53e3e';
    default: return '#718096';
  }
}

function getEventTimes(event, allEvents) {
  const chargeEv = allEvents.find(e => e.type === '투입');
  const preheatEv = allEvents.find(e => e.type === '예열 시작');
  
  // 진행시간은 예열시간 포함 전체 시간이므로, 항상 예열 시작 기점으로 계산하여 음수가 나오지 않고 0부터 시작하게 함
  let totalStr = "00:00";
  if (preheatEv) {
    totalStr = formatTime(event.elapsedSeconds - preheatEv.elapsedSeconds);
  } else {
    totalStr = formatTime(event.elapsedSeconds >= 0 ? event.elapsedSeconds : 0);
  }
  
  let processStr = "00:00";
  
  if (chargeEv) {
    if (event.elapsedSeconds >= chargeEv.elapsedSeconds) {
      processStr = formatTime(event.elapsedSeconds - chargeEv.elapsedSeconds);
    } else if (preheatEv) {
      const diff = event.elapsedSeconds - preheatEv.elapsedSeconds;
      processStr = formatTime(diff);
    }
  } else if (preheatEv) {
    const diff = event.elapsedSeconds - preheatEv.elapsedSeconds;
    processStr = formatTime(diff);
  }
  
  return { total: totalStr, process: processStr };
}

// MARK: - 키보드 단축키
function setupKeyboardShortcuts() {
  document.addEventListener('keydown', (e) => {
    if (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA' || document.activeElement.tagName === 'SELECT') return;
    if (e.repeat) return;
    
    const key = e.key.toLowerCase();
    const code = e.code;
    
    if (key === 'r' || code === 'KeyR') {
      triggerPreheating();
    } else if (key === 's' || code === 'KeyS') {
      triggerCharging();
    } else if (code === 'Space') {
      e.preventDefault();
      if (document.activeElement && typeof document.activeElement.blur === 'function') {
        document.activeElement.blur();
      }
      // 모의 로스팅 진행 중: 스페이스바 = 일시정지/재개
      if (isMockRoasting) {
        toggleMockPause();
        return;
      }
      // 실제 로스팅: 기존 투입/종료 단축키 유지
      if (!isPreheating) return;
      if (!isRoasting) {
        triggerCharging();
      } else {
        triggerFinishing();
      }
    } else if (key === '1' || code === 'Digit1' || code === 'Numpad1') {
      addEvent('1차 팝');
    } else if (key === '2' || code === 'Digit2' || code === 'Numpad2') {
      addEvent('2차 팝');
    } else if (key === 'e' || e.key === 'Escape' || code === 'KeyE') {
      triggerFinishing();
    } else if (e.key === 'ArrowUp' || e.key === '=' || code === 'Equal') {
      e.preventDefault();
      adjustHeatSlider(1);
    } else if (e.key === 'ArrowDown' || e.key === '-' || code === 'Minus') {
      e.preventDefault();
      adjustHeatSlider(-1);
    } else if (e.key === 'Enter' || code === 'Enter' || code === 'NumpadEnter') {
      confirmHeatChange();
    }
  });
}

function updateShortcutHints() {
  const chargeHint = document.getElementById('key-charge-hint');
  const finishHint = document.getElementById('key-finish-hint');
  if (!chargeHint || !finishHint) return;
  
  if (isPreheating && !isRoasting) {
    chargeHint.innerText = 'S / Space';
    finishHint.innerText = 'E';
  } else if (isRoasting) {
    chargeHint.innerText = 'S';
    finishHint.innerText = 'E / Space';
  } else {
    chargeHint.innerText = 'S';
    finishHint.innerText = 'E';
  }
}

function adjustHeatSlider(delta) {
  const slider = document.getElementById('range-heat');
  pendingHeat = Math.max(0, Math.min(12, pendingHeat + delta));
  slider.value = pendingHeat;
  updateHeatDisplay(pendingHeat);

  // 키캡 시각적 꾹 눌리는 피드백 클래스 일시 부여
  const btnId = delta > 0 ? 'btn-heat-up' : 'btn-heat-down';
  const targetBtn = document.getElementById(btnId);
  if (targetBtn) {
    targetBtn.classList.add('pressed');
    setTimeout(() => targetBtn.classList.remove('pressed'), 100);
  }
}

// ── 공통 모달 열기 및 리셋 기능 ──
function openModal(modal) {
  if (!modal) return;
  const card = modal.querySelector('.modal-card') || modal.querySelector('.donation-card');
  if (card) {
    card.style.left = '0px';
    card.style.top = '0px';
  }
  modal.classList.add('active');
}

// ── 모달 드래그 이동(드래그 앤 드롭) 구현 ──
function makeModalDraggable(modalId) {
  const modal = document.getElementById(modalId);
  if (!modal) return;
  const card = modal.querySelector('.modal-card') || modal.querySelector('.donation-card');
  if (!card) return;
  const header = card.querySelector('.modal-header') || card.querySelector('.donation-header');
  if (!header) return;
  
  let isDragging = false;
  let startX = 0;
  let startY = 0;
  let currentX = 0;
  let currentY = 0;
  
  header.style.cursor = 'grab';
  header.style.userSelect = 'none';
  
  header.addEventListener('mousedown', (e) => {
    if (e.target.closest('button') || e.target.closest('input') || e.target.closest('select') || e.target.closest('textarea')) {
      return;
    }
    
    isDragging = true;
    header.style.cursor = 'grabbing';
    startX = e.clientX;
    startY = e.clientY;
    
    const styleLeft = card.style.left ? parseFloat(card.style.left) : 0;
    const styleTop = card.style.top ? parseFloat(card.style.top) : 0;
    currentX = styleLeft;
    currentY = styleTop;
    
    card.style.position = 'relative';
    
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  });
  
  function onMouseMove(e) {
    if (!isDragging) return;
    const dx = e.clientX - startX;
    const dy = e.clientY - startY;
    card.style.left = (currentX + dx) + 'px';
    card.style.top = (currentY + dy) + 'px';
  }
  
  function onMouseUp() {
    isDragging = false;
    header.style.cursor = 'grab';
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
  }
}

// ── 그래프 확대 및 파일 익스포트 기능 구현 ──
function openZoomModal() {
  if (!activeSession) return;
  const modal = document.getElementById('chart-zoom-modal');
  openModal(modal);
  
  // 모달 레이아웃 및 트랜지션이 완전히 정착되어 크기가 계산될 수 있도록 약간의 지연(setTimeout)을 줍니다.
  setTimeout(() => {
    try {
      const zoomCanvas = document.getElementById('zoom-analysis-chart');
      if (!zoomCanvas) {
        alert("zoom-analysis-chart 캔버스 요소를 DOM에서 찾을 수 없습니다.");
        return;
      }
      const zoomCtx = zoomCanvas.getContext('2d');
      if (!zoomCtx) {
        alert("zoom-analysis-chart 2D 컨텍스트를 가져올 수 없습니다.");
        return;
      }
      
      if (zoomChart) {
        zoomChart.destroy();
      }
      
      const xMin = (modalChart && modalChart.options && modalChart.options.scales && modalChart.options.scales.x) ? modalChart.options.scales.x.min : 0;
      const xMax = (modalChart && modalChart.options && modalChart.options.scales && modalChart.options.scales.x) ? modalChart.options.scales.x.max : 900;
      
      const chargeEv = activeSession.events.find(e => e.type === '투입');
      const chargeTime = chargeEv ? chargeEv.elapsedSeconds : 0;
      
      zoomChart = new Chart(zoomCtx, {
        type: 'line',
        data: {
          datasets: [
            {
              label: '온도',
              borderColor: '#e53e3e',
              borderWidth: 3.2,
              pointRadius: 0,
              data: (activeSession.graphPoints || []).map(p => ({ x: p.relativeTime - chargeTime, y: p.temperature })),
              yAxisID: 'y'
            },
            {
              label: 'RoR',
              borderColor: '#38a169',
              segment: {
                borderColor: ctx => {
                  const y0 = ctx.p0.parsed.y;
                  const y1 = ctx.p1.parsed.y;
                  return (y0 < 0 || y1 < 0) ? '#3182ce' : '#38a169';
                },
                borderWidth: ctx => {
                  const y0 = ctx.p0.parsed.y;
                  const y1 = ctx.p1.parsed.y;
                  return (y0 < 0 || y1 < 0) ? 1.2 : 2.5;
                },
                borderDash: ctx => {
                  const y0 = ctx.p0.parsed.y;
                  const y1 = ctx.p1.parsed.y;
                  return (y0 < 0 || y1 < 0) ? [4, 4] : [];
                }
              },
              borderWidth: 2.5,
              pointRadius: 0,
              data: (activeSession.graphPoints || []).map(p => ({ x: p.relativeTime - chargeTime, y: p.ror })),
              yAxisID: 'y1'
            }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              display: true,
              position: 'top',
              labels: {
                usePointStyle: true,
                pointStyle: 'line',
                pointStyleWidth: 40,
                boxWidth: 40,
                font: {
                  size: 12,
                  weight: 'bold'
                }
              }
            },
            tooltip: {
              enabled: true,
              mode: 'index',
              intersect: false,
              bodyFont: { size: 12 },
              titleFont: { size: 12 },
              callbacks: {
                title: (tooltipItems) => {
                  if (tooltipItems && tooltipItems.length > 0) {
                    const seconds = tooltipItems[0].parsed.x;
                    const events = (activeSession && activeSession.events) || [];
                    return formatTooltipTitle(seconds, events);
                  }
                  return '';
                },
                label: (context) => {
                  let label = context.dataset.label || '';
                  if (label) {
                    label += ': ';
                  }
                  const yVal = context.parsed.y;
                  if (yVal !== null && yVal !== undefined && !isNaN(yVal)) {
                    label += yVal.toFixed(1);
                    if (context.dataset.yAxisID === 'y1' || label.includes('RoR') || label.includes('ror')) {
                      label += ' °C/min';
                    } else {
                      label += ' °C';
                    }
                    return label;
                  }
                  return null; // 데이터가 없거나 null이면 툴팁에서 완전히 제외
                }
              }
            }
          },
          scales: {
            x: {
              type: 'linear',
              position: 'bottom',
              min: xMin,
              max: xMax,
              ticks: {
                font: { size: 11 },
                callback: function(val) {
                  const events = (activeSession && activeSession.events) || [];
                  return formatXAxisTick(val, events);
                }
              },
              grid: {
                color: 'rgba(0, 0, 0, 0.05)'
              }
            },
            y: {
              type: 'linear',
              position: 'left',
              min: 0,
              max: 240,
              title: {
                display: true,
                text: '온도 (°C)',
                color: '#e53e3e',
                font: { size: 12, weight: 'bold' }
              },
              ticks: { font: { size: 11 } },
              grid: { color: 'rgba(0, 0, 0, 0.05)' }
            },
            y1: {
              type: 'linear',
              position: 'right',
              min: -15,
              max: 40,
              title: {
                display: true,
                text: 'RoR (°C/min)',
                color: '#38a169',
                font: { size: 12, weight: 'bold' }
              },
              ticks: { font: { size: 11 } },
              grid: { drawOnChartArea: false }
            }
          }
        },
        plugins: [verticalLinesPlugin]
      });
      updateY1AxisMax(zoomChart);
    } catch (e) {
      alert("확대 차트 초기화 중 예외 에러 발생:\n" + e.message + "\n\nStack:\n" + e.stack);
    }
  }, 120);
}

function getZoomChartBase64(format = 'png') {
  if (!zoomChart) return null;
  
  if (format === 'jpg' || format === 'jpeg') {
    const canvas = document.getElementById('zoom-analysis-chart');
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = canvas.width;
    tempCanvas.height = canvas.height;
    const tempCtx = tempCanvas.getContext('2d');
    tempCtx.fillStyle = '#ffffff';
    tempCtx.fillRect(0, 0, tempCanvas.width, tempCanvas.height);
    tempCtx.drawImage(canvas, 0, 0);
    return tempCanvas.toDataURL('image/jpeg', 0.95);
  }
  return document.getElementById('zoom-analysis-chart').toDataURL('image/png');
}

async function exportZoomChart(format) {
  const base64Data = getZoomChartBase64(format);
  if (!base64Data) return;
  
  const ext = format === 'jpg' ? 'jpg' : 'png';
  const safeBeanName = (activeSession.beanName || 'unnamed').replace(/[\s/\\?%*:|"<>. ]+/g, '_');
  const defaultName = `BocaBoa_Graph_${safeBeanName}_${formatDateForFilename(activeSession.date)}.${ext}`;
  
  const res = await window.api.saveChartImage({
    base64Data,
    format: ext,
    defaultName
  });
  
  if (res && res.success) {
    alert('그래프 이미지가 성공적으로 저장되었습니다!');
  } else if (res && res.error) {
    alert('이미지 저장 중 오류가 발생했습니다: ' + res.error);
  }
}

async function exportZoomChartPdf() {
  const base64Data = getZoomChartBase64('png');
  if (!base64Data) return;
  
  const safeBeanName = (activeSession.beanName || 'unnamed').replace(/[\s/\\?%*:|"<>. ]+/g, '_');
  const defaultName = `BocaBoa_Graph_${safeBeanName}_${formatDateForFilename(activeSession.date)}.pdf`;
  
  const res = await window.api.saveChartPdf({
    base64Data,
    defaultName
  });
  
  if (res && res.success) {
    alert('PDF 파일이 성공적으로 저장되었습니다!');
  } else if (res && res.error) {
    alert('PDF 저장 중 오류가 발생했습니다: ' + res.error);
  }
}

async function printZoomChart() {
  const base64Data = getZoomChartBase64('png');
  if (!base64Data) return;
  
  const res = await window.api.printChartImage({ base64Data });
  if (res && res.error) {
    alert('인쇄 중 오류가 발생했습니다: ' + res.error);
  }
}

function formatDateForFilename(dateStr) {
  try {
    const d = new Date(dateStr);
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const hh = String(d.getHours()).padStart(2, '0');
    const min = String(d.getMinutes()).padStart(2, '0');
    return `${yyyy}${mm}${dd}_${hh}${min}`;
  } catch (e) {
    return 'date';
  }
}

// ── 캔버스 뱃지 그리기 유틸리티 함수 ──
function drawRoundedRect(ctx, x, y, width, height, radius) {
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + width - radius, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
  ctx.lineTo(x + width, y + height - radius);
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  ctx.lineTo(x + radius, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
}

function drawEventBadge(ctx, title, timeStr, tempVal, xPos, top, badgeColor, isZoom) {
  ctx.save();
  
  // 1. 이벤트 명칭 배지 그리기 (색상 채우기 + 흰색 글씨)
  const fontSize = isZoom ? 12.5 : 10.5;
  ctx.font = `bold ${fontSize}px sans-serif`;
  ctx.textBaseline = 'top';
  ctx.textAlign = 'center';
  
  const textWidth = ctx.measureText(title).width;
  const paddingX = isZoom ? 7 : 4.5;
  const paddingY = isZoom ? 3.5 : 2;
  
  const badgeW = textWidth + paddingX * 2;
  const badgeH = fontSize + paddingY * 2;
  const badgeX = xPos - badgeW / 2;
  const badgeY = isZoom ? top + 10 : top + 8;
  
  // 배지 배경 채우기
  ctx.fillStyle = badgeColor;
  drawRoundedRect(ctx, badgeX, badgeY, badgeW, badgeH, 4);
  ctx.fill();
  
  // 배지 텍스트 쓰기
  ctx.fillStyle = '#ffffff';
  ctx.fillText(title, xPos, badgeY + paddingY);
  
  // 2. 이벤트 시간/온도 배지 그리기 (흰색 배경 + 테두리 + 회색 글씨)
  const timeFontSize = isZoom ? 11.5 : 9.5;
  ctx.font = `normal ${timeFontSize}px sans-serif`;
  
  const badgeText = typeof tempVal === 'number' ? `${tempVal.toFixed(1)}°C | ${timeStr}` : timeStr;
  const timeWidth = ctx.measureText(badgeText).width;
  
  const timePaddingX = isZoom ? 5.5 : 3.5;
  const timePaddingY = isZoom ? 2.5 : 1.5;
  const timeBadgeW = timeWidth + timePaddingX * 2;
  const timeBadgeH = timeFontSize + timePaddingY * 2;
  const timeBadgeX = xPos - timeBadgeW / 2;
  const timeBadgeY = badgeY + badgeH + (isZoom ? 5 : 3.5);
  
  // 시간 배지 배경 (약간 투명한 흰색)
  ctx.fillStyle = 'rgba(255, 255, 255, 0.95)';
  ctx.strokeStyle = '#cbd5e0';
  ctx.lineWidth = 1;
  drawRoundedRect(ctx, timeBadgeX, timeBadgeY, timeBadgeW, timeBadgeH, 3);
  ctx.fill();
  ctx.stroke();
  
  // 시간 텍스트 쓰기
  ctx.fillStyle = '#4a5568';
  ctx.fillText(badgeText, xPos, timeBadgeY + timePaddingY);
  
  ctx.restore();
}

// ── 상세정보창(Tooltip) 및 X축 틱 시간 포맷터 ──
function formatTooltipTitle(seconds, events) {
  const chargeEv = (events || []).find(e => e.type === '투입');
  if (chargeEv) {
    // 생두 투입 시점이 존재하므로 음수 영역은 예열, 양수 영역은 로스팅으로 매핑
    if (seconds < 0) {
      return `예열: ${formatTime(Math.abs(seconds))}`;
    } else {
      return `로스팅: ${formatTime(seconds)}`;
    }
  } else {
    // 아직 투입 전인 경우 (현재 진행 중인 예열)
    return `예열: ${formatTime(Math.abs(seconds))}`;
  }
}

function formatXAxisTick(val, events) {
  const chargeEv = (events || []).find(e => e.type === '투입');
  const preheatEv = (events || []).find(e => e.type === '예열 시작');
  
  if (isRoasting || chargeEv) {
    const preheatTime = preheatEv ? preheatEv.elapsedSeconds : 0;
    const chargeTime = chargeEv ? chargeEv.elapsedSeconds : 0;
    const preheatDuration = chargeTime - preheatTime;
    
    const processTime = val;
    const totalTime = processTime + preheatDuration;
    
    if (processTime >= 0) {
      return [formatTime(totalTime), formatTime(processTime)];
    } else {
      // 예열 구간의 틱 (음수 영역)
      return formatTime(totalTime);
    }
  } else {
    // 예열 중인 경우
    return formatTime(val);
  }
}

// 7세그먼트 열량 디스플레이 포맷터
function updateHeatDisplay(val) {
  const num = parseInt(val);
  const display = document.getElementById('pending-heat-val');
  if (!display) return;
  
  if (isNaN(num)) {
    display.innerHTML = '<span class="digit-off">0</span><span class="digit-off">0</span>';
    return;
  }
  
  const tens = Math.floor(num / 10);
  const units = num % 10;
  
  if (tens === 0) {
    display.innerHTML = `<span class="digit-off">0</span><span class="digit-on">${units}</span>`;
  } else {
    display.innerHTML = `<span class="digit-on">${tens}</span><span class="digit-on">${units}</span>`;
  }
}

// ── GitHub Integration Helper Functions ──────────────────────────────────────────

let isAdminAuthenticated = false;

function updateGithubConfigStatus() {
  const statusEl = document.getElementById('github-pat-status');
  if (!statusEl) return;
  const selectedType = document.querySelector('input[name="github-repo-type"]:checked').value;
  
  if (selectedType === 'public') {
    statusEl.innerHTML = '<span style="color:var(--success-color);font-weight:600;">✓ 공용 저장소 사용 준비 완료 (토큰 내장됨)</span>';
  } else {
    const ownerVal = document.getElementById('input-github-private-owner').value.trim();
    const repoVal = document.getElementById('input-github-private-repo').value.trim();
    const patVal = document.getElementById('input-github-pat').value.trim();

    if (patVal && ownerVal && repoVal) {
      statusEl.innerHTML = '<span style="color:var(--success-color);font-weight:600;">✓ 개인 저장소 설정이 입력되어 있습니다.</span>';
    } else {
      statusEl.innerHTML = '<span style="color:var(--text-tertiary);">개인 저장소 정보(Owner, Repo, PAT)를 모두 입력해 주세요.</span>';
    }
  }
}

function toggleGithubRepoFields(type) {
  const privateFields = document.getElementById('github-private-fields');
  const userNameLabel = document.getElementById('lbl-github-user-name');
  const userNameInput = document.getElementById('input-github-user-name');
  const patInput = document.getElementById('input-github-pat');
  const patGroup = document.getElementById('github-pat-group');

  if (type === 'private') {
    privateFields.style.display = 'flex';
    userNameLabel.textContent = '사용자 이름 (선택)';
    userNameInput.placeholder = '예: 홍길동 (선택사항)';
    
    // 개인 저장소는 읽기/쓰기 바로 가능, PAT 노출
    patGroup.style.display = 'block';
    patInput.readOnly = false;
    patInput.value = githubConfig.privatePat || '';
  } else {
    privateFields.style.display = 'none';
    userNameLabel.textContent = '사용자 이름';
    userNameInput.placeholder = '예: 홍길동 (공용 저장소 백업 시 필수 입력)';
    
    // 공용 저장소는 PAT 숨김
    patGroup.style.display = 'none';
    patInput.value = '';
  }

  updateGithubConfigStatus();
}

function openGithubSettingsModal() {
  document.getElementById('input-github-user-name').value = githubConfig.userName || '';
  document.getElementById('input-github-private-owner').value = githubConfig.privateOwner || '';
  document.getElementById('input-github-private-repo').value = githubConfig.privateRepo || '';

  // Radio button set
  const radios = document.querySelectorAll('input[name="github-repo-type"]');
  radios.forEach(radio => {
    if (radio.value === githubConfig.repoType) {
      radio.checked = true;
    }
  });

  toggleGithubRepoFields(githubConfig.repoType);
  updateGithubConfigStatus();
  
  document.getElementById('github-settings-modal').classList.add('active');
}

function closeGithubSettingsModal() {
  document.getElementById('github-settings-modal').classList.remove('active');
}

function togglePatVisibility() {
  const patInput = document.getElementById('input-github-pat');
  if (patInput.type === 'password') {
    patInput.type = 'text';
  } else {
    patInput.type = 'password';
  }
}

async function saveGithubConfig() {
  const patVal = document.getElementById('input-github-pat').value.trim();
  const userNameVal = document.getElementById('input-github-user-name').value.trim();
  const ownerVal = document.getElementById('input-github-private-owner').value.trim();
  const repoVal = document.getElementById('input-github-private-repo').value.trim();
  
  const selectedType = document.querySelector('input[name="github-repo-type"]:checked').value;

  if (selectedType === 'public' && !userNameVal) {
    alert('공용 저장소를 사용하려면 사용자 이름을 반드시 입력해야 합니다.');
    return;
  }
  if (selectedType === 'private' && (!ownerVal || !repoVal)) {
    alert('개인 저장소를 사용하려면 GitHub 계정명과 저장소명을 모두 입력해야 합니다.');
    return;
  }

  // 공용 저장소의 경우 publicPat은 고정값 "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"으로 강제 지정
  const finalPublicPat = "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";
  let finalPrivatePat = githubConfig.privatePat;

  if (selectedType === 'private') {
    finalPrivatePat = patVal;
  }

  const statusEl = document.getElementById('github-pat-status');
  statusEl.innerHTML = '<span style="color:var(--text-secondary);">저장 중...</span>';

  const newConfig = {
    publicPat: finalPublicPat,
    privatePat: finalPrivatePat,
    repoType: selectedType,
    userName: userNameVal,
    privateOwner: ownerVal,
    privateRepo: repoVal
  };

  const res = await window.api.githubSaveConfig(newConfig);
  if (res.success) {
    githubConfig = newConfig;
    statusEl.innerHTML = '<span style="color:var(--success-color);font-weight:600;">✓ 설정이 정상적으로 저장되었습니다!</span>';
    setTimeout(() => {
      closeGithubSettingsModal();
    }, 800);
  } else {
    statusEl.innerHTML = `<span style="color:var(--danger-color);">저장 실패: ${res.error}</span>`;
  }
}

async function uploadActiveSessionToGithub() {
  const uploadBtn = document.getElementById('btn-github-upload');
  if (uploadBtn.classList.contains('disabled')) return;

  const pat = githubConfig.repoType === 'public' ? githubConfig.publicPat : githubConfig.privatePat;

  if (!pat) {
    alert('GitHub PAT가 설정되지 않았습니다. 설정 창에서 설정을 완료해 주세요.');
    openGithubSettingsModal();
    return;
  }

  if (githubConfig.repoType === 'public' && !githubConfig.userName) {
    alert('공용 저장소 백업을 사용하려면 사용자 이름을 설정해야 합니다.');
    openGithubSettingsModal();
    return;
  }

  uploadBtn.innerHTML = '<span>업로드 중...</span>';
  uploadBtn.classList.add('disabled');

  activeSession.memo = document.getElementById('modal-memo-text').value;

  const res = await window.api.githubUploadSession({ session: activeSession, config: githubConfig });
  if (res.success) {
    uploadBtn.innerHTML = `
      <svg class="btn-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
      <span>업로드 완료</span>
    `;
  } else {
    alert(`GitHub 업로드 실패: ${res.error}\n토큰 권한 또는 저장소 정보가 올바른지 확인하세요.`);
    uploadBtn.innerHTML = '<span>GitHub에 저장</span>';
    uploadBtn.classList.remove('disabled');
  }
}

function openGithubSessionsModal() {
  closeGithubSettingsModal();
  document.getElementById('github-sessions-modal').classList.add('active');
  loadGithubSessionsList();
}

function closeGithubSessionsModal() {
  document.getElementById('github-sessions-modal').classList.remove('active');
}

let loadedGithubFiles = [];

async function loadGithubSessionsList() {
  const listEl = document.getElementById('github-sessions-list');
  const statusEl = document.getElementById('github-sessions-status');
  
  listEl.innerHTML = '';
  statusEl.textContent = 'GitHub에서 파일 목록을 가져오는 중...';
  
  // 검색어 초기화
  document.getElementById('github-search-input').value = '';

  const res = await window.api.githubListSessions(githubConfig);
  if (!res.success) {
    statusEl.innerHTML = `<span style="color:var(--danger-color);">목록 로드 실패: ${res.error}</span>`;
    return;
  }

  loadedGithubFiles = res.files || [];
  renderGithubSessionsList();
}

function renderGithubSessionsList() {
  const listEl = document.getElementById('github-sessions-list');
  const statusEl = document.getElementById('github-sessions-status');
  const searchQuery = document.getElementById('github-search-input').value.trim().toLowerCase();
  const searchTarget = document.getElementById('github-search-target').value;
  
  listEl.innerHTML = '';

  let filteredFiles = loadedGithubFiles;
  if (searchQuery) {
    filteredFiles = loadedGithubFiles.filter(file => {
      let matchValue = '';
      const match = file.name.match(/^(\d{8})(\d{4})_(.+)\.json$/);
      if (match) {
        if (searchTarget === 'bean') {
          matchValue = match[3].replace(/_/g, ' ');
        } else {
          matchValue = file.userName || '';
        }
      } else {
        if (searchTarget === 'bean') {
          matchValue = file.name;
        } else {
          matchValue = file.userName || '';
        }
      }
      return matchValue.toLowerCase().includes(searchQuery);
    });
  }

  statusEl.textContent = `저장된 파일: 총 ${loadedGithubFiles.length}개${searchQuery ? ` (검색 결과: ${filteredFiles.length}개)` : ''}`;

  if (filteredFiles.length === 0) {
    const emptyMsg = document.createElement('div');
    emptyMsg.style.textAlign = 'center';
    emptyMsg.style.padding = '24px';
    emptyMsg.style.color = 'var(--text-tertiary)';
    emptyMsg.style.fontSize = '13px';
    emptyMsg.textContent = searchQuery ? '검색 결과가 없습니다.' : '저장된 로스팅 기록이 없습니다.';
    listEl.appendChild(emptyMsg);
    return;
  }

  // 최신 순 정렬
  filteredFiles.sort((a, b) => b.name.localeCompare(a.name));

  filteredFiles.forEach(file => {
    const item = document.createElement('div');
    item.className = 'github-session-item';
    item.style.display = 'grid';
    item.style.gridTemplateColumns = '2.2fr 1fr 1.3fr 75px';
    item.style.gap = '12px';
    item.style.alignItems = 'center';
    
    let bean = file.name;
    let userName = file.userName || '-';
    let dateFormatted = '-';
    
    const match = file.name.match(/^(\d{8})(\d{4})_(.+)\.json$/);
    if (match) {
      const dateStr = `${match[1].substring(0,4)}-${match[1].substring(4,6)}-${match[1].substring(6,8)}`;
      const timeStr = `${match[2].substring(0,2)}:${match[2].substring(2,4)}`;
      bean = match[3].replace(/_/g, ' ');
      dateFormatted = `${dateStr} ${timeStr}`;
    }

    item.innerHTML = `
      <span class="session-bean" style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600; font-size: 13px; color: var(--text-primary);" title="${bean}">${bean}</span>
      <span class="session-user" style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 13px; color: var(--text-secondary);" title="${userName}">${userName}</span>
      <span class="session-date" style="font-size: 12px; color: var(--text-tertiary); font-family: monospace; white-space: nowrap;">${dateFormatted}</span>
      <button class="btn btn-outline btn-download" data-url="${file.downloadUrl}" data-name="${file.name}" style="font-size: 11px; padding: 4px 0; justify-content: center; width: 100%;">가져오기</button>
    `;
    listEl.appendChild(item);
  });

  // 다운로드 버튼 이벤트 연동
  listEl.querySelectorAll('.btn-download').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const downloadUrl = btn.getAttribute('data-url');
      const fileName = btn.getAttribute('data-name');
      
      btn.textContent = '받는 중...';
      btn.disabled = true;

      const pat = githubConfig.repoType === 'public' ? githubConfig.publicPat : githubConfig.privatePat;
      const dlRes = await window.api.githubDownloadSession({ downloadUrl, fileName, pat: pat });
      if (dlRes.success) {
        btn.textContent = '완료';
        btn.style.backgroundColor = 'var(--success-color)';
        btn.style.color = '#ffffff';
        btn.style.borderColor = 'var(--success-color)';
        loadSavedSessions();
      } else {
        alert(`다운로드 실패: ${dlRes.error}`);
        btn.textContent = '가져오기';
        btn.disabled = false;
      }
    });
  });
}
