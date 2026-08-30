import 'package:flutter/material.dart';

import 'peilink_tokens.dart';

class PeiLinkTextField extends StatelessWidget {
  const PeiLinkTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.prefix,
    this.suffix,
    this.enabled = true,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final Widget? prefix;
  final Widget? suffix;
  final bool enabled;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    focusNode: focusNode,
    enabled: enabled,
    obscureText: obscureText,
    maxLines: obscureText ? 1 : maxLines,
    minLines: minLines,
    keyboardType: keyboardType,
    validator: validator,
    onChanged: onChanged,
    textInputAction: textInputAction,
    style: PeiLinkTypography.body,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      errorText: error,
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: enabled ? 0.78 : 0.45),
      border: _border(PeiLinkColors.divider),
      enabledBorder: _border(PeiLinkColors.border),
      focusedBorder: _border(PeiLinkColors.brand, width: 1.5),
      errorBorder: _border(PeiLinkColors.danger),
      focusedErrorBorder: _border(PeiLinkColors.danger, width: 1.5),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PeiLinkSpacing.lg,
        vertical: 14,
      ),
    ),
  );

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(PeiLinkRadius.input),
        borderSide: BorderSide(color: color, width: width),
      );
}
