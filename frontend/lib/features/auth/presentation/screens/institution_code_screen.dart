import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/validators.dart';
import '../auth_controller.dart';

class InstitutionCodeScreen extends ConsumerStatefulWidget {
  const InstitutionCodeScreen({super.key});

  @override
  ConsumerState<InstitutionCodeScreen> createState() =>
      _InstitutionCodeScreenState();
}

class _InstitutionCodeScreenState
    extends ConsumerState<InstitutionCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(authControllerProvider.notifier)
        .resolveInstitution(_controller.text.trim());
    if (!ok || !mounted) return;
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: context.palette.limeDeep,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.school_rounded,
                      color: Color(0xFF1E2218), size: 32),
                ),
                const SizedBox(height: 28),
                Text(
                  'Bienvenido a Educa360',
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ingresa el código de tu colegio para continuar.',
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.go,
                    onFieldSubmitted: (_) => _continue(),
                    validator: Validators.institutionCode,
                    decoration: const InputDecoration(
                      labelText: AppStrings.institutionCodeHint,
                      prefixIcon: Icon(Icons.qr_code_2_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      state.error!,
                      style: TextStyle(color: context.palette.danger),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: state.loading ? null : _continue,
                  child: state.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(AppStrings.continueWith),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Modo demo: usa el código  EDU360',
                    style: context.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
