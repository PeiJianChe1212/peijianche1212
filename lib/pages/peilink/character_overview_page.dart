import 'package:flutter/material.dart';

import 'character_detail_page.dart';

/// 兼容旧入口。
///
/// v1.1 起，所有 AI 都统一使用 [CharacterDetailPage]。
/// 即使旧路由仍然误跳到该页面，也不会再显示另一套概览 UI。
class CharacterOverviewPage extends StatelessWidget {
  const CharacterOverviewPage({super.key, this.character});

  final Object? character;

  @override
  Widget build(BuildContext context) {
    return const CharacterDetailPage();
  }
}
