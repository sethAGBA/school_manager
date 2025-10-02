import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:school_manager/services/auth_service.dart';

class TwoFactorPage extends StatefulWidget {
  final String username;
  final VoidCallback onSuccess;
  const TwoFactorPage({super.key, required this.username, required this.onSuccess});

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  final int _digits = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;
  bool _isVerifying = false;
  String? _error;
  Timer? _ticker;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_digits, (_) => TextEditingController());
    _nodes = List.generate(_digits, (_) => FocusNode());
    // Autofocus first box slightly later
    WidgetsBinding.instance.addPostFrameCallback((_) => _nodes.first.requestFocus());
    _secondsLeft = _computeSecondsLeft();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _computeSecondsLeft();
      if (mounted && left != _secondsLeft) {
        setState(() => _secondsLeft = left);
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final n in _nodes) n.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  String _collectCode() => _controllers.map((c) => c.text).join();

  void _handlePaste(String value) {
    final clean = value.replaceAll(RegExp(r"[^0-9]"), "");
    if (clean.length == _digits) {
      for (int i = 0; i < _digits; i++) {
        _controllers[i].text = clean[i];
      }
      _nodes.last.requestFocus();
    }
  }

  Future<void> _verify() async {
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    final ok = await AuthService.instance.verifyTotpCode(widget.username, _collectCode());
    setState(() => _isVerifying = false);
    if (!mounted) return;
    if (ok) {
      widget.onSuccess();
    } else {
      setState(() => _error = 'Code invalide');
    }
  }

  int _computeSecondsLeft() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final mod = now % 30;
    return 30 - mod;
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 48,
      child: TextField(
        controller: _controllers[index],
        focusNode: _nodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(counterText: ''),
        onChanged: (v) async {
          if (v.length > 1) {
            _handlePaste(v);
            return;
          }
          if (v.isNotEmpty && index < _digits - 1) {
            _nodes[index + 1].requestFocus();
          } else if (v.isEmpty && index > 0) {
            _nodes[index - 1].requestFocus();
          }
        },
        onSubmitted: (_) {
          if (index == _digits - 1) _verify();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1E293B), const Color(0xFF334155), const Color(0xFF475569)]
                : [const Color(0xFF6366F1), const Color(0xFF8B5CF6), const Color(0xFFEC4899)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  elevation: 24,
                  shadowColor: Colors.black.withOpacity(0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).cardColor,
                          Theme.of(context).cardColor.withOpacity(0.92),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: const Icon(Icons.verified_user, color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 16),
                          Text('Vérification 2FA', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                            'Entrez le code à 6 chiffres de votre application d\'authentification.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8)),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(_digits, _buildOtpBox),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final data = await Clipboard.getData('text/plain');
                                if (data?.text != null) _handlePaste(data!.text!);
                              },
                              icon: const Icon(Icons.paste, size: 16),
                              label: const Text('Coller le code'),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!, style: const TextStyle(color: Colors.red)),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Nouveau code dans $_secondsLeft s',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withOpacity(0.85),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                minHeight: 6,
                                value: (30 - _secondsLeft) / 30.0,
                                backgroundColor: theme.dividerColor.withOpacity(0.3),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Shortcuts(
                            shortcuts: <LogicalKeySet, Intent>{
                              LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
                              LogicalKeySet(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
                            },
                            child: Actions(
                              actions: <Type, Action<Intent>>{
                                ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (intent) {
                                  if (!_isVerifying) _verify();
                                  return null;
                                }),
                              },
                              child: Focus(
                                autofocus: true,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isVerifying ? null : _verify,
                                    icon: const Icon(Icons.lock_open),
                                    label: _isVerifying ? const Text('Vérification...') : const Text('Vérifier'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Besoin d\'aide ? Contactez votre administrateur.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
