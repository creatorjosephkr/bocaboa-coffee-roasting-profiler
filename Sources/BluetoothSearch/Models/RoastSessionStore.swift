import Foundation
import AppKit

// MARK: - RoastSessionStore

/// ~/Documents/BocaRoast/ 폴더에 RoastSession JSON 파일을 저장·로드·삭제한다.
@MainActor
final class RoastSessionStore: ObservableObject {

    @Published var sessions: [RoastSession] = []

    static let shared = RoastSessionStore()

    private var storageURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("BocaRoast", isDirectory: true)
    }

    private init() {
        ensureDirectory()
        loadAll()
    }

    // MARK: - Public API

    /// 세션을 ~/Documents/BocaRoast/ 에 JSON 저장
    func save(_ session: RoastSession) {
        ensureDirectory()
        let url = storageURL.appendingPathComponent(session.suggestedFileName)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
            loadAll()
        } catch {
            print("RoastSessionStore save error: \(error)")
        }
    }

    /// 저장 위치를 사용자가 직접 선택 (NSSavePanel)
    func saveWithPanel(_ session: RoastSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = session.suggestedFileName
        panel.directoryURL = storageURL
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(session)
                try data.write(to: url, options: .atomic)
                self?.loadAll()
            } catch {
                print("RoastSessionStore saveWithPanel error: \(error)")
            }
        }
    }

    /// 파일 선택 패널로 세션 불러오기 (반환값으로 단일 세션)
    func openWithPanel(completion: @escaping (RoastSession?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = storageURL
        panel.allowsMultipleSelection = false
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { completion(nil); return }
            completion(Self.decode(from: url))
        }
    }

    /// 외부 파일 선택 패널(NSOpenPanel)로 로스팅 JSON 파일을 가져와 BocaRoast 보관 폴더에 영구 등록
    func importSessionStore(completion: @escaping (Bool, String?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "외부 로스팅 프로파일 가져오기"
        panel.prompt = "가져오기"
        
        panel.begin { [weak self] resp in
            guard resp == .OK, let srcURL = panel.url else {
                completion(false, nil)
                return
            }
            
            do {
                // 1. 디코딩 검증
                let data = try Data(contentsOf: srcURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                let session = try decoder.decode(RoastSession.self, from: data)
                
                // 2. 타겟 위치 정의 (~/Documents/BocaRoast/날짜_이름.json)
                self?.ensureDirectory()
                if let destURL = self?.storageURL.appendingPathComponent(session.suggestedFileName) {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try data.write(to: destURL, options: .atomic)
                    self?.loadAll()
                    completion(true, session.beanName)
                } else {
                    completion(false, "저장 경로 생성 실패")
                }
            } catch {
                completion(false, error.localizedDescription)
            }
        }
    }

    /// 세션 삭제
    func delete(_ session: RoastSession) {
        let url = storageURL.appendingPathComponent(session.suggestedFileName)
        try? FileManager.default.removeItem(at: url)
        loadAll()
    }

    /// 기록 이름(원두명) 변경
    func rename(_ session: RoastSession, newName: String) {
        let oldURL = storageURL.appendingPathComponent(session.suggestedFileName)
        // beanName은 let이므로 별도 인코딩
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        // JSON으로 인코드 후 beanName 수정
        if var dict = (try? encoder.encode(session))
            .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) {
            dict["beanName"] = newName
            if let newData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
                let newFileName: String = {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyyMMdd_HHmm"
                    let dateStr = formatter.string(from: session.date)
                    let safe = newName.isEmpty ? "unnamed" : newName.replacingOccurrences(of: " ", with: "_")
                    return "\(dateStr)_\(safe).json"
                }()
                let newURL = storageURL.appendingPathComponent(newFileName)
                try? FileManager.default.removeItem(at: oldURL)
                try? newData.write(to: newURL, options: .atomic)
                loadAll()
            }
        }
    }

    /// 폴더를 Finder에서 열기
    func revealInFinder() {
        NSWorkspace.shared.open(storageURL)
    }

    // MARK: - Private helpers

    func loadAll() {
        ensureDirectory()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? FileManager.default.contentsOfDirectory(
            at: storageURL, includingPropertiesForKeys: nil
        ))?.compactMap { url -> RoastSession? in
            guard url.pathExtension == "json" else { return nil }
            return Self.decode(from: url)
        }.sorted { $0.date > $1.date } ?? []
    }

    private static func decode(from url: URL) -> RoastSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RoastSession.self, from: data)
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageURL.path) {
            try? fm.createDirectory(at: storageURL, withIntermediateDirectories: true)
        }
    }
}
