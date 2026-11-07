import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/sd_colors.dart';
import '../../../core/theme/sd_tokens.dart';
import '../../../core/theme/sd_typography.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/sd_primitives.dart';
import '../../../domain/rarity_tier.dart';
import '../../../domain/spots.dart';
import '../../shell/app_shell.dart';

/// Radar: a live map of where cars were caught around the player.
///
/// Each pin is an area of about 500 m (the server never shares exact spots),
/// coloured by the rarest car caught there. The panel at the bottom lists the
/// cars of the selected area; swiping it moves the map from area to area.
///
/// The map is OpenStreetMap's own tiles, darkened on the device to match the
/// app. Those servers are free but best-effort, with a fair-use policy; for a
/// large audience set a commercial tile server with
/// `--dart-define=MAP_TILE_URL=…`, MAP_ATTRIBUTION and, for tiles that are
/// already dark, `MAP_TILE_DARKEN=false`.
class RadarScreen extends ConsumerStatefulWidget {
  const RadarScreen({super.key});

  /// This tab's index in the shell.
  static const tabIndex = 1;

  static const searchRadiusKm = 10.0;

  static const tileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const attribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );
  static const darkenTiles = bool.fromEnvironment('MAP_TILE_DARKEN', defaultValue: true);

  /// Light map tiles → the app's graphite: greyscale, inverted, then pressed
  /// into a narrow dark range (land ≈ #14, water and labels lighter), with a
  /// touch of blue so it isn't flat grey.
  static const _darken = ColorFilter.matrix([
    -0.117, -0.393, -0.040, 0, 152, //
    -0.117, -0.393, -0.040, 0, 154,
    -0.117, -0.393, -0.040, 0, 162,
    0, 0, 0, 1, 0,
  ]);

  @override
  ConsumerState<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends ConsumerState<RadarScreen> with TickerProviderStateMixin {
  static const _panelHeight = 268.0;
  static const _zoom = 13.5;

  /// Shifts the map's centre up, so what's centred sits between the header
  /// and the panel rather than behind the panel.
  static const _centreOffset = Offset(0, -70);

  final _map = MapController();
  final _pages = PageController(viewportFraction: 0.9);
  AnimationController? _fly;
  StreamSubscription<GeoFix>? _live;

  bool _started = false;
  bool _active = false;
  LocationAccess? _access;
  GeoFix? _me;
  GeoPoint? _searched;

  /// Where the player last left the map after dragging or zooming it.
  LatLng? _cameraTarget;
  bool _loading = false;
  Object? _error;
  List<CarSpot> _spots = const [];
  int _selected = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = ActiveTab.of(context) == RadarScreen.tabIndex;
    // Ask for location only once the player actually opens the Radar.
    if (!_started && _active) {
      _started = true;
      unawaited(_locate(prompt: true));
    }
    _followLive();
  }

  @override
  void dispose() {
    _live?.cancel();
    _fly?.dispose();
    _pages.dispose();
    _map.dispose();
    super.dispose();
  }

  /// The blue dot follows the player only while this tab is on screen.
  void _followLive() {
    final want = _active && _access == LocationAccess.granted;
    if (want && _live == null) {
      _live = ref
          .read(locationServiceProvider)
          .watch()
          .listen((f) => mounted ? setState(() => _me = f) : null, onError: (_) {});
    } else if (!want && _live != null) {
      _live!.cancel();
      _live = null;
    }
  }

  Future<void> _locate({bool prompt = false}) async {
    final svc = ref.read(locationServiceProvider);
    var access = await svc.access();
    if (access == LocationAccess.denied && prompt) access = await svc.request();
    if (!mounted) return;
    setState(() => _access = access);
    _followLive();
    if (access != LocationAccess.granted) return;
    final fix = await svc.captureFix();
    if (!mounted || fix == null) return;
    setState(() {
      _me = fix;
      _cameraTarget = _latLng(fix.point);
    });
    _flyTo(_latLng(fix.point), _zoom);
    await _search(fix.point);
  }

  Future<void> _search(GeoPoint around) async {
    setState(() {
      _loading = true;
      _error = null;
      _searched = around;
    });
    try {
      final spots = await ref
          .read(spotsRepositoryProvider)
          .nearby(around, radiusKm: RadarScreen.searchRadiusKm);
      // Nearest first, so the panel opens on the closest place to go.
      final from = _me?.point ?? around;
      spots.sort((a, b) => _km(from, a.point).compareTo(_km(from, b.point)));
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _selected = 0;
        _loading = false;
      });
      if (_pages.hasClients) _pages.jumpToPage(0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _select(int i, {bool fromPanel = false}) {
    if (i < 0 || i >= _spots.length) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = i);
    if (!fromPanel && _pages.hasClients) {
      _pages.animateToPage(i, duration: SdMotion.medium, curve: SdMotion.curve);
    }
    _flyTo(_latLng(_spots[i].point), max(_map.camera.zoom, _zoom));
  }

  /// Glides the map to [to] instead of jumping.
  void _flyTo(LatLng to, double zoom) {
    final MapCamera from;
    try {
      from = _map.camera;
    } catch (_) {
      return; // the map isn't laid out yet; onMapReady centres it
    }
    _fly?.dispose();
    final c = _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    final t = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    final lat = Tween(begin: from.center.latitude, end: to.latitude);
    final lng = Tween(begin: from.center.longitude, end: to.longitude);
    final z = Tween(begin: from.zoom, end: zoom);
    c.addListener(() {
      _map.move(LatLng(lat.evaluate(t), lng.evaluate(t)), z.evaluate(t), offset: _centreOffset);
    });
    c.forward();
  }

  static LatLng _latLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

  /// Great-circle distance in km.
  static double _km(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final h =
        pow(sin(dLat / 2), 2) +
        cos(a.latitude * pi / 180) * cos(b.latitude * pi / 180) * pow(sin(dLng / 2), 2);
    return 2 * r * asin(sqrt(h));
  }

  bool get _movedAway {
    final t = _cameraTarget, s = _searched;
    if (t == null || s == null) return false;
    return _km(GeoPoint(t.latitude, t.longitude), s) > RadarScreen.searchRadiusKm * 0.4;
  }

  void _onMapEvent(MapEvent e) {
    // Only the player's own drags and zooms count, not the map gliding itself.
    if (e.source == MapEventSource.mapController) return;
    if (e is MapEventMoveEnd || e is MapEventFlingAnimationEnd || e is MapEventDoubleTapZoomEnd) {
      setState(() => _cameraTarget = e.camera.center);
    }
  }

  @override
  Widget build(BuildContext context) {
    final granted = _access == LocationAccess.granted;
    final selected = _spots.isEmpty ? null : _spots[_selected];
    final me = _me;

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: const LatLng(20, 78),
              initialZoom: 3.5,
              minZoom: 3,
              maxZoom: 18,
              backgroundColor: SdColors.ink,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                if (_me != null) _map.move(_latLng(_me!.point), _zoom, offset: _centreOffset);
              },
              onMapEvent: _onMapEvent,
              onTap: (_, _) {},
            ),
            children: [
              TileLayer(
                urlTemplate: RadarScreen.tileUrl,
                // OpenStreetMap asks apps to identify themselves.
                userAgentPackageName: 'com.speeddex.speeddex',
                maxNativeZoom: 19,
                tileBuilder: RadarScreen.darkenTiles
                    ? (_, tile, _) => ColorFiltered(colorFilter: RadarScreen._darken, child: tile)
                    : null,
              ),
              CircleLayer(
                circles: [
                  // The selected pin stands for an area, not a point: show it.
                  if (selected != null)
                    CircleMarker(
                      point: _latLng(selected.point),
                      radius: 300,
                      useRadiusInMeter: true,
                      color: selected.topTier.color.withValues(alpha: 0.14),
                      borderColor: selected.topTier.color.withValues(alpha: 0.6),
                      borderStrokeWidth: 1.2,
                    ),
                  if (me != null && (me.accuracyMeters ?? 0) > 30)
                    CircleMarker(
                      point: _latLng(me.point),
                      radius: me.accuracyMeters!,
                      useRadiusInMeter: true,
                      color: _MeDot.blue.withValues(alpha: 0.10),
                      borderColor: _MeDot.blue.withValues(alpha: 0.3),
                      borderStrokeWidth: 1,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // The selected pin last, so it sits on top.
                  for (final (i, s) in _spots.indexed)
                    if (i != _selected) _pinFor(i, s),
                  if (selected != null) _pinFor(_selected, selected),
                  if (me != null)
                    Marker(point: _latLng(me.point), width: 40, height: 40, child: const _MeDot()),
                ],
              ),
            ],
          ),
        ),
        // Header over a scrim, so the title reads on any part of the map.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SdColors.ink, Color(0xCC0B0C0F), Color(0x000B0C0F)],
                stops: [0, 0.6, 1],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TabHeader(title: 'Radar', subtitle: 'Cars caught near you'),
                  if (_movedAway && !_loading)
                    _SearchHereButton(
                      onTap: () {
                        final t = _cameraTarget!;
                        _search(GeoPoint(t.latitude, t.longitude));
                      },
                    ),
                  const SizedBox(height: SdSpace.lg),
                ],
              ),
            ),
          ),
        ),
        // Map data credit: required by OpenStreetMap and the tile provider.
        Positioned(
          left: SdSpace.sm,
          bottom: _panelHeight + 2,
          child: GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: const Color(0x990B0C0F),
              child: Text(
                RadarScreen.attribution,
                style: SdType.caption.copyWith(fontSize: 10, color: SdColors.textMuted),
              ),
            ),
          ),
        ),
        if (granted && me != null)
          Positioned(
            right: SdSpace.gutter,
            bottom: _panelHeight + SdSpace.xl,
            child: _MapButton(
              icon: Icons.my_location_rounded,
              label: 'Back to my location',
              onTap: () {
                setState(() => _cameraTarget = _latLng(me.point));
                _flyTo(_latLng(me.point), _zoom);
              },
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _panelHeight,
          child: AnimatedSwitcher(duration: SdMotion.medium, child: _panel()),
        ),
      ],
    );
  }

  Marker _pinFor(int i, CarSpot s) {
    final sel = i == _selected;
    final size = sel ? 64.0 : 46.0;
    return Marker(
      key: ValueKey('${s.id}-$sel'),
      point: _latLng(s.point),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => _select(i),
        child: Semantics(
          button: true,
          label: '${s.cars.length} cars caught here, best ${s.topTier.label}',
          child: _SpotPin(tier: s.topTier, count: s.cars.length, selected: sel),
        ),
      ),
    );
  }

  Widget _panel() {
    if (_access == null) {
      return const _PanelShell(key: ValueKey('wait'), child: _Busy('Finding you…'));
    }
    if (_access != LocationAccess.granted) {
      return _PanelShell(
        key: const ValueKey('access'),
        child: _LocationNeeded(
          access: _access!,
          onAllow: () async {
            final svc = ref.read(locationServiceProvider);
            if (_access == LocationAccess.denied) {
              await _locate(prompt: true);
            } else {
              await svc.openSettings(_access!);
            }
          },
        ),
      );
    }
    if (_me == null || (_loading && _spots.isEmpty)) {
      return const _PanelShell(
        key: ValueKey('busy'),
        child: _Busy('Scanning the streets around you…'),
      );
    }
    if (_error != null) {
      return _PanelShell(
        key: const ValueKey('error'),
        child: _Message(
          icon: Icons.wifi_off_rounded,
          title: 'Radar is offline',
          body: 'Couldn’t load cars near you. Check your connection and try again.',
          action: 'Try again',
          onAction: () => _search(_searched ?? _me!.point),
        ),
      );
    }
    if (_spots.isEmpty) {
      return _PanelShell(
        key: const ValueKey('empty'),
        child: _Message(
          icon: Icons.radar_rounded,
          title: 'No catches around here yet',
          body: 'Be the first: scan a car nearby and it lands on the Radar for every spotter.',
          action: 'Scan a car',
          onAction: () => context.go('/scan'),
        ),
      );
    }
    return PageView.builder(
      key: const ValueKey('spots'),
      controller: _pages,
      itemCount: _spots.length,
      onPageChanged: (i) => _select(i, fromPanel: true),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.fromLTRB(SdSpace.xs, 0, SdSpace.xs, SdSpace.md),
        child: _SpotCard(
          spot: _spots[i],
          distanceKm: _km(_me!.point, _spots[i].point),
          index: i,
          count: _spots.length,
        ),
      ),
    );
  }
}

