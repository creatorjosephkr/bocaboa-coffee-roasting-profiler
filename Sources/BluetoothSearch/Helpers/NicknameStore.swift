import Foundation
import Combine

// MARK: - NicknameStore
// UserDefaults에 기기 UUID → 별명 매핑을 저장하는 공유 저장소

final class NicknameStore: ObservableObject {
    @Published private(set) var nicknames: [String: String] = [:]

    private let defaultsKey = "ble.device.nicknames.v1"

    init() {
        load()
    }

    // MARK: - Public API

    func nickname(for uuid: String) -> String? {
        nicknames[uuid]
    }

    /// 빈 문자열이면 삭제, 아니면 저장
    func setNickname(_ nickname: String, for uuid: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            nicknames.removeValue(forKey: uuid)
        } else {
            nicknames[uuid] = trimmed
        }
        save()
    }

    func removeNickname(for uuid: String) {
        nicknames.removeValue(forKey: uuid)
        save()
    }

    func hasNickname(for uuid: String) -> Bool {
        nicknames[uuid] != nil
    }

    // MARK: - Persistence

    private func load() {
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] {
            nicknames = stored
        }
    }

    private func save() {
        UserDefaults.standard.set(nicknames, forKey: defaultsKey)
    }
}
