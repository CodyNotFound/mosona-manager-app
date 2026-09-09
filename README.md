# Mosona Manager APP

Mosona Manager 的官方移动客户端（Flutter），功能与 [mosona-manager-web](https://github.com/mosona-labs/mosona-manager-web) 网页版完全对齐，并针对手机屏幕适配：

- **登录/注册**：邮箱密码、记住我、2FA（TOTP / 邮箱验证码）、首次安装向导、自托管服务器地址配置
- **Dashboard**：SSE 实时服务器状态（1s 节流、5s 在线判定、断线重连）、概览统计卡、分类过滤/管理、服务器卡片（CPU/内存/SWAP/磁盘/剩余周期、标签行、展开详情）、长按/⋮ 操作菜单（终端、告警、编辑、分类、删除）
- **监控详情**：信息卡 + 6 类图表（CPU/内存/磁盘 IO/带宽/SWAP/挂载点用量），real-time 轮询与历史窗口（1h~365d）、聚合模式与 Y 轴设置
- **Web 终端**：服务器列表、多会话管理、xterm 终端（输入/resize JSON 帧、二进制输出、指数退避重连）
- **密钥库 / 日志 / 团队 / 公开页 / 个人资料 / 设置**：与网页版逐页对齐（含 TOTP 开关、OAuth 绑定、会话管理、Shoutrrr 通知、显示偏好持久化）
- **管理后台**：仪表盘（5s 轮询 + 图表）、用户管理、站点/邮件/注册登录/OAuth 设置
- **中英双语** 界面、明暗主题（对齐网页版中性色 + 语义色规范）

## 开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run   # 需要 Android/iOS 平台工具
```

对接文档：`docs/backend-api-spec.md`（后端 API 规格）、`docs/web-ui-spec.md`（网页版 UI 规格）、`docs/app-conventions.md`（本项目实现规范）。

会话机制与网页版一致：Cookie 会话 + 固定 User-Agent（后端绑定 UA），无需 CSRF token；WebSocket 终端复用同一会话。

## 许可

MIT © Mosona Labs
