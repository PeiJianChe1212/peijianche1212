import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme_background.dart';
import 'peilink_app_bar.dart';
import 'peilink_tokens.dart';

class PeiLinkPageScaffold extends StatelessWidget {
  const PeiLinkPageScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset = true,
    this.safeBottom = true,
  });

  final Widget body;
  final PeiLinkAppBar? appBar;
  final Widget? floatingActionButton;
  final bool resizeToAvoidBottomInset;
  final bool safeBottom;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: ThemeBackgroundContainer(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: SafeArea(top: false, bottom: safeBottom, child: body),
      ),
    ),
  );
}

class PeiLinkPageList extends StatelessWidget {
  const PeiLinkPageList({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: padding ?? PeiLinkSpacing.page, children: children);
}
