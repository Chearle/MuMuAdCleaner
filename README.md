# MuMuAdCleaner

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Chearle/MuMuAdCleaner)](https://github.com/Chearle/MuMuAdCleaner/releases/latest)

网易 MuMu 模拟器去广告工具，包含 Android 桌面清理和 Windows 主机端启动广告清理。
Android 端默认使用临时 Root：清理完成后可以关闭 Root，不要求长期保留 KernelSU 模块。

## 下载

https://github.com/Chearle/MuMuAdCleaner/releases/latest

## Android 端

- 顶部搜索栏广告
- 「每日新发现」和广告横幅
- 底栏「小工具」推广入口

游戏中心和已安装应用会保留。默认勾选“临时 Root”：只修改关闭 Root 后仍会保留的广告组件
和桌面数据库，不安装开机模块，因此清理完成后可以关闭 Root。

搜索栏由系统属性 `nemud.player_engine` 控制。关闭 Root 并重启后，系统属性可能恢复，顶部
搜索栏也可能重新出现；推荐横幅和小工具推广仍保持清理。恢复操作会同时还原搜索栏属性，
并将桌面数据库恢复到首次清理前的状态，执行恢复时需要临时开启 Root。

## 使用

1. 在 MuMu 设置中临时开启 Root，并授予桌面上的 KernelSU
2. 安装 [MuMuAdCleaner.apk](https://github.com/Chearle/MuMuAdCleaner/releases/latest/download/MuMuAdCleaner.apk)
3. 打开应用，保留默认的 **临时 Root**，点 **去除广告**
4. 清理完成后在 MuMu 设置中关闭 Root

多开时每台都要装一次。点 **恢复广告** 可还原，恢复前需再次临时开启 Root。如果希望搜索栏
在每次开机后也自动隐藏，取消勾选 **临时 Root**；这会安装 KernelSU 模块并要求 Root 常开。

## Windows 主机端

Windows 开屏广告由 `MuMuNxMain.exe` 和宿主进程双端拉取，只在 Android 内部操作无法
彻底处理。仓库提供可回滚的图形化主机清理器，不需要输入命令：

1. 关闭 MuMu。
2. 双击 `MuMuAdCleaner.exe`，在 UAC 提示中允许管理员权限。
3. 点击 **一键清理广告**。程序会显示检测到的安装目录和运行日志。
4. 需要还原时重新双击，点击 **恢复原状**。

清理器会备份并改名更新、统计和崩溃上报程序，清空 `imageManager.json`，并在用户登录后
持续拦截广告字段重新写入。所有操作均可通过 GUI 完整恢复。详见
[`windows/README.md`](windows/README.md)。

## 编译

需要 JDK 17 和 Android SDK（`android-35`，含 `aapt2` 的 build-tools）。设置 `JAVA_HOME`、`ANDROID_HOME`。

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

APK 输出到本地 `dist/`（不入库，发布走 GitHub Release）。

## Android 原理

临时 Root 模式下执行 `assets/apply.sh --transient`：临时隐藏搜索栏、禁用商店广告组件，
以 SQLite 备份接口清理 Lawnchair 桌面项，不安装开机模块。组件状态和数据库修改会保留，
搜索栏属性则依赖当前 Root 会话。

常驻 Root 模式会额外写入 KernelSU 模块，在开机后重新应用属性。恢复脚本会先停止桌面、
还原数据库和原始属性，再重新启动桌面。

## License

[MIT](LICENSE) © Chearle
