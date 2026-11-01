import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app/providers.dart';
import '../../core/theme/sd_colors.dart';
import '../../core/theme/sd_tokens.dart';
import '../../core/theme/sd_typography.dart';

/// Where banner ads go in a feed of [postCount] posts: one in every block of
/// [every] posts, after a random post of that block (1 to [every]). [seed]
/// keeps the positions steady while the feed grows. Once the feed has
/// [ended], a slot past its last post moves to the end, so a short feed still
/// gets its ad. Returns the number of posts each ad follows, in order. Pure,
/// for testing.
List<int> feedAdSlots(int postCount, {required int seed, int every = 20, bool ended = false}) {
  final slots = <int>[];
  for (var block = 0; block * every < postCount; block++) {
    final after = block * every + Random(seed + block).nextInt(every) + 1;
    if (after <= postCount) {
      slots.add(after);
    } else if (ended) {
      slots.add(postCount);
    }
  }
  return slots;
}

/// A banner between Feed posts, labelled as an ad.
///
/// In the list it is an inline adaptive banner that takes no space until an
/// ad has loaded, and none at all if it fails. In card view ([large]) it is a
/// 300×250 medium rectangle filling its own page, with [placeholder] shown
/// while it loads or if none is available, so the page is never blank.
class FeedBannerAd extends ConsumerStatefulWidget {
  const FeedBannerAd({super.key, this.large = false, this.placeholder});

  final bool large;

  /// Built while loading (failed = false) and when no ad came (failed = true).
  final Widget Function(bool failed)? placeholder;

  @override
  ConsumerState<FeedBannerAd> createState() => _FeedBannerAdState();
}

class _FeedBannerAdState extends ConsumerState<FeedBannerAd> with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  AdSize? _size;
  bool _started = false;
  bool _failed = false;

  // Scrolling away and back shouldn't load (and count) a new ad.
  @override
  bool get wantKeepAlive => _ad != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load(MediaQuery.sizeOf(context).width - SdSpace.gutter * 2);
    }
  }

  Future<void> _load(double width) async {
    final service = ref.read(adsServiceProvider);
    if (!await service.ready()) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    final requested = widget.large
        ? AdSize.mediumRectangle
        : AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(width.truncate());
    final ad = BannerAd(
      adUnitId: service.config.feedBannerUnit,
      size: requested,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (a) async {
          final size = await (a as BannerAd).getPlatformAdSize() ?? requested;
          if (!mounted) return a.dispose();
          setState(() {
            _ad = a;
            _size = size;
          });
          updateKeepAlive();
        },
        onAdFailedToLoad: (a, _) {
          a.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ad = _ad;
    final size = _size;
    if (ad == null || size == null) {
      return widget.placeholder?.call(_failed) ?? const SizedBox.shrink();
    }
    return Semantics(
      label: 'Advertisement',
      child: Container(
        // In card view the frame hugs the ad; in the list it spans the column.
        width: widget.large ? size.width + SdSpace.md * 2 : null,
        padding: EdgeInsets.only(top: SdSpace.sm, bottom: widget.large ? SdSpace.md : 0),
        decoration: BoxDecoration(
          color: SdColors.surface,
          borderRadius: const BorderRadius.all(SdRadius.md),
          border: Border.all(color: SdColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.md),
              child: Text(
                'SPONSORED',
                style: SdType.label.copyWith(fontSize: 10, color: SdColors.textFaint),
              ),
            ),
            const SizedBox(height: SdSpace.sm),
            Center(
              child: SizedBox(
                width: size.width.toDouble(),
                height: size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
