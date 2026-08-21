# LM Studio token 采集

Doris 统计本机 LM Studio 的 token 用量,数据有**两个互不重叠的来源**:

| 来源 | 路径 | 覆盖什么 |
|---|---|---|
| GUI 对话 | `~/.lmstudio/conversations/*.conversation.json` | 在 LM Studio 界面里聊的 |
| API Server | `~/.lmstudio/server-logs/` | 通过 OpenAI 兼容接口调用的(Claude、CLI、脚本等) |

实现见 `packages/DorisCore/Sources/DorisCore/Tokens/Adapters/LMStudioAdapter.swift`。

## ⚠️ API Server 那一半依赖一个 LM Studio 设置

`~/.lmstudio/.internal/http-server-config.json` 里的 **`fileLoggingMode` 必须是 `full`**。

LM Studio 默认是 `succinct`,那种模式下 server-logs 不含 token 计数,采集器会直接跳过(见 `LMStudioAdapter.swift:63` 的前置判断)。GUI 对话那一半不受影响,默认就能采到。

**这台开发机上该值已被改为 `full`。** 这不是遗留的调试改动 —— 它是 API Server 统计能工作的前提。如果你不需要统计 API Server 的用量,可以改回 `succinct`,代价是 Doris 的 token 账单里只剩 GUI 对话那部分。

改动方式:LM Studio 设置里开启完整日志,或直接编辑上述 JSON 后重启 LM Studio。

## 去重

同一次调用可能同时出现在两个来源里,采集器用两套 key 去重:

- GUI:`lmstudio:<convId>#<stepId>`
- API:`lmstudio:api:<chatcmpl-id>`