/// One area's catches: the message, then the cars you can find there.
class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.distanceKm,
    required this.index,
    required this.count,
  });

  final CarSpot spot;
  final double distanceKm;
  final int index;
  final int count;

  String get _distance => distanceKm < 1
      ? '${(distanceKm * 1000 / 50).round() * 50} m away'
      : '${distanceKm.toStringAsFixed(1)} km away';

  Future<void> _directions() async {
    final p = spot.point;
    await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.latitude},${p.longitude}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tier = spot.topTier;
    final n = spot.cars.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SdColors.surface.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.all(SdRadius.lg),
        border: Border.all(color: tier.color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(color: tier.color.withValues(alpha: 0.12), blurRadius: 30),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SdSpace.lg, SdSpace.md, SdSpace.sm, SdSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.place_rounded, size: 16, color: tier.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'YOU CAN FIND ${n == 1 ? 'THIS CAR' : 'THESE CARS'} HERE',
                    style: SdType.label.copyWith(color: SdColors.gold, letterSpacing: 1.4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${index + 1}/$count',
                  style: SdType.dataSmall.copyWith(color: SdColors.textFaint),
                ),
                const SizedBox(width: SdSpace.xs),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$_distance · last seen ${SdFormat.ago(spot.lastSeenAt)} ago · ${spot.sightings} '
              '${spot.sightings == 1 ? 'catch' : 'catches'}',
              style: SdType.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: SdSpace.sm),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: n,
                separatorBuilder: (_, _) => const SizedBox(width: SdSpace.sm),
                itemBuilder: (_, i) => _CarTile(car: spot.cars[i]),
              ),
            ),
            const SizedBox(height: SdSpace.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Areas are approximate to protect spotters.',
                    style: SdType.caption.copyWith(color: SdColors.textFaint, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _directions,
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text('DIRECTIONS'),
                  style: TextButton.styleFrom(
                    foregroundColor: SdColors.gold,
                    textStyle: SdType.label.copyWith(letterSpacing: 1.2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CarTile extends StatelessWidget {
  const _CarTile({required this.car});
  final SpotCar car;

  @override
  Widget build(BuildContext context) {
    final tier = car.tier;
    return Semantics(
      label: '${car.title}, ${tier.label}, seen ${car.sightings} times',
      excludeSemantics: true,
      child: Container(
        width: 148,
        decoration: BoxDecoration(
          color: SdColors.surfaceRaised,
          borderRadius: const BorderRadius.all(SdRadius.md),
          border: Border.all(color: tier.color.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (car.imageUrl != null)
                    Image.network(
                      car.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _NoPhoto(tier: tier),
                    )
                  else
                    _NoPhoto(tier: tier),
                  // Dark backing so the chip reads on bright photos.
                  Positioned(
                    left: 6,
                    top: 6,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xE00B0C0F),
                        borderRadius: BorderRadius.all(SdRadius.xs),
                      ),
                      child: TierChip(tier, dense: true),
                    ),
                  ),
                  if (car.sightings > 1)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const BoxDecoration(
                          color: Color(0xCC0B0C0F),
                          borderRadius: BorderRadius.all(SdRadius.xs),
                        ),
                        child: Text(
                          '×${car.sightings}',
                          style: SdType.dataSmall.copyWith(color: SdColors.text),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SdSpace.sm, 6, SdSpace.sm, SdSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    car.make.toUpperCase(),
                    style: SdType.label.copyWith(color: tier.color, fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    car.variant == null ? car.model : '${car.model} ${car.variant}',
                    style: SdType.bodyStrong.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Seen ${SdFormat.ago(car.lastSeenAt)} ago',
                    style: SdType.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto({required this.tier});
  final RarityTier tier;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: tier.deep,
    child: Icon(Icons.directions_car_filled_rounded, color: tier.color, size: 36),
  );
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.md),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: SdColors.surface.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.all(SdRadius.lg),
        border: Border.all(color: SdColors.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24)],
      ),
      child: Padding(padding: const EdgeInsets.all(SdSpace.lg), child: child),
    ),
  );
}

class _Busy extends StatelessWidget {
  const _Busy(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Sweep(),
        const SizedBox(height: SdSpace.md),
        Text(text, style: SdType.caption, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// A small radar sweep while the first results load.
class _Sweep extends StatefulWidget {
  const _Sweep();

  @override
  State<_Sweep> createState() => _SweepState();
}

class _SweepState extends State<_Sweep> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 56,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _SweepPainter(_c.value)),
    ),
  );
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = SdColors.gold.withValues(alpha: 0.35);
    canvas
      ..drawCircle(c, r - 1, ring)
      ..drawCircle(c, r * 0.6, ring);
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: pi / 2,
        colors: [SdColors.gold.withValues(alpha: 0), SdColors.gold.withValues(alpha: 0.6)],
        transform: GradientRotation(t * 2 * pi),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas
      ..drawArc(Rect.fromCircle(center: c, radius: r - 1), t * 2 * pi, pi / 2, true, sweep)
      ..drawCircle(c, 3, Paint()..color = SdColors.gold);
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.t != t;
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: SdColors.gold, size: 32),
      const SizedBox(height: SdSpace.sm),
      Text(title.toUpperCase(), style: SdType.subheading, textAlign: TextAlign.center),
      const SizedBox(height: SdSpace.xs),
      Text(body, style: SdType.caption, textAlign: TextAlign.center),
      const SizedBox(height: SdSpace.md),
      FilledButton(
        onPressed: onAction,
        style: FilledButton.styleFrom(
          backgroundColor: SdColors.gold,
          foregroundColor: SdColors.ink,
        ),
        child: Text(action.toUpperCase(), style: SdType.label.copyWith(color: SdColors.ink)),
      ),
    ],
  );
}

