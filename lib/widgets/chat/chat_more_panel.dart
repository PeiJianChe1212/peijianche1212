import 'package:flutter/material.dart';

class ChatMorePanel extends StatelessWidget {
  const ChatMorePanel({
    super.key,
    required this.onPickImage,
    required this.onUnavailable,
  });

  final VoidCallback onPickImage;
  final ValueChanged<String> onUnavailable;

  static const _items = <_MoreItem>[
    _MoreItem('相册', Icons.photo_outlined, true),
    _MoreItem('文件', Icons.insert_drive_file_outlined, false),
    _MoreItem('礼物', Icons.card_giftcard_outlined, false),
    _MoreItem('红包', Icons.redeem_outlined, false),
    _MoreItem('虚拟定位', Icons.location_on_outlined, false),
    _MoreItem('音乐', Icons.music_note_outlined, false),
    _MoreItem('语音通话', Icons.call_outlined, false),
    _MoreItem('视频通话', Icons.videocam_outlined, false),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFFF5F5F5),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent: 92,
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final item = _items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(context);
                if (item.available) {
                  onPickImage();
                } else {
                  onUnavailable(item.label);
                }
              },
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(item.icon, size: 27, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.label, this.icon, this.available);

  final String label;
  final IconData icon;
  final bool available;
}
