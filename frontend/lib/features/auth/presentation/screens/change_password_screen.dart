import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../dashboard/presentation/widgets/student_chrome.dart';
import '../auth_controller.dart';

/// Password recovery is public; a signed-in change requires the current password.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.recoveryToken});
  final String? recoveryToken;
  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true, _obscureNew = true, _loading = false;
  String? _error;
  bool get _recovery => widget.recoveryToken != null;
  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(backendApiClientProvider);
      if (api == null) {
        throw StateError('Conéctate al servidor para cambiar la contraseña.');
      }
      await api.post(
        _recovery ? '/auth/reset-password' : '/auth/change-password',
        authenticated: !_recovery,
        data: {
          if (_recovery)
            'tokenHash': widget.recoveryToken
          else
            'currentPassword': _currentCtrl.text,
          'newPassword': _newCtrl.text,
        },
      );
      if (_recovery) await ref.read(authControllerProvider.notifier).signOut();
      if (!mounted) return;
      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Contraseña actualizada correctamente.'),),);
      if (_recovery) {
        context.replace(Routes.login);
      } else if (context.canPop()) {
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : 'No se pudo actualizar la contraseña. Intenta nuevamente.',);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => StudentDetailScaffold(
        title: _recovery ? 'Restablecer contraseña' : 'Cambiar contraseña',
        bottomNav: false,
        child: _recovery && widget.recoveryToken!.isEmpty
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text(
                    'El enlace de recuperación no es válido. Solicita uno nuevo.',),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => context.go(Routes.forgotPassword),
                    child: const Text('Solicitar nuevo enlace'),),
              ],)
            : Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_recovery) ...[
                        const Text(
                            'Elige una contraseña nueva. Después podrás iniciar sesión con ella y verificar tu 2FA si está activado.',),
                        const SizedBox(height: 16),
                      ],
                      if (!_recovery) ...[
                        TextFormField(
                          controller: _currentCtrl,
                          obscureText: _obscureCurrent,
                          autofillHints: const [AutofillHints.password],
                          enabled: !_loading,
                          validator: (v) => v == null || v.isEmpty
                              ? 'Ingresa tu contraseña actual'
                              : null,
                          decoration: InputDecoration(
                              labelText: 'Contraseña actual',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                  tooltip:
                                      'Mostrar u ocultar contraseña actual',
                                  icon: Icon(_obscureCurrent
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,),
                                  onPressed: () => setState(() =>
                                      _obscureCurrent = !_obscureCurrent,),),),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _newCtrl,
                        obscureText: _obscureNew,
                        enabled: !_loading,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (v) => v == null || v.trim().length < 8
                            ? 'Mínimo 8 caracteres'
                            : !_recovery && v == _currentCtrl.text
                                ? 'La nueva contraseña debe ser diferente'
                                : null,
                        decoration: InputDecoration(
                            labelText: 'Nueva contraseña',
                            prefixIcon: const Icon(Icons.lock_reset_rounded),
                            suffixIcon: IconButton(
                                tooltip: 'Mostrar u ocultar nueva contraseña',
                                icon: Icon(_obscureNew
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,),
                                onPressed: () => setState(
                                    () => _obscureNew = !_obscureNew,),),),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureNew,
                        enabled: !_loading,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (v) =>
                            v == _newCtrl.text && v != null && v.isNotEmpty
                                ? null
                                : 'Las contraseñas no coinciden',
                        decoration: const InputDecoration(
                            labelText: 'Confirmar nueva contraseña',
                            prefixIcon: Icon(Icons.lock_reset_rounded),),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(_error!,
                            style: TextStyle(color: context.palette.danger),),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),)
                              : const Text('Guardar cambios'),),
                      const SizedBox(height: 12),
                      Text(
                          'Usa al menos 8 caracteres combinando letras y números.',
                          style: context.textTheme.bodySmall
                              ?.copyWith(color: context.palette.textMuted),),
                      if (_recovery)
                        TextButton(
                            onPressed: _loading
                                ? null
                                : () => context.go(Routes.forgotPassword),
                            child: const Text('Solicitar otro enlace'),),
                    ],),),
      );
}
