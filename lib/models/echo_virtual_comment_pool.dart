enum EchoVirtualCommentSource { relationshipCharacter, worldResident }

class EchoVirtualCommentTemplate {
  const EchoVirtualCommentTemplate({
    required this.id,
    required this.source,
    required this.content,
    this.tags = const {},
  });

  final String id;
  final EchoVirtualCommentSource source;
  final String content;
  final Set<String> tags;
}

/// 受控评论池结构。当前阶段只预留模板，不自动挑选或发布。
class EchoVirtualCommentPool {
  const EchoVirtualCommentPool._();

  static const templates = <EchoVirtualCommentTemplate>[
    EchoVirtualCommentTemplate(
      id: 'world_detail_01',
      source: EchoVirtualCommentSource.worldResident,
      content: '这个细节很有意思。',
      tags: {'daily', 'detail'},
    ),
    EchoVirtualCommentTemplate(
      id: 'world_photo_01',
      source: EchoVirtualCommentSource.worldResident,
      content: '照片拍得很好。',
      tags: {'photo'},
    ),
  ];
}
