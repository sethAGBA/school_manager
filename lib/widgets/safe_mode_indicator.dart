import 'package:flutter/material.dart';
import 'package:school_manager/services/safe_mode_service.dart';

class SafeModeIndicator extends StatelessWidget {
  const SafeModeIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SafeModeService.instance.isEnabledNotifier,
      builder: (context, isEnabled, child) {
        if (!isEnabled) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.security,
                size: 16,
                color: Colors.red[700],
              ),
              const SizedBox(width: 6),
              Text(
                'Mode coffre fort actif',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}