import sys

content = open("Sources/BluetoothSearch/ContentView.swift").read()
start_idx = content.find("private var sidebarView: some View {")
end_idx = content.find("private var mainDashboardView: some View {")

if start_idx == -1 or end_idx == -1:
    print("Could not find boundaries")
    sys.exit(1)

# We will just write a correctly balanced version of sidebarView
sidebar_code = """    @ViewBuilder
    private var sidebarView: some View {
        VStack(spacing: 14) {
            // 앱 로고 및 이름 헤더
            HStack(spacing: 12) {
                let iconImage = NSImage(named: "NSApplicationIcon") ?? NSImage(named: "AppIcon")
                if let appIcon = iconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "flame.circle.fill")
                        .resizable()
                        .foregroundColor(.appWarning)
                        .frame(width: 64, height: 64)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("가마지기")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("보카보카 250BT 커피 로스팅기(가마) 실시간 로스팅 프로파일러")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // ── 가이드 모드 배너 ────────────────────────────
                    if let guide = manager.guideSession {
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.appAccent)
                                Text("가이드 모드")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.appAccent)
                                Spacer()
                                Button {
                                    manager.setGuideSession(nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .help("가이드 해제")
                            }
                            HStack {
                                Text(guide.beanName.isEmpty ? "unnamed" : guide.beanName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)
                                Text("·")
                                    .foregroundColor(.textTertiary)
                                Text(guide.displayDate)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                                Spacer()
                                if let next = manager.nextGuideEvent {
                                    Text("다음: \\(next.type)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.appAccent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appAccent.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                    } else {
                        // 기록 불러오기 버튼
                        Button {
                            showSessionBrowser = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                Text("이전 기록 불러오기")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                    }
                    
                    // 로스팅 설정 카드
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("로스팅 설정")
                            Spacer()
                        }
                        .font(.system(size: 12, weight: .bold))
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("생두 이름")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                TextField("예: 에티오피아 예가체프", text: $manager.beanName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .padding(6)
                                    .background(Color.appBackground)
                                    .cornerRadius(4)
                            }
                            
                            HStack(spacing: 8) {
                                Text("가공 방식")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                Picker("", selection: $manager.processMethod) {
                                    ForEach(ProcessMethod.allCases, id: \\.self) { method in
                                        Text(method.rawValue).tag(method)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                Spacer()
                            }
                            
                            HStack(spacing: 8) {
                                Text("로스팅 목적")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                Picker("", selection: $manager.targetRoastState) {
                                    ForEach(TargetRoastState.allCases, id: \\.self) { state in
                                        Text(state.rawValue).tag(state)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                Spacer()
                            }
                            
                            HStack {
                                Text("투입 온도")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 80, alignment: .leading)
                                TextField("목표 투입온도 (선택)", text: $manager.targetChargeTempString)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .padding(6)
                                    .background(Color.appBackground)
                                    .cornerRadius(4)
                                Text("°C")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    .padding(.horizontal, 16)

                    // 아그트론 색상 예측 패널
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(.brown)
                            Text("아그트론 색상 예측 (목표치)")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("\\(Int(manager.targetAgtron))")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(.appPrimary)
                        }
                        
                        let detail = agtronDetail(for: manager.targetAgtron)
                        HStack {
                            Text(detail.range)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appPrimary.opacity(0.1))
                                .foregroundColor(.appPrimary)
                                .cornerRadius(4)
                            Text(detail.common)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(detail.sca)
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                        }
                        
                        Slider(value: $manager.targetAgtron, in: 25...95, step: 1)
                            .tint(.appPrimary)
                    }
                    .padding(12)
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    .padding(.horizontal, 16)

                    // 화력/풍량 컨트롤 패널 (블루투스 연결 시)
                    if manager.selectedDevice?.status.isConnected == true {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("장치 제어")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                            }
                            
                            VStack(spacing: 16) {
                                // 할로겐 제어
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("할로겐 히터")
                                            .font(.system(size: 11))
                                        Spacer()
                                        Text("\\(Int(manager.currentHeaterValue))%")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }
                                    Slider(value: $manager.currentHeaterValue, in: 0...100, step: 10) { _ in
                                        manager.sendControlCommand(type: .heater, value: Int(manager.currentHeaterValue))
                                    }
                                    .tint(.orange)
                                }
                                
                                // 쿨러 제어
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("쿨링 팬")
                                            .font(.system(size: 11))
                                        Spacer()
                                        Text("\\(Int(manager.currentFanValue))%")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }
                                    Slider(value: $manager.currentFanValue, in: 0...100, step: 10) { _ in
                                        manager.sendControlCommand(type: .fan, value: Int(manager.currentFanValue))
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                        .padding(.horizontal, 16)
                    }

                    // 액션 버튼 그룹
                    VStack(spacing: 10) {
                        Button {
                            manager.startPreheating()
                        } label: {
                            HStack {
                                Image(systemName: "thermometer.sun.fill")
                                Text("예열 시작")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(manager.roastState != .idle)

                        Button {
                            manager.chargeBeans()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.down.to.line.circle.fill")
                                Text("생두 투입 (Charge)")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(manager.roastState != .preheating)
                        
                        Button {
                            manager.markFirstPop()
                        } label: {
                            HStack {
                                Image(systemName: "flame")
                                Text("1차 팝 (1st Crack)")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .disabled(manager.roastState != .roasting)
                        
                        Button {
                            manager.markSecondPop()
                        } label: {
                            HStack {
                                Image(systemName: "flame.fill")
                                Text("2차 팝 (2nd Crack)")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                        .disabled(manager.roastState != .firstPop)
                    }
                    .padding(.horizontal, 16)
                    
                    // 예상 종료 시각 카드 (항상 표시)
                    Group {
                        if let endTime = manager.estimatedEndTime,
                           manager.roastState == .firstPop || manager.roastState == .secondPop {
                            let devSec = manager.estimatedDevSeconds
                            let remaining = max(0, endTime.timeIntervalSinceNow)
                            let isOverdue = endTime.timeIntervalSinceNow < 0
                            
                            VStack(spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "timer")
                                        .font(.system(size: 11))
                                        .foregroundColor(isOverdue ? .appError : .orange)
                                    Text(isOverdue ? "목표 시간 초과" : "예상 종료까지")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(isOverdue ? .appError : .orange)
                                    Spacer()
                                    Text(endTime, style: .time)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                }
                                
                                HStack(spacing: 0) {
                                    // 카운트다운
                                    Text(isOverdue ? "+\\(formatTimeInterval(abs(endTime.timeIntervalSinceNow)))" : formatTimeInterval(remaining))
                                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                                        .foregroundColor(isOverdue ? .appError : .orange)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("목표 DTR \\(String(format: "%.1f", Double(manager.targetDTR) ?? 0))%")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.textTertiary)
                                        let m = Int(devSec) / 60
                                        let s = Int(devSec) % 60
                                        Text(String(format: "Develop Time %02d:%02d", m, s))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isOverdue ? Color.appError.opacity(0.08) : Color.orange.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isOverdue ? Color.appError.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        } else {
                            // 1차 팝 이전 대기 상태
                            VStack(spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11))
                                        .foregroundColor(.textTertiary)
                                    Text("예상 종료까지")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.textTertiary)
                                    Spacer()
                                    Text("--:--")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                }
                                
                                HStack(spacing: 0) {
                                    Text("--:--")
                                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("목표 DTR \\(String(format: "%.1f", Double(manager.targetDTR) ?? 0))%")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.textTertiary)
                                        Text("1차 팝 이후 계산됨")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.appSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // 종료
                    Button {
                        manager.finishRoasting()
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("종료 및 배출")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appSuccess)
                    .disabled(manager.roastState == .idle || manager.roastState == .completed)
                    .padding(.horizontal, 16)

                    if manager.roastState != .idle {
                        HStack(spacing: 8) {
                            // 다시 시작
                            Button {
                                manager.restartRoasting()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("다시 시작")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(.appWarning)

                            // 로스팅 취소
                            Button {
                                manager.cancelRoasting()
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                    Text("로스팅 취소")
                                }
                                .font(.system(size: 10, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(.appError)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 20)
                }
            } // ScrollView
            
            Spacer()
        } // Outer VStack
    }
"""

new_content = content[:start_idx] + sidebar_code + "\n    // MARK: - Main Dashboard View (Right)\n    \n    " + content[end_idx:]

with open("Sources/BluetoothSearch/ContentView.swift", "w") as f:
    f.write(new_content)

print("Done")
