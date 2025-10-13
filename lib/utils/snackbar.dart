import 'package:flutter/material.dart';

/// Global ScaffoldMessenger key to allow showing SnackBars from anywhere,
/// including dialogs that are not direct descendants of a Scaffold.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showRootSnackBar(SnackBar snackBar) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
}

void showSnackBar(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: const Duration(seconds: 3),
    ),
  );
}
