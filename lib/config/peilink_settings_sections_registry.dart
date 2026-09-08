import 'package:flutter/widgets.dart';

/// 设置页扩展点：user 构建永不安装开发者区块。
///
/// 开发者区块（Physical、Core Bridge、Developer Environment、Prompt 测试、
/// Memory 诊断）只由 dev 入口通过 [installDeveloperSections] 注入；
/// user 入口的 import graph 不引用任何 dev-only 页面。
typedef PeiLinkSettingsSectionBuilder =
    List<Widget> Function(BuildContext context);

abstract final class PeiLinkSettingsSectionsRegistry {
  static PeiLinkSettingsSectionBuilder? _developerSections;

  static void installDeveloperSections(PeiLinkSettingsSectionBuilder builder) {
    _developerSections = builder;
  }

  static List<Widget> buildSections(BuildContext context) =>
      _developerSections?.call(context) ?? const <Widget>[];
}
