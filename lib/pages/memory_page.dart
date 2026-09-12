import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/character_user_profile.dart';
import '../models/event_memory.dart';
import '../models/user_memory.dart';
import '../services/memory_center_controller.dart';
import '../services/memory_summary_generation_service.dart';
import '../theme/app_theme_background.dart';
import 'peilink/character_user_profile_page.dart';
import '../widgets/memory_source_sheet.dart';

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
          migratedLegacyIds: current.migratedLegacyIds,
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
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : snapshot == null
            ? const Center(child: Text('暂时无法读取记忆'))
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                          onSource: () => showMemorySources(
                            context,
                            controller,
                            item.sourceMessageIds,
                            legacySourceId: item.legacySourceId,
                          ),
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const Key('add-shared-experience'),
                          onPressed: addEvent,
                          icon: const Icon(Icons.add),
                          label: const Text('添加经历'),
                        ),
                      ),
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
                      onTap: () => showMemorySources(
                        context,
                        widget.controller,
                        item.sourceMessageIds,
                        legacySourceId: item.legacySourceId,
                      ),
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
    required this.onSource,
  });
  final UserMemory item;
  final VoidCallback onEdit, onPin, onDelete, onSource;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(item.isPinned ? Icons.push_pin : Icons.favorite_border),
    title: Text(item.key.isEmpty ? '记住的事' : item.key),
    subtitle: Text(
      '${item.value}${item.userConfirmed ? '\n已确认 · 自动整理不会静默改写' : ''}',
    ),
    trailing: PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'pin') onPin();
        if (v == 'delete') onDelete();
        if (v == 'source') onSource();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'source', child: Text('查看来源')),
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
    subtitle: item.isPinned
        ? const Text('不要忘记 · 已固定')
        : (hint == null ? null : Text(hint!)),
    trailing: PopupMenuButton<String>(
      onSelected: (v) async {
        if (v == 'source') {
          await showMemorySources(
            context,
            controller,
            item.sourceMessageIds,
            legacySourceId: item.legacySourceId,
          );
          return;
        }
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
        const PopupMenuItem(value: 'source', child: Text('查看来源')),
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