class _LocationNeeded extends StatelessWidget {
  const _LocationNeeded({required this.access, required this.onAllow});
  final LocationAccess access;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => _Message(
    icon: Icons.location_on_rounded,
    title: access == LocationAccess.serviceOff ? 'Location is off' : 'See cars near you',
    body: access == LocationAccess.serviceOff
        ? 'Turn on location to see which cars were caught around you.'
        : 'Allow location to see where cars were caught around you. Others only ever see the area, never your exact spot.',
    action: switch (access) {
      LocationAccess.denied => 'Allow location',
      LocationAccess.serviceOff => 'Turn on location',
      _ => 'Open settings',
    },
    onAction: onAllow,
  );
}

class _SearchHereButton extends StatelessWidget {
  const _SearchHereButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: SdColors.surfaceRaised,
    shape: StadiumBorder(side: BorderSide(color: SdColors.goldDeep.withValues(alpha: 0.7))),
    child: InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SdSpace.lg, vertical: SdSpace.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh_rounded, size: 16, color: SdColors.gold),
            const SizedBox(width: 6),
            Text(
              'SEARCH THIS AREA',
              style: SdType.label.copyWith(color: SdColors.gold, letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: SdColors.surfaceRaised,
      shape: const CircleBorder(side: BorderSide(color: SdColors.lineStrong)),
      elevation: 6,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: SdSize.minTouch,
          child: Icon(icon, color: SdColors.text, size: 22),
        ),
      ),
    ),
  );
}

