import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/ai_character.dart';
import '../../models/anniversary_item.dart';
import '../../services/anniversary_storage_service.dart';
import '../../services/character_registry_service.dart';
import '../../theme/app_theme_background.dart';

class AnniversaryPage extends StatefulWidget {
  const AnniversaryPage({super.key});

  @override
  State<AnniversaryPage> createState() => _AnniversaryPageState();
}

class _AnniversaryPageState extends State<AnniversaryPage> {
  final _storage = AnniversaryStorageService();
  List<AnniversaryItem> _items = const [];
  Map<String, AiCharacter> _characters = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _storage.loadAll(),
      CharacterRegistryService().loadCharacters(),
    ]);
    if (!mounted) return;
    final characters = results[1] as List<AiCharacter>;
    setState(() {
      _items = results[0] as List<AnniversaryItem>;
      _characters = {for (final item in characters) item.id: item};
      _loading = false;
    });
  }

  Future<void> _edit([AnniversaryItem? item]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AnniversaryEditPage(item: item)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _items.where((item) => item.isPinned).firstOrNull;
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('纪念日'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: '新增纪念日',
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  const _SectionTitle('置顶纪念日'),
                  if (pinned == null)
                    const _EmptyCard(text: '还没有置顶纪念日')
                  else
                    _AnniversaryCard(
                      item: pinned,
                      character: _characters[pinned.relatedCharacterId],
                      onTap: () => _edit(pinned),
                    ),
                  const SizedBox(height: 20),
                  const _SectionTitle('全部纪念日'),
                  if (_items.isEmpty)
                    const _EmptyCard(text: '记录一个值得记住的日子')
                  else
                    ..._items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AnniversaryCard(
                          item: item,
                          character: _characters[item.relatedCharacterId],
                          onTap: () => _edit(item),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class AnniversaryEditPage extends StatefulWidget {
  const AnniversaryEditPage({super.key, this.item});
  final AnniversaryItem? item;

  @override
  State<AnniversaryEditPage> createState() => _AnniversaryEditPageState();
}

class _AnniversaryEditPageState extends State<AnniversaryEditPage> {
  final _storage = AnniversaryStorageService();
  late final TextEditingController _title;
  late DateTime _date;
  late AnniversaryRepeatType _repeatType;
  late String? _relatedCharacterId;
  late bool _isPinned;
  List<AiCharacter> _characters = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _title = TextEditingController(text: item?.title ?? '');
    _date = item?.date ?? DateTime.now();
    _repeatType = item?.repeatType ?? AnniversaryRepeatType.none;
    _relatedCharacterId = item?.relatedCharacterId;
    _isPinned = item?.isPinned ?? false;
    _loadCharacters();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _loadCharacters() async {
    final characters = await CharacterRegistryService().loadCharacters();
    if (!mounted) return;
    setState(() {
      _characters = characters;
      if (!_characters.any((item) => item.id == _relatedCharacterId)) {
        _relatedCharacterId = null;
      }
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final existing = widget.item;
    await _storage.upsert(
      AnniversaryItem(
        id:
            existing?.id ??
            'anniversary_${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        date: DateTime(_date.year, _date.month, _date.day),
        repeatType: _repeatType,
        relatedCharacterId: _relatedCharacterId,
        isPinned: _isPinned,
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除纪念日？'),
        content: Text('“${item.title}”删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.delete(item.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.item == null ? '新增纪念日' : '编辑纪念日'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _SectionTitle('基本信息'),
            _FormCard(
              children: [
                TextField(
                  controller: _title,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: '纪念日名称',
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FormCard(
              children: [
                _LightFormRow(
                  icon: Icons.calendar_today_rounded,
                  title: '日期',
                  value: _dateLabel(_date),
                  onTap: _pickDate,
                ),
                const Divider(height: 1),
                DropdownButtonFormField<AnniversaryRepeatType>(
                  initialValue: _repeatType,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.repeat_rounded, size: 20),
                    labelText: '重复方式',
                    border: InputBorder.none,
                  ),
                  items: AnniversaryRepeatType.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _repeatType = value);
                  },
                ),
                const Divider(height: 1),
                DropdownButtonFormField<String?>(
                  initialValue: _relatedCharacterId,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    labelText: '关联角色',
                    helperText: '可选，只用于分类与显示',
                    border: InputBorder.none,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('不关联角色'),
                    ),
                    ..._characters.map(
                      (character) => DropdownMenuItem<String?>(
                        value: character.id,
                        child: Row(
                          children: [
                            _CharacterAvatar(character: character, size: 28),
                            const SizedBox(width: 9),
                            Flexible(child: Text(character.displayName)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _relatedCharacterId = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FormCard(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.push_pin_outlined, size: 20),
                  title: const Text('置顶到 Life 首页'),
                  subtitle: const Text('首页只会展示一个置顶纪念日'),
                  value: _isPinned,
                  onChanged: (value) => setState(() => _isPinned = value),
                ),
              ],
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: const Color(0xFF6964A8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(_saving ? '正在保存…' : '保存纪念日'),
            ),
            if (widget.item != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('删除纪念日'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnniversaryCard extends StatelessWidget {
  const _AnniversaryCard({
    required this.item,
    required this.character,
    required this.onTap,
  });
  final AnniversaryItem item;
  final AiCharacter? character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = AnniversaryDayStatus.calculate(item);
    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_dateLabel(item.date)}${character == null ? '' : '  ·  ${character!.displayName}'}',
        ),
        trailing: Text(
          status.displayText,
          style: const TextStyle(
            color: Color(0xFF756A91),
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 9),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF827A91),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF9993A1))),
  );
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(children: children),
  );
}

class _LightFormRow extends StatelessWidget {
  const _LightFormRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20),
    title: Text(title),
    subtitle: Text(value, style: const TextStyle(color: Color(0xFF8E879A))),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: onTap,
  );
}

class _CharacterAvatar extends StatelessWidget {
  const _CharacterAvatar({required this.character, required this.size});

  final AiCharacter character;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = character.avatarPath.trim();
    final exists = path.isNotEmpty && File(path).existsSync();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFEAEFF3),
      backgroundImage: exists ? FileImage(File(path)) : null,
      child: exists
          ? null
          : Icon(
              Icons.auto_awesome_rounded,
              size: size * 0.48,
              color: const Color(0xFF6D8797),
            ),
    );
  }
}

String _dateLabel(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
