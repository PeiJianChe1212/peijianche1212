import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../services/character_deletion_service.dart';
import '../../services/session_reset_service.dart';

class CharacterManagementActions {
  const CharacterManagementActions._();

  static Future<bool> clearChat(
    BuildContext context,
    AiCharacter character,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除聊天记录？'),
        content: const Text('只会清除当前角色的聊天记录，Echo、Life、Memory、关系与角色资料都会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除聊天记录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await SessionResetService(characterId: character.id).clearChatOnly();
    return true;
  }

  static Future<bool> restart(
    BuildContext context,
    AiCharacter character,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新开始角色？'),
        content: const Text(
          '将清除当前角色的聊天记录以及本轮生活轨迹、Echo 等运行数据，并重新开始角色生活。角色资料、长期 Memory、关系数据及个人设置会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD98468),
            ),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await SessionResetService(characterId: character.id).resetSharedStory();
    return true;
  }

  static Future<bool> deleteCharacter(
    BuildContext context,
    AiCharacter character,
  ) async {
    final firstConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除${character.characterName}？'),
        content: const Text('永久删除该角色及其独立数据，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('继续删除'),
          ),
        ],
      ),
    );
    if (firstConfirmed != true || !context.mounted) return false;

    var typedName = '';
    final secondConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('最后确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请输入角色本名“${character.characterName}”确认删除：'),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (value) => typedName = value.trim(),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              typedName == character.characterName,
            ),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (secondConfirmed != true) return false;
    try {
      await CharacterDeletionService().delete(character.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除未完成。请等待记忆整理结束，并检查存储后重试。')),
        );
      }
      return false;
    }
    return true;
  }
}
