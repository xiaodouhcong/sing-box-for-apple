# 设计文档：iOS IPA GitHub Actions 自动编译

## 概述

在 GitHub Actions 的 macOS runner 上，通过自签名证书完成代码签名，编译 sing-box iOS 应用（SFI scheme）并导出 IPA。整个流程不依赖苹果开发者账号，生成的 IPA 可通过 AltStore、Sideloadly 等工具侧载安装。

## 架构

```
触发事件 (push / workflow_dispatch)
        │
        ▼
┌─────────────────────────────────────────┐
│         GitHub Actions Job              │
│         runs-on: macos-latest           │
│                                         │
│  1. Checkout (含 submodules)            │
│  2. 生成自签名证书 + 临时 Keychain       │
│  3. 安装 Swift Package 依赖             │
│  4. xcodebuild archive (SFI)            │
│  5. xcodebuild exportArchive → IPA      │
│  6. Upload artifact                     │
│  7. 清理 Keychain (always)              │
└─────────────────────────────────────────┘
        │
        ▼
   GitHub Artifact
   sing-box-{sha}.ipa
```

## 组件与接口

### 1. Workflow 文件
- 路径：`.github/workflows/build-ios.yml`
- 触发：`push`（main/master 分支）+ `workflow_dispatch`

### 2. 自签名证书生成脚本（内联 shell）
使用 `openssl` 生成临时 RSA 私钥和自签名证书，导入临时 Keychain：

```bash
# 生成私钥和自签名证书
openssl req -x509 -newkey rsa:2048 -keyout /tmp/ci.key \
  -out /tmp/ci.crt -days 1 -nodes \
  -subj "/CN=CI Self-Signed/O=CI/C=US"

# 打包为 p12
openssl pkcs12 -export -out /tmp/ci.p12 \
  -inkey /tmp/ci.key -in /tmp/ci.crt \
  -passout pass:ci_password

# 创建临时 Keychain
security create-keychain -p ci_keychain_password ci-build.keychain
security default-keychain -s ci-build.keychain
security unlock-keychain -p ci_keychain_password ci-build.keychain
security set-keychain-settings -t 3600 -u ci-build.keychain

# 导入证书
security import /tmp/ci.p12 -k ci-build.keychain \
  -P ci_password -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: \
  -s -k ci_keychain_password ci-build.keychain
```

### 3. ExportOptions.plist
导出 IPA 时使用的配置，指定 ad-hoc 签名方式（自签名证书场景下使用 `development` 或直接跳过签名验证）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

### 4. xcodebuild 命令

**Archive：**
```bash
xcodebuild archive \
  -project sing-box.xcodeproj \
  -scheme SFI \
  -configuration Release \
  -archivePath /tmp/sing-box.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="CI Self-Signed" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  | xcpretty
```

**Export IPA：**
```bash
xcodebuild -exportArchive \
  -archivePath /tmp/sing-box.xcarchive \
  -exportPath /tmp/ipa-output \
  -exportOptionsPlist ExportOptions.plist
```

## 数据模型

### Workflow 输入/输出

| 项目 | 类型 | 说明 |
|------|------|------|
| 触发事件 | push / workflow_dispatch | 无额外输入参数 |
| 产物文件名 | `sing-box-{git-sha-short}.ipa` | 包含 commit SHA 便于追溯 |
| 保留天数 | 7 天 | GitHub artifact 默认保留期 |

### 需要的 GitHub Secrets

本方案使用自签名证书，**不需要任何 GitHub Secrets**。所有签名材料在 CI 运行时临时生成，运行结束后自动销毁。

## 正确性属性

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

由于本功能的核心产物是 GitHub Actions workflow YAML 文件（配置文件而非业务逻辑代码），大多数验收标准属于配置正确性检查（example 类型），不适合 property-based testing。以下列出可验证的属性：

**Property 1：Workflow 不含硬编码敏感信息**
*对于* workflow YAML 文件中的任意字符串值，不应包含 base64 编码的证书数据或私钥内容（即不应出现长度超过 100 字符的 base64 字符串作为字面量）
**Validates: Requirements 2.4**

**Property 2：清理步骤始终执行**
*对于* workflow 的任意执行结果（成功或失败），清理 Keychain 的步骤必须带有 `if: always()` 条件
**Validates: Requirements 2.3**

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| submodule 初始化失败 | 步骤失败，workflow 终止，日志可见错误 |
| openssl 证书生成失败 | 步骤失败，workflow 终止 |
| xcodebuild archive 失败 | 步骤失败，workflow 终止，完整 xcodebuild 日志可见 |
| exportArchive 失败 | 步骤失败，workflow 终止 |
| Keychain 清理失败 | 记录警告，不影响整体结果（`continue-on-error: true`） |

## 测试策略

### 单元测试
本功能为 CI 配置文件，不涉及业务代码，无需传统单元测试。

### 验证方式
1. **手动触发验证**：在 GitHub Actions 页面点击 "Run workflow" 触发，检查每个步骤是否成功
2. **Artifact 验证**：下载生成的 IPA，用 `unzip -l` 检查包内容是否包含 `Payload/sing-box.app`
3. **安全验证**：检查 workflow YAML 文件，确认不含任何硬编码敏感信息

### Property-Based Testing
由于产物是 YAML 配置文件，property-based testing 不适用于本功能。正确性通过实际运行 workflow 来验证。
