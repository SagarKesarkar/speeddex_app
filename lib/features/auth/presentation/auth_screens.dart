import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_states.dart';
import '../application/auth_controller.dart';
import 'legal_sheet.dart';

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/onboarding'),
        ),
        title: const SdLogo(height: 44),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                SdSpace.gutter,
                SdSpace.xl,
                SdSpace.gutter,
                SdSpace.xxxl,
              ),
              children: [
                Text(title.toUpperCase(), style: SdType.title),
                const SizedBox(height: SdSpace.sm),
                Text(subtitle, style: SdType.body.copyWith(color: SdColors.textMuted)),
                const SizedBox(height: SdSpace.xxl),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
    this.autofill,
    this.action = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final String? autofill;
  final TextInputAction action;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.action,
      autofillHints: widget.autofill == null ? null : [widget.autofill!],
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// "——— OR ———" between the email form and Google.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: SdColors.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
          child: Text('OR', style: SdType.label.copyWith(color: SdColors.textFaint)),
        ),
        const Expanded(child: Divider(color: SdColors.line)),
      ],
    );
  }
}

class _FormError extends StatelessWidget {
  const _FormError(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: SdMotion.fast,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: SdSpace.lg),
              child: Semantics(liveRegion: true, child: SdInlineError(message: message!)),
            ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  bool _googleBusy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signIn(_email.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dev = ref.watch(appConfigProvider).usesDevData;
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to keep collecting.',
      children: [
        _FormError(_error),
        Form(
          autovalidateMode: _autovalidate,
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: AuthValidators.email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: SdSpace.lg),
                _PasswordField(
                  controller: _password,
                  label: 'Password',
                  validator: AuthValidators.loginPassword,
                  autofill: AutofillHints.password,
                  onSubmitted: _submit,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/auth/forgot'),
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: SdSpace.md),
        SdButton(label: 'Sign in', loading: _busy, onPressed: _submit),
        const SizedBox(height: SdSpace.lg),
        const _OrDivider(),
        const SizedBox(height: SdSpace.lg),
        SdButton(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata_rounded,
          variant: SdButtonVariant.secondary,
          loading: _googleBusy,
          onPressed: _google,
        ),
        const SizedBox(height: SdSpace.xl),
        Center(
          child: TextButton(
            onPressed: () => context.pushReplacement('/auth/register'),
            child: const Text('New to SpeedDex? Create an account'),
          ),
        ),
        if (dev) ...[
          const SizedBox(height: SdSpace.lg),
          Text(
            'Development build: any valid email and password signs in. '
            'Use the password "wrongpassword" to see the error state.',
            style: SdType.caption.copyWith(color: SdColors.warning),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _accepted = false;
  bool _busy = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  bool _showTermsError = false;
  bool _googleBusy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _google() async {
    // Signing up with Google creates the account too: the same terms apply.
    setState(() => _showTermsError = !_accepted);
    if (_googleBusy || !_accepted) return;
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    final valid = _form.currentState!.validate();
    setState(() => _showTermsError = !_accepted);
    if (_busy || !valid || !_accepted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(_name.text, _email.text, _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Get your license',
      subtitle: 'Create an account to start your collection.',
      children: [
        _FormError(_error),
        Form(
          autovalidateMode: _autovalidate,
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  maxLength: 40,
                  validator: AuthValidators.displayName,
                  decoration: const InputDecoration(labelText: 'Display name', counterText: ''),
                ),
                const SizedBox(height: SdSpace.lg),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: AuthValidators.email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: SdSpace.lg),
                _PasswordField(
                  controller: _password,
                  label: 'Password',
                  action: TextInputAction.next,
                  autofill: AutofillHints.newPassword,
                  validator: AuthValidators.password,
                ),
                const SizedBox(height: SdSpace.lg),
                _PasswordField(
                  controller: _confirm,
                  label: 'Confirm password',
                  validator: (v) => v != _password.text ? 'Passwords do not match.' : null,
                  onSubmitted: _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SdSpace.md),
        Row(
          children: [
            Checkbox(
              value: _accepted,
              onChanged: (v) => setState(() {
                _accepted = v ?? false;
                if (_accepted) _showTermsError = false;
              }),
            ),
            const Expanded(child: LegalNotice()),
          ],
        ),
        if (_showTermsError)
          Padding(
            padding: const EdgeInsets.only(left: SdSpace.md),
            child: Text(
              'Please accept the Terms and Privacy Policy to continue.',
              style: SdType.caption.copyWith(color: SdColors.danger),
            ),
          ),
        const SizedBox(height: SdSpace.xl),
        SdButton(label: 'Create account', loading: _busy, onPressed: _submit),
        const SizedBox(height: SdSpace.lg),
        const _OrDivider(),
        const SizedBox(height: SdSpace.lg),
        SdButton(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata_rounded,
          variant: SdButtonVariant.secondary,
          loading: _googleBusy,
          onPressed: _google,
        ),
        const SizedBox(height: SdSpace.lg),
        Center(
          child: TextButton(
            onPressed: () => context.pushReplacement('/auth/login'),
            child: const Text('Already collecting? Sign in'),
          ),
        ),
      ],
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      await ref.read(authRepositoryProvider).requestPasswordReset(email);
      if (mounted) unawaited(context.push('/auth/forgot/code', extra: email));
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Reset password',
      subtitle: 'We’ll email you a 6-digit code. Enter it here to choose a new password.',
      children: [
        _FormError(_error),
        Form(
          autovalidateMode: _autovalidate,
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                validator: AuthValidators.email,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: SdSpace.xl),
              SdButton(label: 'Send code', loading: _busy, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}

/// Step 2 of a reset: the 6-digit code from the email.
class ResetCodeScreen extends ConsumerStatefulWidget {
  const ResetCodeScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<ResetCodeScreen> createState() => _ResetCodeScreenState();
}

class _ResetCodeScreenState extends ConsumerState<ResetCodeScreen> {
  static const _resendWait = 30;
  final _code = TextEditingController();
  bool _busy = false;
  bool _sending = false;
  String? _error;
  int _wait = _resendWait;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = _resendWait);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (_busy) return;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await ref.read(authRepositoryProvider).verifyResetCode(widget.email, code);
      if (mounted) context.pushReplacement('/auth/forgot/new', extra: token);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.userMessage);
        _code.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(widget.email);
      if (!mounted) return;
      _code.clear();
      _startCountdown();
      showSdSnack(context, 'New code sent. Only the newest code works.', success: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Enter code',
      // Neutral wording: never reveal whether the account exists.
      subtitle:
          'If an account exists for ${widget.email}, we sent it a 6-digit code. '
          'It works for 10 minutes.',
      children: [
        _FormError(_error),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: SdType.dataLarge.copyWith(fontSize: 30, letterSpacing: 14),
          decoration: const InputDecoration(hintText: '••••••', counterText: ''),
          // Checks as soon as the sixth digit is typed or pasted.
          onChanged: (v) {
            if (v.length == 6) _verify();
          },
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: SdSpace.xl),
        SdButton(label: 'Verify code', loading: _busy, onPressed: _verify),
        const SizedBox(height: SdSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _wait > 0 || _sending ? null : _resend,
              child: Text(
                _sending
                    ? 'Sending…'
                    : _wait > 0
                    ? 'Send a new code in ${_wait}s'
                    : 'Send a new code',
              ),
            ),
            TextButton(onPressed: () => context.pop(), child: const Text('Change email')),
          ],
        ),
        const SizedBox(height: SdSpace.sm),
        Text(
          "Can't find it? Check your spam folder. The email comes from support@speeddexgame.com.",
          style: SdType.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Step 3 of a reset: the new password.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key, required this.resetToken});
  final String resetToken;

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  String? _error;
  bool _expired = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(widget.resetToken, _password.text);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      showSdSnack(context, 'Password changed. Sign in with your new password.', success: true);
      context.go('/auth/login');
    } on RequestFailure catch (e) {
      // Field errors (a weak password) can be fixed here; anything else means
      // the reset ran out of time.
      if (mounted) {
        setState(() {
          _error = e.fieldErrors['password'] ?? e.message;
          _expired = !e.fieldErrors.containsKey('password');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'New password',
      subtitle: 'Choose a new password. You’ll be signed out on your other devices.',
      children: [
        _FormError(_error),
        if (_expired)
          SdButton(label: 'Start again', onPressed: () => context.go('/auth/forgot'))
        else
          Form(
            autovalidateMode: _autovalidate,
            key: _form,
            child: AutofillGroup(
              child: Column(
                children: [
                  _PasswordField(
                    controller: _password,
                    label: 'New password',
                    validator: AuthValidators.password,
                    autofill: AutofillHints.newPassword,
                    action: TextInputAction.next,
                  ),
                  const SizedBox(height: SdSpace.lg),
                  _PasswordField(
                    controller: _confirm,
                    label: 'Type it again',
                    validator: (v) => v == _password.text ? null : 'The passwords don’t match.',
                    onSubmitted: _submit,
                  ),
                  const SizedBox(height: SdSpace.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'At least 8 characters, with a letter and a number.',
                      style: SdType.caption,
                    ),
                  ),
                  const SizedBox(height: SdSpace.xl),
                  SdButton(label: 'Save new password', loading: _busy, onPressed: _submit),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
