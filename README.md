# 보카보아 (BocaBoa) ☕️

보카보카 250BT 커피 로스팅기(가마)를 위한 실시간 로스팅 프로파일러 macOS 애플리케이션입니다.  
블루투스(BLE)를 통해 로스터기와 실시간 통신하며 온도, 상승률(RoR), 디벨롭 비율(DTR) 등을 추적하고 정밀한 로스팅을 돕는 프로페셔널 프로파일링 솔루션입니다.

<p align="center">
  <img src="icon.png" width="160" alt="보카보아 앱 아이콘">
</p>

<img width="1720" height="1050" alt="image" src="https://github.com/user-attachments/assets/3c038229-d7a7-4b27-9d35-395a7b393181" />

---

## ✨ 핵심 기능 (Key Features)

### 1. 실시간 프로파일링 및 스마트 지표 추적
* **실시간 BLE 온도 동기화:** 블루투스 LE 기술을 사용하여 약 1초 간격으로 유입되는 온도 데이터를 즉각 그래프와 모니터에 반영합니다.
* **디벨롭 지표 실시간 산출:** 생두 투입, T.P(터닝 포인트), 1차/2차 팝핑 시간 및 온도 기록을 수집하며, 발현 시간 비율인 **DTR(Development Time Ratio)** 및 **디벨롭시간(Develop Time)**을 실시간으로 추적·계산합니다.
* **Agtron 로스팅 포인트 예측:** 현재 도달한 온도를 기반으로 에그트론(Agtron) 스케일 수치 및 원두 색상 시뮬레이션을 실시간 제공합니다.

### 2. 혁신적인 RoR 노이즈 감쇄 엔진 (Denoising & Smoothing)
소형 원적외선 히터 로스터기의 특성상 발생하는 급격한 센서 튀기 및 톱니 노이즈를 획기적으로 다듬어 주는 튜닝 엔진이 탑재되어 있습니다.
* **동적 윈도우 & 필터 튜닝:** RoR 측정 구간(5~45초) 및 지수 이동 평균(EMA) 필터 강도(0~95%)를 사용자가 원격으로 미세 조정하여 부드럽고 가독성 높은 RoR S-곡선을 획득할 수 있습니다.
* **실시간 보정 연동:** 로스팅 진행 중 슬라이더를 통해 설정을 보정하거나 초기화하면, 조절하는 즉시 지금까지 쌓인 **실시간 데이터 전체가 일괄 재계산**되어 그래프의 흐름선 전체가 즉시 부드럽게 리프레시됩니다.
* **초기화 단축 버튼 🔄:** 복잡한 세팅 중 언제든지 권장 설정 기본값(**측정 시간 15초, 필터 강도 90%**)으로 한 번에 되돌릴 수 있는 원클릭 초기화 버튼을 실시간 화면 및 리포트창 양쪽에 제공합니다.
* **초기 1분 노이즈 마스킹:** 생두 투입 직후 온도 하강으로 인해 RoR 스케일이 마이너스로 튀어 전체 그래프가 찌그러지는 현상을 방지하고자, 투입 후 초기 60초간의 불안정 구간은 데이터를 비워두어 깔끔하게 표현합니다.

### 3. 정교한 이중 Y축 차트 및 오토 스케일링 (Dynamic Scale)
* **이중 Y축 지원 (Dual Y-Axis):** 좌측 온도축(0~240°C)과 우측 RoR축(0~Max °C/min)을 완벽히 동기화해 렌더링합니다.
* **동적 오토 스케일링:** RoR 최대 기본 범위를 25°C/min으로 방어하되, 데이터 중 이를 초과하는 오버슈트 값이 감지되면 자동으로 차트 스케일 상한선(`rorLimit`)을 5의 배수 단위로 올림하여 그래프 차트가 잘려 나가지 않도록 오토 스케일링합니다.
* **정수형 눈금 매핑:** 우측 RoR 축의 눈금 수치를 소수가 아닌 정수 5의 배수 단위(`0, 5, 10, ... °C/min`)로 딱 맞아떨어지게 매핑하여 전문적인 지표 확인이 가능합니다.

### 4. 강력한 가이드 모드 (Guide Mode)
* **일체형 그래프 타임라인:** 가이드 세션을 로드할 시, 타임라인 뷰포트가 전체 진행 시간을 한 눈에 보여주도록 자동으로 맞춰집니다.
* **기준 RoR 점선 곡선 제공:** 과거 세션의 온도 가이드라인(회색 점선)뿐 아니라 **기준 RoR 곡선(연한 초록 점선)**도 함께 차트 내에 중첩 표기해 줍니다.
* **데이터 복원 엔진:** 과거 파일 내에 RoR 기록이 비어 있더라도, 불러오는 즉시 실시간 로스팅과 동일한 EMA 계산 공식을 활용해 과거의 RoR 곡선을 원본 온도로부터 자동으로 복원하여 렌더링합니다.

