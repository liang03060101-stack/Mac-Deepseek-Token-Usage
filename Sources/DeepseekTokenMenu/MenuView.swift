import SwiftUI

// MARK: - 菜单栏下拉面板

struct MenuView: View {
    @ObservedObject var viewModel: AppViewModel
    let delegate: AppDelegate

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.showSetupGuide {
                setupGuideSection
            } else {
                statsSection
                if viewModel.allTimeUsage.totalTokens > 0 {
                    Divider()
                    chartSection
                    Divider()
                    modelSection
                }
            }
            Divider()
            actionBar
        }
        .frame(width: 320)
    }

    // MARK: - 设置引导

    private var setupGuideSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
            Text("需要配置 API Key")
                .font(.headline)
            Text("点击下方「设置」输入 DeepSeek API Key")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .padding(20)
    }

    // MARK: - 用量概览

    private var statsSection: some View {
        VStack(spacing: 0) {
            // 标题行
            HStack {
                Label("Token 用量", systemImage: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // 余额
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.balanceAvailable ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(viewModel.balance)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 四个时段数据
            VStack(spacing: 4) {
                usageRow("今日",   viewModel.todayUsage)
                usageRow("7 天",   viewModel.weekUsage)
                usageRow("30 天",  viewModel.monthUsage)
                Divider().padding(.horizontal, 14)
                usageRow("全部",   viewModel.allTimeUsage, emphasize: true)
            }
            .padding(.bottom, 10)

            // 代理状态
            proxyStatusRow
        }
    }

    private func usageRow(_ label: String, _ usage: AggregatedUsage, emphasize: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(emphasize ? .subheadline.weight(.medium) : .subheadline)
                .foregroundStyle(emphasize ? .primary : .secondary)
                .frame(width: 40, alignment: .leading)

            Spacer()

            Group {
                Text("↑\(viewModel.formatCompact(usage.promptTokens))")
                    .foregroundStyle(.blue)
                Text("↓\(viewModel.formatCompact(usage.completionTokens))")
                    .foregroundStyle(.purple)
            }
            .font(.system(size: 10, design: .monospaced))

            Text(viewModel.formatCompact(usage.totalTokens))
                .font(.system(size: 12, weight: emphasize ? .semibold : .regular, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    private var proxyStatusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.proxyRunning ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(viewModel.proxyRunning ? "代理运行中 \(viewModel.proxyURL)" : "代理未运行")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            if viewModel.proxyRunning {
                Button {
                    viewModel.copyProxyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制代理 URL")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - 7天趋势图

    private var chartSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("每日趋势")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("7 天")
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            SparklineChart(data: viewModel.dailyChartData, vm: viewModel)
                .frame(height: 60)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }

    // MARK: - 模型分布

    private var modelSection: some View {
        VStack(spacing: 2) {
            HStack {
                Text("模型分布")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            ForEach(viewModel.modelBreakdown.prefix(5), id: \.0) { model, usage in
                HStack(spacing: 6) {
                    Circle().fill(modelColor(model))
                        .frame(width: 6, height: 6)
                    Text(KnownModel.display(for: model))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                        .lineLimit(1)
                    Text(viewModel.formatCompact(usage.totalTokens))
                        .font(.caption.monospacedDigit()).fontWeight(.medium)
                    Spacer()
                    Text("↑\(viewModel.formatCompact(usage.promptTokens)) ↓\(viewModel.formatCompact(usage.completionTokens))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            }
            .padding(.bottom, 6)
        }
    }

    private func modelColor(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("v4") || n.contains("chat") { return .blue }
        if n.contains("r1") || n.contains("reasoner") { return .purple }
        return .green
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.loadLocalData() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                delegate.showSettings(vm: viewModel)
            } label: {
                Label("设置", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - 每日 Sparkline 图

private struct SparklineChart: View {
    let data: [(Date, AggregatedUsage)]
    let vm: AppViewModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxVal = max(data.map(\.1.totalTokens).max() ?? 1, 1)
            let gap: CGFloat = 4
            let barW = max((w - gap * CGFloat(data.count - 1)) / CGFloat(max(data.count, 1)), 4)
            let labelH: CGFloat = 14

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(data.enumerated()), id: \.offset) { i, item in
                    let (date, usage) = item
                    let ratio = CGFloat(usage.totalTokens) / CGFloat(maxVal)
                    let barH  = max(ratio * (h - labelH - 14), usage.totalTokens > 0 ? 2 : 0)

                    VStack(spacing: 2) {
                        // 数值（只显示 > 0 的）
                        if usage.totalTokens > 0 {
                            Text(vm.formatCompact(usage.totalTokens))
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        } else {
                            Spacer()
                        }

                        // 条形
                        RoundedRectangle(cornerRadius: 2)
                            .fill(usage.totalTokens > 0 ? Color.accentColor.opacity(0.7) : Color.clear)
                            .overlay(
                                usage.totalTokens == 0
                                    ? RoundedRectangle(cornerRadius: 2).stroke(.quaternary, lineWidth: 0.5)
                                    : nil
                            )
                            .frame(width: barW, height: max(barH, 2))

                        // 日期标签
                        Text(dayLabel(date))
                            .font(.system(size: 7))
                            .foregroundStyle(.tertiary)
                            .frame(height: labelH)
                    }
                    .frame(maxHeight: h)
                }
            }
        }
    }

    private func dayLabel(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d"
        return df.string(from: d)
    }
}
