import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';

/// "By continuing you agree…" line with tappable Terms / Privacy links.
class LegalNotice extends StatefulWidget {
  const LegalNotice({super.key});

  @override
  State<LegalNotice> createState() => _LegalNoticeState();
}

class _LegalNoticeState extends State<LegalNotice> {
  late final _terms = TapGestureRecognizer()..onTap = () => showLegalSheet(context, 'Terms of Use');
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => showLegalSheet(context, 'Privacy Policy');

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = SdType.caption.copyWith(
      color: SdColors.text,
      decoration: TextDecoration.underline,
      decorationColor: SdColors.textFaint,
    );
    return Text.rich(
      TextSpan(
        style: SdType.caption,
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(text: 'Terms of Use', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Legal documents are versioned server content (GET /v1/legal/documents).
/// Until that endpoint exists this sheet says so rather than showing invented text.
Future<void> showLegalSheet(BuildContext context, String title) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: SdType.heading),
            const SizedBox(height: SdSpace.md),
            Text(
              'The current $title is published by the SpeedDex service. '
              'This development build is not connected to it yet, so the '
              'document cannot be shown here.',
              style: SdType.body.copyWith(color: SdColors.textMuted),
            ),
          ],
        ),
      ),
    ),
  );
}
