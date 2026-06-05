import Foundation

// MARK: - 用量本地持久化（线程安全 Actor）

actor UsageTracker {

    // MARK: 文件路径

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DeepSeekTokenMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_records.json")
    }

    // MARK: - 读写

    func loadAll() throws -> [TokenUsageRecord] {
        let url = Self.storageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TokenUsageRecord].self, from: data)
    }

    func save(_ record: TokenUsageRecord) throws {
        var records = (try? loadAll()) ?? []
        records.append(record)
        try persist(records)
    }

    func deleteRecord(id: UUID) throws {
        var records = try loadAll()
        records.removeAll { $0.id == id }
        try persist(records)
    }

    func clearAll() throws {
        try persist([])
    }

    var recordCount: Int {
        (try? loadAll().count) ?? 0
    }

    // MARK: - 聚合查询

    func getAggregatedUsage(for period: UsagePeriod) throws -> AggregatedUsage {
        let records = try loadAll()
        let filtered = filter(records, for: period)
        return aggregate(filtered)
    }

    func getAllTimeUsage() throws -> AggregatedUsage {
        let records = try loadAll()
        return aggregate(records)
    }

    /// 按日期分组聚合（用于图表）
    func getDailyUsage(lastDays days: Int) throws -> [(Date, AggregatedUsage)] {
        let all = try loadAll()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date()))
        else { return [] }

        let filtered = all.filter { $0.timestamp >= startDate }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.timestamp) }

        return (0..<days).map { offset -> (Date, AggregatedUsage) in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return (Date(), .zero)
            }
            let dayStart = calendar.startOfDay(for: date)
            let records  = grouped[dayStart] ?? []
            return (dayStart, aggregate(records))
        }
    }

    /// 按模型分组
    func getModelBreakdown() throws -> [(String, AggregatedUsage)] {
        let records = try loadAll()
        let grouped = Dictionary(grouping: records) { $0.model }
        return grouped
            .map { (model, recs) in (model, aggregate(recs)) }
            .sorted { $0.1.totalTokens > $1.1.totalTokens }
    }

    // MARK: - 私有

    private func filter(_ records: [TokenUsageRecord], for period: UsagePeriod) -> [TokenUsageRecord] {
        guard let start = period.startDate else { return records }
        return records.filter { $0.timestamp >= start }
    }

    private func aggregate(_ records: [TokenUsageRecord]) -> AggregatedUsage {
        records.reduce(into: .zero) { acc, r in
            acc.promptTokens     += r.promptTokens
            acc.completionTokens += r.completionTokens
        }
    }

    private func persist(_ records: [TokenUsageRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(records)
        try data.write(to: Self.storageURL, options: .atomic)
    }
}
