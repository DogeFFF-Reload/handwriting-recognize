# handwriting-recognize

iPad 笔迹数学。能编译、签名、装到设备上的 Mac 只有一台，就是 RuikAn-n 的 MacBook。演示机是这台 iPad Pro，笔是 Pencil Pro。

P2、P3、P4 把源码推到自己的分支。`main` 只表示这一版已经在那台 iPad 上装过。

- 客户端计划：[docs/P1-iPad客户端开发计划.md](docs/P1-iPad客户端开发计划.md)
- 基线：[docs/笔迹AI家教-Swift原生48小时方案.md](docs/笔迹AI家教-Swift原生48小时方案.md)
- 工程：`app/InkTutor.xcodeproj`

`MyCertificate.c` 不进这个仓库。真机三项验证还没做，结果写在 [docs/device.md](docs/device.md)。

P1 客户端已经接上 P2 的右半屏和 P3 的分行、门禁、批改。没填识别 Key 时走回放，前两幕不靠网络。模拟器编译通过。这一版还没装到 iPad 上，所以没有推到远端 `main`。
