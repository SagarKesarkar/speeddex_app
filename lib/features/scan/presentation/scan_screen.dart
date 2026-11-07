import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/widgets/sd_button.dart';
import '../../../core/widgets/sd_states.dart';
import '../../ads/rewarded_flow.dart';
import '../../shell/app_shell.dart';
import '../application/photo_orientation.dart';
import '../application/scan_controller.dart';
import 'daily_limit_offer.dart';
import 'scan_result_view.dart';
import 'zoom_presets.dart';

enum _Cam { off, starting, ready, denied, unavailable }

/// Scan tab (spec §3.5). Live camera only — there is deliberately no photo
/// library path. The camera runs only while this tab is visible, the app is
/// in the foreground and the user is framing or reviewing a shot.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  _Cam _cam = _Cam.off;
  bool _tabVisible = false;
  bool _foreground = true;
  bool _shooting = false;
  FlashMode _flash = FlashMode.off;

  /// How the phone is held, kept current while the camera runs so a
  /// sideways shot can be turned upright.
  StreamSubscription<AccelerometerEvent>? _tilt;
  HeldAs _held = HeldAs.portrait;

  /// Camera zoom: pinch on the viewfinder or tap a preset.
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  double _pinchStart = 1;
  bool _zooming = false;
  double? _pendingZoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabVisible = ActiveTab.of(context) == 2;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tilt?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  bool get _wantCamera {
    final s = ref.read(scanControllerProvider);
    return _tabVisible && _foreground && (s is ScanFraming || s is ScanPreview);
  }

  void _sync() {
    if (_wantCamera) {
      if (_camera == null && _cam != _Cam.starting && _cam != _Cam.denied) _start();
    } else {
      _stop();
    }
  }

  Future<void> _start() async {
    setState(() => _cam = _Cam.starting);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cam = _Cam.unavailable);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh, // 1080p: enough detail to find small plates and faces
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      // The OS permission prompt appears here, the first time a scan starts.
      await controller.initialize();
      if (!mounted || !_wantCamera) {
        await controller.dispose();
        if (mounted) setState(() => _cam = _Cam.off);
        return;
      }
      await controller.setFlashMode(_flash).catchError((_) {});
      // Each start begins at 1× (or the lens minimum). Digital zoom beyond
      // 8× only adds blur, so the range stops there.
      var minZoom = 1.0, maxZoom = 1.0;
      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = math.min(await controller.getMaxZoomLevel(), 8);
      } catch (_) {}
      final startZoom = 1.0.clamp(minZoom, math.max(minZoom, maxZoom)).toDouble();
      await controller.setZoomLevel(startZoom).catchError((_) {});
      _minZoom = minZoom;
      _maxZoom = math.max(minZoom, maxZoom);
      _zoom = startZoom;
      _tilt ??= accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        (e) => _held = heldAs(e.x, e.y),
        onError: (_) {}, // no sensor: photos are used as saved
      );
      setState(() {
        _camera = controller;
        _cam = _Cam.ready;
      });
    } on CameraException catch (e) {
      final denied = e.code.startsWith('CameraAccess');
      if (mounted) setState(() => _cam = denied ? _Cam.denied : _Cam.unavailable);
    } catch (_) {
      if (mounted) setState(() => _cam = _Cam.unavailable);
    }
  }

  Future<void> _stop() async {
    final c = _camera;
    if (c == null) return;
    _camera = null;
    // Leave "ready" in the same frame the camera goes: a build in between
    // would find no camera (e.g. when a system dialog pauses the app).
    if (mounted) setState(() => _cam = _Cam.off);
    await _tilt?.cancel();
    _tilt = null;
    await c.dispose();
  }

  /// Takes the shot and shows it at once. Straightening, compression and the
  /// face/plate blur happen when the player taps Identify (photo_pipeline),
  /// and nothing leaves the phone before that.
  Future<void> _shoot() async {
    final c = _camera;
    if (c == null || _shooting || !c.value.isInitialized) return;
    setState(() => _shooting = true);
    HapticFeedback.mediumImpact();
    try {
      final held = _held; // as held when the shutter fired
      final file = await c.takePicture();
      ref.read(scanControllerProvider.notifier).captured(file.path, held: held);
    } catch (e) {
      debugPrint('Capture failed: ${e.runtimeType}'); // no image data or paths logged
      if (mounted) showSdSnack(context, 'Couldn’t take the photo. Try again.');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  /// Applies [level] to the camera, at most one request at a time: during a
  /// pinch only the newest level is sent.
  Future<void> _setZoom(double level) async {
    final c = _camera;
    if (c == null) return;
    final z = level.clamp(_minZoom, _maxZoom).toDouble();
    setState(() => _zoom = z);
    if (_zooming) {
      _pendingZoom = z;
      return;
    }
    _zooming = true;
    try {
      double? next = z;
      while (next != null) {
        _pendingZoom = null;
        await c.setZoomLevel(next).catchError((_) {});
        next = _pendingZoom;
      }
    } finally {
      _zooming = false;
    }
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await _camera?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {
      if (mounted) showSdSnack(context, 'This camera has no light.');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scanControllerProvider, (_, _) => _sync());
    final state = ref.watch(scanControllerProvider);
    final summary = ref.watch(garageSummaryProvider).value;

    if (state is ScanResult || state is ScanAdded) {
      return const ScanResultView();
    }

    final (status, statusColor) = switch (state) {
      ScanFraming() when _cam == _Cam.ready => ('READY', SdColors.success),
      ScanFraming() when _cam == _Cam.denied || _cam == _Cam.unavailable => (
        'NO CAMERA',
        SdColors.danger,
      ),
      ScanFraming() => ('STARTING', SdColors.textMuted),
      ScanPreview() => ('REVIEW SHOT', SdColors.gold),
      ScanPreparing() => ('PROTECTING PRIVACY', SdColors.gold),
      ScanIdentifying() => ('IDENTIFYING', SdColors.gold),
      ScanNeedsReview() => ('IN REVIEW', SdColors.warning),
      ScanRejected() => ('REJECTED', SdColors.danger),
      ScanFailed(error: DailyScanLimitFailure()) => ('LIMIT REACHED', SdColors.gold),
      ScanFailed() => ('NOT SENT', SdColors.danger),
      _ => ('', SdColors.textMuted),
    };

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TabHeader(
            title: 'Scan',
            subtitle: summary == null
                ? null
                : summary.premium
                ? 'Unlimited scans · Pro'
                : '${summary.scansLeftToday} of ${summary.dailyScanLimit} scans left today',
            trailing: _StatusTag(status, statusColor),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SdSpace.gutter),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
                  child: _Viewfinder(
                    child: switch (state) {
                      ScanPreview(:final path, :final held) => _RawPhoto(path: path, held: held),
                      ScanPreparing(:final path, :final held) => Stack(
                        fit: StackFit.expand,
                        children: [
                          _RawPhoto(path: path, held: held),
                          const _ScanSweep(),
                        ],
                      ),
                      ScanIdentifying(:final path) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(path), fit: BoxFit.contain),
                          const _ScanSweep(),
                        ],
                      ),
                      ScanNeedsReview() => const _Message(
                        icon: Icons.hourglass_top_rounded,
                        title: 'Sent for review',
                        body:
                            'We couldn’t confirm this car automatically. Once a reviewer '
                            'approves it, it appears under Ready to add in your Garage.',
                      ),
                      ScanRejected(:final reason) => _Message(
                        icon: Icons.block_rounded,
                        title: 'Capture not accepted',
                        body: reason,
                      ),
                      // The car they want stays in view behind the offer.
                      ScanFailed(:final path, error: DailyScanLimitFailure()) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(path), fit: BoxFit.cover),
                          ColoredBox(color: SdColors.ink.withValues(alpha: 0.82)),
                          Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(SdSpace.xl),
                              child: DailyLimitOffer(
                                limit: summary?.dailyScanLimit,
                                adScansLeft: summary?.rewardedScansLeft,
                                onPremium: () => context.push('/pro'),
                                // Granted: identify this same photo straight away.
                                onWatchAd: () async {
                                  if (await earnExtraScan(context, ref)) {
                                    await ref.read(scanControllerProvider.notifier).identify();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      ScanFailed(:final error) => _Message(
                        icon: error is DailyScanLimitFailure
                            ? Icons.timer_outlined
                            : Icons.cloud_off_rounded,
                        title: error is DailyScanLimitFailure ? 'Daily limit reached' : 'Not sent',
                        body: error.userMessage,
                      ),
                      _ => _livePreview(),
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SdSpace.gutter,
              SdSpace.lg,
              SdSpace.gutter,
              SdSpace.lg,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: SdSize.maxContentWidth),
              child: _controls(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _livePreview() {
    switch (_cam) {
      case _Cam.ready:
        final c = _camera!;
        final size = c.value.previewSize;
        return GestureDetector(
          // Pinch to zoom anywhere on the viewfinder.
          onScaleStart: (_) => _pinchStart = _zoom,
          onScaleUpdate: (d) {
            if (d.pointerCount >= 2) _setZoom(_pinchStart * d.scale);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (size == null)
                CameraPreview(c)
              else
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: size.height, height: size.width, child: CameraPreview(c)),
                ),
              const _FrameGuide(),
              if (_maxZoom > _minZoom)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: ZoomPresets(min: _minZoom, max: _maxZoom, zoom: _zoom, onSelect: _setZoom),
                ),
            ],
          ),
        );
      case _Cam.denied:
        return const _Message(
          icon: Icons.no_photography_outlined,
          title: 'Camera access is off',
          body:
              'SpeedDex needs the camera to scan cars. Turn on camera access for '
              'SpeedDex in your device Settings, then return here.',
        );
      case _Cam.unavailable:
        return const _Message(
          icon: Icons.videocam_off_outlined,
          title: 'Camera unavailable',
          body: 'No usable camera was found, or it is in use by another app.',
        );
      case _Cam.off:
      case _Cam.starting:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _controls(ScanState state) {
    final ctrl = ref.read(scanControllerProvider.notifier);
    return switch (state) {
      ScanPreview() => Row(
        children: [
          Expanded(
            child: SdButton(
              label: 'Retake',
              variant: SdButtonVariant.secondary,
              onPressed: ctrl.retake,
            ),
          ),
          const SizedBox(width: SdSpace.md),
          Expanded(
            flex: 2,
            child: SdButton(label: 'Identify', icon: Icons.auto_awesome, onPressed: ctrl.identify),
          ),
        ],
      ),
      ScanPreparing() => Column(
        children: [
          Text(
            'Blurring faces and number plates…',
            style: SdType.body.copyWith(color: SdColors.textMuted),
          ),
          const SizedBox(height: SdSpace.md),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ),
      ScanIdentifying() => Column(
        children: [
          Text(
            'Matching make, model and year…',
            style: SdType.body.copyWith(color: SdColors.textMuted),
          ),
          const SizedBox(height: SdSpace.md),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ),
      ScanFailed(error: DailyScanLimitFailure()) => SdButton(
        label: 'Not now · discard photo',
        variant: SdButtonVariant.ghost,
        onPressed: ctrl.retake,
      ),
      ScanFailed(:final error) => Row(
        children: [
          Expanded(
            child: SdButton(
              label: 'Retake',
              variant: SdButtonVariant.secondary,
              onPressed: ctrl.retake,
            ),
          ),
          if (error is! DailyScanLimitFailure) ...[
            const SizedBox(width: SdSpace.md),
            Expanded(
              flex: 2,
              child: SdButton(label: 'Try again', onPressed: ctrl.identify),
            ),
          ],
        ],
      ),
      ScanNeedsReview() ||
      ScanRejected() => SdButton(label: 'Scan another car', onPressed: ctrl.retake),
      _ => _ShutterRow(
        enabled: _cam == _Cam.ready && !_shooting,
        flashOn: _flash == FlashMode.torch,
        onFlash: _cam == _Cam.ready ? _toggleFlash : null,
        onShoot: _shoot,
        onRetryCamera: (_cam == _Cam.denied || _cam == _Cam.unavailable)
            ? () {
                setState(() => _cam = _Cam.off);
                _sync();
              }
            : null,
      ),
    };
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      label: 'Status: $text',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(SdRadius.xs),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(text, style: SdType.label.copyWith(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: const BorderRadius.all(SdRadius.lg),
        border: Border.all(color: SdColors.lineStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox.expand(child: child),
    );
  }
}

class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.88,
              heightFactor: 0.42,
              child: CustomPaint(painter: _BracketPainter()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: SdSpace.lg,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: SdSpace.md, vertical: 6),
                color: SdColors.scrim,
                child: Text(
                  'FRAME THE WHOLE CAR · SIDE OR 3/4 VIEW',
                  style: SdType.label.copyWith(fontSize: 10, color: SdColors.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    const l = 22.0;
    final p = Paint()
      ..color = SdColors.gold
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, l)
          ..lineTo(0, 0)
          ..lineTo(l, 0),
        p,
      )
      ..drawPath(
        Path()
          ..moveTo(s.width - l, 0)
          ..lineTo(s.width, 0)
          ..lineTo(s.width, l),
        p,
      )
      ..drawPath(
        Path()
          ..moveTo(0, s.height - l)
          ..lineTo(0, s.height)
          ..lineTo(l, s.height),
        p,
      )
      ..drawPath(
        Path()
          ..moveTo(s.width - l, s.height)
          ..lineTo(s.width, s.height)
          ..lineTo(s.width, s.height - l),
        p,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Horizontal scan line sweeping the frozen still while identifying.
class _ScanSweep extends StatefulWidget {
  const _ScanSweep();

  @override
  State<_ScanSweep> createState() => _ScanSweepState();
}

class _ScanSweepState extends State<_ScanSweep> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          children: [
            Container(color: SdColors.ink.withValues(alpha: 0.35)),
            Align(
              alignment: Alignment(0, -1 + 2 * Curves.easeInOut.transform(_c.value)),
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      SdColors.gold.withValues(alpha: 0),
                      SdColors.gold.withValues(alpha: 0.28),
                      SdColors.gold.withValues(alpha: 0),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: Container(height: 1.5, color: SdColors.gold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shot as the camera saved it, turned upright when the phone was held
/// sideways (the app is locked to portrait, so such shots come out on their
/// side). The prepared photo is straightened the same way.
class _RawPhoto extends StatefulWidget {
  const _RawPhoto({required this.path, required this.held});
  final String path;
  final HeldAs held;

  @override
  State<_RawPhoto> createState() => _RawPhotoState();
}

class _RawPhotoState extends State<_RawPhoto> {
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    final portrait = info.image.height > info.image.width;
    info.dispose();
    final turns = widget.held == HeldAs.portrait || !portrait
        ? 0
        : widget.held == HeldAs.landscapeLeft
        ? 3
        : 1;
    if (mounted && turns != _turns) setState(() => _turns = turns);
  });
  int _turns = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = FileImage(File(widget.path)).resolve(createLocalImageConfiguration(context))
      ..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotatedBox(
    quarterTurns: _turns,
    child: Image.file(File(widget.path), fit: BoxFit.contain, gaplessPlayback: true),
  );
}

class _ShutterRow extends StatelessWidget {
  const _ShutterRow({
    required this.enabled,
    required this.flashOn,
    required this.onFlash,
    required this.onShoot,
    required this.onRetryCamera,
  });

  final bool enabled;
  final bool flashOn;
  final VoidCallback? onFlash;
  final VoidCallback onShoot;
  final VoidCallback? onRetryCamera;

  @override
  Widget build(BuildContext context) {
    if (onRetryCamera != null) {
      return SdButton(
        label: 'Try camera again',
        variant: SdButtonVariant.secondary,
        onPressed: onRetryCamera,
      );
    }
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: flashOn ? 'Turn light off' : 'Turn light on',
              onPressed: onFlash,
              icon: Icon(
                flashOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_outlined,
                color: flashOn ? SdColors.gold : SdColors.textMuted,
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          enabled: enabled,
          label: 'Take photo',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: enabled ? onShoot : null,
            child: AnimatedOpacity(
              duration: SdMotion.fast,
              opacity: enabled ? 1 : 0.4,
              child: Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: SdColors.text, width: 3),
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: SdColors.signal),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              'LIVE ONLY',
              style: SdType.label.copyWith(fontSize: 10, color: SdColors.textFaint),
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => SdEmptyState(icon: icon, title: title, message: body);
}
