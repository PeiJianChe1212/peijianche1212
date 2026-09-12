# PeiLink Android Beta2 Final Audit 2

审计日期：2026-09-11（Asia/Shanghai）。本报告针对 HEAD `fff41c0f6282052ecb08a133e55584443eda9610` 加当前未提交工作区，以及本轮生成的正式 APK。没有安装 APK 或操作真机。

## A. Release Verdict

**READY AFTER DEVICE CHECK**

自动化、静态检查、debug 构建、正式 user release 构建及 APK 身份/签名取证均通过。当前未发现代码级 Release Blocker。正式分发给第二批用户前仍需完成第 W 节的受控真机全新安装验收。

## B. Version

- pubspec version：`0.6.8+18`
- APK versionName：`0.6.8`
- APK versionCode：`18`
- user applicationId：`com.peilink.app`
- dev applicationId：`com.peilink.dev`
- namespace：`com.peilink.app`
- minSdk / targetSdk：24 / 36

版本只在 pubspec 的既有正式来源中调整，没有在 Gradle 增加冲突硬编码。

## C. Signing Migration Decision

Beta1 实际分发证据为 `com.peilink.app`、`0.6.7+17`，证书 Subject `Android Debug`，SHA-256 `BC:90:4E:B9:9B:10:8C:6E:85:BF:C4:B4:EF:86:05:EC:51:44:22:D1:A6:EF:04:E2:33:BC:37:03:9D:B3:63:83`。

发布负责人决定从 Beta2 切换到新的长期 PeiLink release key，不再使用 Beta1 debug key。因此 Beta1 不能直接覆盖安装 Beta2；Beta2 作为新的长期签名基线。

keystore 位于仓库外 `G:\PeiLink_Keys\peilink-release.jks`。本机 `android/key.properties` 已由用户创建并被 `android/.gitignore` 排除；未读取、打印或提交密码。仓库内没有 `.jks` / `.keystore`。

## D. Release Certificate

- Subject：`CN=PeiLink Android Release, O=PeiLink`
- Issuer：`CN=PeiLink Android Release, O=PeiLink`
- SHA-256：`36:BC:88:D1:BD:D6:98:20:87:4E:1E:FC:7F:B7:FF:DC:61:65:67:2D:66:1A:C1:59:4F:BF:74:B9:59:C8:A1:BC`
- Validity：2026-09-10 16:40:07 UTC 至 2126-08-17 16:40:07 UTC
- Signer count：1

证书为 RSA 4096-bit，Subject 不是 Android Debug。该 SHA-256 是 **PeiLink Android Beta2+ 正式签名身份**；后续 Android 版本必须使用同一签名私钥。

## E. Git/worktree

审计时工作区有 32 个 modified、40 个 untracked、0 deleted、0 staged 条目。Beta2 功能及测试仍集中在未提交工作区；正式 APK确实由该工作区构建，不能把 HEAD 单独当作本 APK 的可复现源码。

`android/key.properties` 未被跟踪，keystore 不在仓库内。`git diff --check` 通过。发布归档前应单独审阅并提交/标记当前冻结工作区，避免 APK 与源码基线失配；本轮未代替用户提交 Git。

## F. Schema/storage

Final Audit 及 RC closure 已确认：本轮签名/版本工作没有改变 JSON key、schemaVersion、logical key、namespace、storage root 或业务数据路径。Memory2 与 Group Memory 仍为 schemaVersion 2；Appearance 仍只保存 backgroundId、bubbleThemeId、fontThemeId；GroupUserProfile 仍按 groupId 独立。

签名迁移不迁移 Beta1 本地沙盒。卸载 Beta1 通常删除其本地数据，不能承诺自动保留。

## G. Storage race regression

NativePlatformStorage 使用同目录唯一 staging 文件，并对 Windows errno 5/32/33 的短暂读写锁冲突做有界重试。并发回归 6/6 已在 RC closure 通过；本轮 targeted/full 均再次覆盖该测试且通过。

## H. Memory

旧管理 UI 隐藏，Legacy 读取/显式迁移、extraction、history、forgotten lifecycle、retry、Memory2 检索/注入仍保留。本轮未修改 Memory 产品逻辑或存储。

## I. Echo

Public Feed、我的 Echo、发布入口、角色空间及稳定 user owner `peilink_user_echo` 保留。角色仍使用 character.id 隔离。本轮未修改 Echo。

## J. Single Chat

发送/回复、ChatBubbleSurface、背景、字体 fallback、扩展面板、Archive、CharacterProfile 与 CharacterUserProfile 均纳入相关自动化回归。本轮未修改单聊业务。

## K. Group G2.5/G3.1～G3.5

每群用户身份、稳定 speaker label、local participation、Character Voice、按 groupId 隔离的 Group Memory、Reply Target 与每轮生成上限均由 targeted/full 覆盖。测试全部通过。本轮未修改 Group 业务逻辑。

## L. Physical isolation

`physical_release_isolation_test.dart` 3/3 通过：dev enabled 可进入、dev disabled 隐藏、user 隐藏。user 入口使用 `lib/main.dart`；dev 使用 `lib/main_dev.dart`。正式 APK 为 user flavor，Manifest 未暴露 Physical 组件入口。

## M. Theme/Bubble/Font/Background

稳定 ID、Appearance 持久化、真实气泡预览、背景及字体映射均纳入 targeted/full 测试并通过。字体保留 CJK fallback；本轮没有下载或更换资源。

## N. Targeted Tests

