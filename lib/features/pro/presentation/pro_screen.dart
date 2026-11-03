import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/premium.dart';
import '../../auth/presentation/legal_sheet.dart';
import '../application/pro_controller.dart';

/// SpeedDex Pro: what it includes, the store's price, subscribe / restore /
/// manage, and the renewal terms the stores require next to the button.
class ProScreen extends ConsumerWidget {
  const ProScreen({super.key});

  static const _benefits = [
    (Icons.block_rounded, 'No ads', 'No banners in the feed, no rewarded ads to sit through.'),
    (
      Icons.lock_open_rounded,
      'Every card unlocked',
      'Full spec sheets and model photos on every car, free.',
    ),
    (Icons.garage_rounded, 'Unlimited Garage', 'Keep every car you catch. No slot limit.'),
    (
      Icons.photo_camera_rounded,
      'Unlimited daily scans',
      'Scan as many cars as you find (fair use: up to 100 a day).',
    ),
  ];

  bool get _apple => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _manage(ProState s) async {
    final product = s.product?.id ?? 'speeddex_pro_monthly';
    final url = _apple
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse(
            'https://play.google.com/store/account/subscriptions?sku=$product&package=com.speeddex.speeddex',
          );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(proControllerProvider);
    final ctrl = ref.read(proControllerProvider.notifier);
    final store = _apple ? 'the App Store' : 'Google Play';
    return Scaffold(
      appBar: AppBar(title: Text('SPEEDDEX PRO', style: SdType.label)),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                SdSpace.gutter,
                SdSpace.md,
                SdSpace.gutter,
                SdSpace.xxxl,
              ),
              children: [
                const _Hero(),
                const SizedBox(height: SdSpace.xxl),
                for (final (icon, title, detail) in _benefits) ...[
                  _Benefit(icon: icon, title: title, detail: detail),
                  const SizedBox(height: SdSpace.md),
                ],
                const SizedBox(height: SdSpace.lg),
                if (s.premium.active)
                  _Active(premium: s.premium, store: store, onManage: () => _manage(s))
                else if (s.loading)
                  const Padding(
                    padding: EdgeInsets.all(SdSpace.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  if (s.product != null)
                    Center(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: s.product!.price,
                              style: SdType.dataLarge.copyWith(color: SdColors.gold),
                            ),
                            TextSpan(
                              text: ' / month',
                              style: SdType.body.copyWith(color: SdColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: SdSpace.lg),
                  SdButton(
                    label: s.available ? 'Subscribe' : 'Not available yet',
                    icon: Icons.workspace_premium_rounded,
                    variant: SdButtonVariant.gold,
                    loading: s.busy,
                    onPressed: s.available ? ctrl.subscribe : null,
                  ),
                  const SizedBox(height: SdSpace.sm),
                  Center(
                    child: TextButton(
                      onPressed: s.available && !s.busy ? ctrl.restore : null,
                      child: const Text('Restore purchases'),
                    ),
                  ),
                  if (!s.available)
                    Text(
                      'Subscriptions aren’t available on this device yet.',
                      textAlign: TextAlign.center,
                      style: SdType.caption,
                    ),
                ],
                if (s.message != null) ...[
                  const SizedBox(height: SdSpace.md),
                  Text(
                    s.message!,
                    textAlign: TextAlign.center,
                    style: SdType.caption.copyWith(color: SdColors.warning),
                  ),
                ],
                const SizedBox(height: SdSpace.xl),
                Text(
                  'Billed monthly through $store. The subscription renews automatically until you '
                  'cancel it in $store, at least 24 hours before the end of the month. Your Pro '
                  'benefits last until the end of the month you’ve paid for.',
                  textAlign: TextAlign.center,
                  style: SdType.caption.copyWith(height: 1.5),
                ),
                const SizedBox(height: SdSpace.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => showLegalSheet(context, 'Terms of Use'),
                      child: const Text('Terms of Use'),
                    ),
                    TextButton(
                      onPressed: () => showLegalSheet(context, 'Privacy Policy'),
                      child: const Text('Privacy Policy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [SdColors.gold.withValues(alpha: 0.35), Colors.transparent],
            ),
            border: Border.all(color: SdColors.gold, width: 1.5),
          ),
          child: const Icon(Icons.workspace_premium_rounded, color: SdColors.gold, size: 38),
        ),
        const SizedBox(height: SdSpace.md),
        Text('SpeedDex Pro', style: SdType.title),
        const SizedBox(height: SdSpace.xs),
        Text('Collect without limits.', style: SdType.body.copyWith(color: SdColors.textMuted)),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SdPanel(
      padding: const EdgeInsets.all(SdSpace.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SdColors.gold.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.all(SdRadius.md),
            ),
            child: Icon(icon, color: SdColors.gold, size: 22),
          ),
          const SizedBox(width: SdSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SdType.bodyStrong),
                const SizedBox(height: 2),
                Text(detail, style: SdType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Active extends StatelessWidget {
  const _Active({required this.premium, required this.store, required this.onManage});
  final Premium premium;
  final String store;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final until = premium.expiresAt == null ? null : SdFormat.date(premium.expiresAt!);
    return SdPanel(
      accent: SdColors.gold,
      child: Column(
        children: [
          const Icon(Icons.verified_rounded, color: SdColors.gold, size: 30),
          const SizedBox(height: SdSpace.sm),
          Text('You’re Pro', style: SdType.heading),
          const SizedBox(height: SdSpace.xs),
          if (until != null)
            Text(
              premium.autoRenewing ? 'Renews on $until' : 'Ends on $until. It won’t renew.',
              style: SdType.body.copyWith(color: SdColors.textMuted),
            ),
          const SizedBox(height: SdSpace.lg),
          SdButton(
            label: 'Manage in $store',
            icon: Icons.open_in_new_rounded,
            variant: SdButtonVariant.secondary,
            onPressed: onManage,
          ),
        ],
      ),
    );
  }
}
