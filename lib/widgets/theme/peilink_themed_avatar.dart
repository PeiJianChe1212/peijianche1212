import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/peilink_theme_config.dart';

enum PeiLinkAvatarRole { user, character, group, privateEcho }

class PeiLinkThemedAvatar extends StatelessWidget {
  const PeiLinkThemedAvatar({
    super.key,
    required this.size,
    required this.role,
    this.imagePath = '',
    this.image,
    this.fallback,
    this.frame,
    this.shape = BoxShape.rectangle,
    this.onTap,
    this.borderRadius,
  });
  final double size;
  final PeiLinkAvatarRole role;
  final String imagePath;
  final Widget? image;
  final Widget? fallback;
  final AvatarFrameSpec? frame;
  final BoxShape shape;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath.trim());
    final content =
        image ??
        (imagePath.trim().isNotEmpty && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : fallback ??
                  Icon(
                    role == PeiLinkAvatarRole.user
                        ? Icons.person_rounded
                        : Icons.auto_awesome_rounded,
                    color: const Color(0xFF647C8B),
                    size: size * .48,
                  ));
    final radius =
        borderRadius ??
        BorderRadius.circular(size * (frame?.borderRadiusRatio ?? .18));
    final avatar = ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: const Color(0xFFE5EBEE),
        child: SizedBox(width: size, height: size, child: content),
      ),
    );
    final spec = frame;
    final result = SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(size * (spec?.paddingRatio ?? 0)),
            child: avatar,
          ),
          if (spec != null)
            IgnorePointer(
              key: const ValueKey('peilink-avatar-frame-overlay'),
              child: spec.assetPath?.isNotEmpty == true
                  ? Image.asset(
                      spec.assetPath!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: spec.border,
                      ),
                    ),
            ),
        ],
      ),
    );
    return onTap == null
        ? result
        : GestureDetector(onTap: onTap, child: result);
  }
}
