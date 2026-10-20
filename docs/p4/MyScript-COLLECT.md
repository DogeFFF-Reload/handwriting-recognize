# 还缺的两样：SDK 和真实 LaTeX —— 具体在哪、怎么拿

> 你已经有 `MyCertificate.c` 了。剩下两样都不用"下载压缩包"，我把确切位置查到了。

---

## 1. SDK 在哪：不用下载，用 Swift Package

官方示例的 `project.pbxproj` 里就写着（我拆开看的）：

```
XCRemoteSwiftPackageReference "interactive-ink-packages-ios"
repositoryURL = "https://github.com/MyScript/interactive-ink-packages-ios";
requirement = { kind = exactVersion; version = 4.5.1; };
```

**版本是 4.5.1**（这个仓库是公开的，我确认过 `private: false`，tag 有 `4.5.1` 和 `4.5.0`）。

Xcode 里两步：

1. `File → Add Package Dependencies…`
2. 粘 `https://github.com/MyScript/interactive-ink-packages-ios`，选 **Exact Version 4.5.1**，勾 `libiink`

**怎么确认装的是哪个版本**（这就是你问的"版本号在哪"）：

- Xcode → 项目 → `Package Dependencies` → 展开 `interactive-ink-packages-ios`，右边写着版本；
- 或者看工程里的 `Package.resolved`，找 `"identity" : "interactive-ink-packages-ios"`，
  下面 `"version" : "4.5.1"`。

Package 自己会去 GitHub release 拉 `libiinkC` 的 xcframework（带校验和），**不需要另外下 SDK 压缩包**。

---

## 2. 识别资源包在哪：一条脚本，7 个 zip

SPM 包里**不含**识别资源（模型）。示例仓库里有个脚本 `Examples/Demo/retrieve_recognition-assets.sh`，
它从 `download.myscript.com` 拉公开直链：

```bash
./retrieve_recognition-assets.sh <项目根>
# 落到：<项目根>/Resources/recognition-assets/conf/
```

我量了实际体积（HTTP HEAD，刚测的）：

| 资源包 | 体积 | 数学演示要不要 |
|---|---|---|
| `recognition-math.zip` | 1.6 MB | **要** |
| `recognition-math2.zip` | 13.2 MB | **要**（新引擎的数学） |
| `recognition-raw-content.zip` | 0.2 MB | **要**（原始内容识别） |
| `recognition-raw-content2.zip` | 4.5 MB | **要** |
| `handwriting-recognition.zip` | 17.6 MB | 要（笔迹基础模型） |
| `recognition-text-en_US.zip` | 14.5 MB | 不需要（我们不做英文手写） |
| `recognition-diagram.zip` | 未测 | 不需要（幕三不走 iink） |
| **合计** | **≈51.6 MB**（全量） | **数学必需部分 ≈19.5 MB** |

脚本会自己检查 7 个 `.conf` 是否存在（`math.conf`、`math2.conf`、`raw-content.conf`、
`raw-content2.conf`、`en_US.conf`、`mul_Latn.conf`、`diagram.conf`），缺一个就重下全套。

> **修正我之前的说法**：我在 `MyScript-INTEGRATION.md` 里写过"几百 MB 量级"，
> 那是没核实的猜测。实测数学部分只有 ~20 MB，全量 52 MB，对 iPad 不算负担。我去把那段改掉了。

---

## 3. 10 条真实 LaTeX 怎么拿（15 分钟）

LaTeX 只能由引擎产出，所以必须跑一次示例 App。步骤：

```bash
git clone https://github.com/MyScript/interactive-ink-examples-ios.git
cd interactive-ink-examples-ios
cp <你的 MyCertificate.c> Examples/Demo/Demo/MyScriptCertificate/MyCertificate.c
cd Examples/Demo && ./retrieve_recognition-assets.sh .
open Demo.xcworkspace        # 在 Xcode 里加 SPM 依赖 4.5.1、改 bundle id、签名
```

