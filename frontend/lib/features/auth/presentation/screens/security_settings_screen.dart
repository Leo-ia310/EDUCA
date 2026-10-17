import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/depth_card.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../../../notifications/providers.dart';
import '../../domain/auth_repository.dart';
import '../auth_controller.dart';
import '../widgets/authenticator_qr.dart';

String _message(Object error) => error is Failure
    ? error.message
    : error is StateError
        ? error.message.toString()
        : 'No se pudo completar la verificación. Intenta nuevamente.';
String _methodName(String method) =>
    method == 'totp' ? 'App autenticadora' : 'Correo electrónico';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final _code = TextEditingController();
  TwoFactorStatus? _status;
  TwoFactorSetup? _setup;
  String _method = 'totp';
  String? _error;
  bool _loading = true, _busy = false, _expired = false, _canResend = false;
  Timer? _expiryTimer, _resendTimer;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await ref.read(authRepositoryProvider).twoFactorStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _loading = false;
          _setup = null;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(error);
        });
      }
    }
  }

  void _schedule(TwoFactorSetup setup) {
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    _canResend =
        setup.resendAt == null || !setup.resendAt!.isAfter(DateTime.now());
    _expired =
        setup.expiresAt != null && !setup.expiresAt!.isAfter(DateTime.now());
    if (!_canResend) {
      _resendTimer = Timer(setup.resendAt!.difference(DateTime.now()), () {
        if (mounted) setState(() => _canResend = true);
      });
    }
    if (!_expired && setup.expiresAt != null) {
      _expiryTimer = Timer(setup.expiresAt!.difference(DateTime.now()), () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  Future<void> _startSetup() async {
    setState(() {
      _busy = true;
      _error = null;
      _setup = null;
      _code.clear();
    });
    try {
      final setup = await ref
          .read(authRepositoryProvider)
          .setupTwoFactor(method: _method);
      if (mounted) {
        setState(() {
          _setup = setup;
          _schedule(setup);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Ingresa los 6 dígitos del código.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .enableTwoFactor(_code.text.trim(), challengeId: _setup?.id);
      if (!mounted) return;
      _expiryTimer?.cancel();
      _resendTimer?.cancel();
      _code.clear();
      ref.invalidate(notificationsRepositoryProvider);
      setState(() {
        _status = TwoFactorStatus(
          enabled: true,
          required: false,
          method: result.method,
          hasAuthenticator: result.method == 'totp',
          recoveryCodesRemaining: result.recoveryCodes.length,
          verifiedAt: DateTime.now(),
        );
        _setup = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA activado correctamente.')),
      );
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Guarda tus códigos de recuperación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Cada código sirve una sola vez si pierdes acceso a tu método de verificación. Guárdalos en un lugar seguro.',
                ),
                const SizedBox(height: 12),
                SelectableText(result.recoveryCodes.join('\n')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: result.recoveryCodes.join('\n')),
              ),
              child: const Text('Copiar códigos'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ya los guardé'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final disabled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DisableDialog(method: _status!.method),
    );
    if (disabled == true && mounted) {
      ref.invalidate(notificationsRepositoryProvider);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('2FA desactivado.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => StudentDetailScaffold(
        title: 'Seguridad',
        bottomNav: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Autenticación en dos pasos',
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Añade una capa extra de protección: te pediremos un código seguro al iniciar sesión.',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.palette.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  DepthCard(
                    soft: true,
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Consultando el estado de seguridad…',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_status != null) ...[
                  _statusCard(context),
                  if (!_status!.enabled && _setup == null) ...[
                    const SizedBox(height: 14),
                    _methodCard(context),
                  ],
                  if (_setup != null && !_status!.enabled) ...[
                    const SizedBox(height: 14),
                    _setupCard(context),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _errorBanner(context),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _statusCard(BuildContext context) {
    final enabled = _status!.enabled;
    final tone = enabled ? context.palette.success : context.palette.danger;
    return DepthCard(
      soft: true,
      accent: tone,
      glow: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    enabled
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: tone,
                    size: 25,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estado de protección',
                      style: context.textTheme.labelLarge?.copyWith(
                        color: context.palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      enabled ? '2FA activado' : '2FA desactivado',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SecurityStatusBadge(enabled: enabled),
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          const SizedBox(height: 16),
          if (enabled) ...[
            _securityDetail(
              context,
              icon: Icons.verified_rounded,
              title: 'Método activo',
              value: _methodName(_status!.method),
            ),
            const SizedBox(height: 14),
            _securityDetail(
              context,
              icon: Icons.key_rounded,
              title: 'Códigos de recuperación',
              value: '${_status!.recoveryCodesRemaining} disponibles',
              helper: _status!.recoveryCodesRemaining == 0
                  ? 'Guarda los códigos al activar 2FA para poder recuperar tu cuenta.'
                  : 'Cada código solo se puede usar una vez.',
            ),
            const SizedBox(height: 16),
            Text(
              'Para cambiar de método, desactiva primero el actual confirmando tu identidad.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.palette.textMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: _busy ? null : _disable,
              icon: const Icon(Icons.lock_open_rounded, size: 19),
              label: const Text('Desactivar autenticación en dos pasos'),
            ),
          ] else
            Text(
              'Activa la verificación adicional para impedir el acceso aunque alguien conozca tu contraseña.',
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.palette.textMuted,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _methodCard(BuildContext context) => DepthCard(
        soft: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: context.palette.accentDeep),
                const SizedBox(width: 9),
                Text(
                  'Elige cómo verificar',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Puedes usar una app autenticadora o recibir un código por correo.',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _method,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Método de verificación',
                prefixIcon: Icon(
                  _method == 'totp'
                      ? Icons.phonelink_lock_rounded
                      : Icons.mark_email_read_rounded,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'totp',
                  child: Text('App autenticadora'),
                ),
                DropdownMenuItem(
                  value: 'email',
                  child: Text('Correo electrónico'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _method = value!;
                        _setup = null;
                        _error = null;
                        _expiryTimer?.cancel();
                        _resendTimer?.cancel();
                      }),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: _busy ? null : _startSetup,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _method == 'totp'
                          ? Icons.qr_code_rounded
                          : Icons.mark_email_unread_rounded,
                      size: 19,
                    ),
              label: Text(
                _busy
                    ? (_method == 'email'
                        ? 'Enviando código…'
                        : 'Preparando autenticador…')
                    : _method == 'totp'
                        ? 'Activar con app autenticadora'
                        : 'Enviar código por correo',
              ),
            ),
          ],
        ),
      );

  Widget _securityDetail(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    String? helper,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: context.palette.accentDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    helper,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  Widget _setupCard(BuildContext context) => DepthCard(
        soft: true,
        accent: context.palette.accent,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _setup!.method == 'totp'
                      ? Icons.phonelink_lock_rounded
                      : Icons.mark_email_read_rounded,
                  color: context.palette.accentDeep,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _setup!.method == 'totp'
                        ? 'Configurar autenticador'
                        : 'Código enviado',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_setup!.method == 'totp') ...[
              const Text('Escanea este código con tu app autenticadora.'),
              const SizedBox(height: 12),
              AuthenticatorQr(data: _setup!.otpauthUrl),
              const SizedBox(height: 12),
              Text(
                'También puedes ingresar esta clave manual en Google Authenticator, Microsoft Authenticator o una app compatible:',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _setup!.secret,
                style: context.textTheme.titleMedium?.copyWith(
                  color: context.palette.accentDeep,
                  letterSpacing: 0.7,
                ),
              ),
              TextButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: _setup!.secret),
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar clave manual'),
              ),
            ] else
              Text(
                'Te enviamos un código a ${_setup!.emailHint ?? 'tu correo'}. Revisa también la carpeta de spam.',
              ),
            const SizedBox(height: 10),
            Text(
              _expired
                  ? 'Código expirado. Solicita uno nuevo.'
                  : 'La verificación vence en 5 minutos.',
              style: TextStyle(
                color: _expired
                    ? context.palette.danger
                    : context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              enabled: !_busy && !_expired,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Código de 6 dígitos',
                prefixIcon: Icon(Icons.pin_rounded),
              ),
              onSubmitted: (_) {
                if (!_busy && !_expired) _enable();
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy || _expired ? null : _enable,
              child: Text(
                _busy ? 'Verificando…' : 'Verificar y activar 2FA',
              ),
            ),
            if (_setup!.method == 'email' || _expired)
              TextButton(
                onPressed: _busy || (_setup!.method == 'email' && !_canResend)
                    ? null
                    : _startSetup,
                child: Text(
                  _canResend || _setup!.method == 'totp'
                      ? 'Solicitar un nuevo código'
                      : 'Espera 60 segundos para reenviar',
                ),
              ),
          ],
        ),
      );

  Widget _errorBanner(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.danger.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: context.palette.danger.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: context.palette.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.palette.danger,
                ),
              ),
            ),
            if (_status == null)
              IconButton(
                tooltip: 'Reintentar',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
      );
}

class _SecurityStatusBadge extends StatelessWidget {
  const _SecurityStatusBadge({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? context.palette.success : context.palette.danger;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled
                  ? Icons.check_circle_rounded
                  : Icons.remove_circle_outline,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              enabled ? 'Activado' : 'Desactivado',
              style: context.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisableDialog extends ConsumerStatefulWidget {
  const _DisableDialog({required this.method});
  final String method;
  @override
  ConsumerState<_DisableDialog> createState() => _DisableDialogState();
}

class _DisableDialogState extends ConsumerState<_DisableDialog> {
  final _code = TextEditingController();
  TwoFactorSetup? _challenge;
  bool _recovery = false, _busy = false, _resend = true;
  String? _error;
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge =
          await ref.read(authRepositoryProvider).sendTwoFactorEmailCode();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _resend = false;
        _code.clear();
      });
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 60), () {
        if (mounted) setState(() => _resend = true);
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).disableTwoFactor(
            code: _recovery ? null : _code.text.trim(),
            recoveryCode: _recovery ? _code.text.trim() : null,
            challengeId: _challenge?.id,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Confirmar desactivación'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _recovery
                      ? 'Ingresa un código de recuperación guardado.'
                      : widget.method == 'email'
                          ? 'Confirma con un código enviado a tu correo.'
                          : 'Ingresa el código actual de tu app autenticadora.',
                ),
                if (widget.method == 'email' && !_recovery) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy || !_resend ? null : _send,
                    child: Text(
                      _challenge == null ? 'Enviar código' : 'Reenviar código',
                    ),
                  ),
                  if (_challenge != null)
                    Text(
                      'Código enviado a ${_challenge!.emailHint ?? 'tu correo'}. Vence en 5 minutos.',
                    ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  keyboardType:
                      _recovery ? TextInputType.text : TextInputType.number,
                  inputFormatters: _recovery
                      ? const []
                      : [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                  decoration: InputDecoration(
                    labelText: _recovery
                        ? 'Código de recuperación'
                        : 'Código de 6 dígitos',
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _recovery = !_recovery;
                            _code.clear();
                            _error = null;
                          }),
                  child: Text(
                    _recovery
                        ? 'Usar código 2FA'
                        : 'Usar código de recuperación',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(color: context.palette.danger),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _busy ||
                    (widget.method == 'email' &&
                        !_recovery &&
                        _challenge == null)
                ? null
                : _confirm,
            child: Text(_busy ? 'Verificando…' : 'Desactivar 2FA'),
          ),
        ],
      );
}
