import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/feedback_submission_service.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const _categories = ['Bug反馈', '功能建议', '体验问题', '其他'];
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contactController = TextEditingController();
  final _picker = ImagePicker();
  final _submission = FeedbackSubmissionService();
  String _category = _categories.first;
  XFile? _screenshot;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final selected = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (selected != null && mounted) setState(() => _screenshot = selected);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写标题和内容。')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final report = _submission.buildReport(
        category: _category,
        title: title,
        content: content,
        contact: _contactController.text,
        hasScreenshot: _screenshot != null,
      );
      await _submission.copyAndOpen(report: report);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _screenshot == null
                ? '反馈内容已复制，请在问卷中粘贴提交。'
                : '反馈内容已复制；请在问卷上传项中选择刚才的截图。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('暂时无法打开反馈问卷：$error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(title: const Text('帮助与反馈'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: '反馈类型'),
                    items: _categories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? _category),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _titleController,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      hintText: '请简要描述问题或建议',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contentController,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 1200,
                    decoration: const InputDecoration(
                      labelText: '内容',
                      hintText: '请描述发生过程、期望结果或具体建议',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contactController,
                    decoration: const InputDecoration(
                      labelText: '联系方式（可选）',
                      hintText: '邮箱、微信或其他联系方式',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('添加截图'),
              subtitle: Text(
                _screenshot == null ? '可选，仅在你主动选择后使用' : _screenshot!.name,
              ),
              trailing: _screenshot == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : IconButton(
                      onPressed: () => setState(() => _screenshot = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
              onTap: _pickScreenshot,
            ),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '提交时仅附加 PeiLink 版本、系统版本、基础设备信息和时间。不会读取聊天记录、角色资料或其他私人数据。',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new_rounded),
            label: const Text('前往问卷提交'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
