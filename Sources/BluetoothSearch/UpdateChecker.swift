import Foundation

class UpdateChecker: ObservableObject {
    @Published var isUpdateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseUrl: URL?
    
    private let githubApiUrl = URL(string: "https://api.github.com/repos/creatorjosephkr/bocaboa-coffee-roasting-profiler/releases/latest")!
    
    func checkForUpdates() {
        let task = URLSession.shared.dataTask(with: githubApiUrl) { data, response, error in
            guard let data = data, error == nil else {
                print("Failed to fetch update info:", error?.localizedDescription ?? "Unknown error")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let htmlUrlString = json["html_url"] as? String,
                   let htmlUrl = URL(string: htmlUrlString) {
                    
                    // 태그에서 'v' 제거 (예: "v1.1" -> "1.1")
                    let latestVersionString = tagName.replacingOccurrences(of: "v", with: "")
                    
                    // 현재 앱 버전 가져오기
                    if let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        
                        // 버전 비교
                        if self.isVersionGreater(latest: latestVersionString, current: currentVersionString) {
                            DispatchQueue.main.async {
                                self.latestVersion = latestVersionString
                                self.releaseUrl = htmlUrl
                                self.isUpdateAvailable = true
                            }
                        }
                    }
                }
            } catch {
                print("Failed to parse update info JSON:", error.localizedDescription)
            }
        }
        task.resume()
    }
    
    private func isVersionGreater(latest: String, current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        let count = max(latestParts.count, currentParts.count)
        
        for i in 0..<count {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            
            if l > c { return true }
            if l < c { return false }
        }
        
        return false
    }
}
