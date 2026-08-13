import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(8), child: Text(text)),
      );
}
