# 修复说明 — DeepSeek Token Menu

## 核心问题根因

### 问题 1：Streaming 模式不返回 usage（最关键）

DeepSeek API 在 `stream: true` 时，**默认不保证在 SSE 流里包含 usage 字段**。

必须在请求 body 里加上：
```json
{
  "stream": true,
  "stream_options": { "include_usage": true }   // ← 这个字段之前缺失
}
```

**原代码的代理没有注入这个参数** → 90% 的情况下 SSE 流里压根就没有 usage → 永远读不到数据。

---

### 问题 2：`isStreaming` 检测不可靠

原代码用字符串匹配：
```swift
bodyStr.contains("\"stream\":true")
```

这会漏掉 `"stream": true`（有空格）、`"stream":  true`（多空格）等格式。

**修复：先把 body 解析成 JSON dict，再读 `json["stream"] as? Bool`。**

---

### 问题 3：SSE 解析逻辑问题

原代码先试整体 JSON，失败了再试 SSE。对于 streaming 响应，整体 JSON 解析**必然失败**（SSE 不是合法 JSON），白白浪费一次解析。

**修复：根据 `isStreaming` 标志直接分两条路径。**

---

### 问题 4：Actor 并发隔离

`LocalProxyServer` 改为 `actor`，`UsageTracker` 也是 `actor`，避免多并发请求下的数据竞争。

---

## 修改的文件

| 文件 | 修改内容 |
|---|---|
| `LocalProxyServer.swift` | **完全重写**：注入 `stream_options`，JSON解析为流标志，分路径解析 |
| `UsageTracker.swift` | Actor 化，加 `deleteRecord`、`getDailyUsage`、`getModelBreakdown` |
| `Models.swift` | 更新为 V4 模型名，修正 `estimatedCost` 参数 |
| `DeepSeekService.swift` | 只做余额查询和 Key 验证，不再负责用量（用量靠代理） |
| `AppViewModel.swift` | 整合所有功能，修复 `@MainActor` 标注 |
| `SettingsView.swift` | 加代理使用说明 Tab，记录列表，导出按钮 |
| `MenuView.swift` | 余额显示，sparkline 图表修复 |

---

## 如何应用这些修复

```bash
# 1. 把这些文件覆盖你项目里的对应文件
cp -v Sources/DeepSeekTokenMenu/Services/LocalProxyServer.swift  \
      /path/to/your/project/Sources/DeepSeekTokenMenu/Services/

# 2. 同样覆盖其他文件...

# 3. 重新构建
cd /path/to/your/project
swift package clean
./build.sh

# 4. 运行（前台，可以看到 [Proxy] 日志）
./DeepSeekTokenMenu.app/Contents/MacOS/DeepSeekTokenMenu
```

---

## 验证修复是否生效

启动后在终端里你应该看到：

```
[Proxy] ✅ 启动于 http://localhost:18923
```

发一个 DeepSeek 请求后（stream=true）：
```
[Proxy] → POST /v1/chat/completions [stream]
[Proxy] ✅ 已注入 stream_options.include_usage=true
[Proxy] ← 状态: 200 | 前2000字符: data: {...}...
[Proxy] ✅ SSE usage found: ["prompt_tokens": 14, "completion_tokens": 8, "total_tokens": 22]
[Proxy] ✅ 已记录 ↑14 ↓8 [deepseek-v4-flash]
```

---

## DeepSeek V4 模型名称

API 请求时用的 `model` 字段：

| 用途 | model 值 |
|---|---|
| 通用对话（便宜） | `deepseek-v4-flash` |
| 高性能 | `deepseek-v4-pro` |
| 旧别名（自动路由到V4） | `deepseek-chat` |
| 推理 | `deepseek-reasoner` |

---

## 架构说明：为什么用代理而不是直接轮询 API

DeepSeek 平台**没有"历史 token 用量"查询接口**（只有余额 `/user/balance`）。

所以唯一可靠的方式是在请求经过时拦截，从响应的 `usage` 字段读取数据。

代理架构缺点：用户需要配置 `base_url`。替代方案是用 Xcode Network Extension 做 MITM，但需要复杂证书配置，代理方案对开发者用户更实用。
