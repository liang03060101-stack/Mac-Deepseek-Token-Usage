import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("DeepSeek Token Menu")
                .font(.title2.weight(.semibold))

            Text("v1.2.0 · macOS 13+")
                .font(.caption).foregroundStyle(.secondary)

            Divider().frame(width: 200)

            VStack(spacing: 4) {
                featureLine("本地代理拦截 API 请求，实时统计用量")
                featureLine("streaming 模式自动注入 include_usage")
                featureLine("API Key 通过系统钥匙串加密存储")
                featureLine("所有数据仅保存在本地，不上传")
            }
            .font(.caption2).foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)

            Spacer()

            // 链接
            HStack(spacing: 16) {
                Link("DeepSeek Platform", destination: URL(string: "https://platform.deepseek.com")!)
                Link("API Docs", destination: URL(string: "https://api-docs.deepseek.com")!)
            }
            .font(.caption).foregroundStyle(.blue)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func featureLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").foregroundStyle(.green)
            Text(text)
        }
    }
}
