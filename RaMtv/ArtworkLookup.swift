import Foundation

enum ArtworkLookup {
    static func validURL(_ value: String?) -> URL? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !["null", "undefined", "n/a"].contains(value.lowercased()) else { return nil }
        if value.hasPrefix("//") { value = "https:" + value }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    static func seriesTitle(_ raw: String) -> String {
        if raw.range(of: "wwe", options: .caseInsensitive) != nil {
            if raw.range(of: "\\braw\\b", options: [.regularExpression, .caseInsensitive]) != nil { return "WWE Raw" }
            if raw.range(of: "smackdown", options: .caseInsensitive) != nil { return "WWE Friday Night SmackDown" }
        }
        var title = raw.replacingOccurrences(
            of: "\\bS(?:eason)?\\s*\\d{1,4}(?:\\s*E\\d+)?\\b.*$",
            with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(
            of: "\\b(?:19|20)\\d{2}[- /]\\d{1,2}[- /]\\d{1,2}\\s*$",
            with: "", options: .regularExpression)
        title = TitleCleaner.parse(title).title
        return title.isEmpty ? TitleCleaner.parse(raw).title : title
    }

    static func providerURL(_ value: String?, base: String) -> String? {
        if let absolute = validURL(value) { return absolute.absoluteString }
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !["null", "undefined", "n/a"].contains(value.lowercased()),
              let baseURL = URL(string: base + "/"),
              let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else { return nil }
        return validURL(resolved.absoluteString)?.absoluteString
    }

    static func channelName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(
            of: "(?:^|[\\s_-])(?:240|360|480|540|576|720|1080|1440|2160)p?\\b",
            with: " ", options: [.regularExpression, .caseInsensitive])
        name = name.replacingOccurrences(
            of: "[\\s_-]\\d+\\s*h\\b", with: "", options: [.regularExpression, .caseInsensitive])
        return name
    }
}
