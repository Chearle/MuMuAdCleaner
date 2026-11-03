# Windows 主机端清理（图形界面）

论坛里的 Windows 开屏广告不在模拟器内部，APK 无法直接修改主机文件。这个目录提供独立的
PowerShell 清理器，用于 MuMu 12 / 15 的主机端启动广告、更新器、统计和崩溃上报程序。

## 使用

1. 关闭 MuMu。
2. 双击 `MuMuAdCleaner.exe`。
3. Windows 请求管理员权限时点击 **是**。
4. 确认“MuMu 安装”路径正确，点击 **一键清理广告**。
5. 需要还原时再次打开，点击 **恢复原状**。

程序不需要命令行，也不会打开控制台窗口。安装目录无法自动识别时，可点击 **选择目录**，
选择包含 `shell`、`nx_main` 或 `nx_device` 的 MuMu 程序目录。

“安装开机守护”默认开启，用于清除 MuMu 下次启动时重新写入的广告配置。取消勾选后只执行
一次性清理。

## 要求

- Windows 10/11
- .NET Framework 4.x（Windows 自带）
- 修改 `Program Files` 内的文件需要管理员权限

## 可回滚项

脚本不会修改 `MuMuNxMain.exe` 或 `mumunxdevice.exe` 的二进制，也不会伪装会员状态。
它通过清理启动配置并拦截后续广告字段写入来避免广告显示，同时保留模拟器主体功能。

原始 `imageManager.json` 备份在配置文件同目录的 `imageManager.adclean-original.json`。
状态记录保存在 `%LOCALAPPDATA%\MuMuAdCleanerHost\state.json`。

`MuMuHostCleaner.ps1` 仅保留给开发和自动化测试使用，普通用户不需要运行它。
