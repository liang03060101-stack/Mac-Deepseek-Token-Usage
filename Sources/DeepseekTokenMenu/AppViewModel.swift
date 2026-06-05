import SwiftUI
import AppKit

// MARK: - 中央 ViewModel

@MainActor
final class AppViewModel: ObservableObject {

    // MARK: 用量数据
    @Published var todayUsage:   AggregatedUsage = .zero
    @Published var weekUsage:    AggregatedUsage = .zero
    @Published var monthUsage:   AggregatedUsage = .zero
    @Published var allTimeUsage: AggregatedUsage = .zero
    @Published var recordCount:  Int = 0

    // 图表 & 模型分布
    @Published var dailyChartData:  [(Date, AggregatedUsage)] = []
    @Published var modelBreakdown:  [(String, AggregatedUsage)] = []
    @Published var recordHistory:   [TokenUsageRecord] = []

    // MARK: 余额
    @Published var balance: String = "—"
    @Published var balanceAvailable: Bool = true

    // MARK: 代理
    @Published var proxyRunning: Bool    = false
    @Published var proxyPort: UInt16     = 18923
    var proxyURL: String { "http://localhost:\(proxyPort)" }

    // MARK: API Key
    @Published var apiKey: String        = ""
    @Published var apiKeyVerified: Bool  = false
    @Published var apiKeyError: String?  = nil
    var showSetupGuide: Bool { apiKey.isEmpty }

    // MARK: 状态
    @Published var isLoading: Bool       = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool       = false

    // MARK: 记录排序
    enum SortOrder: String, CaseIterable, Identifiable {
        case newestFirst, oldestFirst
        var id: String { rawValue }
        var label: String { self == .newestFirst ? "最新优先" : "最早优先" }
    }
    @Published var recordSort: SortOrder = .newestFirst

    // MARK: Services
    private let usageTracker   = UsageTracker()
    private let deepSeekService = DeepSeekService()
    private var proxy: LocalProxyServer?

    // MARK: 刷新定时器
    private var refreshTask: Task<Void, Never>?
    private var balanceTask: Task<Void, Never>?

    // MARK: - 初始化

    func initialize() async {
        // 加载 API Key
        if let key = KeychainManager.load(), !key.isEmpty {
            apiKey         = key
            apiKeyVerified = true
            await deepSeekService.updateKey(key)
        }

        // 恢复代理端口
        proxyPort = UInt16(UserDefaults.standard.integer(forKey: "proxyPort")
            .clamped(to: 1024...65535)) ?? 18923

        // 自动启动代理
        if apiKeyVerified {
            await startProxy()
        }

        // 加载本地数据 & 余额
        await loadLocalData()
        if apiKeyVerified {
            await refreshBalance()
        }

        // 定时刷新
        startAutoRefresh()
    }

    // MARK: - 数据加载

    func loadLocalData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            todayUsage   = try await usageTracker.getAggregatedUsage(for: .today)
            weekUsage    = try await usageTracker.getAggregatedUsage(for: .week)
            monthUsage   = try await usageTracker.getAggregatedUsage(for: .month)
            allTimeUsage = try await usageTracker.getAllTimeUsage()
            recordCount  = await usageTracker.recordCount

            dailyChartData = try await usageTracker.getDailyUsage(lastDays: 7)
            modelBreakdown = try await usageTracker.getModelBreakdown()

