import Foundation

class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var downloadURL: URL?

    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return latest != currentVersion
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private let repo = "HongChaeMin/catch-catch"

    func check() {
        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self, error == nil, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            // tag: "v0.0.3" → "0.0.3"
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // DMG asset URL
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmgAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            let dmgURL = (dmgAsset?["browser_download_url"] as? String).flatMap { URL(string: $0) }

            DispatchQueue.main.async {
                self.latestVersion = version
                self.downloadURL = dmgURL
            }
        }.resume()
    }
}
