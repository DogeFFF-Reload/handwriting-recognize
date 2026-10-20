# MyScript 接入现状（P4 侧的调查）

> 结论先说：**没好，而且这一步只能你来做。**
> 但条款和接入方式我已经查清了 —— 证书一到，接入是 30 分钟的事。

---

## 1. 为什么我做不了

MyScript 不是"下载一个库"就完事，它是**按你的 Apple bundle id 签发的证书**：

- 注册要邮箱验证、接受条款，账号是你的；
- 证书（一个 `.c` 文件）生成时**绑定 bundle id**；
- 之后每次识别都在你的开发者账号下计费/计数。

我不能用你的身份注册账号 —— 这既是权限问题，也是合规问题。
**你注册，我接线**，这样最快。

---

## 2. 我从定价页 FAQ 里读到的原文事实

定价页是 Vue SPA，我把它的 bundle（`PricingView-SdrtYaJ5.js`）拆开读的，以下是原文：

| 问题 | 原文 | 对我们的意义 |
|---|---|---|
| 免费额度 | "Discover the benefits beyond the **2,000 free limit**!" | 云识别有 2000 次免费，**演示够用**（一场 3 分钟约 6 次） |
| 什么算一次请求 | REST：一次 REST 调用；WebSocket：连接建立到关闭之间的全部交互 | **别用 WebSocket 流式**，一次识别一次 REST，计数清楚 |
| license 是什么 | "It is an activated license that enables handwriting recognition in your app. Once activated, the license is valid for ever." | **设备端 license 一次激活永久有效**，不是订阅 |
| 什么时候消耗 | "A license is activated over internet at the first launch of each new app on each new device." | 首次启动要联网激活一次；**之后可以离线** |
| 断网还能用吗 | "Recognition is enabled during a **30-day grace period** without internet connection." | 会场断网 30 天内照常工作 —— **这条对我们是决定性的** |
| 重装/更新 | 重装不消耗（除非恢复出厂）；bundle id 不变时更新不消耗 | 反复装 App 调试**不会烧额度** |
| 设备 license 价格 | "Contact us to get the pricing" | 官网不标价，是销售谈的；**黑客松用试用证书即可** |

两条路：

- **云识别**：2000 次免费，但要联网 —— 会场断网就废。
- **设备端（iink SDK）**：需要试用证书，**激活一次永久有效 + 离线 30 天** ——
  **这条才符合我们的断网要求**，选它。

---

## 3. 从官方 iOS 示例里读到的接入方式

我 clone 了 `MyScript/interactive-ink-examples-ios`（3 MB，schema 已读），关键代码在这里：

### 3.1 证书是一个 C 数组文件

```
Examples/GetStarted/GetStarted/MyScriptCertificate/MyCertificate.c
Examples/Demo/Demo/MyScriptCertificate/MyCertificate.c
```

README 原话："Copy this certificate to `MyCertificate.c`"。所以它是**编译期**的东西，
不是运行时读的 key —— 换证书要重新编译。

### 3.2 创建引擎（`EngineProvider.swift` 原文）

```swift
if myCertificate.length == 0 { /* 没放证书 */ }

let data = Data(bytes: myCertificate.bytes, count: myCertificate.length)
guard let engine = IINKEngine(certificate: data) else { /* 证书无效 */ }

let configurationPath = resourcePath.appending("/recognition-assets/conf")
try engine.configuration.set(stringArray: [configurationPath],
                             forKey: "configuration-manager.search-path")

try engine.configuration.set(string: NSTemporaryDirectory(),
                            forKey: "content-package.temp-folder")
```

注意 `recognition-assets/conf`：**识别资源包要打进 App**。实测体积：数学部分 ~19.5 MB，
全量 7 个包 ~51.6 MB（见 `MyScript-COLLECT.md`）。不是"几百 MB"，负担很小。

### 3.3 数学识别怎么开（`configurations/interactivity.json`）

