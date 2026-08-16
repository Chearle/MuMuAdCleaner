# MuMuAdCleaner

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-MuMu%20Player-7B6CFF.svg)](https://github.com/Chearle/MuMuAdCleaner)
[![Root](https://img.shields.io/badge/Root-KernelSU-2ea44f.svg)](https://github.com/tiann/KernelSU)

网易 MuMu 模拟器桌面去广告工具。安装后授权 Root，一键去掉搜索栏广告、「每日新发现」和底栏「小工具」推广入口。

> For NetEase MuMu Player (Android 15). Requires KernelSU / root.

## 功能

| 项目 | 处理后 |
| --- | --- |
| 顶部搜索栏广告 | 隐藏 |
| 「每日新发现」桌面组件 | 移除 |
| 广告横幅组件 | 移除 |
| 底栏「小工具」（谷歌安装器 / RE 文件管理器） | 移除 |
| 游戏中心、已安装应用图标 | 保留 |
| 重启后是否仍然有效 | 是（写入 KernelSU 开机脚本） |

Windows 端游戏启动开屏广告不在本工具范围内。

## 环境要求

- MuMu 模拟器 6.x（安卓 15）
- 已开启 Root，桌面能看到 **KernelSU**
- 每台模拟器实例需要单独安装一次

## 下载

- 发布页：https://github.com/Chearle/MuMuAdCleaner/releases/latest
- 安装包：https://github.com/Chearle/MuMuAdCleaner/releases/latest/download/MuMuAdCleaner.apk

## 使用方法

1. 把 APK 拖进模拟器窗口安装，或从 MuMu 共享文件夹打开。
2. 打开 **MuMu去广告**。
3. 在 KernelSU 弹窗中允许 Root。
4. 点击 **去除广告**。
5. 回到桌面确认搜索栏和「每日新发现」已消失。

多开时，每一台都要安装并授权一次。

### 恢复

打开应用，点击 **恢复广告**。桌面布局会尽量还原到清理前的备份。

## 从源码编译

### 依赖

- JDK 17
- Android SDK
  - `platforms;android-35`
  - `build-tools;36.0.0`（需包含 `aapt2`）
- 环境变量 `JAVA_HOME`、`ANDROID_HOME` 或 `ANDROID_SDK_ROOT`

### 命令

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

产物输出到 `dist/MuMuAdCleaner.apk`。

## 目录结构

```text
MuMuAdCleaner/
├── AndroidManifest.xml
├── LICENSE
├── README.md
├── build.ps1                 # Windows 编译脚本
├── assets/
│   ├── apply.sh              # Root 下去广告
│   └── restore.sh            # 恢复
├── dist/
│   └── MuMuAdCleaner.apk     # 预编译安装包
├── res/                      # 界面资源
└── src/dev/adclean/mumu/
    └── MainActivity.java
```

## 工作原理

应用在获得 Root 后执行 `assets/apply.sh`：

1. 将 `nemud.player_engine` 设为 `WOAPRO`，隐藏 MuMu 定制搜索栏。
2. 禁用 `com.mumu.store` 中的广告 Widget 组件，不禁用整个应用商店。
3. 清理 Lawnchair 桌面数据库中的广告项和「小工具」快捷方式。
4. 安装 KernelSU 模块 / `service.d` 脚本，开机后自动重复上述步骤。

## 免责声明

本项目仅用于改善个人使用体验，与网易、MuMu 模拟器官方无关。修改桌面布局和系统属性可能随模拟器更新失效。请自行备份重要数据。

## License

[MIT](LICENSE) © Chearle
