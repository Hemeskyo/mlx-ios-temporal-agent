//
//  WikipediaDataProvider.swift
//  mlx-ios-toolcall
//
//  Fetches daily Wikipedia pageviews for any subject (public data, no key) into a
//  time series for TimesFM. Resolves free-text subjects to a canonical article
//  title first, so messy/varied LLM input maps to the same real article.
//

import Foundation

actor WikipediaDataProvider {
    enum WikiError: LocalizedError {
        case badTopic, http(Int), noMatch, noData, decode
        var errorDescription: String? {
            switch self {
            case .badTopic:    return "Couldn't build a request for that subject."
            case .http(let c): return "Wikipedia returned HTTP \(c)."
            case .noMatch:     return "No Wikipedia article matched that subject."
            case .noData:      return "Not enough Wikipedia pageview history for that subject."
            case .decode:      return "Couldn't parse Wikipedia's response."
            }
        }
    }

    private let userAgent = "Temporal-iOS/1.0 (on-device forecasting demo)"

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // Wikimedia requires a descriptive User-Agent, otherwise it returns 403.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WikiError.noData }
        guard (200 ..< 300).contains(http.statusCode) else { throw WikiError.http(http.statusCode) }
        return data
    }

    /// Resolve free text to a canonical English-Wikipedia article title (handles
    /// case, redirects, and loose phrasing) via the opensearch API.
    private func resolveTitle(_ topic: String) async throws -> String {
        let query = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=opensearch&search=\(encoded)&limit=1&namespace=0&format=json")
        else { throw WikiError.badTopic }

        let data = try await fetch(url)
        // opensearch returns: [query, [titles], [descriptions], [urls]]
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2, let titles = json[1] as? [String],
              let best = titles.first, !best.isEmpty
        else { throw WikiError.noMatch }
        return best
    }

    private struct Response: Decodable {
        struct Item: Decodable { let timestamp: String; let views: Int }
        let items: [Item]
    }

    /// Resolve `topic` to a real article, then fetch its daily pageviews over the
    /// last `days` days. Returns the resolved title plus the series (oldest first).
    func dailyPageviews(topic: String, days: Int = 120) async throws -> (title: String, points: [TimeSeriesPoint]) {
        let title = try await resolveTitle(topic)
        let article = title.replacingOccurrences(of: " ", with: "_")
        guard let encoded = article.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
            throw WikiError.badTopic
        }

        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { throw WikiError.noData }
        let day = DateFormatter()
        day.dateFormat = "yyyyMMdd"
        day.timeZone = TimeZone(identifier: "UTC")

        guard let url = URL(string:
            "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/"
            + "en.wikipedia.org/all-access/user/\(encoded)/daily/\(day.string(from: start))/\(day.string(from: end))")
        else { throw WikiError.badTopic }

        let data = try await fetch(url)
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw WikiError.decode }

        // Wikimedia timestamps look like "2026010100" (YYYYMMDDHH, hour always 00).
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMddHH"
        stamp.timeZone = TimeZone(identifier: "UTC")

        let points = decoded.items.compactMap { item -> TimeSeriesPoint? in
            guard let date = stamp.date(from: item.timestamp) else { return nil }
            return TimeSeriesPoint(date: date, value: Double(item.views))
        }
        guard !points.isEmpty else { throw WikiError.noData }
        return (title, points.sorted { $0.date < $1.date })
    }
}
