# iPad Battery Exercise

给 iPad 使用的本地 CPU／GPU 压测工具。支持单独选择 CPU、GPU 或同时运行；离开 App 时暂停，回到前台后按原选择续跑。压测期间降低屏幕亮度并关闭自动锁屏，控制区和运行状态一起缓慢移动；暂停或停止时恢复原设置。

界面实时显示本 App 的 CPU 使用率，以所有活动 CPU 核心总容量为 100%。数值仅用于显示，不保存历史记录。普通 iPadOS App 无法通过公开接口直接读取电池温度或整个设备的 GPU 使用率，因此不显示这两项。

目标设备是 2020 款 11 英寸 iPad Pro（A12Z），运行 iPadOS 26。App 不上传数据，也不保存测试记录。

## 构建与发布

先在 [GitHub 新建仓库](https://github.com/new) 创建公开的 `ipad-battery-exercise` 仓库，不初始化 README、`.gitignore` 或 license。如果本地代码尚未提交，先创建初始提交：

```powershell
git add .
git commit -m "Initial iPad battery exercise app"
```

连接新仓库并推送代码，然后推送一个版本标签：

```powershell
git remote add origin https://github.com/<用户名>/ipad-battery-exercise.git
git push -u origin main
git tag v1.0.0
git push origin v1.0.0
```

将 `<用户名>` 替换成实际 GitHub 用户名。版本标签须为 `v主版本.次版本.修订版本`，例如 `v1.0.0`。推送标签后，Actions 使用 `macos-26` 和 Xcode 26.6 编译未签名的 ARM64 App，将 `.ipa` 直接上传到对应的 GitHub Release。工作流不上传 Actions Artifact，也不使用 Apple 账户或签名材料。

工作流先创建草稿、上传附件，再发布 Release。如果上传或发布失败，检查 Actions 日志和 Release 草稿后可重新运行作业；已有同名附件只有在文件大小和 SHA-256 均一致时才会被复用。

## 安装与续签

从 GitHub Release 下载 `.ipa`。使用 Windows 上的 AltServer 首次安装 AltStore Classic 并完成设备配对，在 iPad 开启开发者模式；然后在 AltStore 中导入 IPA 并签名安装。

优先使用 AltStore 内置的 Remote AltServer：iPad 连 Wi‑Fi、开启 LocalDevVPN，并在 AltStore 启用后台刷新；需要时使用 **My Apps → Refresh All**。免费 Apple 账户的签名有效期为 7 天。若 AltStore 自身过期，可先用 Windows 上的 AltServer 覆盖安装 AltStore，再刷新本 App。

具体操作参见 [AltStore 远程服务器指南](https://faq.altstore.io/altstore-classic/remote-altservers)和 [AltServer 说明](https://faq.altstore.io/altstore-classic/altserver)。

## 验收

安装后分别短测 CPU、GPU 和双选，检查运行中控制区整体移动、移动中的停止按钮可用、CPU 使用率随负载变化，以及停止后亮度与自动锁屏恢复。运行中切到其他 App 再返回，检查原选择自动续跑；手动停止后切出再返回，应保持待机。关闭 Windows 后，使用 Remote AltServer 手动刷新一次，确认 AltStore 与本 App 的有效期更新。
