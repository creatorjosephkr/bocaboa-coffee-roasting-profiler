import SwiftUI

// MARK: - SessionResultSheet
// 로스팅 종료 직후 표시되는 결과 요약 + 저장/PDF/가이드 설정 시트

struct SessionResultSheet: View {
    let session: RoastSession
    let sessionStore: RoastSessionStore
    let onSetGuide: (RoastSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @State private var showReport = false
    @State private var memoText: String

    init(session: RoastSession, sessionStore: RoastSessionStore, onSetGuide: @escaping (RoastSession) -> Void) {
        self.session = session
        self.sessionStore = sessionStore
        self.onSetGuide = onSetGuide
        _memoText = State(initialValue: session.memo ?? "")
    }

    var body: some View {
        let updatedSession: RoastSession = {
            var s = session
            s.memo = memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memoText
            return s
        }()

        return VStack(spacing: 0) {
            // ── 헤더 ──────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("🎉 로스팅 완료!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(session.displayDate)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 원두 정보
                    beanInfoRow

                    // 결과 지표 그리드
                    metricsGrid

                    // 이벤트 타임라인 요약
                    eventTimeline

                    Divider()

                    // 메모 입력 필드
                    memoInputSection

                    Divider()

                    // 액션 버튼들
                    actionButtons
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 680)
        .background(Color.appBackground)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showReport) {
            VStack(spacing: 0) {
                HStack {
                    Text("리포트 미리보기")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        RoastReportView(session: updatedSession).savePDF()
                    } label: {
                        Label("PDF 저장", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)

                    Button {
                        RoastSessionStore.shared.saveWithPanel(updatedSession)
                    } label: {
                        Label("기록 내보내기", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.appAccent)

                    Button {
                        RoastReportView(session: updatedSession).printReport()
                    } label: {
                        Label("인쇄", systemImage: "printer.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.appAccent)

                    Button { showReport = false } label: {
                        Text("닫기").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.appSurface2)

                Divider()

                ScrollView {
                    RoastReportView(session: updatedSession)
                        .frame(width: 700)
                        .padding(20)
                }
                .background(Color.white)
            }
            .frame(width: 760, height: 700)
        }
    }

    // MARK: - Sub-views

    private var beanInfoRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .font(.system(size: 24))
                .foregroundColor(.appWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.beanName.isEmpty ? "원두명 미입력" : session.beanName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("투입량 \(session.beanWeight)g  ·  예열 \(session.preheatTemp)°C  ·  목표 DTR \(session.targetDTR)%")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
    }

    private var metricsGrid: some View {
        let items: [(String, String, String)] = [
            ("실제 DTR", session.finalDTR.map { String(format: "%.1f%%", $0) } ?? "—", "percent"),
            ("총 로스팅", session.totalRoastSeconds.map { fmtSec($0) } ?? "—", "timer"),
            ("Develop Time", session.devTimeSeconds.map { fmtSec($0) } ?? "—", "waveform"),
            ("배출 온도", session.finishTemp.map { String(format: "%.1f°C", $0) } ?? "—", "thermometer"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { label, value, icon in
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.appAccent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.textTertiary)
                        Text(value)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.appSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
            }
        }
    }

    private var eventTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이벤트 타임라인")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textTertiary)

            VStack(spacing: 4) {
                ForEach(session.events.filter { !["열량 조절", "예열 시작"].contains($0.type) }) { ev in
                    HStack(spacing: 8) {
                        Text(ev.formattedTime)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .frame(width: 50, alignment: .leading)
                        Text(ev.type)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(eventColor(ev.type))
                            .cornerRadius(4)
                        Text(String(format: "%.1f°C", ev.temperature))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textSecondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // 저장
            Button {
                var updated = session
                updated.memo = memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memoText
                sessionStore.save(updated)
                saved = true
            } label: {
                Label(saved ? "저장 완료 ✓" : "기록 저장 (자동경로)", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(saved ? .appSuccess : .appAccent)
            .disabled(saved)

            HStack(spacing: 10) {
                // 리포트/PDF
                Button {
                    showReport = true
                } label: {
                    Label("리포트 / PDF", systemImage: "doc.richtext")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .tint(.appAccent)

                // 가이드로 사용
                Button {
                    var updated = session
                    updated.memo = memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memoText
                    onSetGuide(updated)
                    dismiss()
                } label: {
                    Label("이 세션을 가이드로", systemImage: "map")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .tint(.appWarning)
            }

            Button { dismiss() } label: {
                Text("닫기")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.textTertiary)
        }
    }

    private var memoInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📝 로스팅 메모")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            TextEditor(text: $memoText)
                .font(.system(size: 11))
                .foregroundColor(.black)
                .frame(height: 70)
                .padding(6)
                .background(Color.white)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Helpers
    private func fmtSec(_ s: Double) -> String {
        String(format: "%02d:%02d", Int(s)/60, Int(s)%60)
    }
    private func eventColor(_ type: String) -> Color {
        switch type {
        case "투입": return .blue
        case "1차 팝": return .orange
        case "2차 팝": return .purple
        case "T.P": return .cyan
        case "종료": return .green
        case "목표 DTR 도달": return .red
        default: return .gray
        }
    }
}

// MARK: - SessionBrowserSheet
// 저장된 이전 세션 목록을 보고, 가이드로 불러오거나 삭제하는 시트

struct SessionBrowserSheet: View {
    @ObservedObject var sessionStore: RoastSessionStore
    let onLoadGuide: (RoastSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: RoastSession? = nil
    @State private var showReport = false
    @State private var confirmDeleteId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("로스팅 기록")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("\(sessionStore.sessions.count)개의 기록")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Button {
                    sessionStore.openWithPanel { session in
                        if let s = session { onLoadGuide(s) }
                    }
                } label: {
                    Label("파일에서 열기", systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .tint(.appAccent)

                Button {
                    sessionStore.revealInFinder()
                } label: {
                    Image(systemName: "folder.badge.magnifyingglass")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Finder에서 열기")
                .padding(.leading, 4)

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(16)
            .background(Color.appSurface2)

            Divider()

            if sessionStore.sessions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundColor(.textTertiary)
                    Text("저장된 기록이 없습니다")
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            } else {
                List(sessionStore.sessions) { session in
                    SessionRowView(
                        session: session,
                        onLoadGuide: { onLoadGuide(session) },
                        onShowReport: {
                            selectedSession = session
                            showReport = true
                        },
                        onDelete: {
                            confirmDeleteId = session.id
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.appBackground)
                }
                .listStyle(.plain)
                .background(Color.appBackground)
            }
        }
        .frame(width: 560, height: 500)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showReport) {
            if let session = selectedSession {
                VStack(spacing: 0) {
                    HStack {
                        Text("리포트 미리보기")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Button { RoastReportView(session: session).savePDF() } label: {
                            Label("PDF 저장", systemImage: "arrow.down.doc.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent).tint(.appAccent)
                        
                        Button { RoastSessionStore.shared.saveWithPanel(session) } label: {
                            Label("기록 내보내기", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered).tint(.appAccent)

                        Button { RoastReportView(session: session).printReport() } label: {
                            Label("인쇄", systemImage: "printer")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered).tint(.appAccent)
                        Button { showReport = false } label: { Text("닫기").font(.system(size: 11)) }
                            .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Color.appSurface2)
                    Divider()
                    ScrollView { RoastReportView(session: session).frame(width: 700).padding(20) }
                        .background(Color.white)
                }
                .frame(width: 760, height: 700)
                .preferredColorScheme(.light)
            }
        }
        .alert("기록 삭제", isPresented: Binding(
            get: { confirmDeleteId != nil },
            set: { if !$0 { confirmDeleteId = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let id = confirmDeleteId,
                   let session = sessionStore.sessions.first(where: { $0.id == id }) {
                    sessionStore.delete(session)
                }
                confirmDeleteId = nil
            }
            Button("취소", role: .cancel) { confirmDeleteId = nil }
        } message: {
            Text("이 기록을 삭제하면 복구할 수 없습니다.")
        }
    }
}

// MARK: - SessionRowView

private struct SessionRowView: View {
    let session: RoastSession
    let onLoadGuide: () -> Void
    let onShowReport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.beanName.isEmpty ? "원두명 미입력" : session.beanName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 6) {
                    Text(session.displayDate)
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                    if let dtr = session.finalDTR {
                        Text("DTR \(String(format: "%.1f%%", dtr))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.appWarning)
                    }
                    if let total = session.totalRoastSeconds {
                        let m = Int(total)/60; let s = Int(total)%60
                        Text(String(format: "%02d:%02d", m, s))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    onShowReport()
                } label: {
                    Label("리포트", systemImage: "doc.text")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .tint(.appAccent)

                Button {
                    onLoadGuide()
                } label: {
                    Label("가이드로", systemImage: "map")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderedProminent)
                .tint(.appWarning)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.appError)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
