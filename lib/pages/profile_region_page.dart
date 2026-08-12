import 'package:flutter/material.dart';

class ProfileRegionPage extends StatelessWidget {
  const ProfileRegionPage({super.key, required this.initialValue});

  final String initialValue;

  static const Map<String, List<String>> _mainland = {
    '浙江': ['杭州', '宁波', '温州', '嘉兴', '湖州', '绍兴', '金华', '衢州', '舟山', '台州', '丽水'],
    '北京': ['北京'],
    '上海': ['上海'],
    '江苏': ['南京', '苏州', '无锡', '常州', '南通', '扬州', '徐州'],
    '广东': ['广州', '深圳', '珠海', '佛山', '东莞', '中山'],
    '四川': ['成都', '绵阳', '乐山', '宜宾'],
    '湖北': ['武汉', '宜昌', '襄阳'],
    '河南': ['郑州', '洛阳', '开封'],
  };

  static const Map<String, List<String>> _overseas = {
    '俄罗斯': ['莫斯科', '圣彼得堡', '海参崴'],
    '法国': ['巴黎', '里昂', '马赛'],
    '美国': ['纽约', '洛杉矶', '旧金山'],
    '日本': ['东京', '大阪', '京都'],
    '韩国': ['首尔', '釜山'],
    '新加坡': ['新加坡'],
    '西班牙': ['马德里', '巴塞罗那'],
  };

  Future<void> _custom(BuildContext context) async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _CustomRegionEditPage(initialValue: initialValue),
      ),
    );
    if (!context.mounted || value == null || value.trim().isEmpty) return;
    Navigator.pop(context, value.trim());
  }

  Future<void> _chooseGroup(
    BuildContext context,
    String title,
    Map<String, List<String>> data,
  ) async {
    final first = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _SimpleChoicePage(title: title, values: data.keys.toList()),
      ),
    );
    if (!context.mounted || first == null) return;
    final second = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _SimpleChoicePage(title: first, values: data[first]!),
      ),
    );
    if (!context.mounted || second == null) return;
    Navigator.pop(context, '$first $second');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(title: const Text('选择地区'), centerTitle: true),
      body: ListView(
        children: [
          const _SectionLabel('自定义'),
          _RegionTile(
            title: '自定义地区',
            subtitle: '青丘、月球或任何你想写的地方',
            onTap: () => _custom(context),
          ),
          const _SectionLabel('常规地区'),
          _RegionTile(
            title: '中国大陆',
            subtitle: '最终显示为“省 市”',
            onTap: () => _chooseGroup(context, '选择省份', _mainland),
          ),
          _RegionTile(
            title: '中国香港',
            onTap: () => Navigator.pop(context, '中国香港'),
          ),
          _RegionTile(
            title: '中国澳门',
            onTap: () => Navigator.pop(context, '中国澳门'),
          ),
          _RegionTile(
            title: '中国台湾',
            onTap: () => Navigator.pop(context, '中国台湾'),
          ),
          _RegionTile(
            title: '其他国家和地区',
            subtitle: '最终显示为“国家 城市”',
            onTap: () => _chooseGroup(context, '选择国家', _overseas),
          ),
        ],
      ),
    );
  }
}

class _CustomRegionEditPage extends StatefulWidget {
  const _CustomRegionEditPage({required this.initialValue});
  final String initialValue;

  @override
  State<_CustomRegionEditPage> createState() => _CustomRegionEditPageState();
}

class _CustomRegionEditPageState extends State<_CustomRegionEditPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text('设置地区'),
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        leadingWidth: 72,
        actions: [
          TextButton(
            onPressed: canSave
                ? () => Navigator.pop(context, _controller.text.trim())
                : null,
            child: const Text('完成'),
          ),
        ],
      ),
      body: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: '例如：青丘、月球、天空城',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }
}

class _SimpleChoicePage extends StatelessWidget {
  const _SimpleChoicePage({required this.title, required this.values});
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2F2F2),
    appBar: AppBar(title: Text(title), centerTitle: true),
    body: ListView.separated(
      itemCount: values.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
      itemBuilder: (_, index) => ListTile(
        tileColor: Colors.white,
        title: Text(values[index]),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.pop(context, values[index]),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
    ),
  );
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({required this.title, required this.onTap, this.subtitle});
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    tileColor: Colors.white,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
