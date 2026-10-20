# handwriting-recognize

iPad 笔迹数学。能编译、签名、装到设备上的 Mac 只有一台，就是 RuikAn-n 的 MacBook。演示机是这台 iPad Pro，笔是 Pencil Pro。

P2、P3、P4 把源码推到自己的分支。`main` 只表示这一版已经在那台 iPad 上装过。

- 客户端计划：[docs/P1-iPad客户端开发计划.md](docs/P1-iPad客户端开发计划.md)
- 基线：[docs/笔迹AI家教-Swift原生48小时方案.md](docs/笔迹AI家教-Swift原生48小时方案.md)
- 工程：`app/InkTutor.xcodeproj`

`MyCertificate.c` 不进这个仓库。真机三项验证还没做，结果写在 [docs/device.md](docs/device.md)。

## 这一版怎么用（p1/redesign）

整屏一张纸，顶上只有笔的状态和功能键（笔 / 橡皮、颜色、粗细、撤销、重做、完成一段、清空、识别引擎、设置）。不再有「函数 / 推导 / 几何」的模式按钮，也没有常驻的右半屏。

1. 先只显示原始墨迹。写完一段，**双击 Pencil Pro**，表示这一段输入完了；笔尖旁弹出「函数 / 推导 / 几何」。双击没进回调（或在模拟器上）时点工具栏的「完成一段」。
2. 选 **函数**：用 MyScript iink 的 Math Recognizer 把这段笔迹收成 LaTeX，手写笔迹淡出，换成标准式子。
3. 式子右上角挂一张 GeoGebra 式的函数卡片：网格、坐标轴、零点和极值点，拖动平移、双指缩放、双击复位，Pencil 悬停读坐标。
   点卡片标题栏选中后像 PS 的自由变换一样：拖四角 / 四边改大小，拖上方圆钮旋转（靠近整 90° 吸附），双指捏合缩放、转动。右上角的按钮收起成一枚小胶囊（minimize），点胶囊展开。
4. 点式子出操作条：改式子（手动改 LaTeX）、改笔迹（把原来的笔迹放回画布，擦改完双击、选「函数」更新这一条，卡片位置不变）、收起 / 展开图像、删除。拖动式子，卡片一起走。
5. 选 **推导**、**几何**：沿用 P3 的批改（圈错项、写出正确项和说明，改对后函数卡片标出极值点和切线）和草图识别（三角形 + 中线收成可拖的动态几何卡片），触发方式统一成双击后选。

识别链：MyScript（设备上）→ 百炼 → Mac 上的 Server；都没有就回放，前两幕不靠网络。设置里可以指定引擎。

界面（CI 在 iPad 模拟器上用 `-demo` 摆出来截的，见 `docs/screenshots/`；每次带 `[mac]` 的构建都会重截一套浅色 + 深色，在 Actions 的 `screenshots` 里下载）：

| 双击后笔尖旁的菜单 | 标准式子 + 函数卡片（选中，可变换）+ 推导批注 | 改对之后：极值点、切线、导函数、滑条 |
| --- | --- | --- |
| ![](docs/screenshots/menu-dark.png) | ![](docs/screenshots/card.png) | ![](docs/screenshots/reveal.png) |

## MyScript iink

- SDK：Swift 包 [MyScript/interactive-ink-packages-ios](https://github.com/MyScript/interactive-ink-packages-ios) 4.5.1，工程里已经加好（product `libiink`）。
- 证书：MyScript 开发者后台发的 `MyCertificate.c` 复制到 `app/InkTutor/MyScriptCertificate/MyCertificate.c`。这个目录在 `.gitignore` 里，Xcode 的文件夹同步会把它编进 App。没放证书也能编译运行（`MyScript/CertificateFallback.c` 是空证书的弱定义），函数识别退回其他引擎，设置页写明缺什么。
- 数学识别资源（math2，约 14 MB）不进仓库：Mac 上第一次编译时「MyScript Recognition Assets」这一步自动下载到 `app/MyScript/`，也可以手动跑 `tools/myscript/fetch-assets.sh`。这份资源是 MyScript 给示例程序用的。
- Bundle ID 要和证书对得上，否则设置页显示「证书无效」。

模拟器编译由 CI 验证（`ios-build`，commit 信息带 `[mac]` 或手动触发）。真机上的 Pencil 双击、悬停落点、整笔擦除、MyScript 实际识别效果还要在那台 iPad 上看，结果写进 [docs/device.md](docs/device.md)。这一版还没装到 iPad 上，所以没有推到远端 `main`。
