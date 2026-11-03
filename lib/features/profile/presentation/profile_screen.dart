import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../core/widgets/sd_search_picker.dart';
import '../../../core/widgets/sd_states.dart';
import '../../../domain/profile.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/legal_sheet.dart';
import '../../shell/app_shell.dart';
import 'badge_case.dart';
import 'daily_goals_panel.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final garage = ref.watch(garageSummaryProvider).value;
    final wallet = ref.watch(walletProvider).value;

    return SafeArea(
      bottom: false,
      child: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SdErrorState(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (p) => RefreshIndicator(
          color: SdColors.gold,
          backgroundColor: SdColors.surfaceRaised,
          onRefresh: () async {
            ref
              ..invalidate(walletProvider)
              ..invalidate(garageSummaryProvider)
              ..invalidate(dailyGoalsProvider);
            ref.invalidate(profileProvider);
            await ref.read(profileProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: SdSpace.huge),
            children: [
              const TabHeader(title: 'Profile'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!p.emailVerified) ...[
                      _ConfirmEmail(email: p.email),
                      const SizedBox(height: SdSpace.lg),
                    ],
                    _License(profile: p, cars: garage?.totalCards),
                    const SizedBox(height: SdSpace.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _Stat(
                            'Followers',
                            SdFormat.compact(p.followers),
                            onTap: () => context.push('/followers/${p.id}'),
                          ),
                        ),
                        const SizedBox(width: SdSpace.sm),
                        Expanded(
                          child: _Stat(
                            'Following',
                            SdFormat.compact(p.following),
                            onTap: () => context.push('/following/${p.id}'),
                          ),
                        ),
                        const SizedBox(width: SdSpace.sm),
                        Expanded(
                          child: _Stat('Cars', garage == null ? '—' : '${garage.totalCards}'),
                        ),
                      ],
                    ),
                    if (p.bio != null && p.bio!.isNotEmpty) ...[
                      const SizedBox(height: SdSpace.lg),
                      Text(p.bio!, style: SdType.body.copyWith(color: SdColors.textMuted)),
                    ],
                    const SizedBox(height: SdSpace.xxl),
                    const SdSectionLabel('Daily goals'),
                    const SizedBox(height: SdSpace.md),
                    const DailyGoalsPanel(),
                    const SizedBox(height: SdSpace.xxl),
                    const SdSectionLabel('Wallet'),
                    const SizedBox(height: SdSpace.md),
                    _WalletPanel(wallet: wallet),
                    const SizedBox(height: SdSpace.xxl),
                    SdSectionLabel(
                      'Badges',
                      trailing: Text(
                        p.allBadges.isEmpty
                            ? '${p.badges.length}'
                            : '${p.badges.length} / ${p.allBadges.length}',
                        style: SdType.dataSmall,
                      ),
                    ),
                    const SizedBox(height: SdSpace.md),
                    BadgeCase(badges: p.badgeCase),
                    const SizedBox(height: SdSpace.xxl),
                    const SdSectionLabel('Account'),
                    const SizedBox(height: SdSpace.md),
                    _Settings(profile: p),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks the player to open the link in their confirmation email, and sends
/// a new one on request.
class _ConfirmEmail extends ConsumerStatefulWidget {
  const _ConfirmEmail({required this.email});
  final String? email;

  @override
  ConsumerState<_ConfirmEmail> createState() => _ConfirmEmailState();
}

class _ConfirmEmailState extends ConsumerState<_ConfirmEmail> {
  bool _busy = false;

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      final already = await ref.read(profileRepositoryProvider).resendVerification();
      if (!mounted) return;
      if (already) {
        showSdSnack(context, 'Your email is already confirmed.', success: true);
        ref.invalidate(profileProvider);
      } else {
        showSdSnack(context, 'New link sent. Check your inbox and spam folder.', success: true);
      }
    } catch (e) {
      if (mounted) showSdSnack(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdPanel(
      accent: SdColors.warning,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: SdColors.warning, size: 22),
          const SizedBox(width: SdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Confirm your email', style: SdType.subheading),
                const SizedBox(height: SdSpace.xs),
                Text(
                  widget.email == null
                      ? 'Open the link we emailed you. It keeps your account safe and lets you reset your password.'
                      : 'Open the link we sent to ${widget.email}. It keeps your account safe and lets you reset your password.',
                  style: SdType.caption.copyWith(color: SdColors.textMuted),
                ),
                const SizedBox(height: SdSpace.sm),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _resend,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                      ),
                      child: Text(_busy ? 'Sending…' : 'Send a new link'),
                    ),
                    const SizedBox(width: SdSpace.lg),
                    TextButton(
                      onPressed: () => ref.invalidate(profileProvider),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                      ),
                      child: const Text("I've confirmed"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Spotter License: identity, level and XP progress.
class _License extends StatelessWidget {
  const _License({required this.profile, required this.cars});
  final UserProfile profile;
  final int? cars;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(SdRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26221A), SdColors.surface, Color(0xFF1A1712)],
        ),
        border: Border.all(color: SdColors.goldDeep.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: Pinstripe(opacity: 0.03)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg, vertical: SdSpace.sm),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: SdColors.goldDeep.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'SPOTTER LICENSE',
                      style: SdType.label.copyWith(color: SdColors.gold, fontSize: 11),
                    ),
                    const Spacer(),
                    Text(p.licenseNo, style: SdType.dataSmall),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(SdSpace.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Monogram(
                      initials: p.displayName
                          .split(' ')
                          .where((s) => s.isNotEmpty)
                          .take(2)
                          .map((s) => s[0])
                          .join()
                          .toUpperCase(),
                      size: 76,
                    ),
                    const SizedBox(width: SdSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.displayName,
                            style: SdType.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('@${p.handle}', style: SdType.body.copyWith(color: SdColors.gold)),
                          const SizedBox(height: SdSpace.md),
                          _Field('Rank', 'LV ${p.level}'),
                          _Field('Caught', cars?.toString() ?? '—'),
                          _Field('Issued', SdFormat.date(p.issuedAt)),
                          if (p.region.country != null)
                            _Field('From', p.region.city?.name ?? p.region.country!.name),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SdSpace.lg, 0, SdSpace.lg, SdSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          'LV ${p.level}',
                          style: SdType.label.copyWith(color: SdColors.text, fontSize: 11),
                        ),
                        const Spacer(),
                        Text(
                          '${SdFormat.number(p.xp)} / ${SdFormat.number(p.xpNextLevel)} XP',
                          style: SdType.dataSmall.copyWith(color: SdColors.gold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      label: 'Level progress ${(p.levelProgress * 100).round()} percent',
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(SdRadius.xs),
                        child: LinearProgressIndicator(
                          value: p.levelProgress,
                          minHeight: 6,
                          backgroundColor: SdColors.line,
                          color: SdColors.gold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label.toUpperCase(), style: SdType.label.copyWith(fontSize: 10)),
          ),
          Text(value, style: SdType.data.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.onTap});
  final String label;
  final String value;

  /// Opens the list behind the number (followers, following), if any.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = SdPanel(
      padding: const EdgeInsets.symmetric(vertical: SdSpace.md),
      child: Column(
        children: [
          Text(value, style: SdType.dataLarge.copyWith(fontSize: 18)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: SdType.label.copyWith(fontSize: 10)),
        ],
      ),
    );
    if (onTap == null) return panel;
    return Semantics(
      button: true,
      label: '$value $label',
      excludeSemantics: true,
      child: InkWell(onTap: onTap, borderRadius: const BorderRadius.all(SdRadius.md), child: panel),
    );
  }
}

class _WalletPanel extends ConsumerWidget {
  const _WalletPanel({required this.wallet});
  final Wallet? wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(isProProvider);
    return SdPanel(
      accent: SdColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CoinGlyph(size: 28),
              const SizedBox(width: SdSpace.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet?.coins.toString() ?? '—',
                    style: SdType.dataLarge.copyWith(color: SdColors.gold),
                  ),
                  Text('COINS', style: SdType.label.copyWith(fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: SdSpace.md),
          Text(
            'Earn 3 coins for every new car added to your Garage. Spend 5 to unlock a '
            'card’s full spec sheet.',
            style: SdType.caption,
          ),
          const SizedBox(height: SdSpace.lg),
          SdButton(
            label: pro ? 'SpeedDex Pro · active' : 'Get SpeedDex Pro',
            icon: Icons.workspace_premium_rounded,
            variant: pro ? SdButtonVariant.secondary : SdButtonVariant.gold,
            onPressed: () => context.push('/pro'),
          ),
        ],
      ),
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings({required this.profile});
  final UserProfile profile;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SIGN OUT?'),
        content: const Text('You’ll need to sign in again to scan or see your Garage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('SIGN OUT', style: SdType.label.copyWith(color: SdColors.signal)),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SdPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _SettingRow(
            icon: Icons.edit_outlined,
            label: 'Edit profile',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _EditProfileSheet(profile: profile),
            ),
          ),
          _SettingRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy policy',
            onTap: () => showLegalSheet(context, 'Privacy Policy'),
          ),
          _SettingRow(
            icon: Icons.description_outlined,
            label: 'Terms of use',
            onTap: () => showLegalSheet(context, 'Terms of Use'),
          ),
          _SettingRow(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            color: SdColors.signal,
            onTap: () => _signOut(context, ref),
          ),
          _SettingRow(
            icon: Icons.delete_forever_outlined,
            label: 'Delete account',
            color: SdColors.signal,
            last: true,
            onTap: () => context.push('/settings/delete-account'),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: SdColors.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? SdColors.textMuted),
            const SizedBox(width: SdSpace.md),
            Expanded(
              child: Text(label, style: SdType.body.copyWith(color: color)),
            ),
            const Icon(Icons.chevron_right_rounded, color: SdColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.displayName);
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late Country? _country = widget.profile.region.country;
  late City? _city = widget.profile.region.city;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .update(
            displayName: _name.text.trim(),
            bio: _bio.text.trim(),
            country: _country,
            city: _city,
          );
      ref.invalidate(profileProvider);
      if (mounted) {
        Navigator.pop(context);
        showSdSnack(context, 'Profile updated.', success: true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final geo = ref.read(geoRepositoryProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.xl),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('EDIT PROFILE', style: SdType.heading),
                const SizedBox(height: SdSpace.xl),
                if (_error != null) ...[
                  SdInlineError(message: _error!),
                  const SizedBox(height: SdSpace.lg),
                ],
                TextFormField(
                  controller: _name,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  validator: AuthValidators.displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: SdSpace.md),
                TextFormField(
                  controller: _bio,
                  maxLength: 160,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
                const SizedBox(height: SdSpace.md),
                // Location powers the country, state and city rankings.
                // Optional; pick the country first, then a city in it.
                SdSearchPicker<Country>(
                  label: 'Country',
                  hint: 'Type to search, e.g. India',
                  selected: _country,
                  search: (q) => geo.countries(search: q.isEmpty ? null : q),
                  displayOf: (c) => c.name,
                  subtitleOf: (c) => c.code,
                  onChanged: (c) => setState(() {
                    if (c != _country) _city = null; // a city belongs to one country
                    _country = c;
                  }),
                ),
                const SizedBox(height: SdSpace.lg),
                SdSearchPicker<City>(
                  // Rebuilt per country so stale suggestions never carry over.
                  key: ValueKey('city-${_country?.code}'),
                  label: 'City',
                  hint: _country == null ? 'Choose a country first' : 'Type to search, e.g. Pune',
                  enabled: _country != null,
                  selected: _city,
                  search: (q) => geo.cities(_country!.code, search: q.isEmpty ? null : q),
                  displayOf: (c) => c.name,
                  subtitleOf: (c) => c.regionName,
                  onChanged: (c) => setState(() => _city = c),
                ),
                const SizedBox(height: SdSpace.xl),
                SdButton(label: 'Save', loading: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
