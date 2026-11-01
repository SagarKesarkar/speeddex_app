import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../data/repositories.dart';

final modelPhotosProvider = FutureProvider.autoDispose.family<List<ModelPhoto>, String>(
  (ref, cardId) => ref.watch(cardsRepositoryProvider).modelPhotos(cardId),
);

/// The generation's reference photos (front, left side, right side, rear) in
/// one row. Tapping one opens them full screen. On a locked card the slots
/// show a lock and tapping one starts the unlock ([onUnlock]). Shows nothing
/// while there are none (or if they can't be loaded).
class ModelPhotosStrip extends ConsumerWidget {
  const ModelPhotosStrip({super.key, required this.cardId, required this.modelName, this.onUnlock});

  final String cardId;
  final String modelName;

  /// Starts the card's unlock flow; used when the photos are locked.
  final VoidCallback? onUnlock;

  static const _gap = SdSpace.sm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(modelPhotosProvider(cardId)).value ?? const <ModelPhoto>[];
    if (photos.isEmpty) return const SizedBox.shrink();
    final locked = photos.any((p) => p.locked);
    final shown = [
      for (final p in photos)
        if (!p.locked) p,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: SdSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SdSectionLabel(
            'Photos',
            trailing: locked
                ? const Icon(Icons.lock_rounded, size: 14, color: SdColors.textFaint)
                : Text('${photos.length}', style: SdType.dataSmall),
          ),
          const SizedBox(height: SdSpace.md),
          LayoutBuilder(
            builder: (context, c) {
              // Always four slots wide, so one or two photos keep the same size.
              final size = (c.maxWidth - _gap * 3) / 4;
              return Row(
                children: [
                  for (final (i, p) in photos.take(4).indexed) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    p.locked
                        ? _LockedThumb(label: p.viewLabel, size: size, onTap: onUnlock)
                        : _Thumb(
                            photo: p,
                            size: size,
                            label: '${p.viewLabel} photo of the $modelName',
                            onTap: () => showModelPhotos(
                              context,
                              shown,
                              initial: shown.indexOf(p),
                              modelName: modelName,
                            ),
                          ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A slot whose photo is part of the unlock: a lock over the card's surface.
class _LockedThumb extends StatelessWidget {
  const _LockedThumb({required this.label, required this.size, required this.onTap});
  final String label;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$label photo, locked. Unlock the card to see it',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: size,
              height: size * 0.75,
              decoration: BoxDecoration(
                color: SdColors.surfaceRaised,
                borderRadius: const BorderRadius.all(SdRadius.sm),
                border: Border.all(color: SdColors.gold.withValues(alpha: 0.35)),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.lock_rounded, size: 18, color: SdColors.gold),
            ),
            const SizedBox(height: SdSpace.xs),
            SizedBox(
              width: size,
              child: Text(label, textAlign: TextAlign.center, style: SdType.caption, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.size, required this.label, required this.onTap});
  final ModelPhoto photo;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Hero(
              tag: 'model-photo-${photo.imageUrl}',
              child: ClipRRect(
                borderRadius: const BorderRadius.all(SdRadius.sm),
                child: Container(
                  width: size,
                  height: size * 0.75,
                  color: SdColors.surfaceRaised,
                  child: Image.network(
                    photo.imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, color: SdColors.textFaint),
                    loadingBuilder: (_, child, p) => p == null ? child : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: SdSpace.xs),
            SizedBox(
              width: size,
              child: Text(
                photo.viewLabel,
                textAlign: TextAlign.center,
                style: SdType.caption,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen viewer: swipe between the photos, pinch or double-tap to zoom.
Future<void> showModelPhotos(
  BuildContext context,
  List<ModelPhoto> photos, {
  required int initial,
  required String modelName,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      barrierDismissible: true,
      pageBuilder: (_, _, _) =>
          _PhotoViewer(photos: photos, initial: initial, modelName: modelName),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initial, required this.modelName});
  final List<ModelPhoto> photos;
  final int initial;
  final String modelName;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  /// While a photo is zoomed, one finger pans it instead of turning the page.
  bool _zoomed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load every photo now, so swiping never waits for the next one.
    for (final p in widget.photos) {
      precacheImage(NetworkImage(p.imageUrl!), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            allowImplicitScrolling: true,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              // A thin black gap between photos while swiping.
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.xs),
              child: _ZoomablePhoto(
                photo: widget.photos[i],
                onZoomChanged: (z) {
                  if (z != _zoomed) setState(() => _zoomed = z);
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1} / ${widget.photos.length}',
                    style: SdType.data.copyWith(color: Colors.white),
                  ),
                  const SizedBox(width: SdSpace.md),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(SdSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${p.viewLabel} · ${widget.modelName}',
                      textAlign: TextAlign.center,
                      style: SdType.body.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                    if (p.credit case final credit?)
                      Text(
                        'Photo: $credit',
                        textAlign: TextAlign.center,
                        style: SdType.caption.copyWith(color: Colors.white54),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinch recognizer that leaves one-finger drags on an unzoomed photo to the
/// [PageView], so quick flicks turn the page. (InteractiveViewer claims any
/// fast one-finger move, which is why swiping felt stuck.)
class _PinchRecognizer extends ScaleGestureRecognizer {
  _PinchRecognizer({required this.zoomed});
  final bool Function() zoomed;

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && pointerCount < 2 && !zoomed()) return;
    super.resolve(disposition);
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.photo, required this.onZoomChanged});
  final ModelPhoto photo;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> with SingleTickerProviderStateMixin {
  static const _maxScale = 4.0;

  /// Double-tap zoom, centred on the tapped point.
  static const _doubleTapScale = 2.5;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;

  // Gesture start values.
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  Offset? _doubleTapAt;

  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<double>? _scaleAnim;
  Animation<Offset>? _offsetAnim;

  bool get _zoomed => _scale > 1.01;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      setState(() {
        _scale = _scaleAnim!.value;
        _offset = _offsetAnim!.value;
      });
    });
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onZoomChanged(_zoomed);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Keeps the zoomed photo covering the screen: no empty edges when panning.
  Offset _clamp(Offset o, double s) => Offset(
    o.dx.clamp(_size.width - _size.width * s, 0.0),
    o.dy.clamp(_size.height - _size.height * s, 0.0),
  );

  void _animateTo(double scale, Offset offset) {
    _scaleAnim = Tween(
      begin: _scale,
      end: scale,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _offsetAnim = Tween(
      begin: _offset,
      end: offset,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  void _onStart(ScaleStartDetails d) {
    _anim.stop();
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    final scale = (_startScale * d.scale).clamp(1.0, _maxScale);
    // The point under the fingers at the start stays under them.
    final anchor = (_startFocal - _startOffset) / _startScale;
    setState(() {
      _scale = scale;
      _offset = _clamp(d.localFocalPoint - anchor * scale, scale);
    });
  }

  void _onEnd(ScaleEndDetails d) {
    if (!_zoomed && _scale != 1) {
      _animateTo(1, Offset.zero);
    } else {
      widget.onZoomChanged(_zoomed);
    }
  }

  void _onDoubleTap() {
    if (_zoomed) {
      _animateTo(1, Offset.zero);
    } else {
      final at = _doubleTapAt ?? _size.center(Offset.zero);
      _animateTo(_doubleTapScale, _clamp(at - at * _doubleTapScale, _doubleTapScale));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _size = c.biggest;
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _PinchRecognizer: GestureRecognizerFactoryWithHandlers<_PinchRecognizer>(
              () => _PinchRecognizer(zoomed: () => _zoomed),
              (r) => r
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd,
            ),
            DoubleTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                  DoubleTapGestureRecognizer.new,
                  (r) => r
                    ..onDoubleTapDown = ((d) => _doubleTapAt = d.localPosition)
                    ..onDoubleTap = _onDoubleTap,
                ),
          },
          child: ClipRect(
            child: Transform(
              transform: Matrix4.identity()
                ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                ..scaleByDouble(_scale, _scale, 1, 1),
              child: Center(
                child: Hero(
                  tag: 'model-photo-${widget.photo.imageUrl}',
                  child: Image.network(
                    widget.photo.imageUrl!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    loadingBuilder: (_, child, p) => p == null
                        ? child
                        : const Center(child: CircularProgressIndicator(color: Colors.white)),
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