- passed：488
- failed：0
- skipped：0
- done：正常，`success=true`
- elapsed：约 38.3 秒

日志：`build/final_audit2_targeted.jsonl`。

## O. Full Tests

- passed：919
- failed：0
- skipped：0
- done：正常，`success=true`
- elapsed：约 94.2 秒

没有需要分类的新失败。日志：`build/final_audit2_full.jsonl`。

## P. Analyze

`flutter analyze --no-pub`：

- error：0
- warning：1
- info：3

保留已确认非阻断项：Memory2 两条历史花括号 info、group_chat_create_flow_test 一条注释 info 和一个未使用测试 helper warning。没有为清零修改业务代码。日志：`build/final_audit2_analyze.log`。

## Q. user/dev debug builds

- user debug：PASS，`com.peilink.app`，`0.6.8+18`，debuggable=true
- dev debug：PASS，`com.peilink.dev`，`0.6.8+18`，debuggable=true

产物分别为 `build/app/outputs/flutter-apk/app-user-debug.apk` 与 `app-dev-debug.apk`。Physical 自动化确认 user/dev 隔离。

## R. user release build

PASS。正式命令：

`flutter build apk --release --flavor user --target lib/main.dart --no-pub`

项目包装脚本在 Windows PowerShell 5 解析 `param` 时返回 `Unexpected token ')'`，尚未进入 Flutter。随后严格执行脚本内部相同的 Flutter 命令并成功。此为发布脚本宿主兼容已知问题，不影响本次 APK 内容；本轮未改脚本。

正式 APK：`G:\Development\PeiLink\build\app\outputs\flutter-apk\app-user-release.apk`

文件大小：115,111,167 bytes。

## S. APK Identity

由 APK 本体的 aapt2/apkanalyzer/apksigner 读取：

- packageName：`com.peilink.app`
- versionName：`0.6.8`
- versionCode：`18`
- minSdk：24
- targetSdk：36
- debuggable：false
- application label：PeiLink
- signer count：1
- v1：false
- v2：true
- v3 / v3.1 / v4：false
- signature verification：PASS，apksigner exit 0
- certificate：非 Android Debug

## T. APK SHA-256

`82DBE03B095292E6659DDF3225A39F0CCD420DE9C2F1F6598EAA8D909BA3E153`

该值只对应本报告中的 115,111,167-byte APK；任何重新构建都会产生需要重新取证的产物。

## U. Known Issues

1. Analyze 保留 1 warning / 3 info，均为已知非阻断项。
2. `scripts/build_user_release.ps1` 在本次调用的 Windows PowerShell 5 中有解析兼容问题；直接等价 Flutter 命令成功。
3. 工作区尚未提交，当前 APK 的可复现基线是 HEAD + 现有 dirty worktree。
4. 真机安装、首次启动、交互和持久化尚未执行。
5. 必须安全备份新 keystore、alias 与密码；丢失私钥将阻断 Beta2 之后的同包覆盖升级。

## V. Beta1 -> Beta2 Migration Notice

- Beta1：`0.6.7+17`，Android Debug certificate。
- Beta2：`0.6.8+18`，新 PeiLink Release Certificate。

两者证书不同，Beta1 **无法直接覆盖安装** Beta2。内部测试用户如有重要 Beta1 本地数据，应先明确当前版本没有签名迁移覆盖能力；卸载通常会删除本地数据。既定迁移方式为卸载 Beta1后全新安装 Beta2。从 Beta2 开始，后续版本使用本报告 D 节同一证书可正常覆盖升级。

## W. Device Validation Pending

- [ ] 卸载 Beta1（先确认无需保留或已人工处理重要数据）。
- [ ] 全新安装本报告对应的 Beta2 APK。
- [ ] 验证首次启动。
- [ ] 创建角色并发送单聊消息。
- [ ] 检查 Memory。
- [ ] 检查 Echo 公共流、我的 Echo 与角色空间。
- [ ] 创建群聊，设置群聊身份。
- [ ] 测试 @、+ 扩展面板和多角色回复。
- [ ] 检查背景、气泡、字体及深色背景可读性。
- [ ] 重启 App，确认角色、聊天、Memory、Echo、群聊身份和 Appearance 持久化。
- [ ] 后续有更高 versionCode 且使用同一证书的测试包时，再验证覆盖安装；本轮不额外生成测试版本。

## X. Final Verdict

1. 当前是否还有代码级 Release Blocker：**没有发现**。
2. 正式 APK 是否成功构建：**是**。
3. APK 路径：`G:\Development\PeiLink\build\app\outputs\flutter-apk\app-user-release.apk`。
4. APK SHA-256：`82DBE03B095292E6659DDF3225A39F0CCD420DE9C2F1F6598EAA8D909BA3E153`。
5. Beta2 certificate SHA-256：`36:BC:88:D1:BD:D6:98:20:87:4E:1E:FC:7F:B7:FF:DC:61:65:67:2D:66:1A:C1:59:4F:BF:74:B9:59:C8:A1:BC`。
6. 是否为非 Debug certificate：**是**。
7. versionName/versionCode：`0.6.8 / 18`。
8. 是否允许发给第二批 Android 内测用户：**完成一轮受控真机检查后允许；当前先用于该检查，不应在未安装验证前广泛分发**。
9. 仍需真机确认：首次安装/启动、核心单聊/Memory/Echo/群聊流程、装扮可读性、重启持久化。

最终 verdict：**READY AFTER DEVICE CHECK**。完成上述真机验收前保持发布暂停；本轮不进入 Guide、功能介绍、Web、Beta3 或新功能。
