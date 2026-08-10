import 'package:flutter/material.dart';
class RentHubButton extends StatelessWidget { const RentHubButton({super.key,required this.label,required this.onPressed}); final String label; final VoidCallback? onPressed; @override Widget build(BuildContext context)=>FilledButton(onPressed:onPressed,child:Text(label)); }
class EmptyState extends StatelessWidget { const EmptyState({super.key,required this.message}); final String message; @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(32),child:Text(message))); }
class StatusBadge extends StatelessWidget { const StatusBadge({super.key,required this.label}); final String label; @override Widget build(BuildContext context)=>Chip(label:Text(label)); }

