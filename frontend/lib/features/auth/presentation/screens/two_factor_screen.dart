import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../auth_controller.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key, this.developerLogin = false});
  final bool developerLogin;
  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _code = TextEditingController();
  bool _recovery = false, _resendAllowed = false, _expired = false;
  Timer? _resendTimer, _expiryTimer;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _resendTimer?.cancel();
    _expiryTimer?.cancel();
    final challenge = ref.read(authControllerProvider).pendingTwoFactor;
    final now = DateTime.now();
    _resendAllowed =
        challenge?.resendAt == null || !challenge!.resendAt!.isAfter(now);
    _expired =
        challenge?.expiresAt != null && !challenge!.expiresAt!.isAfter(now);
    if (!_resendAllowed) {
      _resendTimer = Timer(challenge!.resendAt!.difference(now), () {
        if (mounted) setState(() => _resendAllowed = true);
      });
    }
    if (!_expired && challenge?.expiresAt != null) {
      _expiryTimer = Timer(challenge!.expiresAt!.difference(now), () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _resendTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = await ref
        .read(authControllerProvider.notifier)
        .verifyTwoFactor(_code.text.trim(), recovery: _recovery);
    if (role != null && mounted) {
      context
          .go(widget.developerLogin ? Routes.developer : role.dashboardRoute);
    }
  }

  Future<void> _resend() async {
    final sent =
        await ref.read(authControllerProvider.notifier).resendTwoFactor();
    if (sent && mounted) {
      setState(() {
        _code.clear();
        _schedule();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final challenge = state.pendingTwoFactor;
    if (challenge == null) {
      return const Scaffold(
          body: Center(child: Text('Inicia sesión nuevamente.')),);
    }
    final email = challenge.method == 'email';
    return StudentDetailScaffold(
        title: 'Verificación en dos pasos',
        bottomNav: false,
        onBack: () => context.go(Routes.login),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.verified_user_rounded,
              size: 52, color: context.palette.accent,),
          const SizedBox(height: 20),
          Text(
              _recovery
                  ? 'Código de recuperación'
                  : email
                      ? 'Código enviado por correo'
                      : 'Código de autenticador',
              style: context.textTheme.headlineSmall,),
          const SizedBox(height: 12),
          Text(_recovery
              ? 'Ingresa uno de los códigos de recuperación guardados al activar 2FA.'
              : email
                  ? 'Te enviamos un código a ${challenge.emailHint ?? 'tu correo'}. Revisa también la carpeta de spam.'
                  : 'Abre Google Authenticator, Microsoft Authenticator u otra app compatible e ingresa el código actual.',),
          const SizedBox(height: 12),
          Text(_expired
              ? 'La verificación expiró. Inicia sesión nuevamente.'
              : 'Esta verificación vence en 5 minutos.',),
          const SizedBox(height: 20),
          TextField(
              controller: _code,
              enabled: !state.loading && !_expired,
              keyboardType:
                  _recovery ? TextInputType.text : TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: _recovery
                  ? const []
                  : [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
              onSubmitted: (_) {
                if (!state.loading && !_expired) _submit();
              },
              decoration: InputDecoration(
                  labelText: _recovery
                      ? 'Código de recuperación'
                      : 'Código de 6 dígitos',
                  prefixIcon:
                      Icon(_recovery ? Icons.key_rounded : Icons.pin_rounded),),),
          const SizedBox(height: 12),
          TextButton.icon(
              onPressed: state.loading
                  ? null
                  : () => setState(() {
                        _recovery = !_recovery;
                        _code.clear();
                      }),
              icon: const Icon(Icons.key_rounded),
              label: Text(_recovery
                  ? 'Usar código 2FA'
                  : 'Usar código de recuperación',),),
          if (email && !_recovery && !_expired)
            TextButton(
                onPressed: state.loading || !_resendAllowed ? null : _resend,
                child: Text(_resendAllowed
                    ? 'Reenviar código'
                    : 'Espera 60 segundos para reenviar',),),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(state.error!, style: TextStyle(color: context.palette.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
              onPressed: state.loading
                  ? null
                  : _expired
                      ? () => context.go(Routes.login)
                      : _submit,
              child: Text(state.loading
                  ? 'Verificando…'
                  : _expired
                      ? 'Volver a iniciar sesión'
                      : 'Verificar',),),
        ],),);
  }
}
