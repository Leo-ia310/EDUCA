import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../auth_controller.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key, this.developerLogin = false});

  final bool developerLogin;

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _codeCtrl = TextEditingController();
  bool _useRecoveryCode = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _codeCtrl.text.trim();
    if (value.isEmpty) return;
    final role =
        await ref.read(authControllerProvider.notifier).verifyTwoFactor(
              value,
              recovery: _useRecoveryCode,
            );
    if (role == null || !mounted) return;
    context.go(widget.developerLogin ? Routes.developer : role.dashboardRoute);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final challenge = state.pendingTwoFactor;
    if (challenge == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Inicia sesión nuevamente.')),
      );
    }
    final isEmail = challenge.method == 'email';
    final title = _useRecoveryCode
        ? 'Código de recuperación'
        : isEmail
            ? 'Código enviado por correo'
            : 'Código de autenticador';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Atrás',
          onPressed: () => context.go(Routes.login),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.palette.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  color: context.palette.accentDeep,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: context.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _description(challenge.method, challenge.emailHint),
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: context.palette.textMuted),
              ),
              if (challenge.debugCode != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'Código de desarrollo: ${challenge.debugCode}',
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.palette.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              TextField(
                controller: _codeCtrl,
                keyboardType: _useRecoveryCode
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters: _useRecoveryCode
                    ? const []
                    : [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: _useRecoveryCode
                      ? 'Código de recuperación'
                      : 'Código de 6 dígitos',
                  prefixIcon: Icon(
                    _useRecoveryCode ? Icons.key_rounded : Icons.pin_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _useRecoveryCode = !_useRecoveryCode;
                    _codeCtrl.clear();
                  });
                },
                icon: Icon(
                  _useRecoveryCode ? Icons.password_rounded : Icons.key_rounded,
                ),
                label: Text(
                  _useRecoveryCode
                      ? 'Usar código 2FA'
                      : 'Usar código de recuperación',
                ),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: TextStyle(color: context.palette.danger),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: state.loading ? null : _submit,
                child: state.loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verificar'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _description(String method, String? emailHint) {
    if (_useRecoveryCode) {
      return 'Ingresa uno de los códigos guardados al activar 2FA.';
    }
    if (method == 'email') {
      final hint =
          emailHint == null || emailHint.isEmpty ? 'tu correo' : emailHint;
      return 'Enviamos un código temporal a $hint. Vence en pocos minutos.';
    }
    return 'Abre Google Authenticator, Authy u otra app compatible e ingresa el código actual.';
  }
}
