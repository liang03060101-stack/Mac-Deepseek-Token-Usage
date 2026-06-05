import Foundation

// MARK: - DeepSeek API 客户端

actor DeepSeekService {

    private let baseURL = "https://api.deepseek.com"
    private var apiKey: String

    init(apiKey: String = "") {
        self.apiKey = apiKey
    }

    func updateKey(_ key: String) {
        self.apiKey = key
    }

    // MARK: - 余额查询

    func fetchBalance() async throws -> UserBalanceResponse {
        let url = URL(string: "\(baseURL)/user/balance")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.invalidResponse
        }
        if http.statusCode == 401 {
            throw DeepSeekError.invalidAPIKey
        }
        guard http.statusCode == 200 else {
            throw DeepSeekError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(UserBalanceResponse.self, from: data)
    }

    // MARK: - API Key 验证（发一个最小请求）

    func verifyAPIKey(_ key: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/models")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

// MARK: -

enum DeepSeekError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case httpError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:     return "API Key 无效，请检查后重试"
        case .invalidResponse:   return "服务器返回了无效响应"
        case .httpError(let c):  return "HTTP 错误 \(c)"
        case .decodingFailed:    return "响应数据解析失败"
        }
    }
}
