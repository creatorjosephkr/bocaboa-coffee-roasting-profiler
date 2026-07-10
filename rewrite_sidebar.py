import sys

content = open("Sources/BluetoothSearch/ContentView.swift").read()
start_idx = content.find("    @ViewBuilder\n    private var sidebarView: some View {")
end_idx = content.find("    // MARK: - Main Dashboard View (Right)")

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
                    
                    Divider().padding(.horizontal, 16)
                    
                    // 로스팅 세션 입력 폼
                    VStack(spacing: 10) {
                        Text("로스팅 세션 설정")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("커피 품종")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            TextField("예: Ethiopia Yirgacheffe G1", text: $manager.beanName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack(spacing: 8) {
                            Text("가공 방식")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            let methods = ["워시드 (Washed)", "내추럴 (Natural)", "허니 (Honey)", "무산소 (Anaerobic)", "디카페인 (Decaf)", "기타"]
                            Picker("", selection: $manager.processingMethod) {
                                ForEach(methods, id: \\.self) { method in
                                    Text(method).tag(method)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            Text("로스팅 목적")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            let purposes = ["핸드드립용", "에스프레소용", "모카포트용", "프렌치프레스용", "기타"]
                            Picker("", selection: $manager.roastPurpose) {
                                ForEach(purposes, id: \\.self) { purpose in
                                    Text(purpose).tag(purpose)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("투입 용량 (g)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                TextField("160", text: $manager.beanWeight)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("예열 온도 (°C)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                TextField("220", text: $manager.preheatTemp)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("목표 DTR(%)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Text("권장 14~18%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.appAccent)
                            }
                            
                            HStack(spacing: 8) {
                                Slider(value: dtrSliderBinding, in: 10.0...25.0)
                                
                                TextField("15.0", text: $manager.targetDTR)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // 아그트론 그라데이션 바
                        let agtronColors = [
                            Color(hex: "#CE8101"), // 95
                            Color(hex: "#C47C04"), // 85
                            Color(hex: "#B46B0C"), // 75
                            Color(hex: "#995515"), // 65
                            Color(hex: "#8B4B1B"), // 55
                            Color(hex: "#7A4719"), // 45
                            Color(hex: "#673F1C"), // 35
                            Color(hex: "#532C1B")  // 25
                        ]
                        
                        VStack(spacing: 4) {
                            HStack {
                                Text("Agtron: #\\(currentAgtronValue)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.appAccent)
                                Spacer()
                            }
                            
                            GeometryReader { geo in
                                let dtrVal = Double(manager.targetDTR) ?? 15.0
                                let clampedDtr = max(10.0, min(25.0, dtrVal))
                                let percent = (clampedDtr - 10.0) / 15.0
                                let indicatorWidth: CGFloat = 8.0
                                let safeWidth = geo.size.width - indicatorWidth
                                let indicatorX = (safeWidth * CGFloat(percent)) + (indicatorWidth / 2)
                                
                                ZStack(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(LinearGradient(colors: agtronColors, startPoint: .leading, endPoint: .trailing))
                                        .frame(height: 14)
                                        .padding(.top, 8)
                                    
                                    Image(systemName: "triangle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.appAccent)
                                        .position(x: indicatorX, y: 4)
                                }
                            }
                            .frame(height: 22)
                        }
                        .padding(.top, 4)
                        
                        // 1행 3열 Agtron 상세 정보 테이블
                        HStack(spacing: 0) {
                            let detail = currentAgtronDetail
                            
                            VStack(spacing: 2) {
                                Text("수치 범위")
                                    .font(.system(size: 9))
                                    .foregroundColor(.textSecondary)
                                Text(detail.range)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider().frame(height: 18)
                            
                            VStack(spacing: 2) {
                                Text("일반 분류")
                                    .font(.system(size: 9))
                                    .foregroundColor(.textSecondary)
                                Text(detail.common)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider().frame(height: 18)
                            
                            VStack(spacing: 2) {
                                Text("SCA 분류")
                                    .font(.system(size: 9))
                                    .foregroundColor(.textSecondary)
                                Text(detail.sca)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 6)
                        .background(Color.appSurface2)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)

                    Divider().padding(.horizontal, 16)

                    // 수동 열량 조절 (0~12)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("수동 열량 조절 (0~12)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Text("\\(manager.currentHeat)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                        }
                        
                        HStack {
                            Slider(value: Binding(
                                get: { Double(manager.currentHeat) },
                                set: { manager.currentHeat = Int($0) }
                            ), in: 0...12, step: 1.0)
                            
                            Stepper("", value: Binding(
                                get: { manager.currentHeat },
                                set: { manager.currentHeat = $0 }
                            ), in: 0...12)
                            .labelsHidden()
                        }
                        
                        Button {
                            manager.adjustHeat(to: manager.currentHeat)
                        } label: {
                            Text("열량 변경 확인")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.gray)
                    }
                    .padding(8)
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    .padding(.horizontal, 16)

                    // 액션 버튼 그룹 (2x2)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                manager.startPreheating()
                            } label: {
                                HStack {
                                    Image(systemName: "flame.fill")
                                    Text("예열 시작")
                                }
                                .font(.system(size: 11, weight: .bold))
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
                                    Image(systemName: "tray.and.arrow.down.fill")
                                    Text("생두 투입")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.appAccent)
                            .disabled(manager.roastState != .preheating)
                        }
                        
                        HStack(spacing: 8) {
                            Button {
                                manager.triggerFirstPop()
                            } label: {
                                Text("1차 팝")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(manager.roastState == .roasting ? .white : .textTertiary)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(manager.roastState == .roasting ? .pink : Color.appSurface)
                            .disabled(manager.roastState != .roasting)
                            
                            Button {
                                manager.triggerSecondPop()
                            } label: {
                                Text("2차 팝")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundColor(manager.roastState == .firstPop ? .white : .textTertiary)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(manager.roastState == .firstPop ? .pink : Color.appSurface)
                            .disabled(manager.roastState != .firstPop)
                        }
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
        .frame(width: 320)
        .background(Color.appSurface2)
    }
"""

new_content = content[:start_idx] + sidebar_code + "\n" + content[end_idx:]

with open("Sources/BluetoothSearch/ContentView.swift", "w") as f:
    f.write(new_content)

