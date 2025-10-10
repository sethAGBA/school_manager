import 'package:flutter/material.dart';
import 'package:school_manager/main.dart';
import 'package:school_manager/screens/students/widgets/custom_dialog.dart';
import 'package:school_manager/utils/snackbar.dart';
import 'package:school_manager/services/auth_service.dart';
import 'dart:math';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final bool isDarkMode;
  final Function(bool) onThemeToggle;
  final AnimationController animationController;
  final String? currentRole;
  final Set<String>? currentPermissions;
  final Set<int>? allowedIndices;

  Sidebar({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.animationController,
    this.currentRole,
    this.currentPermissions,
    this.allowedIndices,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDarkMode
              ? [Color(0xFF1E3A8A), Color(0xFF3B82F6)]
              : [Color(0xFF60A5FA), Color(0xFF93C5FD)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: animationController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: animationController.value * 2 * pi,
                      child: Icon(Icons.school, size: 50, color: Colors.white),
                    );
                  },
                ),
                SizedBox(height: 16),
                Text(
                  'École Manager',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Theme.of(context).dividerColor),
          ListTile(
            leading: Icon(
              isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: Colors.white,
            ),
            title: Text(
              isDarkMode ? 'Mode Sombre' : 'Mode Clair',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            trailing: Switch(
              value: isDarkMode,
              onChanged: onThemeToggle,
              activeColor: Colors.blue[300],
            ),
          ),
          Divider(color: Theme.of(context).dividerColor),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  _buildMenuItem(
                    context,
                    0,
                    Icons.dashboard,
                    'Tableau de bord',
                  ),
                  _buildMenuItem(context, 1, Icons.people, 'Élèves'),
                  _buildMenuItem(context, 2, Icons.person, 'Personnel'),
                  _buildMenuItem(context, 3, Icons.grade, 'Notes & Bulletins'),
                  _buildMenuItem(context, 4, Icons.payment, 'Paiements'),
                  if ((currentRole ?? '') == 'admin' ||
                      (currentPermissions?.contains('view_users') ?? false))
                    _buildMenuItem(
                      context,
                      6,
                      Icons.admin_panel_settings,
                      'Utilisateurs',
                    ),
                  _buildMenuItem(
                    context,
                    7,
                    Icons.calendar_today,
                    'Emplois du Temps',
                  ),
                  _buildMenuItem(context, 9, Icons.book, 'Matières'),
                  _buildMenuItem(context, 10, Icons.inventory_2, 'Finance & Matériel'),
                  _buildMenuItem(context, 11, Icons.receipt_long, 'Audits'),
                  // Place Paramètres as the penultimate item (just above logout)
                  _buildMenuItem(context, 5, Icons.settings, 'Paramètres'),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(
                      color: Colors.white.withOpacity(0.5),
                      thickness: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Tooltip(
                      message: 'Terminer la session',
                      waitDuration: Duration(milliseconds: 400),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final theme = Theme.of(context);
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: theme
                                  .cardColor, // Use captured theme's card color
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ), // Consistent shape
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFE11D48),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Déconnexion',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE11D48),
                                    ),
                                  ),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.exit_to_app,
                                      size: 40,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Voulez-vous vraiment vous déconnecter ?\nVotre session en cours sera terminée.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: theme.textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ),
                              actions: [
                                Row(
                                  // Use Row for buttons
                                  mainAxisAlignment: MainAxisAlignment
                                      .spaceEvenly, // Distribute buttons evenly
                                  children: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: theme.dividerColor,
                                        ),
                                      ),
                                      child: const Text(
                                        'Annuler',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Se déconnecter',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            // ignore: use_build_context_synchronously
                            await _handleLogout(context);
                          }
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Se déconnecter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFFE11D48,
                          ), // red accent for danger
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    int index,
    IconData icon,
    String title,
  ) {
    bool isSelected = selectedIndex == index;
    final bool isAllowed =
        allowedIndices == null || allowedIndices!.contains(index);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: ListTile(
          leading: Icon(
            icon,
            color: isAllowed
                ? (isSelected ? Colors.white : Colors.white70)
                : Colors.white24,
            size: 28,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isAllowed
                  ? (isSelected ? Colors.white : Colors.white70)
                  : Colors.white24,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
          onTap: () {
            if (!isAllowed) {
              // Use root messenger to avoid missing Scaffold when in dialogs
              showRootSnackBar(
                const SnackBar(content: Text('Accès refusé pour cet écran')),
              );
              return;
            }
            onItemSelected(index);
          },
        ),
      ),
    );
  }
}

Future<void> _handleLogout(BuildContext context) async {
  // Ensure any dialogs/menus are closed
  // Close any open dialogs/popups gracefully
  while (Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
  await performGlobalLogout(context);
}