/// A glowing pin in the colour of the rarest car caught in the area, with
/// how many different cars were caught there.
class _SpotPin extends StatelessWidget {
  const _SpotPin({required this.tier, required this.count, required this.selected});

  final RarityTier tier;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final core = selected ? 34.0 : 24.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            tier.color.withValues(alpha: selected ? 0.55 : 0.35),
            tier.color.withValues(alpha: 0),
          ],
        ),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: SdMotion.medium,
          width: core,
          height: core,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SdColors.ink,
            border: Border.all(color: tier.color, width: 2.5),
          ),
          child: Text(
            '$count',
            style: SdType.dataSmall.copyWith(
              color: selected ? tier.color : SdColors.text,
              fontWeight: FontWeight.w800,
              fontSize: selected ? 14 : 11,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The player: a blue dot with a slow pulse.
class _MeDot extends StatefulWidget {
  const _MeDot();

  static const blue = Color(0xFF4C8DFF);

  @override
  State<_MeDot> createState() => _MeDotState();
}

class _MeDotState extends State<_MeDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'You are here',
    child: AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 14 + 26 * _pulse.value,
            height: 14 + 26 * _pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _MeDot.blue.withValues(alpha: 0.35 * (1 - _pulse.value)),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _MeDot.blue,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [BoxShadow(color: _MeDot.blue.withValues(alpha: 0.6), blurRadius: 8)],
            ),
          ),
        ],
      ),
    ),
  );
}
