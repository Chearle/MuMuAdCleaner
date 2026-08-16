# MuMuAdCleaner

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Chearle/MuMuAdCleaner)](https://github.com/Chearle/MuMuAdCleaner/releases/latest)

网易 MuMu 模拟器（安卓 15）桌面去广告。需要 KernelSU。

## 下载

https://github.com/Chearle/MuMuAdCleaner/releases/latest

## 去掉什么

- 顶部搜索栏广告
- 「每日新发现」和广告横幅
- 底栏「小工具」推广入口

游戏中心和已安装应用会保留。开机后仍然有效。Windows 开屏广告不在范围内。

## 使用

1. 模拟器开启 Root（桌面有 KernelSU）
2. 安装 [MuMuAdCleaner.apk](https://github.com/Chearle/MuMuAdCleaner/releases/latest/download/MuMuAdCleaner.apk)
3. 打开应用，KernelSU 授权后点 **去除广告**

多开时每台都要装一次。点 **恢复广告** 可还原。

## 编译

需要 JDK 17 和 Android SDK（`android-35`，含 `aapt2` 的 build-tools）。设置 `JAVA_HOME`、`ANDROID_HOME`。

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

APK 输出到本地 `dist/`（不入库，发布走 GitHub Release）。

## 原理

Root 下执行 `assets/apply.sh`：改 `nemud.player_engine` 隐藏搜索栏，禁用商店广告组件，清理 Lawnchair 桌面项，并写入 KernelSU 模块以便开机复用。

## License

[MIT](LICENSE) © Chearle