```json
"raw-content": {
  "configuration": {
    "math": { "bundle": "math", "name": "standard" }
  },
  "recognition": { "types": [ "text", "math" ] },
  "interactive-blocks": { "feedback": [ "math" ] }
}
```

必须把 `math` 加进 `recognition.types`，否则它只认普通手写文字，
`f'(x)=3x^2-3x` 会被当成一串字母数字。

### 3.4 导出 LaTeX

示例里是**枚举 mime type** 再按用户选择导出：

```swift
IINKMimeTypeValue.iinkMimeTypeGetName(mimeTypeValue.value)
```

所以正确做法不是硬编码字符串，而是**运行时枚举支持的类型，挑名字里带 latex 的那个**。
我这台机器上没有 SDK 二进制（仓库里不含 framework），没法当场确认具体字符串，
所以代码里按枚举写，别赌。

---

## 4. 你拿到证书后的四步（约 30 分钟）

1. `MyCertificate.c` 放进 `InkTutor/App/MyScriptCertificate/`；
2. `IINKEngine(certificate:)` 建引擎，设 `configuration-manager.search-path` 与 `temp-folder`；
3. 把 `recognition-assets/` 拖进 target（注意用 folder reference，别让 Xcode 拆散）；
4. 用 3.3 的 `interactivity.json` 配置数学识别，导出走 mime 枚举。

**验收标准**（写在 KICKOFF 的 4 小时闸门里）：

> 真机上把 `f'(x)=3x^2-3x` 转成 LaTeX，**端到端 < 800 ms**，且**飞行模式下仍能识别**。

过了就用它；不过就切 Flash，**不要在比赛里换第三家**。

---

## 5. 你要回传给我的三样东西

| # | 东西 | 用来干什么 |
|---|---|---|
| 1 | `MyCertificate.c` | 接线 + 真机跑通 |
| 2 | SDK 版本号（`iink` 的 pod / framework 版本） | 对上 API，避免抄错签名 |
| 3 | **10 条真实输出的 LaTeX 字符串**（手写那 4 条 + 常见错法） | 补进 `golden_cases.json` 的 `parse` 段 —— 这是解析器的验收依据 |

第 3 条最重要。我的解析器现在是按"我猜识别器会输出什么"写的；
真实输出可能带 `\mathrm`、`\cdot`、`^{\prime}`、甚至 `\begin{matrix}`，
每一种都能让看似没问题的解析器当场返回 `parse_error`。

---

## 6. 在证书下来之前，链路已经能跑

`server/mock_v2.py` 里加了一个**占位识别器** `POST /recognize`：

```bash
cd server && python -m uvicorn mock_v2:app --port 8100
curl -X POST localhost:8100/recognize -d '{"mode":"derivative","region":{"x":40,"y":320,"w":600,"h":80}}'
```

- 按脚本轮换演示的三句 LaTeX（`f(x)=x^3-3x` → `f'(x)=3x^2-3x` → `f'(x)=3x^2-3`）；
- `?say=<latex>` 可以强制返回某一句，方便测错法；
- 响应里 `source: "stub"` **明确标注这是占位**，答辩时不要拿它当识别能力的证据；
- `POST /admin/stub_reset` 每遍彩排前拨回第一句。

这样 P1 今天就能把「落笔 → /recognize → /check → 画圈 → /hint」整条链路串起来，
证书一到只替换识别器，UI 一行不用改。

---

## 7. 风险登记

| 风险 | 应对 |
|---|---|
| 证书审核要时间 | **今天就注册**；4 小时内没下来就走 Flash 后备，不等 |
| 识别资源包体积 | 实测数学部分 ~19.5 MB、全量 ~51.6 MB，不构成风险 |
| bundle id 改了要重新申请 | 建工程时**先把 bundle id 定死**（`com.<team>.inktutor`），别中途改 |
| 设备 license 是"Contact us" | 黑客松用试用证书；路演时不要承诺"商用免费" |
| iink 的 LaTeX 方言与我的解析器不符 | 第 4 小时收 10 条真实字符串，补进 `golden_cases.json` |
