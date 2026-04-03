# 需求文档

## 简介

本功能为 sing-box iOS 应用（SFI scheme）在 GitHub Actions 上实现自动化 IPA 编译流程。目标是通过 GitHub Actions workflow，在代码推送或手动触发时，自动完成编译、打包，并将 IPA 文件作为 artifact 上传供下载。

由于没有苹果开发者证书，采用**自签名证书**（self-signed）方式完成代码签名。生成的 IPA 可通过 AltStore、Sideloadly 等工具侧载安装，或直接用于存档分发。项目包含 Network Extension（VPN）扩展，需要一并编译打包。

## 词汇表

- **IPA**：iOS App Archive，iOS 应用安装包格式
- **GitHub Actions**：GitHub 提供的 CI/CD 自动化平台
- **Workflow**：GitHub Actions 的自动化流程配置文件（YAML 格式）
- **Artifact**：GitHub Actions 构建产物，可供下载
- **自签名证书**：在 CI 环境中临时生成的代码签名证书，不依赖苹果开发者账号
- **Code Signing**：苹果平台代码签名流程
- **Keychain**：macOS 密钥链，用于存储证书
- **SFI**：本项目的 iOS 应用 scheme 名称，编译产物为 sing-box.app
- **Network Extension**：iOS VPN 隧道扩展（PacketTunnelProvider），作为 SFI 的子 target 一并编译
- **xcodebuild**：苹果官方命令行编译工具
- **xcarchive**：Xcode 归档文件，IPA 导出的中间产物
- **ExportOptions.plist**：xcodebuild 导出 IPA 时使用的配置文件，指定签名方式
- **侧载**：通过非 App Store 渠道将 IPA 安装到 iOS 设备的方式（如 AltStore、Sideloadly）

## 需求

### 需求 1

**用户故事：** 作为开发者，我希望在 GitHub 上触发自动编译，以便无需本地 Mac 环境即可获得可下载的 IPA 文件。

#### 验收标准

1. WHEN 开发者向仓库推送代码或手动触发 workflow，THE GitHub Actions 系统 SHALL 在 macOS runner 上启动 iOS 编译任务
2. WHEN 编译任务启动，THE 编译系统 SHALL 检出代码并递归初始化 git submodule（Runestone 框架）
3. WHEN 代码检出完成，THE 编译系统 SHALL 在 CI 环境中生成临时自签名证书并导入临时 Keychain
4. WHEN 签名环境就绪，THE 编译系统 SHALL 使用 xcodebuild 对 SFI scheme 执行 archive 操作
5. WHEN archive 成功，THE 编译系统 SHALL 将 xcarchive 以 ad-hoc 方式导出为 IPA 文件
6. WHEN IPA 文件生成，THE GitHub Actions 系统 SHALL 将 IPA 作为 artifact 上传，保留期不少于 7 天

### 需求 2

**用户故事：** 作为开发者，我希望签名流程完全在 CI 环境中自动完成，以便不依赖任何外部证书或开发者账号。

#### 验收标准

1. WHEN workflow 运行，THE 编译系统 SHALL 使用 `openssl` 或 `security` 命令在 runner 上生成临时 RSA 私钥和自签名证书
2. WHEN 临时证书生成，THE 编译系统 SHALL 创建临时 Keychain 并将证书导入其中
3. WHEN workflow 完成（无论成功或失败），THE 编译系统 SHALL 删除临时 Keychain 以清理环境
4. THE workflow 配置文件 SHALL 不包含任何硬编码的证书内容或私钥数据

### 需求 3

**用户故事：** 作为开发者，我希望 workflow 支持手动触发，以便按需生成 IPA。

#### 验收标准

1. THE workflow SHALL 支持 `workflow_dispatch` 手动触发事件
2. THE workflow SHALL 支持 `push` 事件触发，限定在 `main` 或 `master` 分支
3. WHEN workflow 触发，THE 编译系统 SHALL 将编译产物以包含 commit SHA 的文件名上传为 artifact
