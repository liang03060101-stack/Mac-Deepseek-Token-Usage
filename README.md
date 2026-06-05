# DeepSeek Token Menu 🪙

在 macOS 菜单栏实时查看 **DeepSeek-V4** 等模型的 Token 用量。

## 功能

- ✅ **菜单栏显示** — 一眼看到总 Token 数（自动格式化 K/M）
- ✅ **用量概览** — 今日、本周、总计的 Prompt / Completion 拆分
- ✅ **模型分布** — 按模型分组（DeepSeek-V4, R1 等）查看用量
- ✅ **API Key 安全存储** — 使用系统钥匙串加密存储
- ✅ **自动刷新** — 可配置的刷新间隔（30s ~ 30min）
- ✅ **余额查询** — 自动获取 DeepSeek 账户余额
- ✅ **本地持久化** — 用量数据保存在本地，跨会话积累
- ✅ **中文本地化** — 完整的中文界面

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Xcode 15+（仅构建时需要）
- DeepSeek API Key

## 快速开始

### 1. 获取 API Key

登录 [DeepSeek 平台](https://platform.deepseek.com) → API Keys → 创建新 Key。

### 2. 构建

```bash
# 克隆/进入项目目录
cd DeepSeekTokenMenu

# 构建
chmod +x build.sh
./build.sh
```

### 3. 运行

```bash
# 方式一：双击打开
open DeepSeekTokenMenu.app

# 方式二：命令行前台运行（调试用）
./DeepSeekTokenMenu.app/Contents/MacOS/DeepSeekTokenMenu
```

### 4. 配置

点击菜单栏图标 → 设置 → 输入你的 `sk-` 开头的 API Key → 保存。

## 项目结构

```
DeepSeekTokenMenu/
├── Package.swift                      # SwiftPM 包配置
├── Info.plist                         # App 元信息
├── build.sh                           # 构建脚本
├── Sources/
│   └── DeepSeekTokenMenu/
│       ├── App.swift                  # @main — MenuBarExtra 入口
│       ├── Models/
│       │   └── Models.swift           # 数据模型 & API 响应结构
│       ├── Services/
│       │   ├── DeepSeekService.swift   # DeepSeek API 客户端
│       │   ├── UsageTracker.swift      # 用量本地持久化
│       │   └── KeychainManager.swift   # 钥匙串安全存储
│       ├── ViewModels/
│       │   └── AppViewModel.swift      # 中央 ViewModel
│       └── Views/
│           ├── MenuView.swift          # 菜单栏下拉面板
│           ├── SettingsView.swift      # 设置界面
│           └── AboutView.swift         # 关于界面
└── Resources/
    └── Assets.xcassets/
```

## 技术细节

- **架构**: SwiftUI + `MenuBarExtra` (macOS 13+)
- **网络**: `URLSession` 异步请求 DeepSeek API
- **存储**: Keychain (API Key) + JSON 文件 (用量历史)
- **并发**: Swift Actors + `@MainActor` 保证线程安全
- **构建**: Swift Package Manager, 无需 Xcode GUI

## 常见问题

**Q: 为什么菜单栏显示 0？**
A: 初始状态下没有数据。设置 API Key 后，App 会定期采样获取用量。

**Q: 数据安全吗？**
A: API Key 存储在系统钥匙串 (Keychain) 中，用量数据仅保存在本地。

**Q: 如何彻底卸载？**
A: 将 App 从「应用程序」移到废纸篓，钥匙串中的 API Key 会自动残留，可手动在「钥匙串访问」中删除。

## License

MIT
