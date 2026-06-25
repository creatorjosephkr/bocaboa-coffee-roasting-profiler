# 보카보아 (BocaBoa) ☕️

보카보카 250BT 커피 로스팅기를 위한 실시간 로스팅 프로파일러 macOS 애플리케이션입니다.
블루투스(BLE)를 통해 로스터기와 연결하여 실시간 온도, RoR, DTR 등을 추적하고 체계적인 로스팅을 도와줍니다.

<p><!-- blank --></p>
<p><!-- blank --></p>

<p align="center">
  <img src="icon.png" width="200" alt="보카보아 앱 아이콘">
</p>
<p><!-- blank --></p>

<p align="center">
  <img width="491" height="391" alt="bocaboca" src="https://github.com/user-attachments/assets/6bcc56bf-d017-4b75-9815-dca835039d41" />
</p>

<img width="1412" height="1004" alt="image" src="https://github.com/user-attachments/assets/ec66c13e-d3d9-4f9d-8627-84b30f7f3c09" />

<p><!-- blank --></p>

## ✨ 주요 기능
- **실시간 프로파일링:** 블루투스를 통한 실시간 온도 모니터링 및 실시간 RoR 추적
- **스마트 지표 추적:** 투입, 터닝 포인트(T.P), 1차/2차 팝핑 시간 및 목표 DTR 실시간 계산
- **가이드 모드:** 이전 로스팅 세션 기록을 불러와 비교하며 로스팅할 수 있는 가이드 기능
- **직관적인 UI:** Agtron 수치 및 색상 기반의 예상 로스팅 포인트 가이드

<p><!-- blank --></p>

## 📥 설치 방법
본 프로젝트는 소스 코드를 공개하지 않는 **클로즈드 소스(Closed-source)**로 운영됩니다.
앱 설치 파일(`.dmg`)만 Releases 페이지를 통해 배포하고 있습니다.

1. 이 저장소의 [Releases](../../releases) 페이지로 이동합니다.
2. 최신 버전의 `BocaBoa.dmg` 파일을 다운로드합니다.
3. 다운로드한 `.dmg` 파일을 더블클릭하여 마운트한 후, `보카보아.app`을 `Applications(응용프로그램)` 폴더로 드래그하여 설치합니다.

> **참고:** 최초 실행 시 시스템 보안 알림이 나타날 수 있습니다. `시스템 설정` > `개인정보 보호 및 보안`에서 "확인 없이 열기"를 클릭하여 실행을 허용해 주시고, 기기 연결을 위해 블루투스 권한을 허용해 주세요.

---

# BocaBoa ☕️

A real-time roasting profiler macOS application designed for the BocaBoa 250BT coffee roaster.
It connects to your roaster via Bluetooth (BLE) to track real-time temperature, Rate of Rise (RoR), Development Time Ratio (DTR), and helps you achieve consistent roasts.

## ✨ Key Features
- **Real-time Profiling:** Monitor real-time temperature and track Rate of Rise (RoR) via Bluetooth.
- **Smart Metric Tracking:** Instantly calculates Charge, Turning Point (T.P), First/Second Crack times, and target DTR.
- **Guide Mode:** Load previous roasting sessions to use as a reference guide during your current roast.
- **Intuitive UI:** Visual guidance for expected roasting points based on Agtron scale and colors.

## 📥 How to Install
This project operates as **Closed-source**. Only the application binary is distributed via `.dmg` files.

1. Go to the [Releases](../../releases) page of this repository.
2. Download the latest `BocaBoa.dmg` file.
3. Double-click the downloaded `.dmg` file, and drag the `보카보아.app` (BocaBoa.app) into your `Applications` folder to install.

> **Note:** Upon first launch, you might see a macOS security warning. Go to `System Settings` > `Privacy & Security` and click "Open Anyway" to allow the app to run. Please also ensure you grant Bluetooth permissions for the app to connect to the roaster.
