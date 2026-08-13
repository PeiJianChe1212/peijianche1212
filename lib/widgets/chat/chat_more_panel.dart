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
  });

  final VoidCallback onUserPersona;
  final VoidCallback onPickImage;
  final VoidCallback onRedPacket;
  final VoidCallback onChangeAvatar;
  final ValueChanged<String> onUnavailable;
  final bool closeOnSelection;

  @override
  State<ChatMorePanel> createState() => _ChatMorePanelState();
}

class _ChatMorePanelState extends State<ChatMorePanel> {
  static const _pageSize = 8;
  int _page = 0;

  static const _items = <_MoreItem>[
    _MoreItem('我的个人设定', Icons.badge_outlined, _MoreAction.userPersona),
    _MoreItem('相册', Icons.photo_outlined, _MoreAction.photo),
    _MoreItem('红包', Icons.redeem_outlined, _MoreAction.redPacket),
    _MoreItem('文件', Icons.insert_drive_file_outlined),
    _MoreItem('礼物', Icons.card_giftcard_outlined),
    _MoreItem(
      '让 Ta 换头像',
      Icons.switch_account_outlined,
      _MoreAction.changeAvatar,
    ),
    _MoreItem('虚拟定位', Icons.location_on_outlined),
    _MoreItem('音乐', Icons.music_note_outlined),
    _MoreItem('语音通话', Icons.call_outlined),
    _MoreItem('视频通话', Icons.videocam_outlined),
  ];

  int get _pageCount => (_items.length / _pageSize).ceil();

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
        color: const Color(0xFFF5F5F5),
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
                    itemBuilder: (context, index) =>
                        _MoreButton(item: pageItems[index], onTap: _select),
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
  const _MoreButton({required this.item, required this.onTap});

  final _MoreItem item;
  final ValueChanged<_MoreItem> onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(item),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: item.isAvailable
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              item.icon,
              size: 26,
              color: item.isAvailable
                  ? Colors.black87
                  : const Color(0xFFB8B8B8),
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: item.action == _MoreAction.userPersona ? 11 : 12,
                color: item.isAvailable
                    ? Colors.black87
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
