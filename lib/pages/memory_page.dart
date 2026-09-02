import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/character_user_profile.dart';
import '../models/event_memory.dart';
import '../models/legacy_memory_view.dart';
import '../models/user_memory.dart';
import '../services/memory_center_controller.dart';
import '../services/memory_summary_generation_service.dart';
import '../services/legacy_memory_migration_service.dart';
import '../theme/app_theme_background.dart';
import 'memory_review_page.dart';
import 'peilink/character_user_profile_page.dart';

const _memoryMutationFailureMessage = '操作未完成，原始记忆仍保留，请检查存储后重试。';

Future<void> _runMemoryMutation(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_memoryMutationFailureMessage)),
      );
    }
  }
}

class MemoryPage extends StatefulWidget {
  const MemoryPage({
    super.key,
    required this.characterId,
    this.controller,
    this.summaryGenerator,
  });
  final String characterId;
  final MemoryCenterController? controller;
  final MemorySummaryGenerationGateway? summaryGenerator;
  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  late final MemoryCenterController controller;
  late final MemorySummaryGenerationGateway summaryGenerator;
  final search = TextEditingController();
  MemoryCenterSnapshot? data;
  bool loading = true;
  bool generating = false;
  String query = '';
  bool migrating = false;

  Future<void> migrateLegacy() async {
    if (migrating) return;
    setState(() => migrating = true);
    try {
      final service = LegacyMemoryMigrationService(
        characterId: widget.characterId,
        storage: controller.storage,
        fileProvider: controller.storage.fileProvider,
      );
      final preview = await service.preview();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('迁移旧版记忆'),
          content: Text(
            '关于我的记忆：${preview.users} 条\n经历过的事：${preview.events} 条\n已存在或重复：${preview.duplicates} 条\n无法确定类型：${preview.unclassified} 条\n已归档：${preview.archived} 条\n无效或空内容：${preview.invalid} 条\n\n原始旧数据会保留，不会自动生成总结。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: preview.transferable + preview.duplicates == 0
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('确认整理'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await service.execute(preview);
      if (!mounted) return;
      snack(result.success ? '旧记忆已经整理到新的记忆系统中，原始数据仍为你保留。' : result.error!);
      await load();
    } catch (_) {
      if (mounted) snack('无法安全读取旧记忆，请检查数据后重试。');
    } finally {
      if (mounted) setState(() => migrating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        MemoryCenterController(characterId: widget.characterId);
    summaryGenerator =
        widget.summaryGenerator ?? MemorySummaryGenerationService();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final next = await controller.load();
      if (mounted) {
        setState(() {
          data = next;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void snack(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text('删除后无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;

  List<EventMemory> events(EventMemoryStatus status) {
    final q = query.trim().toLowerCase();
    final items = (data?.events ?? const <EventMemory>[])
        .where(
          (e) =>
              e.status == status &&
              (q.isEmpty || e.content.toLowerCase().contains(q)),
        )
        .toList();
    items.sort(
      (a, b) => a.isPinned != b.isPinned
          ? (a.isPinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt),
    );
    return items;
  }

  List<UserMemory> get users {
    final q = query.trim().toLowerCase();
    final items = (data?.userMemories ?? const <UserMemory>[])
        .where(
          (e) =>
              e.status == UserMemoryStatus.active &&
              (q.isEmpty || e.displayText.toLowerCase().contains(q)),
        )
        .toList();
    items.sort(
      (a, b) => a.isPinned != b.isPinned
          ? (a.isPinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt),
    );
    return items;
  }

  Future<void> editUser([UserMemory? item]) async {
    final draft = await showDialog<_UserDraft>(
      context: context,
      builder: (_) => _UserDialog(item: item),
    );
    if (draft == null) return;
    if (!mounted) return;
    await _runMemoryMutation(context, () async {
      if (item == null) {
        await controller.addUserMemory(draft.key, draft.value);
      } else {
        await controller.updateUserMemory(
          item,
          key: draft.key,
          value: draft.value,
        );
      }
      await load();
    });
  }

  Future<void> addEvent() async {
    final draft = await showDialog<_EventDraft>(
      context: context,
      builder: (_) => const _EventDialog(),
    );
    if (draft == null) return;
    if (!mounted) return;
    await _runMemoryMutation(context, () async {
      await controller.addEvent(draft.text, isPinned: draft.pinned);
      await load();
    });
  }

  Future<void> editSummary() async {
    final current = data!;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: '编辑记忆汇总',
        initial: current.summary.effectiveText,
        allowEmpty: true,
      ),
    );
    if (text == null) return;
    if (!mounted) return;
    await _runMemoryMutation(context, () async {
      await controller.saveUserEditedSummary(current.summary, text);
      await load();
    });
  }

  Future<void> updateSummary() async {
    final current = data!;
    if (generating) return;
    setState(() => generating = true);
    try {
      final result = await summaryGenerator.generate(
        MemorySummaryGenerationInput(
          currentSummary: current.summary,
          eventMemories: current.events,
          userMemories: current.userMemories,
          legacyMemories: current.legacy,
        ),
      );
      if (!mounted) return;
      final preview = await showDialog<_PreviewResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PreviewDialog(
          initial: result,
          hasUserEdit: current.summary.userEditedText.trim().isNotEmpty,
        ),
      );
      if (preview == null) return;
      await controller.saveGeneratedSummary(
        current.summary,
        preview.text,
        replaceUserEdit: preview.replace,
      );
      await load();
    } catch (_) {
      snack('更新总结失败，原来的内容没有改变');
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> copyAll() async {
    final text = controller.buildCopyText(data!);
    if (text.isEmpty) return snack('还没有可以复制的记忆');
    await Clipboard.setData(ClipboardData(text: text));
    snack('已复制全部记忆');
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = data;
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            snapshot == null ? '记忆' : '${snapshot.settings.characterName}的记忆',
          ),
          centerTitle: true,
          actions: [
            PopupMenuButton<String>(
              tooltip: '管理记忆',
              onSelected: (value) async {
                if (value == 'copy') await copyAll();
                if (value == 'migrate') await migrateLegacy();
                if (value == 'forgotten') {
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ForgottenMemoriesPage(controller: controller),
                    ),
                  );
                  await load();
                }
                if (!context.mounted) return;
                if (value == 'legacy') {
                  await showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => _LegacySheet(
                      items: snapshot?.legacy ?? const [],
                      migratedIds: snapshot?.migratedLegacyIds ?? const {},
                    ),
                  );
                }
                if (!context.mounted) return;
                if (value == 'review') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MemoryReviewPage(characterId: widget.characterId),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'migrate',
                  enabled:
                      !migrating &&
                      (snapshot?.legacy.any(
                            (item) =>
                                !item.legacyArchived &&
                                item.kind !=
                                    LegacyMemoryKind.legacyUnclassified,
                          ) ??
                          false),
                  child: const Text('迁移旧版记忆'),
                ),
                PopupMenuItem(value: 'copy', child: Text('复制全部记忆')),
                PopupMenuItem(value: 'forgotten', child: Text('已遗忘的记忆')),
                PopupMenuItem(value: 'legacy', child: Text('旧版记忆')),
                PopupMenuItem(value: 'review', child: Text('旧版待审核')),
              ],
            ),
          ],
        ),
        floatingActionButton: snapshot == null
            ? null
            : FloatingActionButton.extended(
                onPressed: addEvent,
                icon: const Icon(Icons.add),
                label: const Text('新增经历'),
              ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : snapshot == null
            ? const Center(child: Text('暂时无法读取记忆'))
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    const Text(
                      '有些事被认真记住，也有些会随着时间慢慢变淡。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8F8799)),
                    ),
                    const SizedBox(height: 14),
                    _glass(
                      SwitchListTile(
                        value: snapshot.settings.autoMemoryEnabled,
                        onChanged: (value) async {
                          await controller.setAutoMemoryEnabled(
                            snapshot.settings,
                            value,
                          );
                          await load();
                        },
                        secondary: const Icon(Icons.auto_awesome_rounded),
                        title: const Text('自动记忆'),
                        subtitle: const Text('聊天一段时间后，Ta 会自动整理值得记住的内容。'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _section('Ta 心中的我', '我告诉 Ta 的我', [
                      _ProfileView(profile: snapshot.characterUserProfile),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CharacterUserProfilePage(
                                  characterId: widget.characterId,
                                  characterName:
                                      snapshot.settings.characterName,
                                ),
                              ),
                            );
                            await load();
                          },
                          child: const Text('编辑我的设定'),
                        ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ta 逐渐了解到',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: editUser,
                            icon: const Icon(Icons.add),
                            label: const Text('添加'),
                          ),
                        ],
                      ),
                      if (users.isEmpty) const _Empty('相处久一点，Ta 会慢慢了解你。'),
                      for (final item in users)
                        _UserTile(
                          item: item,
                          onEdit: () => editUser(item),
                          onPin: () async {
                            await _runMemoryMutation(context, () async {
                              await controller.setUserMemoryPinned(
                                item,
                                !item.isPinned,
                              );
                              await load();
                            });
                          },
                          onDelete: () async {
                            if (await confirm('删除这条认识？')) {
                              if (!context.mounted) return;
                              await _runMemoryMutation(context, () async {
                                await controller.deleteUserMemory(item);
                                await load();
                              });
                            }
                          },
                        ),
                    ]),
                    const SizedBox(height: 14),
                    _section('记忆汇总', '一份简短、长期保留的相处总结', [
                      if (snapshot.summary.effectiveText.isEmpty)
                        const _Empty('还没有整理长期记忆')
                      else
                        SelectableText(
                          snapshot.summary.effectiveText,
                          style: const TextStyle(height: 1.6),
                        ),
                      if (snapshot.summary.userEditedText.trim().isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '当前显示的是你编辑过的版本',
                            style: TextStyle(
                              color: Color(0xFF7B70B3),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: editSummary,
                            child: const Text('编辑'),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('update-memory-summary'),
                            onPressed: generating ? null : updateSummary,
                            icon: const Icon(Icons.auto_awesome_rounded),
                            label: Text(generating ? '正在整理…' : '更新总结'),
                          ),
                          if (snapshot.summary.effectiveText.isNotEmpty)
                            TextButton(
                              onPressed: () async {
                                if (await confirm('清空整个记忆汇总？')) {
                                  if (!context.mounted) return;
                                  await _runMemoryMutation(context, () async {
                                    await controller.clearSummary();
                                    await load();
                                  });
                                }
                              },
                              child: const Text('清空全部'),
                            ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 14),
                    TextField(
                      controller: search,
                      onChanged: (value) => setState(() => query = value),
                      decoration: InputDecoration(
                        hintText: '搜索经历和 Ta 了解的我',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .72),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _section('经历过的事', '共同经历会留在这里', [
                      for (final item in events(EventMemoryStatus.active))
                        _EventTile(
                          item: item,
                          controller: controller,
                          reload: load,
                          confirm: confirm,
                        ),
                      for (final item in events(EventMemoryStatus.fading))
                        Opacity(
                          opacity: .78,
                          child: _EventTile(
                            item: item,
                            controller: controller,
                            reload: load,
                            confirm: confirm,
                          ),
                        ),
                      if (events(EventMemoryStatus.pendingForget).isNotEmpty)
                        const _FadingDivider(key: Key('fading-divider')),
                      for (final item in events(
                        EventMemoryStatus.pendingForget,
                      ))
                        Opacity(
                          opacity: .62,
                          child: _EventTile(
                            item: item,
                            controller: controller,
                            reload: load,
                            confirm: confirm,
                            hint: '这段记忆正在变淡',
                          ),
                        ),
                      if ([
                        ...events(EventMemoryStatus.active),
                        ...events(EventMemoryStatus.fading),
                        ...events(EventMemoryStatus.pendingForget),
                      ].isEmpty)
                        const _Empty('还没有共同经历被记下来。'),
                    ]),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _glass(Widget child) => Material(
    color: Colors.white.withValues(alpha: .74),
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
  Widget _section(String title, String subtitle, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .85)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF948C9D), fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class ForgottenMemoriesPage extends StatefulWidget {
  const ForgottenMemoriesPage({super.key, required this.controller});
  final MemoryCenterController controller;
  @override
  State<ForgottenMemoriesPage> createState() => _ForgottenState();
}

class _ForgottenState extends State<ForgottenMemoriesPage> {
  List<EventMemory>? items;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final s = await widget.controller.load();
    if (mounted) {
      setState(
        () => items = s.events
            .where((e) => e.status == EventMemoryStatus.forgotten)
            .toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ThemeBackgroundContainer(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('已遗忘的记忆'),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items!.isEmpty
          ? const Center(child: Text('这里还没有已遗忘的记忆'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final item in items!)
                  Card(
                    child: ListTile(
                      title: Text(item.content),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'restore') {
                            await _runMemoryMutation(context, () async {
                              await widget.controller.restoreEvent(item);
                            });
                          }
                          if (v == 'copy') {
                            await Clipboard.setData(
                              ClipboardData(text: item.content),
                            );
                          }
                          if (v == 'delete') {
                            if (!context.mounted) return;
                            await _runMemoryMutation(context, () async {
                              await widget.controller.deleteEvent(item);
                            });
                          }
                          await load();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'restore', child: Text('恢复记忆')),
                          PopupMenuItem(value: 'copy', child: Text('复制')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.profile});
  final CharacterUserProfile profile;
  @override
  Widget build(BuildContext context) {
    final rows = [
      if (profile.userName.trim().isNotEmpty) '我的称呼  ${profile.userName}',
      if (profile.gender.trim().isNotEmpty) '性别  ${profile.gender}',
      if (profile.effectiveDescription.trim().isNotEmpty)
        profile.effectiveDescription,
    ];
    return rows.isEmpty
        ? const _Empty('还没有告诉 Ta 你的设定。')
        : Text(rows.join('\n'), style: const TextStyle(height: 1.6));
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.item,
    required this.onEdit,
    required this.onPin,
    required this.onDelete,
  });
  final UserMemory item;
  final VoidCallback onEdit, onPin, onDelete;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(item.isPinned ? Icons.push_pin : Icons.favorite_border),
    title: Text(item.key.isEmpty ? '记住的事' : item.key),
    subtitle: item.value.isEmpty ? null : Text(item.value),
    trailing: PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'pin') onPin();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        PopupMenuItem(value: 'pin', child: Text(item.isPinned ? '取消固定' : '固定')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.item,
    required this.controller,
    required this.reload,
    required this.confirm,
    this.hint,
  });
  final EventMemory item;
  final MemoryCenterController controller;
  final Future<void> Function() reload;
  final Future<bool> Function(String) confirm;
  final String? hint;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(item.isPinned ? Icons.push_pin : Icons.auto_stories_outlined),
    title: Text(item.content),
    subtitle: hint == null ? null : Text(hint!),
    trailing: PopupMenuButton<String>(
      onSelected: (v) async {
        if (v == 'pin') {
          await _runMemoryMutation(context, () async {
            await controller.setEventPinned(item, !item.isPinned);
          });
        }
        if (v == 'copy') {
          await Clipboard.setData(ClipboardData(text: item.content));
        }
        if (v == 'delete' && await confirm('删除这段经历？')) {
          if (!context.mounted) return;
          await _runMemoryMutation(context, () async {
            await controller.deleteEvent(item);
          });
        }
        await reload();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(item.isPinned ? '取消固定' : '不要忘记'),
        ),
        const PopupMenuItem(value: 'copy', child: Text('复制')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ),
  );
}

class _FadingDivider extends StatelessWidget {
  const _FadingDivider({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '以下记忆逐渐模糊',
            style: TextStyle(color: Color(0xFF938C9C), fontSize: 12),
          ),
        ),
        Expanded(child: Divider()),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: const TextStyle(color: Color(0xFF9B94A1))),
  );
}

class _EventDraft {
  const _EventDraft(this.text, this.pinned);
  final String text;
  final bool pinned;
}

class _EventDialog extends StatefulWidget {
  const _EventDialog();
  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final text = TextEditingController();
  bool pinned = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新增经历'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: text,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: '写下值得记住的共同经历…'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: pinned,
          onChanged: (v) => setState(() => pinned = v ?? false),
          title: const Text('不要忘记'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (text.text.trim().isNotEmpty) {
            Navigator.pop(context, _EventDraft(text.text.trim(), pinned));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _UserDraft {
  const _UserDraft(this.key, this.value);
  final String key, value;
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({this.item});
  final UserMemory? item;
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final TextEditingController key, value;
  @override
  void initState() {
    super.initState();
    key = TextEditingController(text: widget.item?.key ?? '');
    value = TextEditingController(text: widget.item?.value ?? '');
  }

  @override
  void dispose() {
    key.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? '添加关于我的记忆' : '编辑关于我的记忆'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: key,
          decoration: const InputDecoration(labelText: '是什么'),
        ),
        TextField(
          controller: value,
          decoration: const InputDecoration(labelText: 'Ta 记住的内容'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (key.text.trim().isNotEmpty || value.text.trim().isNotEmpty) {
            Navigator.pop(
              context,
              _UserDraft(key.text.trim(), value.text.trim()),
            );
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    this.allowEmpty = false,
  });
  final String title, initial;
  final bool allowEmpty;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController text;
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: text, minLines: 8, maxLines: 14),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final v = text.text.trim();
          if (widget.allowEmpty || v.isNotEmpty) Navigator.pop(context, v);
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _PreviewResult {
  const _PreviewResult(this.text, this.replace);
  final String text;
  final bool replace;
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.initial, required this.hasUserEdit});
  final String initial;
  final bool hasUserEdit;
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final TextEditingController text;
  bool replace = false;
  @override
  void initState() {
    super.initState();
    text = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新的记忆汇总'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.hasUserEdit) const Text('你当前有手动编辑内容，本次 AI 总结不会覆盖它。'),
          TextField(controller: text, minLines: 8, maxLines: 14),
          if (widget.hasUserEdit)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: replace,
              onChanged: (v) => setState(() => replace = v ?? false),
              title: const Text('用本次结果替换我的编辑'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (text.text.trim().isNotEmpty) {
            Navigator.pop(context, _PreviewResult(text.text.trim(), replace));
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class _LegacySheet extends StatelessWidget {
  const _LegacySheet({required this.items, this.migratedIds = const {}});
  final Set<String> migratedIds;
  final List<dynamic> items;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: 480,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              '旧版记忆',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text('原始旧记忆只读保留，已整理的内容会标记为已迁移。'),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('没有旧版记忆'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(items[i].content.toString()),
                        subtitle: migratedIds.contains(items[i].legacySourceId)
                            ? const Text('已迁移')
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
