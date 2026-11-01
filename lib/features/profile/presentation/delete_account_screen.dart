import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../auth/application/auth_controller.dart';

/// Deletes the player's account for good (Google Play's account deletion
/// requirement). Asks for the password and for DELETE to be typed, so it
/// can't happen by accident or from an unlocked phone left on a table.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _passwordError;
  String? _error;

  static const _deleted = [
    'Your profile, username and email address',
    'Every card in your Garage, with its photos',
    'Your posts, comments, likes and follows',
    'Your coins, XP, level and unlocked cards',
  ];

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _confirmed => _confirm.text.trim() == 'DELETE';

  Future<void> _delete() async {
    if (_busy || !_form.currentState!.validate() || !_confirmed) return;
    setState(() {
      _busy = true;
      _passwordError = null;
      _error = null;
    });
    // Captured first: this screen goes away as soon as the account is gone.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount(_password.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account was deleted. We’ve sent a confirmation email.')),
      );
    } on InvalidCredentialsFailure {
      if (mounted) setState(() => _passwordError = 'That password isn’t right.');
    } on RequestFailure catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors['password'] ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DELETE ACCOUNT')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  SdSpace.gutter,
                  SdSpace.lg,
                  SdSpace.gutter,
                  SdSpace.huge,
                ),
                children: [
                  Text('THIS CAN’T BE UNDONE', style: SdType.heading),
                  const SizedBox(height: SdSpace.sm),
                  Text(
                    'Deleting your account removes it straight away, along with:',
                    style: SdType.body.copyWith(color: SdColors.textMuted),
                  ),
                  const SizedBox(height: SdSpace.md),
                  SdPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in _deleted)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: SdSpace.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: SdColors.signal,
                                  ),
                                ),
                                const SizedBox(width: SdSpace.sm),
                                Expanded(child: Text(line, style: SdType.body)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SdSpace.md),
                  Text(
                    'Your cards won’t come back if you sign up again with the same email.',
                    style: SdType.caption,
                  ),
                  const SizedBox(height: SdSpace.xxl),
                  if (_error != null) ...[
                    Text(_error!, style: SdType.body.copyWith(color: SdColors.signal)),
                    const SizedBox(height: SdSpace.md),
                  ],
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                    onChanged: (_) {
                      if (_passwordError != null) setState(() => _passwordError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Your password',
                      errorText: _passwordError,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: SdSpace.lg),
                  TextFormField(
                    controller: _confirm,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _delete(),
                    decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
                  ),
                  const SizedBox(height: SdSpace.xl),
                  SdButton(
                    label: 'Delete my account',
                    loading: _busy,
                    onPressed: _confirmed ? _delete : null,
                  ),
                  const SizedBox(height: SdSpace.md),
                  SdButton(
                    label: 'Keep my account',
                    variant: SdButtonVariant.ghost,
                    onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
