import Foundation
import Network

// MARK: - 本地代理服务器
// 架构说明：
//   用户把 LLM 工具的 base_url 设为 http://localhost:<port>
//   所有请求经过本代理转发到 https://api.deepseek.com
//   代理在转发前注入 stream_options.include_usage=true，确保 streaming 模式也返回 usage
//   代理在收到响应后解析 usage 字段并写入本地存储

actor LocalProxyServer {

    // MARK: 公开属性
    private(set) var running = false
    private(set) var requestCount = 0
    private(set) var port: UInt16

    // MARK: 私有
    private var listener: NWListener?
    private let usageTracker: UsageTracker

    init(port: UInt16, usageTracker: UsageTracker) {
        self.port = port
        self.usageTracker = usageTracker
    }

    // MARK: - 启动 / 停止

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ProxyError.invalidPort(port)
        }
        let nwListener = try NWListener(using: params, on: nwPort)
        nwListener.newConnectionHandler = { [weak self] conn in
            Task { await self?.handleConnection(conn) }
        }
        nwListener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                print("[Proxy] ❌ Listener 失败: \(err)")
            }
        }
        nwListener.start(queue: .global(qos: .utility))
        self.listener = nwListener
        running = true
        print("[Proxy] ✅ 启动于 http://localhost:\(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
        print("[Proxy] 已停止")
    }

    // MARK: - 连接处理

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        receiveRequest(conn: conn)
    }

    private func receiveRequest(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error = error {
                print("[Proxy] ⚠️ 接收错误: \(error)")
                conn.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete { conn.cancel() }
                return
            }
            Task { await self.processRequest(conn: conn, rawData: data) }
        }
    }

    // MARK: - HTTP 请求解析

    private func processRequest(conn: NWConnection, rawData: Data) {
        guard let rawStr = String(data: rawData, encoding: .utf8) else {
            sendError(conn: conn, status: 400, message: "Invalid UTF-8 request")
            return
        }

        // 分离 headers 和 body
        let separator = "\r\n\r\n"
        guard let separatorRange = rawStr.range(of: separator) else {
            sendError(conn: conn, status: 400, message: "Malformed HTTP request")
            return
        }

        let headerSection = String(rawStr[rawStr.startIndex..<separatorRange.lowerBound])
        let bodyStr = String(rawStr[separatorRange.upperBound...])
        let bodyData = Data(bodyStr.utf8)

        let headerLines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else {
            sendError(conn: conn, status: 400, message: "Empty request")
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendError(conn: conn, status: 400, message: "Bad request line")
            return
        }

        let method = String(parts[0])
        let path   = String(parts[1])

        // 解析 headers
        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces).lowercased()
                let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        // 处理 OPTIONS 预检（部分 SDK 会发）
        if method == "OPTIONS" {
            sendOptions(conn: conn)
            return
        }

        proxyRequest(conn: conn, method: method, path: path, headers: headers, body: bodyData)
    }

    // MARK: - 代理转发

    private func proxyRequest(conn: NWConnection, method: String, path: String,
                              headers: [String: String], body: Data) {
        // 构造上游 URL
        let base = "https://api.deepseek.com"
        guard let url = URL(string: base + path) else {
            sendError(conn: conn, status: 400, message: "Invalid path: \(path)"); return
        }

        // ── 关键：注入 stream_options.include_usage = true ──
        // DeepSeek 在 stream:true 时，默认不一定返回 usage
        // 需要显式传 "stream_options": {"include_usage": true}
        let (processedBody, isStreaming) = injectStreamOptions(body: body, path: path, method: method)

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        req.httpMethod = method
        req.httpBody = processedBody.isEmpty ? nil : processedBody

        // 转发全部请求头（跳过 hop-by-hop）
        let hopByHop: Set<String> = ["connection", "proxy-connection", "transfer-encoding",
                                      "host", "content-length", "keep-alive",
                                      "proxy-authenticate", "proxy-authorization",
                                      "te", "trailer", "upgrade"]
        for (key, value) in headers where !hopByHop.contains(key) {
            req.setValue(value, forHTTPHeaderField: key)
        }
        // Content-Length 要根据实际 body 设置
        if !processedBody.isEmpty {
            req.setValue("\(processedBody.count)", forHTTPHeaderField: "Content-Length")
        }

        print("[Proxy] → \(method) \(path) \(isStreaming ? "[stream]" : "[非stream]")")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error {
                print("[Proxy] ❌ 上游请求失败: \(error.localizedDescription)")
                self.sendError(conn: conn, status: 502, message: "Upstream error: \(error.localizedDescription)")
                conn.cancel()
                return
            }

            guard let httpResp = response as? HTTPURLResponse,
                  let respData = data else {
                self.sendError(conn: conn, status: 502, message: "No response")
                conn.cancel()
                return
            }

            // ── 调试：打印原始响应前 2000 字符 ──
            if let preview = String(data: respData, encoding: .utf8) {
                let short = preview.prefix(2000)
                print("[Proxy] ← 状态: \(httpResp.statusCode) | 前2000字符:\n\(short)")
            }

            // ── 捕获 usage ──
            if path.contains("/chat/completions") || path.contains("/completions") {
                Task {
                    await self.captureUsage(from: respData, isStreaming: isStreaming)
                }
            }

            Task { @MainActor in self.requestCount += 1 }

            // ── 构造 HTTP 响应 ──
            var respStr = "HTTP/1.1 \(httpResp.statusCode) \(Self.statusText(httpResp.statusCode))\r\n"
            let skipHeaders: Set<String> = ["connection", "transfer-encoding",
                                             "content-length", "keep-alive"]
            for (k, v) in httpResp.allHeaderFields {
                let ks = "\(k)".lowercased()
                if !skipHeaders.contains(ks) {
                    respStr += "\(k): \(v)\r\n"
                }
            }
            respStr += "Content-Length: \(respData.count)\r\n"
            respStr += "Access-Control-Allow-Origin: *\r\n"
            respStr += "Connection: close\r\n\r\n"

            var out = Data(respStr.utf8)
            out.append(respData)
            conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
        }.resume()
    }

    // MARK: - 注入 stream_options

    /// 如果是 streaming 请求，注入 stream_options.include_usage=true
    /// 返回 (处理后的 body, isStreaming)
    private func injectStreamOptions(body: Data, path: String, method: String) -> (Data, Bool) {
        guard method == "POST",
              path.contains("/chat/completions") || path.contains("/completions"),
              !body.isEmpty,
              var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return (body, false)
        }

        // 检测是否 streaming（安全方式：解析 JSON，而不是字符串匹配）
        let isStreaming = (json["stream"] as? Bool) == true

        if isStreaming {
            // 注入 stream_options.include_usage = true
            var streamOpts = (json["stream_options"] as? [String: Any]) ?? [:]
            streamOpts["include_usage"] = true
            json["stream_options"] = streamOpts
            if let newBody = try? JSONSerialization.data(withJSONObject: json) {
                print("[Proxy] ✅ 已注入 stream_options.include_usage=true")
                return (newBody, true)
            }
        }
        return (body, isStreaming)
    }

    // MARK: - Usage 捕获

    private func captureUsage(from respData: Data, isStreaming: Bool) async {
        guard !respData.isEmpty else {
            print("[Proxy] ⚠️ captureUsage: 响应体为空")
            return
        }

        if isStreaming {
            await captureUsageFromSSE(respData: respData)
        } else {
            await captureUsageFromJSON(respData: respData)
        }
    }

    /// 非流式：直接从顶层 JSON 读 usage
    private func captureUsageFromJSON(respData: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            let preview = String(data: respData, encoding: .utf8)?.prefix(300) ?? "<binary>"
            print("[Proxy] ❌ JSON 解析失败。前300字: \(preview)")
            return
        }

        guard let usage = json["usage"] as? [String: Any] else {
            print("[Proxy] ⚠️ JSON 无 usage 字段。顶层 keys: \(Array(json.keys))")
            return
        }

        print("[Proxy] ✅ 非流式 usage: \(usage)")
        await recordUsage(from: usage, model: json["model"] as? String)
    }

    /// 流式：逐行解析 SSE 事件，从包含 usage 的 chunk 提取
    private func captureUsageFromSSE(respData: Data) async {
        guard let text = String(data: respData, encoding: .utf8) else {
            print("[Proxy] ❌ SSE 解码失败（非 UTF-8）")
            return
        }

        // SSE 格式：每行 "data: {...}" 或 "data: [DONE]"
        var foundUsage = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonStr = String(trimmed.dropFirst(6))
            guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }
            guard let lineData = jsonStr.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if let usage = chunk["usage"] as? [String: Any],
               (usage["prompt_tokens"] as? Int ?? 0) > 0 || (usage["completion_tokens"] as? Int ?? 0) > 0 {
                print("[Proxy] ✅ SSE usage found: \(usage)")
                await recordUsage(from: usage, model: chunk["model"] as? String)
                foundUsage = true
                break   // 找到就退出，避免重复计数
            }
        }

        if !foundUsage {
            // 诊断信息
            let eventCount = text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("data: ") && !$0.contains("[DONE]") }.count
            print("[Proxy] ⚠️ SSE: \(eventCount) 个事件，均无有效 usage。可能原因：")
            print("[Proxy]   1. stream_options.include_usage 未被 DeepSeek 接受")
            print("[Proxy]   2. 模型/接口不支持 streaming usage（尝试 stream:false）")
        }
    }

    /// 记录到持久化存储
    private func recordUsage(from usage: [String: Any], model: String?) async {
        let prompt     = usage["prompt_tokens"]     as? Int ?? 0
        let completion = usage["completion_tokens"] as? Int ?? 0
        let modelName  = model ?? "deepseek-chat"

        guard prompt > 0 || completion > 0 else {
            print("[Proxy] ⚠️ 跳过：prompt=\(prompt) completion=\(completion)")
            return
        }

        let record = TokenUsageRecord(model: modelName, promptTokens: prompt, completionTokens: completion)
        do {
            try await usageTracker.save(record)
            print("[Proxy] ✅ 已记录 ↑\(prompt) ↓\(completion) [\(modelName)]")
        } catch {
            print("[Proxy] ❌ 保存失败: \(error)")
        }
    }

    // MARK: - 辅助方法

    private func sendError(conn: NWConnection, status: Int, message: String) {
        let body = message
        var resp  = "HTTP/1.1 \(status) \(Self.statusText(status))\r\n"
        resp += "Content-Type: text/plain\r\n"
        resp += "Content-Length: \(body.utf8.count)\r\n"
        resp += "Connection: close\r\n\r\n"
        resp += body
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private func sendOptions(conn: NWConnection) {
        let resp = "HTTP/1.1 200 OK\r\n" +
                   "Access-Control-Allow-Origin: *\r\n" +
                   "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
                   "Access-Control-Allow-Headers: *\r\n" +
                   "Content-Length: 0\r\n" +
                   "Connection: close\r\n\r\n"
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default:  return "Unknown"
        }
    }
}

// MARK: -

enum ProxyError: Error {
    case invalidPort(UInt16)
}
