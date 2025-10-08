import 'package:flutter/material.dart';
import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/constants/sizes.dart';
import 'form_field.dart';

class CustomDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback? onSubmit;
  final List<Map<String, String>> fields;
  final List<Widget>? actions;
  final bool showCloseIcon;

  const CustomDialog({
    required this.title,
    required this.content,
    this.onSubmit,
    this.fields = const [],
    this.actions,
    this.showCloseIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color? textColor = Theme.of(context).textTheme.bodyLarge?.color;
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          if (showCloseIcon)
            IconButton(
              icon: Icon(
                Icons.close,
                color: Theme.of(context).iconTheme.color,
                size: 20,
              ),
              tooltip: 'Fermer',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
      content: SingleChildScrollView(
        child: Container(width: AppSizes.dialogWidth, child: content),
      ),
      actions: actions ?? _buildDefaultActions(context),
    );
  }

  List<Widget> _buildDefaultActions(BuildContext context) {
    final List<Widget> widgets = [];
    widgets.add(
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          'Fermer',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyMedium!.color,
          ),
        ),
      ),
    );
    if (onSubmit != null) {
      widgets.add(
        ElevatedButton(
          onPressed: onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Valider'),
        ),
      );
    }
    return widgets;
  }
}