跑起来后：

1. 在画布上写 `f(x)=x^3-3x`，停一下；
2. 点导出按钮（工具栏 `…` → Export）；
3. 导出列表里挑 **LaTeX** 那一项，复制出来。

**如果导出列表里没有 LaTeX**，那说明枚举出来的 mime type 名不带 latex 字样。
在 `ExportViewModel.swift` 的 `export(indexOfMimeTypeSelected:)` 前面加一行打印，跑一次就知道：

```swift
// 临时调试：把所有可导出的 mime type 打出来
for v in viewModel?.mimeTypes ?? [] {
    print("MIME:", IINKMimeTypeValue.iinkMimeTypeGetName(v))
}
```

这也是我在方案里强调"用枚举而不是硬编码字符串"的原因 —— 我不敢赌那个字符串。

**如果数学识别没开**（写出来被当成普通文字）：把配置里的 `recognition.types` 加上 `math`，
参考仓库根的 `configurations/interactivity.json`：

```json
"raw-content": {
  "configuration": { "math": { "bundle": "math", "name": "standard" } },
  "recognition": { "types": [ "text", "math" ] }
}
```

### 要采集的 10 条

| # | 在纸上写 | 为什么 |
|---|---|---|
| 1 | `f(x)=x^3-3x` | 幕一开场 |
| 2 | `f'(x)=3x^2-3x` | 幕二写错的那行 |
| 3 | `f'(x)=3x^2-3` | 幕二改对的那行 |
| 4 | `f(x)=x^3-x` | 改系数之后 |
| 5 | `f'(x)=2x^2-3` | 系数错 |
| 6 | `f'(x)=-3x^2-3` | 符号错 |
| 7 | `f'(x)=3x^2` | 漏项 |
| 8 | `x^2-4` | 只有两项的函数 |
| 9 | `2x+3=7` | 等式（推导模式） |
| 10 | `\int 2x dx = x^2` 对应的手写：`∫2x dx = x²` | 积分（加分项） |

每条**用你平时写字的写法写两遍**（一遍工整、一遍随手），一共 20 个字符串。
把 "纸上写什么 → 引擎吐出什么 LaTeX" 做成一张表发我。

---

## 4. 我已经替你先挡了一刀

LaTeX 还没到手，但 iink 的写法我大概能猜：它会加 `\mathrm{}`、`\left(...\right)`、
`\cdot`、`^{\prime}`，还会在 `^` 两边留空格。所以我把 10 种"可能的写法"写进了夹具
（`golden_cases.json` 里 `"source": "suspected-iink"` 那 10 条）。

**结果当场抓出两个真缺口**：

```
P93  解析失败：这一行是等式，请用残差形式处理  [\mathrm{f}(x)=x^{3}-3x]
P100 解析失败：这一行是等式，请用残差形式处理  [\mathit{f}(x)=x^{3}-3x]
```

原因：`\mathrm{f}` 没被剥掉，导致 `f(x)` 标签认不出来，整行被当成等式。
已经在 Swift 侧加了 `stripWrappers`（处理 `\mathrm / \mathit / \mathbf / \mathsf / \text / \operatorname`），
现在 **51 条解析用例全绿**。

也就是说：**真实样本到之前，最可能的三种方言已经过了一遍测试。**
你把那 20 条发我，我替换掉这 10 条推测用例就行。

---

## 5. 一张表，填完发我

| # | 纸上写的 | 引擎输出的 LaTeX | 耗时 | 认错了没 |
|---|---|---|---|---|
| 1 | `f(x)=x³−3x` | | | |
| 2 | `f'(x)=3x²−3x` | | | |
| … | | | | |

有这张表，我就能：
1. 把 `parse` 夹具换成真实样本；
2. 知道哪些写法要**改学生的书写习惯**（这是演示脚本里"写法约定"那一节的依据）；
3. 给 `4 小时闸门`一个真实数字，而不是"感觉还行"。
