# MuMu去广告

给网易 MuMu 模拟器（安卓 15 / KernelSU）用的去广告 APK。去掉开屏以外的桌面广告：顶部搜索栏、「每日新发现」、底栏「小工具」推广入口。

## 安装包

`dist/MuMuAdCleaner.apk`

## 使用

1. 模拟器开启 Root（桌面能看到 KernelSU）
2. 把 APK 拖进模拟器安装
3. 打开 **MuMu去广告**，在 KernelSU 里授权
4. 点 **去除广告**

每台模拟器装一次即可，重启后仍然有效。点 **恢复广告** 可以还原桌面。

Windows 端开屏广告不在这个 APK 里处理。

## 编译

本机需要 JDK 17 和 Android SDK（build-tools 36、platform android-35）。

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```
