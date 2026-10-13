import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/brutal.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/admin_backend_repository.dart';
import '../../data/admin_permissions.dart';
import '../../data/admin_profile.dart';
import 'admin_widgets.dart';

/// Alta/edición de un perfil administrativo: rol (administrador, supervisor /
/// coordinador o director) y permisos por módulo, individuales por persona.
Future<void> showAdminProfileSheet(
  BuildContext context, {
  AdminProfile? existing,
}) {
  return showBrutalSheet<void>(
    context,
    title: existing == null ? 'Nuevo perfil' : 'Editar ${existing.fullName}',
    child: _AdminProfileForm(existing: existing),
  );
}

class _AdminProfileForm extends ConsumerStatefulWidget {
  const _AdminProfileForm({this.existing});

  final AdminProfile? existing;

  @override
  ConsumerState<_AdminProfileForm> createState() => _AdminProfileFormState();
}

class _AdminProfileFormState extends ConsumerState<_AdminProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _password;
  late String _roleCode;
  late bool _active;
  late Set<String> _perms;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _saveError;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.fullName ?? '');
    _email = TextEditingController(text: p?.email ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _password = TextEditingController();
    _roleCode = p?.roleCode ?? 'coordinator';
    _active = p?.active ?? true;
    _perms = {...?p?.permissions};
    if (_isNew) _perms.add(Perm.dashboardView);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Tu propio acceso no se edita aquí (evita quedarte sin permisos).
  bool get _isSelf =>
      widget.existing != null &&
      widget.existing!.id == ref.read(authControllerProvider).user?.id;

  bool _canGrant(String code) =>
      ref.read(authControllerProvider).user?.can(code) ?? false;

  void _toggle(AdminPermissionModule m, AdminPermissionAction a) {
    final code = m.code(a);
    setState(() {
      if (_perms.contains(code)) {
        _perms.remove(code);
        // Quitar "ver" quita también el resto de acciones del módulo.
        if (a.key == 'view') _perms.removeAll(m.codes);
      } else {
        _perms.add(code);
        // Cualquier acción requiere poder ver el módulo.
        if (a.key != 'view' && m.key != 'dashboard') {
          final view = '${m.key}.view';
          if (_canGrant(view)) _perms.add(view);
        }
      }
    });
  }

  void _preset(Set<String> codes) => setState(() {
        _perms = codes.where(_canGrant).toSet();
      });

  bool _validate() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'El nombre es obligatorio' : null;
      _emailError = email.isEmpty
          ? 'El correo es obligatorio'
          : !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
              ? 'Correo no válido'
              : null;
      _passwordError =
          _isNew && _password.text.length < 6 ? 'Mínimo 6 caracteres' : null;
      _saveError = null;
    });
    return _nameError == null && _emailError == null && _passwordError == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final repo = ref.read(adminBackendRepositoryProvider);
    if (repo == null) {
      setState(
        () => _saveError = 'Conéctate al servidor para guardar perfiles.',
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final payload = <String, dynamic>{
        'fullName': _name.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        if (!_isSelf) ...{
          'roleCode': _roleCode,
          'permissions': _perms.toList()..sort(),
          'active': _active,
        },
      };
      if (_isNew) {
        await repo.createProfile({
          ...payload,
          'email': _email.text.trim(),
          'password': _password.text,
        });
      } else {
        await repo.updateProfile(widget.existing!.id, payload);
      }
      ref.invalidate(adminProfilesProvider);
      await ref.read(adminProfilesProvider.future);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isNew ? 'Perfil creado correctamente' : 'Cambios guardados',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: palette.textMuted,
    );
    final locked = _isSelf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrutalTextField(
          controller: _name,
          label: 'Nombre completo',
          icon: Icons.person_rounded,
          errorText: _nameError,
        ),
        const SizedBox(height: 12),
        BrutalTextField(
          controller: _email,
          label: 'Correo',
          icon: Icons.mail_rounded,
          keyboardType: TextInputType.emailAddress,
          errorText: _emailError,
        ),
        const SizedBox(height: 12),
        BrutalTextField(
          controller: _phone,
          label: 'Teléfono (opcional)',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
        ),
        if (_isNew) ...[
          const SizedBox(height: 12),
          BrutalTextField(
            controller: _password,
            label: 'Contraseña inicial',
            icon: Icons.lock_rounded,
            obscureText: true,
            errorText: _passwordError,
          ),
        ],
        const FormLabel('Rol'),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final r in adminProfileRoles)
              BrutalPill(
                compact: true,
                label: r.$2,
                selected: _roleCode == r.$1,
                onTap: locked || (r.$1 == 'admin' && !_canGrant('roles.create'))
                    ? null
                    : () => setState(() => _roleCode = r.$1),
              ),
          ],
        ),
        const FormLabel('Permisos por módulo'),
        if (locked)
          Text(
            'No puedes cambiar tu propio rol ni tus permisos.',
            style: muted,
          )
        else ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              BrutalPill(
                compact: true,
                label: 'Todo',
                selected: false,
                onTap: () => _preset(allAdminPermissionCodes.toSet()),
              ),
              BrutalPill(
                compact: true,
                label: 'Solo ver',
                selected: false,
                onTap: () => _preset({
                  for (final m in adminPermissionModules) '${m.key}.view',
                }),
              ),
              BrutalPill(
                compact: true,
                label: 'Ninguno',
                selected: false,
                onTap: () => _preset({}),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        for (final m in adminPermissionModules)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: BrutalBox(
              color: palette.cardElevated,
              radius: Radii.md,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(m.icon, size: 18, color: palette.accentDeep),
                      const SizedBox(width: 8),
                      Text(
                        m.label,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final a in m.actions)
                        BrutalPill(
                          compact: true,
                          label: a.label,
                          selected: _perms.contains(m.code(a)),
                          onTap: locked || !_canGrant(m.code(a))
                              ? null
                              : () => _toggle(m, a),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!_isNew && !locked) ...[
          const FormLabel('Estado'),
          Wrap(
            spacing: 4,
            children: [
              BrutalPill(
                compact: true,
                label: 'Activo',
                selected: _active,
                onTap: () => setState(() => _active = true),
              ),
              BrutalPill(
                compact: true,
                label: 'Inactivo',
                selected: !_active,
                onTap: () => setState(() => _active = false),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'El rol define el tipo de usuario; los permisos definen exactamente '
          'qué ve y qué puede hacer. Solo puedes conceder permisos que tú tienes.',
          style: muted,
        ),
        const SizedBox(height: 16),
        if (_saveError != null) ...[
          Text(
            _saveError!,
            style: context.textTheme.bodySmall?.copyWith(
              color: palette.danger,
            ),
          ),
          const SizedBox(height: 10),
        ],
        BrutalButton(
          expand: true,
          onTap: _saving ? () {} : _save,
          icon: Icons.check_rounded,
          label: _saving
              ? 'Guardando…'
              : _isNew
                  ? 'Crear perfil'
                  : 'Guardar cambios',
        ),
      ],
    );
  }
}
