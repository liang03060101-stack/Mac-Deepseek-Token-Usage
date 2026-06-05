import Foundation

// MARK: - Token 用量记录（本地持久化）

struct TokenUsageRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let model: String
    let promptTokens: Int
    let completionTokens: Int

    var totalTokens: Int { promptTokens + completionTokens }

    init(model: String, promptTokens: Int, completionTokens: Int) {
        self.id               = UUID()
        self.timestamp        = Date()
        self.model            = model
        self.promptTokens     = promptTokens
        self.completionTokens = completionTokens
    }
}

// MARK: - 聚合用量

struct AggregatedUsage {
    var promptTokens: Int     = 0
    var completionTokens: Int = 0
    var totalTokens: Int { promptTokens + completionTokens }

    static var zero: AggregatedUsage { AggregatedUsage() }

    /// 按 DeepSeek V4 定价估算费用（CNY）
    /// deepseek-v4-flash: 输入 ¥0.06/M  输出 ¥0.18/M
    /// deepseek-v4-pro:   输入 ¥0.48/M  输出 ¥1.44/M
    /// 混合用量按 flash 价格估算（保守）
    func estimatedCost(modelName: String = "deepseek-v4-flash") -> Double {
        let inputRate:  Double
        let outputRate: Double
        if modelName.lowercased().contains("pro") {
            inputRate  = 0.48 / 1_000_000
            outputRate = 1.44 / 1_000_000
        } else {
            inputRate  = 0.06 / 1_000_000
            outputRate = 0.18 / 1_000_000
        }
        return Double(promptTokens) * inputRate + Double(completionTokens) * outputRate
    }
}

// MARK: - 已知模型

enum KnownModel: String, CaseIterable {
    // DeepSeek V4（新）
    case deepseekV4Flash = "deepseek-v4-flash"
    case deepseekV4Pro   = "deepseek-v4-pro"
    // 别名：chat / reasoner 会路由到 V4
    case deepseekChat     = "deepseek-chat"
    case deepseekReasoner = "deepseek-reasoner"
    // 老版本
    case deepseekV3  = "deepseek-v3"
    case deepseekR1  = "deepseek-r1"
    case deepseekR1Distill = "deepseek-r1-distill-qwen-32b"

    var displayName: String {
        switch self {
        case .deepseekV4Flash:    return "V4 Flash"
        case .deepseekV4Pro:      return "V4 Pro"
        case .deepseekChat:       return "Chat (V4)"
        case .deepseekReasoner:   return "Reasoner (R1)"
        case .deepseekV3:         return "V3"
        case .deepseekR1:         return "R1"
        case .deepseekR1Distill:  return "R1-Distill-32B"
        }
    }

    /// 是否为推理模型
    var isReasoner: Bool {
        [.deepseekReasoner, .deepseekR1, .deepseekR1Distill].contains(self)
    }

    static func display(for raw: String) -> String {
        KnownModel(rawValue: raw)?.displayName ?? raw
    }
}

// MARK: - 用量时间段

enum UsagePeriod: String, CaseIterable, Identifiable {
    case today, week, month, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "今日"
        case .week:  return "7 天"
        case .month: return "30 天"
        case .all:   return "全部"
        }
    }

    /// 该时间段的起始时间（nil 表示全部）
    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: Date())
        case .week:  return cal.date(byAdding: .day, value: -7, to: Date())
        case .month: return cal.date(byAdding: .day, value: -30, to: Date())
        case .all:   return nil
        }
    }
}

// MARK: - DeepSeek Balance API 响应

struct UserBalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable  = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct BalanceInfo: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency        = "currency"
        case totalBalance    = "total_balance"
        case grantedBalance  = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}
