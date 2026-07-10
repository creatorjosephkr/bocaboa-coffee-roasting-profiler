import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bocaboa.BluetoothSearch"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let otherApps = runningApps.filter { $0.processIdentifier != currentProcessID }
        
        if !otherApps.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "앱이 이미 실행 중입니다."
            alert.informativeText = "이미 실행 중인 보카보아 앱이 있습니다. 기존 앱을 강제 종료하고 새로 실행하시겠습니까?"
            alert.addButton(withTitle: "기존 앱 종료 후 실행")
            alert.addButton(withTitle: "실행 취소")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                for app in otherApps {
                    app.forceTerminate()
                }
            } else {
                NSApp.terminate(nil)
            }
        }
    }
}

@main
struct BluetoothSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var nicknameStore = NicknameStore()

    var body: some Scene {
        WindowGroup(id: "BocaBoaMain") {
            ContentView()
                .environmentObject(nicknameStore)
        }
        .defaultSize(width: 1700, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("보카보아 정보") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "보카보아",
                            NSApplication.AboutPanelOptionKey.version: "BocaBoa - 보카보카250BT 커피로스터 로스팅 프로파일러"
                        ]
                    )
                }
            }
        }
    }
}
