import 'package:flutter/material.dart';

class ChatMorePanel extends StatefulWidget {
  const ChatMorePanel({
    super.key,
    required this.onUserPersona,
    required this.onPickImage,
    required this.onRedPacket,
    required this.onChangeAvatar,
    required this.onUnavailable,
    this.closeOnSelection = true,
    this.personaLabel = '我的个人设定',
    this.disabledLabels = const [],
    this.highlightPersona = false,
  });

  final VoidCallback onUserPersona;
  final VoidCallback onPickImage;
  final VoidCallback onRedPacket;
  final VoidCallback onChangeAvatar;
  final ValueChanged<String> onUnavailable;
  final bool closeOnSelection;
  final bool highlightPersona;

  /// 首项文案：单聊为「我的个人设定」，群聊替换为「我的群聊身份」。
  final String personaLabel;

  /// 当前场景没有真实链路的入口，按不可用样式展示（不弹假入口）。
  final List<String> disabledLabels;

  @override
  State<ChatMorePanel> createState() => _ChatMorePanelState();
}

class _ChatMorePanelState extends State<ChatMorePanel> {
  static const _pageSize = 8;
  int _page = 0;

  static const _items = <_MoreItem>[
    _MoreItem('我的个人设定', Icons.badge_outlined, _MoreAction.userPersona),
    _MoreItem('相册', Icons.photo_outlined, _MoreAction.photo),
    _MoreItem(
      '红包',
      Icons.account_balance_wallet_outlined,
      _MoreAction.redPacket,
    ),
    _MoreItem(
      '让 Ta 换头像',
      Icons.switch_account_outlined,
      _MoreAction.changeAvatar,
    ),
    _MoreItem('礼物', Icons.card_giftcard_outlined),
    _MoreItem('文件', Icons.insert_drive_file_outlined),
    _MoreItem('虚拟定位', Icons.location_on_outlined),
    _MoreItem('音乐', Icons.music_note_outlined),
    _MoreItem('语音通话', Icons.call_outlined),
    _MoreItem('视频通话', Icons.videocam_outlined),
  ];

  int get _pageCount => (_items.length / _pageSize).ceil();

  String _labelFor(_MoreItem item) =>
      item.action == _MoreAction.userPersona ? widget.personaLabel : item.label;

  bool _isAvailable(_MoreItem item) {
    if (item.action == _MoreAction.unavailable) return false;
    return !widget.disabledLabels.contains(_labelFor(item));
  }

  void _select(_MoreItem item) {
    if (widget.closeOnSelection) Navigator.maybePop(context);
    switch (item.action) {
      case _MoreAction.userPersona:
        widget.onUserPersona();
      case _MoreAction.photo:
        widget.onPickImage();
      case _MoreAction.redPacket:
        widget.onRedPacket();
      case _MoreAction.changeAvatar:
        widget.onChangeAvatar();
      case _MoreAction.unavailable:
        widget.onUnavailable(item.label);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: widget.highlightPersona
            ? const Color(0xFFF7F5FB)
            : const Color(0xFFF5F5F5),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 190,
              child: PageView.builder(
                itemCount: _pageCount,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, pageIndex) {
                  final start = pageIndex * _pageSize;
                  final pageItems = _items.skip(start).take(_pageSize).toList();
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pageItems.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisExtent: 92,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 4,
                        ),
                    itemBuilder: (context, index) {
                      final item = pageItems[index];
                      return _MoreButton(
                        item: item,
                        label: _labelFor(item),
                        isAvailable: _isAvailable(item),
                        highlighted:
                            widget.highlightPersona &&
                            item.action == _MoreAction.userPersona,
                        onTap: _select,
                      );
                    },
                  );
                },
              ),
            ),
            if (_pageCount > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pageCount,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: index == _page ? 14 : 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index == _page
                          ? const Color(0xFF777777)
                          : const Color(0xFFC8C8C8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.item,
    required this.label,
    required this.isAvailable,
    this.highlighted = false,
    required this.onTap,
  });

  final _MoreItem item;
  final String label;
  final bool isAvailable;
  final bool highlighted;
  final ValueChanged<_MoreItem> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: isAvailable ? () => onTap(item) : null,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isAvailable
                  ? (highlighted ? const Color(0xFFE9E3F5) : Colors.white)
                  : Colors.white.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              item.icon,
              size: 26,
              color: isAvailable
                  ? (highlighted ? const Color(0xFF7668A6) : Colors.black87)
                  : const Color(0xFFB8B8B8),
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: item.action == _MoreAction.userPersona ? 11 : 12,
                color: isAvailable
                    ? (highlighted ? const Color(0xFF7668A6) : Colors.black87)
                    : const Color(0xFFAAAAAA),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(
    this.label,
    this.icon, [
    this.action = _MoreAction.unavailable,
  ]);

  final String label;
  final IconData icon;
  final _MoreAction action;
  bool get isAvailable => action != _MoreAction.unavailable;
}

enum _MoreAction { userPersona, photo, redPacket, changeAvatar, unavailable }
