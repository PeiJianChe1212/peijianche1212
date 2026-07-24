import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/memory_item.dart';
import '../services/chat_storage_service.dart';
import '../services/deepseek_service.dart';
import '../services/memory_review_service.dart';
import '../services/memory_storage_service.dart';
import 'memory_review_page.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

enum _MemorySort { newest, oldest, alphabetical }

class _MemoryPageState extends State<MemoryPage> {
  static const _categories = [
    '关于我',
    '兴趣偏好',
    '生活习惯',
    '害怕与禁忌',
    '重要关系',
    '经历过的事',
    '我们的约定',
    '共同纪念',
    '收藏回复',
  ];

  final MemoryStorageService _storage = MemoryStorageService();
  final MemoryReviewService _reviewStorage = MemoryReviewService();
  final TextEditingController _searchController = TextEditingController();
  final ChatStorageService _chatStorage = ChatStorageService();
  final DeepSeekService _deepSeekService = DeepSeekService();

  List<MemoryItem> _items = [];
  bool _loading = true;
  bool _showArchived = false;
  bool _isAnalyzing = false;
  int _pendingCount = 0;
  String _query = '';
  String? _selectedCategory;
  _MemorySort _sort = _MemorySort.newest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _deepSeekService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _storage.loadItems(),
      _reviewStorage.loadItems(),
    ]);
    if (!mounted) return;

    final loadedItems = results[0] as List<MemoryItem>;
    var needsMigration = false;
    final migratedItems = loadedItems.map((item) {
      if (item.category != '关于念念') return item;
      needsMigration = true;
      return item.copyWith(category: '关于我');
    }).toList();

    if (needsMigration) {
      await _storage.saveItems(migratedItems);
    }
    if (!mounted) return;
    setState(() {
      _items = migratedItems;
      _pendingCount = (results[1] as List).length;
      _loading = false;
    });
  }

  Future<void> _save() => _storage.saveItems(_items);

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _analyzeMemory() async {
    if (_isAnalyzing) return;
    if (!await _deepSeekService.hasApiKey) {
      _showSnack('请先配置模型与 API');
      return;
    }
    final messages = await _chatStorage.loadMessages();
    if (!messages.any((message) => message.role == 'user')) {
      _showSnack('还没有足够的聊天内容');
      return;
    }
    setState(() => _isAnalyzing = true);
    try {
      final candidates = await _deepSeekService.extractMemories(
        messages: List<ChatMessage>.from(messages),
      );
      final added = await _reviewStorage.addCandidates(candidates);
      await _load();
      if (candidates.isEmpty) {
        _showSnack('这段聊天里没有适合长期保存的内容');
      } else if (added == 0) {
        _showSnack('候选记忆已经存在，没有重复添加');
      } else {
        _showSnack('发现 $added 条候选记忆，已送去审核');
      }
    } on TimeoutException {
      _showSnack('记忆分析超时了，稍后再试');
    } on SocketException {
      _showSnack('当前无法连接网络');
    } catch (error) {
      _showSnack('记忆分析失败：$error');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _openEditor({MemoryItem? item, String? initialCategory}) async {
    final result = await showDialog<_MemoryDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MemoryEditorDialog(
        item: item,
        categories: _categories,
        initialCategory: initialCategory,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      if (item == null) {
        _items.add(
          MemoryItem(content: result.content, category: result.category),
        );
      } else {
        final index = _items.indexWhere((candidate) => candidate.id == item.id);
        if (index >= 0) {
          _items[index] = item.copyWith(
            content: result.content,
            category: result.category,
          );
        }
      }
    });
    await _save();
  }

  Future<void> _togglePinned(MemoryItem item) async {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    setState(() => _items[index] = item.copyWith(isPinned: !item.isPinned));
    await _save();
  }

  Future<void> _toggleArchived(MemoryItem item) async {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    setState(() => _items[index] = item.copyWith(isArchived: !item.isArchived));
    await _save();
  }

  Future<void> _delete(MemoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _items.removeWhere((candidate) => candidate.id == item.id));
    await _save();
  }

  List<MemoryItem> _visibleItemsFor(String category) {
    final normalizedQuery = _query.trim().toLowerCase();
    final result = _items.where((item) {
      if (item.category != category) return false;
      if (_showArchived != item.isArchived) return false;
      if (normalizedQuery.isEmpty) return true;
      return item.content.toLowerCase().contains(normalizedQuery);
    }).toList();

    result.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return switch (_sort) {
        _MemorySort.newest => b.createdAt.compareTo(a.createdAt),
        _MemorySort.oldest => a.createdAt.compareTo(b.createdAt),
        _MemorySort.alphabetical => a.content.compareTo(b.content),
      };
    });
    return result;
  }

  List<String> get _visibleCategories {
    if (_selectedCategory != null) return [_selectedCategory!];
    return _categories;
  }

  int get _currentMemoryCount =>
      _items.where((item) => item.isArchived == _showArchived).length;

  Future<void> _openReview() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MemoryReviewPage()));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF10151D),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('裴简澈的记忆'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: '待审核记忆',
                    onPressed: _openReview,
                    icon: const Icon(Icons.inbox_outlined),
                  ),
                  if (_pendingCount > 0)
                    Positioned(
                      right: 3,
                      top: 3,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD86B7E),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF10151D),
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _pendingCount > 99 ? '99+' : '$_pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<_MemorySort>(
              tooltip: '排序',
              initialValue: _sort,
              onSelected: (value) => setState(() => _sort = value),
              icon: const Icon(Icons.sort_rounded),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _MemorySort.newest, child: Text('最新优先')),
                PopupMenuItem(value: _MemorySort.oldest, child: Text('最早优先')),
                PopupMenuItem(
                  value: _MemorySort.alphabetical,
                  child: Text('按文字排序'),
                ),
              ],
            ),
            IconButton(
              tooltip: _showArchived ? '查看当前记忆' : '查看归档',
              onPressed: () => setState(() => _showArchived = !_showArchived),
              icon: Icon(
                _showArchived
                    ? Icons.inventory_2_rounded
                    : Icons.inventory_2_outlined,
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openEditor(initialCategory: _selectedCategory),
          icon: const Icon(Icons.add_rounded),
          label: const Text('新增记忆'),
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF273748), Color(0xFF151D27), Color(0xFF090D13)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      _MemoryIntro(
                        showArchived: _showArchived,
                        count: _currentMemoryCount,
                        pendingCount: _pendingCount,
                      ),
                      const SizedBox(height: 14),

                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.psychology_alt_outlined),
                          title: Text(_isAnalyzing ? '正在分析记忆…' : '分析当前聊天'),
                          subtitle: const Text('提取候选记忆，送入待审核列表'),
                          onTap: _isAnalyzing ? null : _analyzeMemory,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '搜索记忆，例如：历史、旅行、害怕……',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.42),
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white60,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white60,
                                  ),
                                ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _CategoryChip(
                              label: '全部',
                              selected: _selectedCategory == null,
                              onTap: () =>
                                  setState(() => _selectedCategory = null),
                            ),
                            for (final category in _categories)
                              _CategoryChip(
                                label: category,
                                selected: _selectedCategory == category,
                                onTap: () => setState(
                                  () => _selectedCategory = category,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final category in _visibleCategories) ...[
                        _MemorySection(
                          title: category,
                          items: _visibleItemsFor(category),
                          onAdd: () => _openEditor(initialCategory: category),
                          onEdit: (item) => _openEditor(item: item),
                          onPin: _togglePinned,
                          onArchive: _toggleArchived,
                          onDelete: _delete,
                          showArchived: _showArchived,
                          isSearching: _query.trim().isNotEmpty,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _MemoryIntro extends StatelessWidget {
  const _MemoryIntro({
    required this.showArchived,
    required this.count,
    required this.pendingCount,
  });

  final bool showArchived;
  final int count;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CountPill(label: showArchived ? '已归档' : '长期记忆', count: count),
              const SizedBox(width: 8),
              _CountPill(label: '待审核', count: pendingCount),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            showArchived
                ? '这里放暂时不参与聊天的旧记忆。需要时可以随时恢复。'
                : 'AI 只会读取未归档的记忆。你可以搜索、筛选、编辑和归档，记忆不会偷偷越长越胖。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF17202B) : Colors.white70,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        selectedColor: const Color(0xFFE7D7DE),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }
}

class _MemorySection extends StatelessWidget {
  const _MemorySection({
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
    required this.showArchived,
    required this.isSearching,
  });

  final String title;
  final List<MemoryItem> items;
  final VoidCallback onAdd;
  final ValueChanged<MemoryItem> onEdit;
  final ValueChanged<MemoryItem> onPin;
  final ValueChanged<MemoryItem> onArchive;
  final ValueChanged<MemoryItem> onDelete;
  final bool showArchived;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 13, 8, 9),
            child: Row(
              children: [
                Text(
                  '$title  ${items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '添加到$title',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 0, 17, 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isSearching
                      ? '没有找到匹配的记忆。'
                      : showArchived
                      ? '这里还没有归档内容。'
                      : '还没有内容，点右上角的＋添加。',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ...items.map(
              (item) => _MemoryTile(
                item: item,
                onEdit: () => onEdit(item),
                onPin: () => onPin(item),
                onArchive: () => onArchive(item),
                onDelete: () => onDelete(item),
                showArchived: showArchived,
              ),
            ),
          const SizedBox(height: 7),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.item,
    required this.onEdit,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
    required this.showArchived,
  });

  final MemoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final bool showArchived;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.isPinned)
            const Padding(
              padding: EdgeInsets.only(top: 2, right: 8),
              child: Icon(
                Icons.push_pin_rounded,
                size: 16,
                color: Color(0xFFD9B7C6),
              ),
            ),
          Expanded(
            child: Text(
              item.content,
              style: const TextStyle(
                color: Colors.white,
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white60,
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                  break;
                case 'pin':
                  onPin();
                  break;
                case 'archive':
                  onArchive();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(
                value: 'pin',
                child: Text(item.isPinned ? '取消固定' : '固定在前面'),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(showArchived ? '恢复记忆' : '归档'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({
    required this.item,
    required this.categories,
    this.initialCategory,
  });

  final MemoryItem? item;
  final List<String> categories;
  final String? initialCategory;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  late final TextEditingController _controller;
  late String _category;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item?.content ?? '');
    final preferred = widget.item?.category ?? widget.initialCategory;
    _category = widget.categories.contains(preferred)
        ? preferred!
        : widget.categories.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_MemoryDraft(content: content, category: _category));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? '新增记忆' : '编辑记忆'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: '分类',
                  border: OutlineInputBorder(),
                ),
                items: widget.categories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: '记住什么',
                  hintText: '尽量写成简短、长期有效的一句话。',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

class _MemoryDraft {
  const _MemoryDraft({required this.content, required this.category});

  final String content;
  final String category;
}
