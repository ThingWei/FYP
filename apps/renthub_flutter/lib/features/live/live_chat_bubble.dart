import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ChatBubbleFrame extends StatelessWidget {
  const ChatBubbleFrame(
      {super.key, required this.own, required this.child, this.system = false});
  final bool own, system;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: system
              ? AppColors.surface
              : own
                  ? AppColors.primaryLight
                  : AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14)),
      child: child);
}
