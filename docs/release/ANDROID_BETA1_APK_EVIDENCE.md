# PeiLink Beta1 APK Evidence

取证日期：2026-09-11（Asia/Shanghai）。本报告直接读取用户提供的 APK 与当前 Beta2 工程配置。未修改、安装或重新签名 APK；未构建 Beta2；未读取任何私钥或密码。

## A. APK source

- 完整路径：`G:\Development\PeiLink_Test_RC1.apk`
- 文件大小：81,941,141 bytes
- 最后修改时间：2026-09-11 00:08:58.0564691（Asia/Shanghai）
- 最后修改时间 UTC：2026-09-10T16:08:58.0564691Z
- ZIP/APK 结构：有效 ZIP，102 个条目，包含 `AndroidManifest.xml`
- Manifest：Android SDK `aapt2` 与 `apkanalyzer` 均可解析
- APK signing block：`apksigner` 可读取并验证 v2 签名

## B. File SHA-256

`E48FECB8E55BE946912155EE8BF311C18BC6B1A78D70F64F6A158CCBE71578DD`

## C. Package identity

- packageName/applicationId：`com.peilink.app`
- application label：`PeiLink`
- launchable activity：`com.example.peijianche_app.MainActivity`
- ABI：`arm64-v8a`、`armeabi-v7a`、`x86_64`

包名是 user 包名，不是 `com.peilink.dev`。launchable activity 仍使用旧 Java/Kotlin 类命名空间；这不改变 APK 的安装包身份。

## D. Version identity

- versionName：`0.6.7`
- versionCode：`17`
- compileSdk：`36`
- platform build version：Android 16 / API 36

## E. SDK info

- minSdk：`24`
- targetSdk：`36`

以上均由 APK 自身 Manifest 读取，不取自项目 pubspec。

## F. Debuggable

`apkanalyzer manifest debuggable` 返回 `false`。解析出的 `<application>` 没有 `android:debuggable=true`，因此此 APK 的应用调试标志为关闭。

Manifest 和 APK 文件列表未发现名为 Physical、developer 或 dev_only 的组件/资源条目。这个检查只能证明 Manifest/文件名层面没有对应特征，不能证明编译后的 Dart/AOT 内容绝对不含开发代码。

## G. Signing verification

Android SDK 36.0.0 `apksigner verify --verbose --print-certs`：验证成功，退出码 0。

- signer 数量：1
- v1 (JAR)：false
- v2：true
- v3：false
- v3.1：false
- v4：false
- SourceStamp：false
- 公钥算法：RSA 2048-bit

该 APK 依靠 v2 签名。`apksigner` 能正常读取 signing block，没有损坏证据。

## H. Certificate fingerprints

- Subject / DN：`CN=Android Debug, O=Android, C=US`
- Issuer：`CN=Android Debug, O=Android, C=US`（自签名）
- Serial number：`01`
- Valid from：2026-08-09 09:05:59 UTC
- Valid until：2056-08-01 09:05:59 UTC
- Certificate SHA-256：`BC:90:4E:B9:9B:10:8C:6E:85:BF:C4:B4:EF:86:05:EC:51:44:22:D1:A6:EF:04:E2:33:BC:37:03:9D:B3:63:83`
- Certificate SHA-1：`92:20:CC:78:E3:E6:47:8D:CC:57:76:51:06:F1:77:4D:3F:E0:A0:9F`
- Certificate MD5：`AC:20:6D:69:F2:10:27:D8:68:32:94:83:7E:7A:FE:2D`
- Public key SHA-256：`56:27:93:56:A3:F2:23:69:5D:ED:02:0D:71:6B:C9:6D:86:D2:1B:ED:18:D9:83:1F:77:DB:8D:43:34:7D:E7:54`

证书 Subject 明确为 `Android Debug`。按本次验收规则，结论为 **BETA1 WAS DEBUG-SIGNED**。

## I. Comparison with current Beta2

| 项目 | Beta1 APK 实证 | 当前 Beta2 工程 | 结论 |
|---|---|---|---|
| user applicationId | `com.peilink.app` | `com.peilink.app` | PASS |
| dev applicationId | 不适用；APK 不是 dev 包 | `com.peilink.dev` | user/dev 仍分离 |
| namespace | APK package 为 `com.peilink.app`；activity 使用旧类路径 | `com.peilink.app` | 安装包名一致 |
| versionName | `0.6.7` | `0.6.7` | 尚未体现 Beta2 版本递增 |
| versionCode | `17` | `17` | **NEEDS VERSION BUMP** |
| minSdk | 24 | Flutter 当前默认 24 | PASS |
| targetSdk | 36 | Flutter 当前默认 36 | PASS |
| signing | Android Debug cert，SHA-256 如上 | `android/key.properties` 不存在，四个 PEILINK signing 环境变量未配置 | BLOCKED |

当前 Beta2 versionCode 没有严格高于 Beta1。最小安全建议值为 **18**（Beta1 versionCode + 1）；本次未修改版本。

当前 versionName 与 Beta1 相同。Android 覆盖升级主要由 package、证书和 versionCode 决定，但发布识别上建议由发布负责人为 Beta2 选择明确的新 versionName；本次不代替负责人决定或修改。

## J. Upgrade compatibility verdict

最终结论：**BLOCKED BY DEBUG SIGNING**。

包名一致，数据目录具备原地覆盖的必要条件，但当前状态不能覆盖：

1. 当前 Beta2 versionCode 17 不高于 Beta1 的 17。
2. Beta1 使用 Android Debug 证书签名。
3. 当前 Beta2 没有 signing config，也没有证据证明持有该证书对应的同一私钥。

Android 覆盖安装要求新 APK 使用同一签名身份，并具有更高 versionCode。若 Beta2 使用另一张“正式”证书，即使包名相同也不能直接覆盖 Beta1。理论覆盖仅在把 versionCode 提升到至少 18，并使用产生上述 SHA-256 证书指纹的同一私钥签名后成立。

这不等于建议长期使用 debug key。是否继续使用该旧签名身份，或让测试用户卸载 debug-signed Beta1 后安装采用新正式证书的 Beta2，是发布与数据保留决策；卸载通常会删除应用本地数据，必须先另行评估备份/迁移方案。本轮不执行该决策。

## K. Remaining requirements

1. 发布负责人确认 `PeiLink_Test_RC1.apk` 确为实际分发的 Beta1 原包，而不是同名重建产物。
2. 将 Beta2 versionCode 设置为至少 18；本轮仅给出建议，没有修改。
3. 若要求覆盖安装，安全定位现有 Beta1 签名私钥，并在不暴露私钥的环境中先验证其证书 SHA-256 必须等于 `BC:90:...:63:83`。
4. 若不能或不应继续使用该 debug 签名，明确采用“无法原地覆盖”的新正式签名路线，并单独处理用户数据保留和安装说明。
5. 配置选定的签名环境后，再执行 Final Audit 2、正式构建、产物证书复核及真机覆盖/全新安装测试。

当前**不允许直接进入 Final Audit 2 + 正式签名阶段**。必须先由发布负责人解决 debug signing 路线并确认 versionCode/versionName；本报告不授权生成新密钥、写 signing 配置或构建 APK。

### Tools used

- Android SDK 36.0.0 `aapt2 dump badging`
- Android SDK `apkanalyzer apk summary / manifest print / manifest debuggable`
- Android SDK 36.0.0 `apksigner verify --verbose --print-certs[-pem]`
- OpenSSL `x509`（只解析 apksigner 导出的公开证书，用于 serial/validity）
- PowerShell `Get-FileHash` 和 ZIP 只读检查