            await loadRecordHistory()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func loadRecordHistory() async {
        do {
            var recs = try await usageTracker.loadAll()
            recs.sort { recordSort == .newestFirst ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp }
            recordHistory = recs
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - 余额

    func refreshBalance() async {
        guard apiKeyVerified else { return }
        do {
            let resp = try await deepSeekService.fetchBalance()
            balanceAvailable = resp.isAvailable
            if let cny = resp.balanceInfos.first(where: { $0.currency == "CNY" }) {
                balance = "¥\(cny.totalBalance)"
            } else if let usd = resp.balanceInfos.first(where: { $0.currency == "USD" }) {
                balance = "$\(usd.totalBalance)"
            } else {
                balance = "—"
            }
        } catch {
            balance = "查询失败"
        }
    }

    // MARK: - API Key 管理

    func saveAndVerifyKey(_ raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { apiKeyError = "Key 不能为空"; return }

        isLoading    = true
        apiKeyError  = nil

        defer { isLoading = false }

        do {
            let valid = try await deepSeekService.verifyAPIKey(key)
            if valid {
                try KeychainManager.save(key)
                apiKey         = key
                apiKeyVerified = true
                await deepSeekService.updateKey(key)
                await startProxy()
                await loadLocalData()
                await refreshBalance()
                startAutoRefresh()
            } else {
                apiKeyError = "API Key 无效，请检查"
            }
        } catch let e as DeepSeekError {
            apiKeyError = e.errorDescription
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    func deleteAPIKey() {
        try? KeychainManager.delete()
        apiKey         = ""
        apiKeyVerified = false
        apiKeyError    = nil
        balance        = "—"
        stopProxy()
        refreshTask?.cancel()
        balanceTask?.cancel()
    }

    // MARK: - 代理管理

    func startProxy() async {
        guard !proxyRunning else { return }
        let p = LocalProxyServer(port: proxyPort, usageTracker: usageTracker)
        do {
            try await p.start()
            proxy        = p
            proxyRunning = true
        } catch {
            showError("代理启动失败: \(error.localizedDescription)")
        }
    }

    func stopProxy() {
        Task { await proxy?.stop() }
        proxy        = nil
        proxyRunning = false
    }

    func restartProxy(port: UInt16) async {
        stopProxy()
        proxyPort = port
        UserDefaults.standard.set(Int(port), forKey: "proxyPort")
        await startProxy()
    }

    func copyProxyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(proxyURL, forType: .string)
    }

    // MARK: - 记录管理

    func deleteRecord(_ id: UUID) async {
        do {
            try await usageTracker.deleteRecord(id: id)
            await loadLocalData()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func clearAllData() async {
        do {
            try await usageTracker.clearAll()
            await loadLocalData()
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - 导出

    func exportAsJSON() {
        Task {
            do {
                let records = try await usageTracker.loadAll()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(records)
                await saveFile(data: data, defaultName: "deepseek_usage_\(isoDateTag()).json",
                               type: "public.json")
            } catch {
                showError("导出失败: \(error.localizedDescription)")
            }
        }
    }

    func exportAsCSV() {
        Task {
            do {
                let records = try await usageTracker.loadAll().sorted { $0.timestamp < $1.timestamp }
                let df = ISO8601DateFormatter()
                var csv = "时间,模型,Prompt Tokens,Completion Tokens,总计\n"
                for r in records {
                    csv += "\(df.string(from: r.timestamp)),\(r.model),\(r.promptTokens),\(r.completionTokens),\(r.totalTokens)\n"
                }
                await saveFile(data: Data(csv.utf8), defaultName: "deepseek_usage_\(isoDateTag()).csv",
                               type: "public.comma-separated-values-text")
            } catch {
                showError("导出失败: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func saveFile(data: Data, defaultName: String, type: String) {
        let panel = NSSavePanel()
        panel.title = "导出用量数据"
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 菜单栏标题

    func menuBarTitle() -> String {
        let total = allTimeUsage.totalTokens
        if total == 0 { return "DS" }
        return "DS " + formatCompact(total)
    }

    // MARK: - 格式化

    func formatCompact(_ n: Int) -> String {
        switch n {
        case 0..<1_000:         return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default:                return String(format: "%.2fM", Double(n) / 1_000_000)
        }
    }

    func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - 私有

    private func startAutoRefresh() {
        refreshTask?.cancel()
        balanceTask?.cancel()

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30s
                guard !Task.isCancelled else { break }
                await loadLocalData()
            }
        }

        balanceTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000) // 5min
                guard !Task.isCancelled else { break }
                await refreshBalance()
            }
        }
    }

    private func showError(_ msg: String) {
        errorMessage = msg
        showError    = true
    }

    private func isoDateTag() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df.string(from: Date())
    }
}

// MARK: - Int 扩展

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

private extension Optional where Wrapped == Int {
    static func ?? (lhs: Int?, rhs: UInt16) -> UInt16 {
        guard let v = lhs, v > 0 else { return rhs }
        return UInt16(exactly: v) ?? rhs
    }
}
