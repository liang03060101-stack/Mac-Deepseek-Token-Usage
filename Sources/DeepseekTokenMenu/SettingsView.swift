import SwiftUI

// MARK: - 设置界面

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var editingKey    = ""
    @State private var isEditingKey  = false
    @State private var showClearAlert    = false
    @State private var showDeleteAlert   = false
    @State private var recordToDelete: TokenUsageRecord?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            proxyTab
                .tabItem { Label("代理", systemImage: "network") }
            dataTab
                .tabItem { Label("数据", systemImage: "folder") }
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 500)
    }

    // MARK: - 通用 Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // API Key
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.apiKeyVerified && !isEditingKey {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("API Key 已验证").font(.subheadline)
                                Spacer()
                                Button("更换") { isEditingKey = true; editingKey = "" }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Button("删除") { viewModel.deleteAPIKey() }
                                    .buttonStyle(.bordered).controlSize(.small)
                                    .foregroundStyle(.red)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("输入 DeepSeek API Key（sk-... 格式）")
                                    .font(.caption).foregroundStyle(.secondary)
                                SecureField("sk-xxxxxxxxxxxxxxxx", text: $editingKey)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { Task { await saveKey() } }

                                if let err = viewModel.apiKeyError {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                HStack {
                                    Button(isEditingKey ? "取消" : "") {
                                        isEditingKey = false
                                        viewModel.apiKeyError = nil
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(isEditingKey ? 1 : 0)

                                    Spacer()

                                    Button {
                                        Task { await saveKey() }
                                    } label: {
                                        if viewModel.isLoading {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Text(isEditingKey ? "验证并保存" : "保存并验证")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(editingKey.isEmpty || viewModel.isLoading)
                                }
                            }
                        }
                    }
                    .padding(6)
                } label: {
                    Label("API Key", systemImage: "key.fill")
                }

                // 余额
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("账户余额").font(.subheadline)
                            Text(viewModel.balance)
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(viewModel.balanceAvailable ? .primary : .red)
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.refreshBalance() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!viewModel.apiKeyVerified)
                    }
                    .padding(6)
                } label: {
                    Label("余额", systemImage: "creditcard")
                }
            }
            .padding(16)
        }
        .onAppear {
            if !viewModel.apiKeyVerified { isEditingKey = false }
        }
    }

    private func saveKey() async {
        await viewModel.saveAndVerifyKey(editingKey)
        if viewModel.apiKeyVerified { isEditingKey = false }
    }

    // MARK: - 代理 Tab

    private var proxyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Circle()
                                .fill(viewModel.proxyRunning ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.proxyRunning ? "运行中" : "已停止")
                                .font(.subheadline)
                            Spacer()
                            Button(viewModel.proxyRunning ? "停止" : "启动") {
                                Task {
                                    if viewModel.proxyRunning { viewModel.stopProxy() }
                                    else { await viewModel.startProxy() }
                                }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }

                        Divider()

                        HStack {
                            Text("代理地址").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            Text(viewModel.proxyURL)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                            Button {
                                viewModel.copyProxyURL()
                            } label: {
                                Image(systemName: "doc.on.doc").font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                } label: {
                    Label("本地代理", systemImage: "network")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("如何使用").font(.subheadline.weight(.medium))

                        instructionItem(n: "1", text: "确保代理已启动（绿色状态）")
                        instructionItem(n: "2", text: "复制代理地址 \(viewModel.proxyURL)")
                        instructionItem(n: "3", text: "在 Claude Code 中：")
                        HStack {
                            Spacer().frame(width: 20)
                            Text("DEEPSEEK_BASE_URL=\(viewModel.proxyURL)")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(6)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                        instructionItem(n: "4", text: "在 Cursor 中：Settings > AI > Base URL 设为代理地址")
                        instructionItem(n: "5", text: "正常使用 DeepSeek API，Token 用量自动记录")
                    }
                    .padding(6)
                } label: {
                    Label("使用说明", systemImage: "questionmark.circle")
                }
            }
            .padding(16)
        }
    }

    private func instructionItem(n: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(n + ".")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 数据 Tab

    private var dataTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    usageSummarySection
                    exportSection
                    recordListSection
                }
                .padding(16)
            }

            // 底部刷新按钮
            HStack {
                Spacer()
                Button("刷新数据") { Task { await viewModel.loadLocalData() } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor).opacity(0.5))
        }
        .alert("确认清除", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清除全部", role: .destructive) {
                Task { await viewModel.clearAllData() }
            }
        } message: {
            Text("将删除所有本地 Token 记录，无法撤销。")
        }
        .alert("确认删除", isPresented: $showDeleteAlert, presenting: recordToDelete) { rec in
            Button("取消", role: .cancel) { recordToDelete = nil }
            Button("删除", role: .destructive) {
                Task {
                    await viewModel.deleteRecord(rec.id)
                    recordToDelete = nil
                }
            }
        } message: { rec in
            let df = DateFormatter(); df.dateFormat = "MM/dd HH:mm"
            return Text("删除 \(KnownModel.display(for: rec.model)) 在 \(df.string(from: rec.timestamp)) 的记录？")
        }
    }

    // MARK: 数据子视图

    private var usageSummarySection: some View {
        GroupBox {
            VStack(spacing: 6) {
                dataRow("今日", viewModel.todayUsage.totalTokens)
                dataRow("7 天", viewModel.weekUsage.totalTokens)
                dataRow("30 天", viewModel.monthUsage.totalTokens)
                dataRow("全部", viewModel.allTimeUsage.totalTokens)
                Divider()
                dataRow("Prompt 累计", viewModel.allTimeUsage.promptTokens)
                dataRow("Completion", viewModel.allTimeUsage.completionTokens)
                dataRow("记录数", viewModel.recordCount)
                // 费用估算
                HStack {
                    Text("预估费用（CNY）").foregroundStyle(.secondary)
                    Spacer()
                    let cost = viewModel.allTimeUsage.estimatedCost()
                    Text("¥\(String(format: "%.4f", cost))")
                        .fontWeight(.medium).foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
            .padding(6)
        } label: {
            Label("用量汇总", systemImage: "chart.bar")
        }
    }

    private var exportSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button { viewModel.exportAsJSON() } label: {
                        Label("导出 JSON", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(viewModel.recordCount == 0)

                    Button { viewModel.exportAsCSV() } label: {
                        Label("导出 CSV", systemImage: "tablecells")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(viewModel.recordCount == 0)
                }

                Button(role: .destructive) { showClearAlert = true } label: {
                    Label("清除所有本地数据", systemImage: "trash")
                }
                .disabled(viewModel.recordCount == 0)

                HStack {
                    Text("存储路径").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Text("~/Library/Application Support/DeepSeekTokenMenu/")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(6)
        } label: {
            Label("管理", systemImage: "wrench")
        }
    }

    private var recordListSection: some View {
        Group {
            if !viewModel.recordHistory.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("历史记录").font(.subheadline.weight(.medium))
                            Spacer()
                            Picker("排序", selection: $viewModel.recordSort) {
                                ForEach(AppViewModel.SortOrder.allCases) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .pickerStyle(.menu).labelsHidden()
                            .onChange(of: viewModel.recordSort) { _ in
                                Task { await viewModel.loadRecordHistory() }
                            }
                        }
                        Divider()
                        if viewModel.recordHistory.count > 100 {
                            Text("显示最近 100 条（共 \(viewModel.recordHistory.count) 条）")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        ForEach(viewModel.recordHistory.prefix(100)) { record in
                            RecordRow(record: record, vm: viewModel) {
                                recordToDelete = record
                                showDeleteAlert = true
                            }
                        }
                    }
                    .padding(6)
                } label: {
                    Label("历史记录", systemImage: "list.bullet")
                }
            }
        }
    }

    // MARK: Helpers

    private func dataRow(_ label: String, _ val: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(viewModel.formatNumber(val)).fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - 记录行

private struct RecordRow: View {
    let record: TokenUsageRecord
    let vm: AppViewModel
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(timeStr)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(KnownModel.display(for: record.model))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            HStack(spacing: 2) {
                Text("↑\(vm.formatCompact(record.promptTokens))").foregroundStyle(.blue)
                Text("↓\(vm.formatCompact(record.completionTokens))").foregroundStyle(.purple)
            }
            .font(.system(size: 10, design: .monospaced))
            Spacer()
            Text(vm.formatCompact(record.totalTokens))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            Button { onDelete() } label: {
                Image(systemName: "trash").font(.system(size: 8)).foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain).help("删除")
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(4)
    }

    private var timeStr: String {
        let df = DateFormatter(); df.dateFormat = "MM/dd HH:mm"
        return df.string(from: record.timestamp)
    }
}