### 5. 키보드 단축키 기반 안전 조절 시스템
* **키보드 열량 제어:** 로스팅 중 시선을 빼앗기지 않고 마우스 조작 없이 키보드의 `+` (혹은 숫자 패드가 없는 기기를 위해 백스페이스 왼쪽 `=` 키 겸용) 및 `-` 키로 간편히 열량을 제어합니다.
* **엔터(Enter) 키 안전 적용:** 열량을 변경한 뒤 `Enter` 키를 눌러 최종 확정하기 전에는 로스터기에 신호가 가지 않도록 오작동 방지 안전장치를 결합했습니다.

### 6. 체계적인 로스팅 리포트 & PDF 인쇄
* **기록 열람 및 사후 보정:** 이전에 저장된 로스팅 로그를 더블클릭해 세션 요약, DTR 분석, 전체 온도/RoR 그래프를 상세히 관찰할 수 있으며, 이 상세창에서도 슬라이더를 통해 RoR 노이즈를 사후 보정할 수 있습니다.
* **A4 레이아웃 PDF 저장 및 인쇄:** `NSSavePanel`을 통해 깔끔한 보고서를 PDF 파일로 내보내거나 시스템 인쇄 창을 연결할 수 있습니다. 이때 보정 슬라이더 등의 조작 패널들은 **자동 은닉(`isForPrinting`)** 처리되어 깔끔한 문서 결과물만 인쇄됩니다.

---

## 📥 설치 방법

본 프로젝트는 소스 코드를 공개하지 않는 **클로즈드 소스(Closed-source)**로 운영됩니다.  
앱 설치 파일(`.dmg`)만 Releases 페이지를 통해 배포하고 있습니다.

1. 이 저장소의 [Releases](../../releases) 페이지로 이동합니다.
2. 최신 버전의 `BocaBoa.dmg` 파일을 다운로드합니다.
3. 다운로드한 `.dmg` 파일을 더블클릭하여 마운트한 후, `보카보아.app`을 `Applications(응용프로그램)` 폴더로 드래그하여 설치합니다.

> ⚠️ **참고:** 최초 실행 시 시스템 보안 알림이 나타날 수 있습니다. `시스템 설정` > `개인정보 보호 및 보안`에서 "확인 없이 열기"를 클릭하여 실행을 허용해 주시고, 기기 연결을 위해 블루투스 권한을 허용해 주세요.
> **더 자세한 방법**은 개발자의 블로그 글 참조: <a href="https://blog.naver.com/josephk1010/224329183551" target="_blank">보카보카250/500 블루투스 로스팅 프로파일링 어플리케이션(앱) PC용 '보카보아(BocaBoa)'</a>

---

# BocaBoa ☕️

A real-time roasting profiler macOS application designed for the **BocaBoca 250BT** coffee roaster.  
It connects to your roaster via Bluetooth (BLE) to track real-time temperature, Rate of Rise (RoR), Development Time Ratio (DTR), and helps you achieve professional and consistent roasts.

---

## ✨ Key Features

* **Real-time BLE Synchronization:** Receives temperature packets from the roaster at ~1-second intervals and reflects them instantly.
* **Develop Metrics Tracking:** Tracks Charge, Turning Point (T.P), First/Second Crack times, and calculates real-time **DTR (Development Time Ratio)** and **Develop Time**.
* **Innovative RoR Denoising Engine:** Damps out high-frequency noise from remote infrared heating lamps. Adjust the comparison window (5–45s) and EMA filter strength (0–95%) dynamically.
* **Instant Live Recalculation:** Adjusting the sliders or clicking the reset button instantly recalculates the entire history of the current live session, immediately smoothing out the live RoR line on the chart.
* **One-Click Reset 🔄:** Easily reset parameters to recommended defaults (15s window, 90% filter) both on the live screen and report view.
* **Dynamic Auto-Scaling & Integer Ticks:** The RoR axis locks at 25°C/min as default but auto-scales upwards in multiples of 5 when exceeded. Ticks align perfectly to clean integers (`0, 5, 10, ... °C/min`) on the dual-axis chart.
* **Full-Timeline Guide Mode:** Load previous sessions to display as reference lines. Instantly recovers guide RoR curves from raw temperature logs even if the RoR values are missing in old files.
* **Keyboard Hotkeys for Heat:** Change heater levels using `+` (or `=` next to backspace) and `-` keys, and press `Enter` to apply.
* **PDF Export & Print:** Print reports or save them as A4-scaled PDF documents. Sliders and settings panels are automatically hidden (`isForPrinting`) in document outputs for a clean layout.
