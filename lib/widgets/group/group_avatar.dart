import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/peilink_theme_scope.dart';
import '../theme/peilink_themed_avatar.dart';

@immutable
class GroupAvatarMember {
  const GroupAvatarMember({
    required this.id,
    required this.avatarPath,
    required this.isUser,
  });

  final String id;
  final String avatarPath;
  final bool isUser;
}

List<GroupAvatarMember> groupAvatarMembers({
  required String userAvatarPath,
  required Iterable<GroupAvatarMember> characters,
}) => <GroupAvatarMember>[
  GroupAvatarMember(id: 'user', avatarPath: userAvatarPath, isUser: true),
  ...characters,
];

class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.members,
    this.size = 48,
    this.customAvatarPath = '',
  });

  final List<GroupAvatarMember> members;
  final double size;
  final String customAvatarPath;

  @override
  Widget build(BuildContext context) {
    final custom = File(customAvatarPath.trim());
    Widget content;
    if (customAvatarPath.trim().isNotEmpty && custom.existsSync()) {
      content = Image.file(custom, fit: BoxFit.cover);
    } else {
      final visible = members.take(4).toList(growable: false);
      content = Container(
        padding: const EdgeInsets.all(2),
        color: const Color(0xFFE1E5E7),
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: [
            for (final member in visible) _MemberAvatar(member: member),
            for (var i = visible.length; i < 4; i++)
              Container(color: const Color(0xFFF2F4F5)),
          ],
        ),
      );
    }
    return PeiLinkThemedAvatar(
      size: size,
      role: PeiLinkAvatarRole.group,
      shape: BoxShape.rectangle,
      image: content,
      frame: PeiLinkThemeScope.of(context).avatarFrameTheme.group,
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final GroupAvatarMember member;

  @override
  Widget build(BuildContext context) {
    final path = member.avatarPath.trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: const Color(0xFFEDF1F3),
      child: Icon(
        member.isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
        size: 13,
        color: const Color(0xFF647C8B),
      ),
    );
  }
}
