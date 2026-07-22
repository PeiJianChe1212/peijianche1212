import 'package:flutter/material.dart';

import '../models/pending_memory.dart';
import '../services/memory_review_service.dart';

class MemoryReviewPage extends StatefulWidget {
  const MemoryReviewPage({super.key});

  @override
  State<MemoryReviewPage> createState() => _MemoryReviewPageState();
}

class _MemoryReviewPageState extends State<MemoryReviewPage> {
  static const _categories = [
    '关于念念',
    '兴趣偏好',
    '生活习惯',
    '害怕与禁忌',
    '重要关系',
    '经历过的事',
    '我们的约定',
  ];
  final MemoryReviewService _service = MemoryReviewService();
  List<PendingMemory> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _service.loadItems();
    if (!mounted) return;
    setState(() {
      _items = items..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loading = false;
    });
  }

  Future<void> _approve(PendingMemory item) async {
    await _service.approve(item);
    if (!mounted) return;
    setState(() => _items.removeWhere((candidate) => candidate.id == item.id));
    _showSnack('已写入长期记忆');
  }

  Future<void> _reject(PendingMemory item) async {
    await _service.reject(item.id);
    if (!mounted) return;
    setState(() => _items.removeWhere((candidate) => candidate.id == item.id));
    _showSnack('已忽略这条候选');
  }

  Future<void> _edit(PendingMemory item) async {
    final result = await showDialog<PendingMemory>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _EditPendingMemoryDialog(item: item, categories: _categories),
    );

    if (result == null || !mounted) return;
    await _service.update(result);
    if (!mounted) return;

    final index = _items.indexWhere((candidate) => candidate.id == result.id);
    if (index >= 0) {
      setState(() => _items[index] = result);
      _showSnack('候选记忆已修改');
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EC),
      appBar: AppBar(
        title: const Text('待审核记忆'),
        backgroundColor: const Color(0xFFF4F1EC),
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const _EmptyReview()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 13),
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFFE9E1D8)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE9F0F6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                item.category,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '编辑',
                              onPressed: () => _edit(item),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.content,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F1ED),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.lightbulb_outline_rounded,
                                size: 17,
                                color: Color(0xFF8C6F5A),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '为什么值得记住：${item.reason}',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _reject(item),
                                child: const Text('忽略'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _approve(item),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('确认记住'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 54, color: Colors.black26),
            SizedBox(height: 14),
            Text(
              '没有待审核记忆',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              '在聊天菜单里点“分析记忆”，候选内容会先来这里，不会偷偷写入。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditPendingMemoryDialog extends StatefulWidget {
  const _EditPendingMemoryDialog({
    required this.item,
    required this.categories,
  });

  final PendingMemory item;
  final List<String> categories;

  @override
  State<_EditPendingMemoryDialog> createState() =>
      _EditPendingMemoryDialogState();
}

class _EditPendingMemoryDialogState extends State<_EditPendingMemoryDialog> {
  late final TextEditingController _controller;
  late String _category;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.content);
    _category = widget.categories.contains(widget.item.category)
        ? widget.item.category
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
    ).pop(widget.item.copyWith(content: content, category: _category));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认前再看一眼'),
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
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 7,
                maxLength: 240,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: '记忆内容',
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
        FilledButton(onPressed: _save, child: const Text('保存修改')),
      ],
    );
  }
}
