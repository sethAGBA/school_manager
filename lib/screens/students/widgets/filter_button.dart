import 'package:flutter/material.dart';
import 'package:school_manager/constants/sizes.dart';

class FilterButton extends StatelessWidget {
  final String title;

  const FilterButton({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.buttonHeight,
      padding: EdgeInsets.symmetric(horizontal: AppSizes.spacing, vertical: AppSizes.smallSpacing / 2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppSizes.textFontSize,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
          SizedBox(width: AppSizes.smallSpacing / 1.5),
          Icon(
            Icons.keyboard_arrow_down,
            color: Theme.of(context).iconTheme.color,
            size: 20,
          ),
        ],
      ),
    );
  }
}