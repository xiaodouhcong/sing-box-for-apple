# 实现计划

- [x] 1. 创建 GitHub Actions workflow 文件基础结构


  - 创建 `.github/workflows/build-ios.yml`
  - 配置触发事件：`push`（main/master 分支）和 `workflow_dispatch`
  - 配置 job 运行在 `macos-latest` runner
  - _Requirements: 1.1, 3.1, 3.2_


- [ ] 2. 实现代码检出步骤
  - 使用 `actions/checkout@v4`，配置 `submodules: recursive` 以初始化 Runestone 子模块

  - _Requirements: 1.2_

- [ ] 3. 实现自签名证书生成与 Keychain 配置
  - 使用 `openssl` 生成临时 RSA 私钥和自签名证书
  - 将证书打包为 p12 格式
  - 创建临时 Keychain 并导入证书

  - 配置 `security set-key-partition-list` 允许 codesign 访问
  - _Requirements: 2.1, 2.2_

- [x] 4. 创建 ExportOptions.plist 文件

  - 在仓库根目录创建 `ExportOptions.plist`
  - 配置 `method: ad-hoc`，`signingStyle: manual`
  - _Requirements: 1.5_

- [ ] 5. 实现 xcodebuild archive 步骤
  - 配置 `xcodebuild archive` 命令，指定 SFI scheme、Release configuration

  - 设置 `CODE_SIGN_STYLE=Manual`，`CODE_SIGN_IDENTITY` 指向临时证书
  - 设置 `PROVISIONING_PROFILE_SPECIFIER=""` 跳过 Profile 验证
  - 输出路径为 `/tmp/sing-box.xcarchive`
  - _Requirements: 1.4_


- [ ] 6. 实现 exportArchive 导出 IPA 步骤
  - 配置 `xcodebuild -exportArchive` 命令
  - 引用 `ExportOptions.plist`
  - 输出路径为 `/tmp/ipa-output`
  - _Requirements: 1.5_



- [ ] 7. 实现 artifact 上传步骤
  - 使用 `actions/upload-artifact@v4`
  - 产物名称包含 commit SHA：`sing-box-${{ github.sha }}`
  - 设置 `retention-days: 7`
  - _Requirements: 1.6, 3.3_

- [ ] 8. 实现 Keychain 清理步骤
  - 添加清理步骤，删除临时 Keychain
  - 配置 `if: always()` 确保无论成功失败都执行
  - _Requirements: 2.3_

- [ ] 9. 最终检查点
  - 确认 workflow YAML 文件不含任何硬编码敏感信息
  - 确认所有步骤顺序正确，依赖关系完整
  - 在 GitHub 上手动触发 workflow，验证 IPA artifact 成功生成
