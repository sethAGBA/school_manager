import 'package:flutter/material.dart';
import 'package:school_manager/services/safe_mode_service.dart';
import 'package:school_manager/utils/snackbar.dart';

class SafeModeHelper {
  /// Vérifie si une action est autorisée et affiche un message d'erreur si nécessaire
  static bool checkActionAllowed(BuildContext context) {
    if (!SafeModeService.instance.isActionAllowed()) {
      showSnackBar(
        context,
        SafeModeService.instance.getBlockedActionMessage(),
        isError: true,
      );
      return false;
    }
    return true;
  }

  /// Vérifie si une action est autorisée sans afficher de message
  static bool isActionAllowed() {
    return SafeModeService.instance.isActionAllowed();
  }

  /// Obtient le message d'erreur pour les actions bloquées
  static String getBlockedActionMessage() {
    return SafeModeService.instance.getBlockedActionMessage();
  }
}