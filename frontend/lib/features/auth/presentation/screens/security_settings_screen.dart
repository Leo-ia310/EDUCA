import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../domain/auth_repository.dart';
import '../auth_controller.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final _codeCtrl = TextEditingController();
  TwoFactorStatus? _status;
  TwoFactorSetup? _setup;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await ref.read(authRepositoryProvider).twoFactorStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _setup = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la seguridad de la cuenta.';
      });
    }
  }

  Future<void> _startSetup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final setup = await ref.read(authRepositoryProvider).setupTwoFactor();
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo iniciar la activación 2FA.';
      });
    }
  }

  Future<void> _enable() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(authRepositoryProvider).enableTwoFactor(code);
      if (!mounted) return;
      _codeCtrl.clear();
      await _showRecoveryCodes(result.recoveryCodes);
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'El código es incorrecto o venció.';
      });
    }
  }

  Future<void> _disable() async {
    final code = await _askCode();
    if (code == null || code.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).disableTwoFactor(code: code);
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo desactivar 2FA. Revisa el código.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Atrás',
          onPressed: () => context.pop(),
        ),
        title: const Text('Seguridad'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Autenticación en dos pasos',
              style: context.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Disponible para todos los usuarios. Protege la cuenta con un código adicional al iniciar sesión.',
              style: context.textTheme.bodyMedium
                  ?.copyWith(color: context.palette.textMuted),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (status != null)
              DepthCard(
                soft: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          status.enabled
                              ? Icons.verified_user_rounded
                              : Icons.shield_outlined,
                          color: status.enabled
                              ? context.palette.success
                              : context.palette.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            status.enabled ? '2FA activado' : '2FA desactivado',
                            style: context.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status.required
                          ? 'Esta cuenta requiere una verificación adicional. Si no activas app autenticadora, el sistema usará código por correo.'
                          : 'Puedes activarlo de forma opcional para reforzar tu cuenta.',
                      style: context.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Códigos de recuperación disponibles: ${status.recoveryCodesRemaining}',
                      style: context.textTheme.labelLarge
                          ?.copyWith(color: context.palette.textMuted),
                    ),
                    const SizedBox(height: 16),
                    if (status.enabled)
                      OutlinedButton.icon(
                        onPressed: _disable,
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Desactivar 2FA'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _startSetup,
                        icon: const Icon(Icons.add_moderator_rounded),
                        label: const Text('Activar con app autenticadora'),
                      ),
                  ],
                ),
              ),
            if (_setup != null) ...[
              const SizedBox(height: 16),
              _SetupCard(
                setup: _setup!,
                codeCtrl: _codeCtrl,
                onEnable: _loading ? null : _enable,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: context.palette.danger)),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _askCode() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar desactivación'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Código 2FA'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecoveryCodes(List<String> codes) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Guarda tus códigos'),
        content: SelectableText(codes.join('\n')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.setup,
    required this.codeCtrl,
    required this.onEnable,
  });

  final TwoFactorSetup setup;
  final TextEditingController codeCtrl;
  final VoidCallback? onEnable;

  @override
  Widget build(BuildContext context) {
    return DepthCard(
      soft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configurar autenticador',
            style: context.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Agrega esta clave en tu app autenticadora y luego ingresa el código de 6 dígitos.',
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SelectableText(
            setup.secret,
            style: context.textTheme.titleMedium?.copyWith(
              color: context.palette.accentDeep,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: codeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Código de 6 dígitos',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onEnable,
            child: const Text('Activar 2FA'),
          ),
        ],
      ),
    );
  }
}
