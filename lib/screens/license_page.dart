import 'package:flutter/material.dart';
import 'dart:async';
import 'package:school_manager/services/license_service.dart';

class LicensePage extends StatefulWidget {
  const LicensePage({Key? key}) : super(key: key);

  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage>
    with TickerProviderStateMixin {
  final _keyController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fade;

  LicenseStatus? _status;
  bool _loading = true;
  bool _showKey = false;
  bool _inputObscured = true;
  Timer? _revealTimer;
  bool _allConsumed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _load();
  }

  Future<void> _load() async {
    final st = await LicenseService.instance.getStatus();
    final all = await LicenseService.instance.allKeysUsed();
    setState(() {
      _status = st;
      _keyController.text = st.key ?? '';
      // expiry is computed by service; no manual editing here
      _loading = false;
      _allConsumed = all;
    });
    _animController.forward();
  }

  @override
  void dispose() {
    try {
      _revealTimer?.cancel();
    } catch (_) {}
    _animController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnack('Veuillez saisir la clé de licence', isError: true);
      return;
    }
    try {
      await LicenseService.instance.saveLicense(key: key);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
      return;
    }
    _showSnack('Licence enregistrée');
    await _load();
  }

  Future<void> _clear() async {
    final st = await LicenseService.instance.getStatus();
    final controller = TextEditingController();
    String normalize(String s) =>
        s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmer la suppression'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Saisissez la clé de licence actuelle pour confirmer. La clé restera marquée comme utilisée.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Clé de licence',
                  prefixIcon: Icon(Icons.vpn_key),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                final input = normalize(controller.text);
                final current = normalize(st.key ?? '');
                if (input.isEmpty || input != current) {
                  Navigator.of(ctx).pop(false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clé de licence incorrecte')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53E3E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
    if (proceed != true) return;
    await LicenseService.instance.clearLicense();
    _showSnack('Licence supprimée');
    await _load();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? const Color(0xFFE53E3E)
            : const Color(0xFF10B981),
      ),
    );
  }

  Future<bool> _ensureSupAdmin() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mot de passe SupAdmin'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mot de passe'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final valid = await LicenseService.instance.verifySupAdmin(
                controller.text,
              );
              Navigator.of(ctx).pop(valid);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (ok == true) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mot de passe SupAdmin incorrect')),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _fade,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildStatusCard(theme),
                          const SizedBox(height: 16),
                          _buildFormCard(theme),
                          const SizedBox(height: 8),
                          Text(
                            'La licence est valable 12 mois à partir de la date d\'enregistrement.',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.vpn_key_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Licence',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              Text(
                'Gérez votre clé et la validité',
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
            ),
            child: Text(
              'Powered by ACTe',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _armRevealTimeout() {
    try {
      _revealTimer?.cancel();
    } catch (_) {}
    _revealTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted) return;
      setState(() {
        _showKey = false;
        _inputObscured = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Affichage sensible masqué (timeout)')),
      );
    });
  }

  Widget _buildStatusCard(ThemeData theme) {
    final st = _status;
    final isLifetime = st?.isLifetime ?? false;
    final isActive = st?.isActive ?? false;
    final isExpired = st?.isExpired ?? false;
    final days = st?.daysRemaining ?? 0;

    final color = isActive
        ? const Color(0xFF10B981)
        : (isExpired ? const Color(0xFFE53E3E) : const Color(0xFFF59E0B));

    final label = isLifetime
        ? 'Active (à vie)'
        : (isActive ? 'Active' : (isExpired ? 'Expirée' : 'Incomplète'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statut: $label',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Clé: ${_formatKeyForDisplay(_status?.key ?? '', masked: !_showKey)}',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: _showKey ? 'Masquer' : 'Afficher',
                      onPressed: () async {
                        if (!_showKey) {
                          final ok = await _ensureSupAdmin();
                          if (!ok) return;
                        }
                        setState(() {
                          _showKey = !_showKey;
                        });
                        if (_showKey) {
                          _armRevealTimeout();
                        } else {
                          try {
                            _revealTimer?.cancel();
                          } catch (_) {}
                        }
                      },
                      icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                        color: theme.iconTheme.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_status?.registeredAt != null)
                  Text(
                    'Enregistrée le: ${_formatDate(_status!.registeredAt!)}',
                    style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Expiration: ${isLifetime ? 'À vie' : (_status?.expiry != null ? _formatDate(_status!.expiry!) : '—')}',
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jours restants: ${isLifetime ? 'Illimités' : (isActive ? days : (isExpired ? 0 : '—'))}',
                  style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                ),
                if (_allConsumed) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.3),
                      ),
                    ),
                    child: const Text(
                      'Lot de 12 licences consommé — application débloquée',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mettre à jour la licence',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            obscureText: _inputObscured,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Clé de licence',
              prefixIcon: const Icon(Icons.vpn_key),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                tooltip: _inputObscured ? 'Afficher (SupAdmin)' : 'Masquer',
                icon: Icon(
                  _inputObscured ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () async {
                  if (_inputObscured) {
                    final ok = await _ensureSupAdmin();
                    if (!ok) return;
                  }
                  setState(() {
                    _inputObscured = !_inputObscured;
                  });
                  if (!_inputObscured) {
                    _armRevealTimeout();
                  } else {
                    try {
                      _revealTimer?.cancel();
                    } catch (_) {}
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Enregistrer'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Supprimer',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _maskedKey(String? key) {
    if (key == null || key.isEmpty) return '—';
    if (key.length <= 6) return '•••';
    final start = key.substring(0, 3);
    final end = key.substring(key.length - 3);
    return '$start••••••$end';
  }

  String _formatKeyForDisplay(String raw, {required bool masked}) {
    if (raw.isEmpty) return '—';
    final grouped = _groupKey(raw);
    if (!masked) return grouped;
    final parts = grouped.split('-');
    if (parts.length <= 2) return _maskedKey(raw);
    final first = parts.first;
    final last = parts.last;
    final middle = List.generate(parts.length - 2, (_) => '••••');
    return ([first, ...middle, last]).join('-');
  }

  String _groupKey(String raw) {
    final s = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
