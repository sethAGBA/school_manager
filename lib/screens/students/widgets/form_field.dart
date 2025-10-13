import 'package:flutter/material.dart';
import 'package:school_manager/constants/colors.dart';
import 'package:school_manager/constants/sizes.dart';

class CustomFormField extends StatelessWidget {
  final TextEditingController? controller;
  final String labelText;
  final String? hintText;
  final String? Function(String?)? validator;
  final bool isDropdown;
  final List<String>? dropdownItems;
  final String? dropdownValue;
  final ValueChanged<String?>? onDropdownChanged;
  final bool isTextArea;
  final VoidCallback? onTap;
  final bool readOnly;
  final IconData? suffixIcon;
  final TextInputType? keyboardType;

  const CustomFormField({
    this.controller,
    required this.labelText,
    this.hintText,
    this.validator,
    this.isDropdown = false,
    this.dropdownItems,
    this.dropdownValue,
    this.onDropdownChanged,
    this.isTextArea = false,
    this.onTap,
    this.readOnly = false,
    this.suffixIcon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: AppSizes.smallSpacing / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            labelText,
            style: TextStyle(
              fontSize: AppSizes.textFontSize,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            ),
          ),
          SizedBox(height: AppSizes.smallSpacing / 2),
          isDropdown
              ? Builder(
                  builder: (context) {
                    // Normalize dropdown items: remove duplicates while preserving order
                    final rawItems = dropdownItems ?? <String>[];
                    final uniqueItems = <String>[];
                    for (final it in rawItems) {
                      if (!uniqueItems.contains(it)) uniqueItems.add(it);
                    }

                    // Use the provided dropdownValue only if it exists in the items
                    final effectiveValue =
                        (dropdownValue != null &&
                            uniqueItems.contains(dropdownValue))
                        ? dropdownValue
                        : null;

                    return DropdownButtonFormField<String>(
                      value: effectiveValue,
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppColors.primaryBlue,
                            width: 2,
                          ),
                        ),
                        contentPadding: EdgeInsets.all(AppSizes.spacing),
                      ),
                      items: uniqueItems.isEmpty
                          ? null
                          : uniqueItems.map((item) {
                              return DropdownMenuItem<String>(
                                value: item,
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge!.color,
                                  ),
                                ),
                              );
                            }).toList(),
                      onChanged: onDropdownChanged,
                      validator: validator,
                    );
                  },
                )
              : TextFormField(
                  controller: controller,
                  maxLines: isTextArea ? 4 : 1,
                  onTap: onTap,
                  readOnly: readOnly,
                  keyboardType: keyboardType,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.primaryBlue,
                        width: 2,
                      ),
                    ),
                    contentPadding: EdgeInsets.all(AppSizes.spacing),
                    suffixIcon: suffixIcon != null
                        ? Icon(
                            suffixIcon,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black,
                          )
                        : null,
                  ),
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                  validator: validator,
                ),
        ],
      ),
    );
  }
}
