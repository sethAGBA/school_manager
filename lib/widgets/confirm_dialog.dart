import 'package:flutter/material.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';

Future<bool> showDangerConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Annuler',
  String confirmLabel = 'Supprimer',
  IconData icon = Icons.warning_amber_rounded,
  Color color = const Color(0xFFEF4444),
}) async {
  final theme = Theme.of(context);
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => CustomDialog(
      title: title,
      showCloseIcon: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 36),
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
          const SizedBox(height: 8),
          Text('Cette action est irréversible.',
              style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8), fontSize: 12)),
        ],
      ),
      fields: const [],
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.textTheme.bodyMedium?.color,
            side: BorderSide(color: theme.dividerColor),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

