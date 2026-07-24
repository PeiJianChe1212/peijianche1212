import 'package:flutter/material.dart';

class ProfileTextEditPage extends StatefulWidget {
  const ProfileTextEditPage({
    super.key,
    required this.title,
    required this.initialValue,
    this.hintText = '',
    this.maxLength = 40,
    this.maxLines = 1,
    this.allowEmpty = true,
  });

  final String title;
  final String initialValue;
  final String hintText;
  final int maxLength;
  final int maxLines;
  final bool allowEmpty;

  @override
  State<ProfileTextEditPage> createState() => _ProfileTextEditPageState();
}

class _ProfileTextEditPageState extends State<ProfileTextEditPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave {
    final value = _controller.text.trim();
    if (!widget.allowEmpty && value.isEmpty) return false;
    return value != widget.initialValue.trim();
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F2),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 76,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Color(0xFF222222))),
        ),
        centerTitle: true,
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                disabledBackgroundColor: const Color(0xFFE2E2E2),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 40),
              ),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: widget.maxLines,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          decoration: InputDecoration(
            hintText: widget.hintText,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            border: InputBorder.none,
            suffixIcon: widget.maxLines == 1 && _controller.text.isNotEmpty
                ? IconButton(
                    onPressed: _controller.clear,
                    icon: const Icon(Icons.cancel, color: Color(0xFFBDBDBD)),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class ProfileGenderEditPage extends StatefulWidget {
  const ProfileGenderEditPage({super.key, required this.initialValue});

  final String initialValue;

  @override
  State<ProfileGenderEditPage> createState() => _ProfileGenderEditPageState();
}

class _ProfileGenderEditPageState extends State<ProfileGenderEditPage> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F2),
        surfaceTintColor: Colors.transparent,
        leadingWidth: 76,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Color(0xFF222222))),
        ),
        centerTitle: true,
        title: const Text('设置性别'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _value == widget.initialValue
                  ? null
                  : () => Navigator.pop(context, _value),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                disabledBackgroundColor: const Color(0xFFE2E2E2),
                minimumSize: const Size(0, 40),
              ),
              child: const Text('完成'),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GenderTile(
              title: '男',
              selected: _value == '男',
              onTap: () => setState(() => _value = '男'),
            ),
            const Divider(height: 1, indent: 20),
            _GenderTile(
              title: '女',
              selected: _value == '女',
              onTap: () => setState(() => _value = '女'),
            ),
            const Divider(height: 1, indent: 20),
            _GenderTile(
              title: '不展示',
              selected: _value.isEmpty,
              onTap: () => setState(() => _value = ''),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderTile extends StatelessWidget {
  const _GenderTile({required this.title, required this.selected, required this.onTap});
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 18)),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xFF07C160))
          : null,
      onTap: onTap,
    );
  }
}
