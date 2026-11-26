// AlexLMP Revived: Material 3 Expressive UI.
//
// Colours come from what's playing (dynamic colour), bold shapes that morph,
// squishy springy buttons, wavy progress, and a bunch of player styles.

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'main.dart';
import 'revived_shell.dart';

// ═══════════════════════════════ Dynamic colour ═══════════════════════════════

const Color kXpDefaultSeed = Color(0xFFFF8A50);

ColorScheme _xpSchemeFor(Color seed) => AppPalette.scheme(seed);

final ValueNotifier<ColorScheme> xpScheme =
    ValueNotifier<ColorScheme>(_xpSchemeFor(kXpDefaultSeed));

bool _xpInited = false;
int _xpSeq = 0;

/// Call once at start-up. Keeps [xpScheme] in step with the playing song.
void xpInit() {
  if (_xpInited) return;
  _xpInited = true;
  audioHandler.currentIndex.addListener(xpRefreshColors);
  appState.addListener(_xpSettingsChanged);
  xpRefreshColors();
  unawaited(xpEqRestore());
}

String _xpLastColorKey = '';
void _xpSettingsChanged() {
  final k = '${appState.b('xp_dynamic', true)}_${appState.str('xp_seed', '')}';
  if (k != _xpLastColorKey) {
    _xpLastColorKey = k;
    xpRefreshColors();
  }
}

Color xpFixedSeed() {
  final s = appState.str('xp_seed', '');
  final v = int.tryParse(s, radix: 16);
  return v == null ? kXpDefaultSeed : Color(v);
}

Future<void> xpRefreshColors() async {
  final my = ++_xpSeq;
  if (!appState.b('xp_dynamic', true)) {
    xpScheme.value = _xpSchemeFor(xpFixedSeed());
    return;
  }
  final t = audioHandler.currentTrack;
  if (t == null) {
    xpScheme.value = _xpSchemeFor(xpFixedSeed());
    return;
  }
  final now = artSeedNow(t);
  if (now != null) {
    xpScheme.value = _xpSchemeFor(now);
    return;
  }
  try {
    final c = await artSeedFor(t);
    if (my == _xpSeq) xpScheme.value = _xpSchemeFor(c);
  } catch (_) {}
}

ThemeData xpThemeData(ColorScheme cs) => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: cs.onSurface,
            displayColor: cs.onSurface,
          ),
      sliderTheme: SliderThemeData(
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withOpacity(0.12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: cs.outline,
      ),
    );

/// Wraps a screen in the live, animated dynamic-colour theme.
class XpThemed extends StatelessWidget {
  final Widget child;
  const XpThemed({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ColorScheme>(
      valueListenable: xpScheme,
      builder: (context, cs, _) => AnimatedTheme(
        data: xpThemeData(cs),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

extension XpCtx on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
}

TextStyle xpT(double size,
        {FontWeight w = FontWeight.w600, Color? c, double? ls, double? h}) =>
    TextStyle(
      fontSize: size,
      fontWeight: w,
      color: c,
      letterSpacing: ls ?? (size >= 22 ? -0.6 : (size >= 16 ? -0.2 : 0)),
      height: h,
    );

// ═══════════════════════════════ Shapes ═══════════════════════════════
// Material 3 Expressive shapes, drawn as polar curves so any two can morph.

enum XpShape { circle, square, cookie4, cookie6, cookie9, cookie12, clover, burst, flower, ghost, pill }

const List<XpShape> kXpCardShapes = [
  XpShape.cookie9,
  XpShape.clover,
  XpShape.square,
  XpShape.flower,
  XpShape.cookie12,
  XpShape.ghost,
  XpShape.burst,
  XpShape.cookie6,
];

double _xpR(XpShape s, double t) {
  switch (s) {
    case XpShape.circle:
      return 1;
    case XpShape.square:
      // Rounded square (superellipse).
      final c = cos(t).abs(), sn = sin(t).abs();
      return pow(pow(c, 7) + pow(sn, 7), -1 / 7).toDouble() / 1.0;
    case XpShape.pill:
      final c = cos(t).abs(), sn = sin(t).abs();
      return pow(pow(c, 4) + pow(sn, 4), -0.25).toDouble();
    case XpShape.cookie4:
      return 0.88 + 0.12 * cos(4 * t);
    case XpShape.cookie6:
      return 0.9 + 0.1 * cos(6 * t);
    case XpShape.cookie9:
      return 0.91 + 0.09 * cos(9 * t);
    case XpShape.cookie12:
      return 0.94 + 0.06 * cos(12 * t);
    case XpShape.clover:
      return 0.74 + 0.26 * pow(cos(2 * t).abs(), 0.6).toDouble();
    case XpShape.burst:
      final v = cos(8 * t);
      return 0.84 + 0.16 * v * v * v;
    case XpShape.flower:
      return 0.8 + 0.2 * cos(6 * t);
    case XpShape.ghost:
      return 0.89 + 0.11 * cos(5 * t);
  }
}

double _xpMaxR(XpShape s) => s == XpShape.square ? sqrt2 * 0.95 : 1.0;

Path xpShapePath(Size size, XpShape a, XpShape b, double mix, {double rot = 0}) {
  final p = Path();
  final cx = size.width / 2, cy = size.height / 2;
  const n = 180;
  // Normalise so each shape just fills the box.
  double norm(XpShape s, double t) {
    final r = _xpR(s, t);
    if (s == XpShape.square || s == XpShape.pill) return r;
    return r;
  }

  for (var i = 0; i <= n; i++) {
    final t = 2 * pi * i / n;
    final tt = t + rot;
    final ra = norm(a, tt), rb = norm(b, tt);
    var r = ra + (rb - ra) * mix;
    var x = cos(t) * r, y = sin(t) * r;
    // Superellipse radii can exceed 1 on the diagonal; keep in box.
    x = x.clamp(-1.0, 1.0);
    y = y.clamp(-1.0, 1.0);
    final px = cx + size.width / 2 * x;
    final py = cy + size.height / 2 * y;
    if (i == 0) {
      p.moveTo(px, py);
    } else {
      p.lineTo(px, py);
    }
  }
  return p..close();
}

class XpShapeClipper extends CustomClipper<Path> {
  final XpShape a;
  final XpShape b;
  final double mix;
  final double rot;
  XpShapeClipper(this.a, [XpShape? b, this.mix = 0, this.rot = 0]) : b = b ?? a;
  @override
  Path getClip(Size size) {
    if (a == b && a == XpShape.circle) return Path()..addOval(Offset.zero & size);
    return xpShapePath(size, a, b, mix, rot: rot);
  }

  @override
  bool shouldReclip(XpShapeClipper o) =>
      o.a != a || o.b != b || o.mix != mix || o.rot != rot;
}

class XpShaped extends StatelessWidget {
  final XpShape shape;
  final Widget child;
  final double? size;
  final double rot;
  const XpShaped(
      {super.key, required this.shape, required this.child, this.size, this.rot = 0});
  @override
  Widget build(BuildContext context) {
    final c = ClipPath(clipper: XpShapeClipper(shape, shape, 0, rot), child: child);
    return size == null ? c : SizedBox(width: size, height: size, child: c);
  }
}

/// A shape that morphs (with a springy overshoot) whenever [shape] changes.
class XpMorph extends StatefulWidget {
  final XpShape shape;
  final Widget child;
  final double rot;
  final Duration duration;
  const XpMorph({
    super.key,
    required this.shape,
    required this.child,
    this.rot = 0,
    this.duration = const Duration(milliseconds: 520),
  });
  @override
  State<XpMorph> createState() => _XpMorphState();
}

class _XpMorphState extends State<XpMorph> with SingleTickerProviderStateMixin {
  late XpShape _from = widget.shape;
  late XpShape _to = widget.shape;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration, value: 1);

  @override
  void didUpdateWidget(XpMorph old) {
    super.didUpdateWidget(old);
    if (old.shape != widget.shape) {
      _from = _to;
      _to = widget.shape;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final m = Curves.easeOutBack.transform(_c.value);
        return ClipPath(
          clipper: XpShapeClipper(_from, _to, m, widget.rot),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════ Squish ═══════════════════════════════

/// Squishes on press (wider, shorter) then springs back with a wobble.
class XpPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double amount;
  final bool haptic;
  const XpPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.amount = 1,
    this.haptic = true,
  });
  @override
  State<XpPress> createState() => _XpPressState();
}

class _XpPressState extends State<XpPress> with SingleTickerProviderStateMixin {
  late final AnimationController _p = AnimationController.unbounded(vsync: this, value: 0);
  static const _spring = SpringDescription(mass: 1, stiffness: 520, damping: 14);

  void _down() {
    _p.animateTo(1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut);
  }

  void _up() {
    _p.animateWith(SpringSimulation(_spring, _p.value, 0, -4));
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _down() : null,
      onTapUp: enabled ? (_) => _up() : null,
      onTapCancel: enabled ? _up : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              _up();
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _p,
        builder: (context, child) {
          final v = _p.value * widget.amount;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(1 - 0.05 * v, 1 - 0.11 * v, 1),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Pops in with a little spring when first shown (lists, cards).
class XpPopIn extends StatefulWidget {
  final Widget child;
  final int index;
  const XpPopIn({super.key, required this.child, this.index = 0});
  @override
  State<XpPopIn> createState() => _XpPopInState();
}

class _XpPopInState extends State<XpPopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 30 * min(widget.index, 10)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - v)),
            child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Round/square tonal icon button with squish.
class XpIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? bg;
  final Color? fg;
  final double? radius;
  final String? tip;
  const XpIconBtn(this.icon,
      {super.key, this.onTap, this.size = 44, this.bg, this.fg, this.radius, this.tip});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final b = XpPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius ?? size / 2),
        ),
        child: Icon(icon, size: size * 0.48, color: fg ?? cs.onSurface),
      ),
    );
    return tip == null ? b : Tooltip(message: tip!, child: b);
  }
}

// ═══════════════════════════════ Art ═══════════════════════════════

String? xpHiRes(String? url) {
  if (url == null) return null;
  // YouTube Music thumbnails: ask for a big version.
  final m = RegExp(r'=w\d+-h\d+').firstMatch(url);
  if (m != null) return url.replaceFirst(m.group(0)!, '=w720-h720');
  if (url.contains('i.ytimg.com') && url.contains('/default')) {
    return url.replaceFirst(RegExp(r'/(mq|hq|sd)?default'), '/hqdefault');
  }
  return url;
}

Widget xpTrackArt(TrackItem t, {bool hiRes = false}) {
  final url = hiRes ? xpHiRes(t.artworkUrl) : t.artworkUrl;
  final fallback = FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(width: 200, height: 200, child: CustomAlbumArtwork(track: t)),
  );
  if (url == null || url.isEmpty) return fallback;
  return Image.network(
    url,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => hiRes && t.artworkUrl != null
        ? Image.network(t.artworkUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
        : fallback,
  );
}

Widget xpUrlArt(String? url, {IconData icon = Icons.music_note_rounded}) {
  return Builder(builder: (context) {
    final cs = context.cs;
    final fb = Container(
      color: cs.surfaceContainerHighest,
      child: Icon(icon, color: cs.onSurfaceVariant, size: 28),
    );
    if (url == null || url.isEmpty) return fb;
    return Image.network(url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fb);
  });
}

// ═══════════════════════════════ Wavy progress ═══════════════════════════════

class _XpWavePainter extends CustomPainter {
  final double frac;
  final double phase;
  final double amp;
  final Color active;
  final Color rest;
  final double stroke;
  final double wavelength;
  final bool thumb;
  _XpWavePainter({
    required this.frac,
    required this.phase,
    required this.amp,
    required this.active,
    required this.rest,
    required this.stroke,
    this.wavelength = 30,
    this.thumb = true,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final y = s.height / 2;
    final x1 = (s.width * frac.clamp(0.0, 1.0));
    final gap = thumb ? 6.0 : 3.0;
    final pa = Paint()
      ..color = active
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final endWave = max(0.0, x1 - gap);
    for (double x = stroke / 2; x <= endWave; x += 1) {
      final yy = y + amp * sin(2 * pi * x / wavelength - phase);
      if (x <= stroke / 2) {
        path.moveTo(x, yy);
      } else {
        path.lineTo(x, yy);
      }
    }
    if (endWave > stroke / 2) canvas.drawPath(path, pa);
    final pr = Paint()
      ..color = rest
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (x1 + gap < s.width - stroke / 2) {
      canvas.drawLine(Offset(x1 + gap, y), Offset(s.width - stroke / 2, y), pr);
    }
    // Stop dot at the end.
    canvas.drawCircle(Offset(s.width - stroke / 2, y), stroke / 2, Paint()..color = active);
    if (thumb) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x1, y), width: stroke * 0.9, height: s.height * 0.9),
              Radius.circular(stroke)),
          Paint()..color = active);
    }
  }

  @override
  bool shouldRepaint(_XpWavePainter o) =>
      o.frac != frac || o.phase != phase || o.amp != amp || o.active != active || o.rest != rest;
}

/// Material 3 Expressive wavy seek bar: wiggles while playing, flattens on
/// pause, drag to seek.
class XpWaveSeek extends StatefulWidget {
  final double height;
  final double stroke;
  final bool showTimes;
  final bool interactive;
  final Color? active;
  final Color? rest;
  const XpWaveSeek({
    super.key,
    this.height = 30,
    this.stroke = 5,
    this.showTimes = true,
    this.interactive = true,
    this.active,
    this.rest,
  });
  @override
  State<XpWaveSeek> createState() => _XpWaveSeekState();
}

class _XpWaveSeekState extends State<XpWaveSeek> with TickerProviderStateMixin {
  late final AnimationController _phase =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _amp =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  StreamSubscription<bool>? _sub;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _sync(audioHandler.player.playing);
    _sub = audioHandler.player.playingStream.listen(_sync);
  }

  void _sync(bool playing) {
    if (!mounted) return;
    if (playing) {
      if (!_phase.isAnimating) _phase.repeat();
      _amp.animateTo(1, curve: Curves.easeOutBack);
    } else {
      _amp.animateTo(0, curve: Curves.easeOut).whenComplete(() {
        if (mounted && !audioHandler.player.playing) _phase.stop();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<Duration>(
      stream: audioHandler.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? audioHandler.player.position;
        final t = audioHandler.currentTrack;
        final dur = audioHandler.player.duration ??
            Duration(seconds: max(1, t?.durationSeconds ?? 1));
        final total = max(1, dur.inMilliseconds);
        final frac = _drag ?? (pos.inMilliseconds / total).clamp(0.0, 1.0);
        final shown = Duration(milliseconds: (frac * total).round());
        return LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          double at(double x) => (x / w).clamp(0.0, 1.0);
          void commit() {
            final d = _drag;
            if (d != null) audioHandler.seek(Duration(milliseconds: (d * total).round()));
            setState(() => _drag = null);
          }

          final bar = AnimatedBuilder(
            animation: Listenable.merge([_phase, _amp]),
            builder: (context, _) => CustomPaint(
              size: Size(w, widget.height),
              painter: _XpWavePainter(
                frac: frac,
                phase: _phase.value * 2 * pi,
                amp: (widget.height * 0.14) * _amp.value * (_drag != null ? 0.4 : 1),
                active: widget.active ?? cs.primary,
                rest: widget.rest ?? cs.surfaceContainerHighest,
                stroke: _drag != null ? widget.stroke + 2 : widget.stroke,
                wavelength: widget.height * 1.2,
                thumb: widget.interactive,
              ),
            ),
          );
          final body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: widget.height, width: w, child: bar),
              if (widget.showTimes)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Text(formatDuration(shown),
                        style: xpT(12, c: cs.onSurfaceVariant, w: FontWeight.w600)),
                    const Spacer(),
                    Text(formatDuration(dur),
                        style: xpT(12, c: cs.onSurfaceVariant, w: FontWeight.w600)),
                  ]),
                ),
            ],
          );
          if (!widget.interactive) return body;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              HapticFeedback.selectionClick();
              setState(() => _drag = at(d.localPosition.dx));
            },
            onHorizontalDragUpdate: (d) => setState(() => _drag = at(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => commit(),
            onTapUp: (d) {
              _drag = at(d.localPosition.dx);
              commit();
            },
            child: body,
          );
        });
      },
    );
  }
}

// ═══════════════════════════════ Shared helpers ═══════════════════════════════

Route<T> xpRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => XpThemed(child: page),
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    );

void xpOpenShelf(BuildContext context, YtShelfItem it) {
  HapticFeedback.selectionClick();
  if (it.kind == 'album') {
    Navigator.of(context).push(xpRoute(RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail)));
  } else if (it.kind == 'artist') {
    Navigator.of(context).push(xpRoute(RevivedArtistPage(url: it.id, name: it.title, initialThumb: it.thumbnail)));
  } else if (it.kind == 'playlist') {
    Navigator.of(context).push(xpRoute(RevivedPlaylistPage.youtube(playlistId: it.id, title: it.title, thumbnail: it.thumbnail)));
  } else {
    final t = YouTubeMusic.trackFromShelf(it, it.subtitle);
    audioHandler.playYouTubeTrack(t);
  }
}

void xpPlay(List<TrackItem> list, int i, {bool shuffle = false}) {
  if (list.isEmpty) return;
  audioHandler.setShuffleMode(shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none);
  audioHandler.playYouTubeList(list, shuffle ? Random().nextInt(list.length) : i);
}

List<TrackItem> xpLikedTracks() {
  final yt = YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music')?.tracks ?? const <TrackItem>[];
  final local = audioHandler.tracks.where((t) => appState.isLiked(t.id)).toList();
  final seen = <String>{};
  return [
    for (final t in [...yt, ...local])
      if (seen.add(t.id)) t
  ];
}

void xpSnack(BuildContext context, String msg) {
  final cs = context.cs;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(msg, style: xpT(14, c: cs.onInverseSurface)),
    backgroundColor: cs.inverseSurface,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    duration: const Duration(seconds: 2),
  ));
}

/// A list row for a song.
class XpSongRow extends StatelessWidget {
  final TrackItem track;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? leading;
  final XpShape shape;
  const XpSongRow({
    super.key,
    required this.track,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.shape = XpShape.square,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final playing = audioHandler.currentTrack?.id == track.id;
    return XpPress(
      amount: 0.5,
      onTap: onTap,
      onLongPress: () => showRevivedTrackMenu(context, track),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          XpShaped(shape: shape, size: 52, child: xpTrackArt(track)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: xpT(15.5, c: playing ? cs.primary : cs.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle ?? track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (playing) ...[
            XpEqBars(color: cs.primary),
            const SizedBox(width: 4),
          ],
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant),
            onPressed: () => showRevivedTrackMenu(context, track),
          ),
        ]),
      ),
    );
  }
}

/// Little bouncing bars for the playing song.
class XpEqBars extends StatefulWidget {
  final Color color;
  const XpEqBars({super.key, required this.color});
  @override
  State<XpEqBars> createState() => _XpEqBarsState();
}

class _XpEqBarsState extends State<XpEqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      initialData: audioHandler.player.playing,
      builder: (context, s) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final on = s.data ?? false;
          return SizedBox(
            width: 18,
            height: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 4,
                    height: on ? 4 + 12 * (0.5 + 0.5 * sin(2 * pi * _c.value + i * 2.1)).abs() : 4,
                    decoration: BoxDecoration(
                        color: widget.color, borderRadius: BorderRadius.circular(2)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Section header: title + optional action.
Widget xpSection(BuildContext context, String title, {String? action, VoidCallback? onAction}) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
    child: Row(children: [
      Expanded(child: Text(title, style: xpT(21, w: FontWeight.w700))),
      if (action != null)
        XpPress(
          onTap: onAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(action, style: xpT(14, c: cs.primary, w: FontWeight.w700)),
          ),
        ),
    ]),
  );
}

/// Filter chip with a check that pops in.
class XpChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const XpChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return XpPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 15),
        decoration: BoxDecoration(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(selected ? 18 : 10),
          border: Border.all(color: selected ? cs.secondaryContainer : cs.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.check_rounded, size: 18, color: cs.onSecondaryContainer),
                  )
                : (icon != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
                      )
                    : const SizedBox.shrink()),
          ),
          Text(label,
              style: xpT(13.5,
                  c: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════ Shell ═══════════════════════════════

class XpShell extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const XpShell({super.key, this.aiChatBuilder});
  @override
  State<XpShell> createState() => _XpShellState();
}

class _XpShellState extends State<XpShell> {
  int _tab = 0;
  int _dir = 1;
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    xpInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkRevivedUpdate(context);
    });
  }

  void _go(int i) {
    if (i == _tab) return;
    setState(() {
      _dir = i > _tab ? 1 : -1;
      _tab = i;
      _visited.add(i);
    });
  }

  Widget _page(int i) {
    switch (i) {
      case 1:
        return const XpSearchPage();
      case 2:
        return const XpLibraryPage();
      case 3:
        return XpYouPage(aiChatBuilder: widget.aiChatBuilder);
      default:
        return XpHomePage(aiChatBuilder: widget.aiChatBuilder, onGoTab: _go);
    }
  }

  @override
  Widget build(BuildContext context) {
    return XpThemed(
      child: Builder(builder: (context) {
        final cs = context.cs;
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: cs.surfaceContainer,
          systemNavigationBarIconBrightness: Brightness.light,
        ));
        return PopScope(
          canPop: _tab == 0,
          onPopInvoked: (did) {
            if (!did) _go(0);
          },
          child: Scaffold(
            backgroundColor: cs.surface,
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                // Soft colour wash from the playing song at the top.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 380,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 700),
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -1.2),
                          radius: 1.3,
                          colors: [cs.primaryContainer.withOpacity(0.55), cs.surface.withOpacity(0)],
                        ),
                      ),
                    ),
                  ),
                ),
                for (final i in (_visited.toList()..sort()))
                  Positioned.fill(
                    key: ValueKey('xptab$i'),
                    child: Offstage(
                      offstage: i != _tab,
                      child: TickerMode(
                        enabled: i == _tab,
                        child: _XpTabIn(active: i == _tab, dir: _dir.toDouble(), child: _page(i)),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const XpMiniPlayer(),
                      XpNavBar(index: _tab, onSelect: _go),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

double xpBottomPad(BuildContext context) =>
    MediaQuery.of(context).padding.bottom + 80 + (audioHandler.currentTrack != null ? 82 : 0) + 16;

class _XpTabIn extends StatefulWidget {
  final bool active;
  final double dir;
  final Widget child;
  const _XpTabIn({required this.active, required this.dir, required this.child});
  @override
  State<_XpTabIn> createState() => _XpTabInState();
}

class _XpTabInState extends State<_XpTabIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380), value: 1);
  @override
  void didUpdateWidget(_XpTabIn old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        final s = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(28 * widget.dir * (1 - s), 0),
            child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ── Navigation bar: pill indicator that stretches open, icons squish ──
class XpNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const XpNavBar({super.key, required this.index, required this.onSelect});

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.search_rounded, Icons.saved_search_rounded, 'Search'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'You'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      color: cs.surfaceContainer,
      padding: EdgeInsets.only(top: 10, bottom: bottom + 10),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: XpPress(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelect(i);
                },
                haptic: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeOutBack,
                            width: i == index ? 64 : 18,
                            height: 32,
                            decoration: BoxDecoration(
                              color: i == index ? cs.secondaryContainer : cs.secondaryContainer.withOpacity(0),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          AnimatedScale(
                            scale: i == index ? 1.08 : 1,
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutBack,
                            child: Icon(i == index ? _items[i].$2 : _items[i].$1,
                                size: 24,
                                color: i == index ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: xpT(12,
                          w: i == index ? FontWeight.w800 : FontWeight.w600,
                          c: i == index ? cs.onSurface : cs.onSurfaceVariant),
                      child: Text(_items[i].$3),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Floating mini player ──
class XpMiniPlayer extends StatefulWidget {
  const XpMiniPlayer({super.key});
  @override
  State<XpMiniPlayer> createState() => _XpMiniPlayerState();
}

class _XpMiniPlayerState extends State<XpMiniPlayer> with TickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this, value: 0);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = audioHandler.player.playingStream.listen((p) {
      if (!mounted) return;
      if (p) {
        _spin.repeat();
      } else {
        _spin.stop();
      }
    });
    if (audioHandler.player.playing) _spin.repeat();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dx.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _end(double v) {
    final x = _dx.value;
    if (x < -70 || v < -600) {
      HapticFeedback.lightImpact();
      audioHandler.skipToNext();
    } else if (x > 70 || v > 600) {
      HapticFeedback.lightImpact();
      audioHandler.skipToPrevious();
    }
    _dx.animateWith(SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 380, damping: 18), x, 0, v / 400));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ValueListenableBuilder<int>(
      valueListenable: audioHandler.currentIndex,
      builder: (context, _, __) {
        final t = audioHandler.currentTrack;
        return AnimatedSize(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          child: t == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: GestureDetector(
                    onTap: () => openPlayer(context),
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -250) openPlayer(context);
                    },
                    onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
                    onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
                    child: AnimatedBuilder(
                      animation: _dx,
                      builder: (context, child) {
                        final k = (_dx.value.abs() / 300).clamp(0.0, 0.2);
                        return Transform.translate(
                          offset: Offset(_dx.value * 0.6, 0),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(1 - k * 0.3, 1 - k * 0.5, 1),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        height: 70,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8)),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 10),
                                AnimatedBuilder(
                                  animation: _spin,
                                  builder: (context, child) => XpShaped(
                                    shape: XpShape.cookie9,
                                    rot: _spin.value * 2 * pi,
                                    size: 48,
                                    child: child!,
                                  ),
                                  child: xpTrackArt(t),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 380),
                                    transitionBuilder: (c, a) => FadeTransition(
                                      opacity: a,
                                      child: SlideTransition(
                                        position: Tween(begin: const Offset(0, 0.5), end: Offset.zero)
                                            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                                        child: c,
                                      ),
                                    ),
                                    child: Column(
                                      key: ValueKey(t.id),
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15)),
                                        Text(t.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ),
                                XpPlayButton(size: 48),
                                const SizedBox(width: 2),
                                IconButton(
                                  icon: Icon(Icons.skip_next_rounded, color: cs.onSurface, size: 28),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    audioHandler.skipToNext();
                                  },
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                            const Positioned(
                              left: 16,
                              right: 16,
                              bottom: 3,
                              child: XpWaveSeek(height: 8, stroke: 2.6, showTimes: false, interactive: false),
                            ),
                          ],
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

/// Play / pause button that morphs between a cookie (paused) and a rounded
/// square (playing), squishing when pressed.
class XpPlayButton extends StatelessWidget {
  final double size;
  final double? width;
  final Color? bg;
  final Color? fg;
  final XpShape playingShape;
  final XpShape pausedShape;
  const XpPlayButton({
    super.key,
    this.size = 64,
    this.width,
    this.bg,
    this.fg,
    this.playingShape = XpShape.square,
    this.pausedShape = XpShape.cookie9,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final st = snap.data;
        final playing = st?.playing ?? audioHandler.player.playing;
        final loading = st?.processingState == AudioProcessingState.loading ||
            st?.processingState == AudioProcessingState.buffering;
        return XpPress(
          onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
          child: XpMorph(
            shape: playing ? playingShape : pausedShape,
            child: Container(
              width: width ?? size,
              height: size,
              color: bg ?? cs.primary,
              alignment: Alignment.center,
              child: loading
                  ? SizedBox(
                      width: size * 0.36,
                      height: size * 0.36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: fg ?? cs.onPrimary))
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (c, a) => ScaleTransition(
                          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                      child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        key: ValueKey(playing),
                        size: size * 0.5,
                        color: fg ?? cs.onPrimary,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════ Home ═══════════════════════════════

class XpHomePage extends StatefulWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  final ValueChanged<int> onGoTab;
  const XpHomePage({super.key, this.aiChatBuilder, required this.onGoTab});
  @override
  State<XpHomePage> createState() => _XpHomePageState();
}

class _XpHomePageState extends State<XpHomePage> {
  late Future<List<YtShelf>> _feed = YouTubeMusic.homeFeed();
  final PageController _car = PageController(viewportFraction: 0.72);

  @override
  void initState() {
    super.initState();
    _preloadLiked();
  }

  Future<void> _preloadLiked() async {
    try {
      await YouTubeMusic.playlistPage('LM', title: 'Liked Music');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _car.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Up late';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _refresh() async {
    setState(() => _feed = YouTubeMusic.homeFeed(refresh: true));
    try {
      await _feed;
    } catch (_) {}
  }

  void _openAi(BuildContext context) {
    final b = widget.aiChatBuilder;
    if (b == null) return;
    Navigator.of(context).push(xpRoute(Scaffold(body: b(appState.palette))));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount, LibraryStore.revision, audioHandler.currentIndex]),
      builder: (context, _) {
        final yt = appState.homeMode == 'youtube';
        final acct = ytAccount.value;
        final name = acct.signedIn ? (acct.name ?? '').split(' ').first : '';
        return RefreshIndicator(
          onRefresh: _refresh,
          color: cs.primary,
          backgroundColor: cs.surfaceContainerHigh,
          edgeOffset: top,
          child: ListView(
            padding: EdgeInsets.only(top: top + 8, bottom: xpBottomPad(context)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 14, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting, style: xpT(14, c: cs.onSurfaceVariant)),
                        Text(name.isEmpty ? 'AlexLMP' : 'Hey $name', style: xpT(32, w: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (widget.aiChatBuilder != null)
                    XpIconBtn(Icons.auto_awesome_rounded,
                        tip: 'Ask AI', bg: cs.tertiaryContainer, fg: cs.onTertiaryContainer, radius: 16,
                        onTap: () => _openAi(context)),
                  const SizedBox(width: 8),
                  XpPress(
                    onTap: () => widget.onGoTab(3),
                    child: XpShaped(
                      shape: XpShape.cookie9,
                      size: 46,
                      child: Container(
                        color: cs.primaryContainer,
                        alignment: Alignment.center,
                        child: acct.signedIn && acct.photo != null
                            ? Image.network(acct.photo!, fit: BoxFit.cover, width: 46, height: 46,
                                errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: cs.onPrimaryContainer))
                            : Icon(Icons.person_rounded, color: cs.onPrimaryContainer),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: _XpSegmented(
                  options: const ['YouTube Music', 'On device'],
                  index: yt ? 0 : 1,
                  onChanged: (i) => appState.setStr('home_mode', i == 0 ? 'youtube' : 'local'),
                ),
              ),
              _carousel(context, yt),
              _quickGroup(context, yt),
              const _XpWeekCard(),
              if (yt) _ytShelves(context) else ..._localShelves(context),
            ],
          ),
        );
      },
    );
  }

  // Hero carousel: what's playing + recent things, cards grow as they centre.
  Widget _carousel(BuildContext context, bool yt) {
    final cs = context.cs;
    final items = <(Widget, String, String, VoidCallback)>[];
    final cur = audioHandler.currentTrack;
    if (cur != null) {
      items.add((xpTrackArt(cur, hiRes: true), cur.title, 'Continue · ${cur.artist}', () => openPlayer(context)));
    }
    for (final id in appState.recent.take(8)) {
      final t = audioHandler.trackById(id);
      if (t == null || t.id == cur?.id) continue;
      items.add((xpTrackArt(t, hiRes: true), t.title, t.artist, () => audioHandler.playYouTubeTrack(t)));
    }
    if (yt) {
      final feed = YouTubeMusic.cachedHomeFeed();
      for (final sh in feed ?? const <YtShelf>[]) {
        for (final it in sh.items.where((i) => i.kind != 'video').take(3)) {
          items.add((xpUrlArt(xpHiRes(it.thumbnail)), it.title, it.subtitle, () => xpOpenShelf(context, it)));
        }
        if (items.length > 10) break;
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 230,
      child: PageView.builder(
        controller: _car,
        padEnds: false,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (art, title, sub, tap) = items[i];
          return AnimatedBuilder(
            animation: _car,
            builder: (context, child) {
              double page = 0;
              try {
                page = _car.hasClients && _car.position.haveDimensions ? (_car.page ?? 0) : 0;
              } catch (_) {}
              final d = (page - i).abs().clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 4, 8 + 18 * d, 4, 8 + 18 * d),
                child: ClipRRect(borderRadius: BorderRadius.circular(28 + 12 * d), child: child),
              );
            },
            child: XpPress(
              onTap: tap,
              amount: 0.6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                        stops: const [0.4, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sub.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: xpT(11, c: Colors.white70, ls: 0.8, w: FontWeight.w700)),
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: xpT(20, c: Colors.white, w: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (i == 0 && cur != null)
                    Positioned(right: 12, top: 12, child: XpPlayButton(size: 46)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _quickGroup(BuildContext context, bool yt) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: XpButtonGroup(items: [
        XpGroupItem(Icons.shuffle_rounded, 'Shuffle', cs.primary, cs.onPrimary, () {
          final list = yt ? xpLikedTracks() : audioHandler.tracks.where((t) => !t.isYouTube).toList();
          if (list.isEmpty) {
            xpSnack(context, 'Nothing to shuffle yet');
            return;
          }
          xpPlay(list, 0, shuffle: true);
          openPlayer(context);
        }, weight: 1.3),
        XpGroupItem(Icons.favorite_rounded, 'Liked', cs.secondaryContainer, cs.onSecondaryContainer, () {
          Navigator.of(context).push(xpRoute(yt
              ? const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music')
              : RevivedPlaylistPage.custom(title: 'Liked songs', tracks: xpLikedTracks(), isLikedStyle: true)));
        }),
        XpGroupItem(Icons.graphic_eq_rounded, 'AI DJ', cs.tertiaryContainer, cs.onTertiaryContainer, () {
          startOrStepAiDj(openInPlayer: context);
        }),
      ]),
    );
  }

  Widget _ytShelves(BuildContext context) {
    return FutureBuilder<List<YtShelf>>(
      future: _feed,
      initialData: YouTubeMusic.cachedHomeFeed(),
      builder: (context, snap) {
        final shelves = snap.data ?? const <YtShelf>[];
        if (shelves.isEmpty) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(40), child: Center(child: XpLoading()));
          }
          return _XpEmpty(
            icon: Icons.cloud_off_rounded,
            title: ytAccount.value.signedIn ? "Couldn't load your feed" : 'Sign in to YouTube Music',
            sub: ytAccount.value.signedIn ? 'Pull down to try again.' : 'Get your mixes, likes and playlists here.',
            action: ytAccount.value.signedIn ? null : ('Sign in', () => showYtAccountSheet(context)),
          );
        }
        var k = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final sh in shelves)
              if (sh.items.isNotEmpty) XpShelf(shelf: sh, shapeIndex: k++),
          ],
        );
      },
    );
  }

  List<Widget> _localShelves(BuildContext context) {
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    if (local.isEmpty) {
      return [
        _XpEmpty(
          icon: Icons.folder_open_rounded,
          title: 'No music on this phone yet',
          sub: 'Add a folder in You › Settings, or switch to YouTube Music.',
        ),
      ];
    }
    final recent = [
      for (final id in appState.recent)
        if (audioHandler.trackById(id) case final t?) if (!t.isYouTube) t
    ];
    final byAlbum = <String, List<TrackItem>>{};
    for (final t in local) {
      byAlbum.putIfAbsent(t.album, () => []).add(t);
    }
    final albums = byAlbum.entries.toList();
    return [
      if (recent.isNotEmpty) ...[
        xpSection(context, 'Jump back in'),
        _cardRow([
          for (var i = 0; i < min(12, recent.length); i++)
            XpCard(
              art: xpTrackArt(recent[i]),
              title: recent[i].title,
              sub: recent[i].artist,
              shape: kXpCardShapes[i % kXpCardShapes.length],
              onTap: () => xpPlay(recent, i),
            ),
        ]),
      ],
      if (appState.playlists.isNotEmpty) ...[
        xpSection(context, 'Your playlists'),
        _cardRow([
          for (var i = 0; i < appState.playlists.length; i++)
            XpCard(
              art: Container(
                color: context.cs.secondaryContainer,
                child: Icon(Icons.queue_music_rounded, color: context.cs.onSecondaryContainer, size: 40),
              ),
              title: appState.playlists[i].name,
              sub: '${appState.playlists[i].trackIds.length} songs',
              shape: kXpCardShapes[(i + 3) % kXpCardShapes.length],
              onTap: () => Navigator.of(context).push(xpRoute(RevivedPlaylistPage.local(playlist: appState.playlists[i]))),
            ),
        ]),
      ],
      xpSection(context, 'Albums'),
      _cardRow([
        for (var i = 0; i < min(20, albums.length); i++)
          XpCard(
            art: xpTrackArt(albums[i].value.first),
            title: albums[i].key,
            sub: albums[i].value.first.artist,
            shape: XpShape.square,
            onTap: () => Navigator.of(context).push(xpRoute(RevivedPlaylistPage.custom(
                title: albums[i].key, subtitle: albums[i].value.first.artist, tracks: albums[i].value))),
          ),
      ]),
    ];
  }
}

Widget _cardRow(List<Widget> cards) => SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => XpPopIn(index: i, child: cards[i]),
      ),
    );

/// One YouTube Music home shelf: songs as a list, everything else as cards.
class XpShelf extends StatelessWidget {
  final YtShelf shelf;
  final int shapeIndex;
  const XpShelf({super.key, required this.shelf, required this.shapeIndex});
  @override
  Widget build(BuildContext context) {
    final songs = shelf.kind == 'song' || shelf.items.every((i) => i.kind == 'video');
    if (songs) {
      final list = [for (final it in shelf.items) YouTubeMusic.trackFromShelf(it, it.subtitle)];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          xpSection(context, shelf.title.isEmpty ? 'For you' : shelf.title,
              action: list.length > 4 ? 'Play all' : null, onAction: () {
            xpPlay(list, 0);
            openPlayer(context);
          }),
          for (var i = 0; i < min(4, list.length); i++)
            XpPopIn(
              index: i,
              child: XpSongRow(
                track: list[i],
                shape: i.isEven ? XpShape.square : XpShape.cookie12,
                onTap: () => xpPlay(list, i),
              ),
            ),
        ],
      );
    }
    final shape = kXpCardShapes[shapeIndex % kXpCardShapes.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        xpSection(context, shelf.title.isEmpty ? 'For you' : shelf.title),
        _cardRow([
          for (final it in shelf.items)
            XpCard(
              art: xpUrlArt(it.thumbnail),
              title: it.title,
              sub: it.subtitle,
              shape: it.kind == 'artist' ? XpShape.circle : shape,
              onTap: () => xpOpenShelf(context, it),
            ),
        ]),
      ],
    );
  }
}

class XpCard extends StatelessWidget {
  final Widget art;
  final String title;
  final String sub;
  final XpShape shape;
  final VoidCallback onTap;
  final double size;
  const XpCard({
    super.key,
    required this.art,
    required this.title,
    required this.sub,
    required this.shape,
    required this.onTap,
    this.size = 136,
  });
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return XpPress(
      onTap: onTap,
      amount: 0.7,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            XpShaped(shape: shape, size: size, child: art),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: xpT(12.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Connected button group: the pressed button grows, its neighbours make room.
class XpGroupItem {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final double weight;
  const XpGroupItem(this.icon, this.label, this.bg, this.fg, this.onTap, {this.weight = 1});
}

class XpButtonGroup extends StatefulWidget {
  final List<XpGroupItem> items;
  final double height;
  final bool showLabels;
  const XpButtonGroup({super.key, required this.items, this.height = 58, this.showLabels = true});
  @override
  State<XpButtonGroup> createState() => _XpButtonGroupState();
}

class _XpButtonGroupState extends State<XpButtonGroup> with TickerProviderStateMixin {
  late List<AnimationController> _p = _make();

  List<AnimationController> _make() => [
        for (final _ in widget.items) AnimationController.unbounded(vsync: this, value: 0),
      ];

  @override
  void didUpdateWidget(XpButtonGroup old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      for (final c in _p) {
        c.dispose();
      }
      _p = _make();
    }
  }

  @override
  void dispose() {
    for (final c in _p) {
      c.dispose();
    }
    super.dispose();
  }

  void _down(int i) =>
      _p[i].animateTo(1, duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
  void _up(int i) => _p[i].animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 420, damping: 13), _p[i].value, 0, -3));

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        return AnimatedBuilder(
          animation: Listenable.merge(_p),
          builder: (context, _) {
            const gap = 4.0;
            final avail = c.maxWidth - gap * (n - 1);
            final ws = [for (var i = 0; i < n; i++) widget.items[i].weight + 0.35 * _p[i].value];
            final sum = ws.fold<double>(0, (a, b) => a + b);
            final h = widget.height;
            return Row(
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _down(i),
                    onTapUp: (_) => _up(i),
                    onTapCancel: () => _up(i),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.items[i].onTap();
                    },
                    child: Container(
                      width: avail * ws[i] / sum,
                      height: h,
                      decoration: BoxDecoration(
                        color: widget.items[i].bg,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(i == 0 ? h / 2 : 10 + (h / 2 - 10) * _p[i].value.clamp(0.0, 1.0)),
                          right: Radius.circular(i == n - 1 ? h / 2 : 10 + (h / 2 - 10) * _p[i].value.clamp(0.0, 1.0)),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(widget.items[i].icon, color: widget.items[i].fg, size: widget.height * 0.38),
                            if (widget.showLabels && widget.items[i].label.isNotEmpty) ...[
                              const SizedBox(width: 7),
                              Text(widget.items[i].label, style: xpT(14.5, c: widget.items[i].fg, w: FontWeight.w700)),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      }),
    );
  }
}

class _XpSegmented extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const _XpSegmented({required this.options, required this.index, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / options.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(18)),
            ),
          ),
          Row(children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: XpPress(
                  onTap: () => onChanged(i),
                  child: Center(
                    child: Text(options[i],
                        style: xpT(14,
                            w: i == index ? FontWeight.w800 : FontWeight.w600,
                            c: i == index ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class _XpEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final (String, VoidCallback)? action;
  const _XpEmpty({required this.icon, required this.title, required this.sub, this.action});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
      child: Column(children: [
        XpShaped(
          shape: XpShape.clover,
          size: 84,
          child: Container(color: cs.secondaryContainer, child: Icon(icon, size: 36, color: cs.onSecondaryContainer)),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: xpT(18, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(sub, textAlign: TextAlign.center, style: xpT(14, w: FontWeight.w500, c: cs.onSurfaceVariant)),
        if (action != null) ...[
          const SizedBox(height: 16),
          XpPress(
            onTap: action!.$2,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(23)),
              child: Text(action!.$1, style: xpT(15, c: cs.onPrimary, w: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Material 3 Expressive loading indicator: a shape that morphs and spins.
class XpLoading extends StatefulWidget {
  final double size;
  const XpLoading({super.key, this.size = 48});
  @override
  State<XpLoading> createState() => _XpLoadingState();
}

class _XpLoadingState extends State<XpLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  static const _seq = [XpShape.cookie9, XpShape.clover, XpShape.burst, XpShape.flower, XpShape.pill];
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final f = _c.value * _seq.length;
        final i = f.floor() % _seq.length;
        final m = Curves.easeInOutBack.transform((f - f.floor()).clamp(0.0, 1.0));
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: ClipPath(
            clipper: XpShapeClipper(_seq[i], _seq[(i + 1) % _seq.length], m.clamp(0.0, 1.0), _c.value * 4 * pi),
            child: ColoredBox(color: cs.primary),
          ),
        );
      },
    );
  }
}

/// "This week" card: minutes + a 7-day bar chart. Opens Stats.
class _XpWeekCard extends StatelessWidget {
  const _XpWeekCard();
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final s = ListenStats.i;
    final today = ListenStats.today();
    final days = [for (var i = 6; i >= 0; i--) ListenStats.dayKey(today.subtract(Duration(days: i)))];
    final secs = [for (final d in days) s.dayTotal(d)];
    final total = secs.fold<int>(0, (a, b) => a + b);
    final peak = secs.fold<int>(1, (a, b) => max(a, b));
    final top = xpTopTracks(days.toSet(), 1);
    final topName = top.isEmpty ? null : s.titleOf(top.first.$1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: XpPress(
        amount: 0.5,
        onTap: () => Navigator.of(context).push(xpRoute(const XpStatsPage())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            XpShaped(
              shape: XpShape.burst,
              size: 70,
              child: Container(
                color: cs.tertiary,
                alignment: Alignment.center,
                child: Text(xpHoursLabel(total), style: xpT(17, c: cs.onTertiary, w: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('THIS WEEK', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(topName == null ? 'Play something to start your stats' : 'Most played: $topName',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: xpT(15.5, w: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 26,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: secs[i] / peak),
                              duration: Duration(milliseconds: 500 + 60 * i),
                              curve: Curves.easeOutBack,
                              builder: (_, v, __) => Container(
                                height: max(4.0, 26 * v.clamp(0.0, 1.2)),
                                decoration: BoxDecoration(
                                  color: i == 6 ? cs.primary : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

String xpHoursLabel(int secs) {
  if (secs >= 3600) return '${(secs / 3600).toStringAsFixed(secs >= 36000 ? 0 : 1)}h';
  return '${(secs / 60).round()}m';
}

/// Top tracks over the given days, by plays then seconds.
List<(String, int)> xpTopTracks(Set<String> days, int n) {
  final s = ListenStats.i;
  final plays = <String, int>{};
  for (final d in days) {
    s.plays[d]?.forEach((id, p) => plays[id] = (plays[id] ?? 0) + p);
  }
  if (plays.isEmpty) {
    for (final d in days) {
      s.days[d]?.forEach((id, secs) => plays[id] = (plays[id] ?? 0) + (secs ~/ 60));
    }
  }
  final l = plays.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in l.take(n)) (e.key, e.value)];
}

// ═══════════════════════════════ Search ═══════════════════════════════

class XpSearchPage extends StatefulWidget {
  const XpSearchPage({super.key});
  @override
  State<XpSearchPage> createState() => _XpSearchPageState();
}

class _XpSearchPageState extends State<XpSearchPage> {
  final TextEditingController _q = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  int _filter = 0;
  bool _busy = false;
  String _last = '';
  List<TrackItem> _songs = [];
  List<YtArtist> _artists = [];
  List<YtAlbum> _albums = [];
  List<YtPlaylistRef> _playlists = [];
  List<YtVideoResult> _videos = [];

  static const _filters = ['All', 'Songs', 'Artists', 'Albums', 'Playlists', 'Videos'];
  static const _genres = [
    ('Hip-Hop', Icons.mic_external_on_rounded, XpShape.clover),
    ('Chill', Icons.spa_rounded, XpShape.cookie9),
    ('Workout', Icons.fitness_center_rounded, XpShape.burst),
    ('Focus', Icons.center_focus_strong_rounded, XpShape.pill),
    ('Throwback', Icons.history_rounded, XpShape.flower),
    ('Sad', Icons.water_drop_rounded, XpShape.ghost),
    ('Party', Icons.celebration_rounded, XpShape.cookie12),
    ('R&B', Icons.favorite_rounded, XpShape.cookie6),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _history {
    try {
      return YouTubeMusic.prefs?.getStringList('search_history') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  void _remember(String q) {
    final list = [q, ..._history.where((x) => x.toLowerCase() != q.toLowerCase())].take(12).toList();
    YouTubeMusic.prefs?.setStringList('search_history', list);
  }

  void _changed(String v) {
    _debounce?.cancel();
    setState(() {});
    if (v.trim().isEmpty) {
      setState(() => _last = '');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _run(v.trim()));
  }

  Future<void> _run(String q, {bool save = false}) async {
    if (q.isEmpty) return;
    if (save) _remember(q);
    setState(() {
      _busy = true;
      _last = q;
    });
    try {
      switch (_filter) {
        case 0:
          final r = await Future.wait([
            YouTubeMusic.searchArtists(q).catchError((_) => <YtArtist>[]),
            YouTubeMusic.search(q).catchError((_) => <TrackItem>[]),
            YouTubeMusic.searchAlbums(q).catchError((_) => <YtAlbum>[]),
            YouTubeMusic.searchPlaylists(q).catchError((_) => <YtPlaylistRef>[]),
          ]);
          if (!mounted || q != _last) return;
          setState(() {
            _artists = r[0] as List<YtArtist>;
            _songs = r[1] as List<TrackItem>;
            _albums = r[2] as List<YtAlbum>;
            _playlists = r[3] as List<YtPlaylistRef>;
          });
          break;
        case 1:
          final r = await YouTubeMusic.search(q);
          if (mounted && q == _last) setState(() => _songs = r);
          break;
        case 2:
          final r = await YouTubeMusic.searchArtists(q);
          if (mounted && q == _last) setState(() => _artists = r);
          break;
        case 3:
          final r = await YouTubeMusic.searchAlbums(q);
          if (mounted && q == _last) setState(() => _albums = r);
          break;
        case 4:
          final r = await YouTubeMusic.searchPlaylists(q);
          if (mounted && q == _last) setState(() => _playlists = r);
          break;
        default:
          final r = await YouTubeMusic.searchVideos(q);
          if (mounted && q == _last) setState(() => _videos = r);
      }
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _voice() async {
    try {
      final t = await const MethodChannel('com.alexlmp.app/media')
          .invokeMethod<String>('listen', {'prompt': 'Search music'});
      if (t != null && t.trim().isNotEmpty) {
        _q.text = t.trim();
        _run(t.trim(), save: true);
      }
    } catch (_) {
      if (mounted) xpSnack(context, "Voice search isn't available");
    }
  }

  void _openArtist(YtArtist a) => Navigator.of(context)
      .push(xpRoute(RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail)));
  void _openAlbum(YtAlbum a) => Navigator.of(context)
      .push(xpRoute(RevivedAlbumPage(url: a.url, initialTitle: a.title, initialThumb: a.thumbnail)));
  void _openPlaylist(YtPlaylistRef p) => Navigator.of(context)
      .push(xpRoute(RevivedPlaylistPage.youtube(playlistId: p.playlistId, title: p.title, thumbnail: p.thumbnail)));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final bottom = max(xpBottomPad(context), kb + 20);
    return Column(
      children: [
        SizedBox(height: top + 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            height: 58,
            decoration: BoxDecoration(
              color: _focus.hasFocus ? cs.surfaceContainerHighest : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(29),
            ),
            child: Row(children: [
              const SizedBox(width: 18),
              Icon(Icons.search_rounded, color: cs.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Focus(
                  onFocusChange: (_) => setState(() {}),
                  child: TextField(
                    controller: _q,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    style: xpT(16.5, w: FontWeight.w500),
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      hintText: 'Songs, artists, albums',
                      hintStyle: xpT(16.5, w: FontWeight.w500, c: cs.onSurfaceVariant),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onChanged: _changed,
                    onSubmitted: (v) => _run(v.trim(), save: true),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: _q.text.isNotEmpty
                    ? IconButton(
                        key: const ValueKey('x'),
                        icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                        onPressed: () {
                          _q.clear();
                          _changed('');
                        },
                      )
                    : IconButton(
                        key: const ValueKey('mic'),
                        icon: Icon(Icons.mic_rounded, color: cs.onSurfaceVariant),
                        onPressed: _voice,
                      ),
              ),
              const SizedBox(width: 6),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => XpChip(
              label: _filters[i],
              selected: _filter == i,
              onTap: () {
                setState(() => _filter = i);
                if (_q.text.trim().isNotEmpty) _run(_q.text.trim());
              },
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _q.text.trim().isEmpty
                ? _idle(context, bottom)
                : (_busy && _songs.isEmpty && _artists.isEmpty && _albums.isEmpty && _playlists.isEmpty && _videos.isEmpty
                    ? const Center(child: XpLoading())
                    : _results(context, bottom)),
          ),
        ),
      ],
    );
  }

  Widget _idle(BuildContext context, double bottom) {
    final cs = context.cs;
    final h = _history;
    final tones = [
      (cs.primaryContainer, cs.onPrimaryContainer),
      (cs.tertiaryContainer, cs.onTertiaryContainer),
      (cs.secondaryContainer, cs.onSecondaryContainer),
    ];
    return ListView(
      key: const ValueKey('idle'),
      padding: EdgeInsets.only(bottom: bottom),
      children: [
        if (h.isNotEmpty) ...[
          xpSection(context, 'Recent', action: 'Clear', onAction: () {
            YouTubeMusic.prefs?.setStringList('search_history', []);
            setState(() {});
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in h)
                XpChip(
                  label: q,
                  icon: Icons.history_rounded,
                  selected: false,
                  onTap: () {
                    _q.text = q;
                    _run(q, save: true);
                  },
                ),
            ]),
          ),
        ],
        xpSection(context, 'Browse'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.65,
            children: [
              for (var i = 0; i < _genres.length; i++)
                XpPopIn(
                  index: i,
                  child: XpPress(
                    onTap: () {
                      final q = '${_genres[i].$1} music';
                      _q.text = q;
                      setState(() => _filter = 4);
                      _run(q, save: true);
                    },
                    child: Container(
                      decoration: BoxDecoration(color: tones[i % 3].$1, borderRadius: BorderRadius.circular(24)),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(children: [
                        Positioned(
                          left: 16,
                          top: 14,
                          child: Text(_genres[i].$1, style: xpT(18, c: tones[i % 3].$2, w: FontWeight.w800)),
                        ),
                        Positioned(
                          right: -14,
                          bottom: -14,
                          child: Transform.rotate(
                            angle: 0.3,
                            child: XpShaped(
                              shape: _genres[i].$3,
                              size: 78,
                              child: Container(
                                color: tones[i % 3].$2.withOpacity(0.18),
                                alignment: const Alignment(-0.2, -0.2),
                                child: Icon(_genres[i].$2, color: tones[i % 3].$2, size: 28),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context, double bottom) {
    final cs = context.cs;
    final kids = <Widget>[];
    void songs(List<TrackItem> list, int limit) {
      for (var i = 0; i < min(limit, list.length); i++) {
        kids.add(XpPopIn(index: i, child: XpSongRow(track: list[i], onTap: () => xpPlay(list, i))));
      }
    }

    Widget artistRow(YtArtist a) => XpPress(
          amount: 0.5,
          onTap: () => _openArtist(a),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              XpShaped(shape: XpShape.cookie12, size: 56, child: xpUrlArt(a.thumbnail, icon: Icons.person_rounded)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(16)),
                  Text('Artist', style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ]),
          ),
        );
    Widget albumRow(String? thumb, String t, String s, VoidCallback tap) => XpPress(
          amount: 0.5,
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              XpShaped(shape: XpShape.square, size: 56, child: xpUrlArt(thumb)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15.5)),
                  Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        );

    switch (_filter) {
      case 0:
        if (_artists.isNotEmpty) {
          final a = _artists.first;
          kids.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: XpPress(
              amount: 0.5,
              onTap: () => _openArtist(a),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(32)),
                child: Row(children: [
                  XpShaped(shape: XpShape.cookie9, size: 86, child: xpUrlArt(xpHiRes(a.thumbnail), icon: Icons.person_rounded)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TOP RESULT', style: xpT(11.5, c: cs.onPrimaryContainer.withOpacity(0.8), ls: 0.8, w: FontWeight.w800)),
                      Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: xpT(24, c: cs.onPrimaryContainer, w: FontWeight.w800)),
                      Text('Artist', style: xpT(13, c: cs.onPrimaryContainer.withOpacity(0.8))),
                    ]),
                  ),
                  XpIconBtn(Icons.arrow_forward_rounded, bg: cs.primary, fg: cs.onPrimary, radius: 16,
                      onTap: () => _openArtist(a)),
                ]),
              ),
            ),
          ));
        }
        if (_songs.isNotEmpty) {
          kids.add(xpSection(context, 'Songs', action: 'See all', onAction: () {
            setState(() => _filter = 1);
          }));
          songs(_songs, 5);
        }
        if (_albums.isNotEmpty) {
          kids.add(xpSection(context, 'Albums'));
          kids.add(_cardRow([
            for (final a in _albums)
              XpCard(art: xpUrlArt(a.thumbnail), title: a.title, sub: a.artist, shape: XpShape.square, onTap: () => _openAlbum(a)),
          ]));
        }
        if (_artists.length > 1) {
          kids.add(xpSection(context, 'Artists'));
          kids.add(_cardRow([
            for (final a in _artists.skip(1))
              XpCard(art: xpUrlArt(a.thumbnail, icon: Icons.person_rounded), title: a.name, sub: 'Artist', shape: XpShape.circle, onTap: () => _openArtist(a)),
          ]));
        }
        if (_playlists.isNotEmpty) {
          kids.add(xpSection(context, 'Playlists'));
          kids.add(_cardRow([
            for (var i = 0; i < _playlists.length; i++)
              XpCard(
                  art: xpUrlArt(_playlists[i].thumbnail),
                  title: _playlists[i].title,
                  sub: _playlists[i].subtitle,
                  shape: kXpCardShapes[i % kXpCardShapes.length],
                  onTap: () => _openPlaylist(_playlists[i])),
          ]));
        }
        break;
      case 1:
        songs(_songs, 60);
        break;
      case 2:
        for (final a in _artists) {
          kids.add(artistRow(a));
        }
        break;
      case 3:
        for (final a in _albums) {
          kids.add(albumRow(a.thumbnail, a.title, a.artist, () => _openAlbum(a)));
        }
        break;
      case 4:
        for (final p in _playlists) {
          kids.add(albumRow(p.thumbnail, p.title, p.subtitle, () => _openPlaylist(p)));
        }
        break;
      default:
        for (var i = 0; i < _videos.length; i++) {
          final v = _videos[i];
          kids.add(XpSongRow(
            track: v.track,
            subtitle: '${v.track.artist}${v.uploaded == null ? '' : ' · ${v.uploaded}'}',
            onTap: () => xpPlay([for (final x in _videos) x.track], i),
          ));
        }
    }
    if (kids.isEmpty) {
      return _XpEmpty(icon: Icons.search_off_rounded, title: 'Nothing found', sub: 'Try another search.');
    }
    return ListView(
      key: ValueKey('res$_filter$_last'),
      padding: EdgeInsets.only(bottom: bottom),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: kids,
    );
  }
}

// ═══════════════════════════════ Library ═══════════════════════════════

class XpLibraryPage extends StatefulWidget {
  const XpLibraryPage({super.key});
  @override
  State<XpLibraryPage> createState() => _XpLibraryPageState();
}

class _XpLibraryPageState extends State<XpLibraryPage> {
  int _tab = 0;
  bool _grid = false;
  bool _az = false;
  late final Future<List<YtPlaylistRef>> _pl = YouTubeMusic.libraryPlaylists().catchError((_) => <YtPlaylistRef>[]);
  late final Future<List<YtArtist>> _ar = YouTubeMusic.libraryArtists().catchError((_) => <YtArtist>[]);
  late final Future<List<YtAlbum>> _al = YouTubeMusic.libraryAlbums().catchError((_) => <YtAlbum>[]);

  static const _tabs = ['Playlists', 'Artists', 'Albums', 'Songs', 'Downloaded'];

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, LibraryStore.revision, OfflineStore.revision, audioHandler.libraryRevision]),
      builder: (context, _) => Column(
        children: [
          SizedBox(height: top + 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 14, 8),
            child: Row(children: [
              Expanded(child: Text('Library', style: xpT(32, w: FontWeight.w800))),
              XpIconBtn(_az ? Icons.sort_by_alpha_rounded : Icons.schedule_rounded,
                  tip: _az ? 'A–Z' : 'Recent', onTap: () => setState(() => _az = !_az)),
              const SizedBox(width: 8),
              XpIconBtn(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  tip: 'Layout', onTap: () => setState(() => _grid = !_grid)),
              const SizedBox(width: 8),
              XpIconBtn(Icons.add_rounded,
                  tip: 'New playlist', bg: cs.primaryContainer, fg: cs.onPrimaryContainer, radius: 16,
                  onTap: () => showCreateOrEditPlaylistDialog(context)),
            ]),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => XpChip(label: _tabs[i], selected: _tab == i, onTap: () => setState(() => _tab = i)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              child: KeyedSubtree(key: ValueKey('lib$_tab$_grid$_az'), child: _body(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<_LibItem> items) {
    final bottom = xpBottomPad(context);
    if (_az) items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (items.isEmpty) {
      return ListView(children: [
        _XpEmpty(icon: Icons.library_music_rounded, title: 'Nothing here yet', sub: 'Things you save show up here.'),
      ]);
    }
    if (_grid) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.8),
        itemCount: items.length,
        itemBuilder: (_, i) => XpPopIn(
          index: i,
          child: XpPress(
            amount: 0.6,
            onTap: items[i].onTap,
            onLongPress: items[i].onLong,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: XpShaped(shape: items[i].shape, child: SizedBox.expand(child: items[i].art))),
              const SizedBox(height: 8),
              Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14.5)),
              Text(items[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: xpT(12.5, w: FontWeight.w500, c: context.cs.onSurfaceVariant)),
            ]),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottom, top: 4),
      itemCount: items.length,
      itemBuilder: (_, i) => XpPopIn(
        index: i,
        child: XpPress(
          amount: 0.5,
          onTap: items[i].onTap,
          onLongPress: items[i].onLong,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              XpShaped(shape: items[i].shape, size: 60, child: items[i].art),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(16)),
                  const SizedBox(height: 2),
                  Text(items[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: xpT(13, w: FontWeight.w500, c: context.cs.onSurfaceVariant)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.cs.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _heroTiles(BuildContext context) {
    final cs = context.cs;
    Widget tile(String t, String s, IconData icon, Color bg, Color fg, Color blob, XpShape shape, VoidCallback tap) =>
        Expanded(
          child: XpPress(
            onTap: tap,
            child: Container(
              height: 116,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: xpT(17, c: fg, w: FontWeight.w800)),
                  Text(s, style: xpT(12.5, c: fg.withOpacity(0.8), w: FontWeight.w600)),
                ]),
                Positioned(
                  right: -14,
                  bottom: -18,
                  child: XpShaped(
                    shape: shape,
                    size: 76,
                    child: Container(color: blob, alignment: const Alignment(-0.15, -0.2), child: Icon(icon, color: bg, size: 30)),
                  ),
                ),
              ]),
            ),
          ),
        );
    final liked = xpLikedTracks();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        tile('Liked', '${liked.length} songs', Icons.favorite_rounded, cs.primaryContainer, cs.onPrimaryContainer, cs.primary,
            XpShape.ghost, () {
          Navigator.of(context).push(xpRoute(appState.homeMode == 'youtube'
              ? const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music')
              : RevivedPlaylistPage.custom(title: 'Liked songs', tracks: liked, isLikedStyle: true)));
        }),
        const SizedBox(width: 10),
        tile('Downloads', '${OfflineStore.count} · ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
            Icons.download_done_rounded, cs.tertiaryContainer, cs.onTertiaryContainer, cs.tertiary, XpShape.clover,
            () => openDownloads(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final local = audioHandler.tracks.where((t) => !t.isYouTube).toList();
    switch (_tab) {
      case 1:
        return FutureBuilder<List<YtArtist>>(
          future: _ar,
          builder: (context, snap) {
            final byArtist = <String, List<TrackItem>>{};
            for (final t in local) {
              byArtist.putIfAbsent(t.artist, () => []).add(t);
            }
            return _list([
              for (final a in snap.data ?? const <YtArtist>[])
                _LibItem(xpUrlArt(a.thumbnail, icon: Icons.person_rounded), a.name, 'Artist', XpShape.circle,
                    () => Navigator.of(context).push(xpRoute(RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail)))),
              for (final e in byArtist.entries)
                _LibItem(xpTrackArt(e.value.first), e.key, '${e.value.length} songs · On device', XpShape.circle,
                    () => Navigator.of(context).push(xpRoute(RevivedPlaylistPage.custom(title: e.key, subtitle: 'Artist', tracks: e.value)))),
            ]);
          },
        );
      case 2:
        return FutureBuilder<List<YtAlbum>>(
          future: _al,
          builder: (context, snap) {
            final byAlbum = <String, List<TrackItem>>{};
            for (final t in local) {
              byAlbum.putIfAbsent(t.album, () => []).add(t);
            }
            return _list([
              for (final a in snap.data ?? const <YtAlbum>[])
                _LibItem(xpUrlArt(a.thumbnail), a.title, a.artist, XpShape.square,
                    () => Navigator.of(context).push(xpRoute(RevivedAlbumPage(url: a.url, initialTitle: a.title, initialThumb: a.thumbnail)))),
              for (final e in byAlbum.entries)
                _LibItem(xpTrackArt(e.value.first), e.key, '${e.value.first.artist} · On device', XpShape.square,
                    () => Navigator.of(context).push(xpRoute(RevivedPlaylistPage.custom(title: e.key, subtitle: e.value.first.artist, tracks: e.value)))),
            ]);
          },
        );
      case 3:
        final all = audioHandler.tracks;
        final songs = _az ? ([...all]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()))) : all;
        if (songs.isEmpty) return _list([]);
        return ListView.builder(
          padding: EdgeInsets.only(bottom: xpBottomPad(context), top: 4),
          itemCount: songs.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: XpButtonGroup(height: 50, items: [
                  XpGroupItem(Icons.play_arrow_rounded, 'Play', context.cs.primary, context.cs.onPrimary, () => xpPlay(songs, 0)),
                  XpGroupItem(Icons.shuffle_rounded, 'Shuffle', context.cs.secondaryContainer, context.cs.onSecondaryContainer,
                      () => xpPlay(songs, 0, shuffle: true)),
                ]),
              );
            }
            return XpSongRow(track: songs[i - 1], onTap: () => xpPlay(songs, i - 1));
          },
        );
      case 4:
        final dl = OfflineStore.tracks();
        if (dl.isEmpty) {
          return ListView(children: [
            _XpEmpty(icon: Icons.download_rounded, title: 'No downloads yet', sub: 'Download songs to play them offline.'),
          ]);
        }
        return ListView.builder(
          padding: EdgeInsets.only(bottom: xpBottomPad(context), top: 4),
          itemCount: dl.length,
          itemBuilder: (_, i) => XpSongRow(track: dl[i], onTap: () => xpPlay(dl, i)),
        );
      default:
        return FutureBuilder<List<YtPlaylistRef>>(
          future: _pl,
          initialData: YouTubeMusic.cachedLibrary(),
          builder: (context, snap) {
            final items = <_LibItem>[
              for (var i = 0; i < appState.playlists.length; i++)
                _LibItem(
                    Container(
                      color: context.cs.secondaryContainer,
                      child: Icon(Icons.queue_music_rounded, color: context.cs.onSecondaryContainer, size: 28),
                    ),
                    appState.playlists[i].name,
                    '${appState.playlists[i].trackIds.length} songs · On device',
                    kXpCardShapes[i % kXpCardShapes.length],
                    () => Navigator.of(context).push(xpRoute(RevivedPlaylistPage.local(playlist: appState.playlists[i])))),
              for (final p in snap.data ?? const <YtPlaylistRef>[])
                if (p.playlistId != 'LM')
                  _LibItem(xpUrlArt(p.thumbnail), p.title, p.subtitle.isEmpty ? 'YouTube Music' : p.subtitle, XpShape.square,
                      () => Navigator.of(context).push(xpRoute(RevivedPlaylistPage.youtube(playlistId: p.playlistId, title: p.title, thumbnail: p.thumbnail)))),
            ];
            return Column(children: [
              _heroTiles(context),
              Expanded(child: _list(items)),
            ]);
          },
        );
    }
  }
}

class _LibItem {
  final Widget art;
  final String title;
  final String sub;
  final XpShape shape;
  final VoidCallback onTap;
  final VoidCallback? onLong;
  _LibItem(this.art, this.title, this.sub, this.shape, this.onTap, [this.onLong]);
}

// ═══════════════════════════════ You (profile + settings) ═══════════════════════════════

class XpYouPage extends StatelessWidget {
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const XpYouPage({super.key, this.aiChatBuilder});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final top = MediaQuery.of(context).padding.top;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, ytAccount, audioHandler.sleepLabel]),
      builder: (context, _) {
        final acct = ytAccount.value;
        final s = ListenStats.i;
        final today = ListenStats.today();
        final month = [
          for (var i = 0; i < today.day; i++) ListenStats.dayKey(today.subtract(Duration(days: i)))
        ];
        final monthSecs = month.fold<int>(0, (a, d) => a + s.dayTotal(d));
        return ListView(
          padding: EdgeInsets.only(top: top + 10, bottom: xpBottomPad(context)),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: XpPress(
                amount: 0.4,
                onTap: () => showYtAccountSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(32)),
                  child: Row(children: [
                    XpShaped(
                      shape: XpShape.cookie9,
                      size: 72,
                      child: Container(
                        color: cs.primaryContainer,
                        alignment: Alignment.center,
                        child: acct.signedIn && acct.photo != null
                            ? Image.network(acct.photo!, fit: BoxFit.cover, width: 72, height: 72,
                                errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, size: 34, color: cs.onPrimaryContainer))
                            : Icon(Icons.person_rounded, size: 34, color: cs.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(acct.signedIn ? (acct.name ?? 'You') : 'Not signed in', style: xpT(22, w: FontWeight.w800)),
                        Text(acct.signedIn ? 'YouTube Music account' : 'Tap to sign in to YouTube Music',
                            style: xpT(13.5, w: FontWeight.w500, c: cs.onSurfaceVariant)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: XpPress(
                amount: 0.4,
                onTap: () => Navigator.of(context).push(xpRoute(const XpStatsPage())),
                child: Container(
                  height: 120,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(32)),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('THIS MONTH', style: xpT(11.5, c: cs.onPrimaryContainer.withOpacity(0.8), ls: 0.8, w: FontWeight.w800)),
                      Text('${(monthSecs / 60).round()} min', style: xpT(36, c: cs.onPrimaryContainer, w: FontWeight.w900)),
                      Text('See your stats', style: xpT(13.5, c: cs.onPrimaryContainer, w: FontWeight.w700)),
                    ]),
                    Positioned(
                      right: -20,
                      bottom: -30,
                      child: XpShaped(
                        shape: XpShape.burst,
                        size: 120,
                        child: Container(color: cs.primary.withOpacity(0.55),
                            alignment: const Alignment(-0.3, -0.3),
                            child: Icon(Icons.insights_rounded, color: cs.onPrimary, size: 36)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            _group(context, 'Player', [
              _row(context, Icons.style_rounded, 'Player style', xpPlayerStyleName(appState.str('xp_player', 'expressive')),
                  () => showXpPlayerStylePicker(context)),
              _toggle(context, Icons.crop_square_rounded, 'Rounded square album art',
                  'Tap the art in the player to switch', appState.str('xp_art_shape', 'cookie') == 'square',
                  (v) => appState.setStr('xp_art_shape', v ? 'square' : 'cookie')),
              _row(context, Icons.equalizer_rounded, 'Sound & tools', 'EQ, crossfade, speed, sleep timer',
                  () => showXpToolsSheet(context)),
              _row(context, Icons.bedtime_rounded, 'Sleep timer', audioHandler.sleepLabel.value ?? 'Off',
                  () => showXpToolsSheet(context, focusSleep: true)),
            ]),
            _group(context, 'Look', [
              _toggle(context, Icons.palette_rounded, 'Colors from album art', 'The whole app follows the song',
                  appState.b('xp_dynamic', true), (v) => appState.setB('xp_dynamic', v)),
              if (!appState.b('xp_dynamic', true)) _seedPicker(context),
            ]),
            _group(context, 'AI', [
              _row(context, Icons.graphic_eq_rounded, 'Start AI DJ', 'Talks between songs and picks what plays next',
                  () => startOrStepAiDj(openInPlayer: context)),
              if (aiChatBuilder != null)
                _row(context, Icons.auto_awesome_rounded, 'Ask AI', 'Make mixes, find songs, control the app', () {
                  Navigator.of(context).push(xpRoute(Scaffold(body: aiChatBuilder!(appState.palette))));
                }),
            ]),
            _group(context, 'App', [
              _row(context, Icons.download_rounded, 'Downloads', '${OfflineStore.count} songs', () => openDownloads(context)),
              _row(context, Icons.tune_rounded, 'More settings', 'Library folders, playback, data and more',
                  () => openRevivedSettings(context)),
              _row(context, Icons.system_update_rounded, 'Check for updates', 'Version $kAppVersion',
                  () => checkRevivedUpdate(context, manual: true)),
            ]),
          ],
        );
      },
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> rows) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(title, style: xpT(14, c: cs.primary, w: FontWeight.w800)),
        ),
        for (var i = 0; i < rows.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 24 : 6),
                bottom: Radius.circular(i == rows.length - 1 ? 24 : 6),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: rows[i],
          ),
      ]),
    );
  }

  Widget _icon(BuildContext context, IconData icon) {
    final cs = context.cs;
    return XpShaped(
      shape: XpShape.cookie9,
      size: 42,
      child: Container(color: cs.secondaryContainer, child: Icon(icon, color: cs.onSecondaryContainer, size: 21)),
    );
  }

  Widget _row(BuildContext context, IconData icon, String t, String s, VoidCallback onTap) {
    final cs = context.cs;
    return XpPress(
      amount: 0.35,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          _icon(context, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: xpT(16)),
              Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }

  Widget _toggle(BuildContext context, IconData icon, String t, String s, bool v, ValueChanged<bool> onChanged) {
    final cs = context.cs;
    return InkWell(
      onTap: () => onChanged(!v),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          _icon(context, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: xpT(16)),
              Text(s, style: xpT(13, w: FontWeight.w500, c: cs.onSurfaceVariant)),
            ]),
          ),
          Switch(
            value: v,
            onChanged: onChanged,
            thumbIcon: WidgetStatePropertyAll(Icon(v ? Icons.check_rounded : Icons.close_rounded, size: 16)),
          ),
        ]),
      ),
    );
  }

  Widget _seedPicker(BuildContext context) {
    const seeds = [0xFFFF8A50, 0xFFE91E63, 0xFF9C27B0, 0xFF3F51B5, 0xFF00BCD4, 0xFF4CAF50, 0xFFFFC107, 0xFF795548];
    final cur = appState.str('xp_seed', '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final s in seeds)
          XpPress(
            onTap: () => appState.setStr('xp_seed', s.toRadixString(16)),
            child: XpMorph(
              shape: cur == s.toRadixString(16) ? XpShape.cookie9 : XpShape.circle,
              child: Container(
                width: 46,
                height: 46,
                color: Color(s),
                child: cur == s.toRadixString(16) ? const Icon(Icons.check_rounded, color: Colors.white) : null,
              ),
            ),
          ),
      ]),
    );
  }
}

// ═══════════════════════════════ Stats ═══════════════════════════════

class XpStatsPage extends StatefulWidget {
  const XpStatsPage({super.key});
  @override
  State<XpStatsPage> createState() => _XpStatsPageState();
}

class _XpStatsPageState extends State<XpStatsPage> {
  int _range = 1; // 0 week, 1 month, 2 all time

  Set<String> _days() {
    final s = ListenStats.i;
    final today = ListenStats.today();
    if (_range == 2) return s.days.keys.toSet();
    final n = _range == 0 ? 7 : 30;
    return {for (var i = 0; i < n; i++) ListenStats.dayKey(today.subtract(Duration(days: i)))};
  }

  int _streak() {
    final s = ListenStats.i;
    var d = ListenStats.today();
    var n = 0;
    if (s.dayTotal(ListenStats.dayKey(d)) == 0) d = d.subtract(const Duration(days: 1));
    while (s.dayTotal(ListenStats.dayKey(d)) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final s = ListenStats.i;
    final days = _days();
    final secs = days.fold<int>(0, (a, d) => a + s.dayTotal(d));
    final hours = List<int>.filled(24, 0);
    for (final d in days) {
      final h = s.hours[d];
      if (h == null) continue;
      for (var i = 0; i < min(24, h.length); i++) {
        hours[i] += h[i];
      }
    }
    final peakH = hours.fold<int>(1, (a, b) => max(a, b));
    final top = xpTopTracks(days, 10);
    final artists = <String, int>{};
    final allTop = xpTopTracks(days, 300);
    for (final (id, p) in allTop) {
      final a = s.artistOf(id);
      artists[a] = (artists[a] ?? 0) + p;
    }
    final topArtists = artists.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final streak = _streak();
    final bestHour = hours.indexOf(peakH);
    String hourName(int h) => h == 0 ? '12 AM' : (h < 12 ? '$h AM' : (h == 12 ? '12 PM' : '${h - 12} PM'));

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            title: Text('Your stats', style: xpT(30, w: FontWeight.w800)),
            leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _XpSegmented(
                options: const ['Week', 'Month', 'All time'],
                index: _range,
                onChanged: (i) => setState(() => _range = i),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  flex: 6,
                  child: Container(
                    height: 168,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(32)),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(children: [
                      Positioned(
                        right: -30,
                        bottom: -34,
                        child: XpShaped(shape: XpShape.burst, size: 120, child: ColoredBox(color: cs.primary.withOpacity(0.5))),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('MINUTES', style: xpT(11.5, c: cs.onPrimaryContainer, ls: 0.8, w: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: secs / 60),
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => FittedBox(
                            child: Text(v.round().toString(), style: xpT(46, c: cs.onPrimaryContainer, w: FontWeight.w900)),
                          ),
                        ),
                        Text(xpHoursLabel(secs), style: xpT(13.5, c: cs.onPrimaryContainer.withOpacity(0.85))),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Column(children: [
                    _mini(context, 'STREAK', '$streak ${streak == 1 ? 'day' : 'days'}', Icons.local_fire_department_rounded,
                        cs.surfaceContainerHigh, cs.onSurface),
                    const SizedBox(height: 10),
                    _mini(context, 'PEAK HOUR', secs == 0 ? '—' : hourName(bestHour), Icons.schedule_rounded,
                        cs.tertiaryContainer, cs.onTertiaryContainer),
                  ]),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LISTENING BY HOUR', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 80,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < 24; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: hours[i] / peakH),
                          duration: Duration(milliseconds: 400 + 25 * i),
                          curve: Curves.easeOutBack,
                          builder: (_, v, __) => Container(
                            height: max(4.0, 80 * v.clamp(0.0, 1.1)),
                            decoration: BoxDecoration(
                              color: hours[i] == peakH && peakH > 1 ? cs.primary : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  for (final l in ['12a', '6a', '12p', '6p', '12a'])
                    Expanded(child: Text(l, textAlign: TextAlign.center, style: xpT(11, c: cs.onSurfaceVariant))),
                ]),
              ]),
            ),
          ),
          if (topArtists.isNotEmpty) ...[
            SliverToBoxAdapter(child: xpSection(context, 'Top artists')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: min(10, topArtists.length),
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) {
                    final name = topArtists[i].key;
                    final id = allTop.firstWhere((e) => s.artistOf(e.$1) == name, orElse: () => allTop.first).$1;
                    final t = s.trackFor(id);
                    return XpPopIn(
                      index: i,
                      child: SizedBox(
                        width: 100,
                        child: Column(children: [
                          XpShaped(
                            shape: i == 0 ? XpShape.burst : XpShape.cookie12,
                            size: 96,
                            child: t == null ? Container(color: cs.secondaryContainer) : xpTrackArt(t),
                          ),
                          const SizedBox(height: 8),
                          Text('${i + 1}. $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(13.5)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(child: xpSection(context, 'Top songs')),
          if (top.isEmpty)
            SliverToBoxAdapter(
              child: _XpEmpty(icon: Icons.insights_rounded, title: 'No listening yet', sub: 'Play some music and come back.'),
            )
          else
            SliverList.builder(
              itemCount: top.length,
              itemBuilder: (_, i) {
                final t = s.trackFor(top[i].$1);
                if (t == null) return const SizedBox.shrink();
                return XpPopIn(
                  index: i,
                  child: XpSongRow(
                    track: t,
                    subtitle: '${t.artist} · ${top[i].$2} plays',
                    shape: i == 0 ? XpShape.cookie9 : XpShape.square,
                    leading: SizedBox(
                      width: 26,
                      child: Text('${i + 1}', style: xpT(18, c: cs.primary, w: FontWeight.w900)),
                    ),
                    onTap: () => audioHandler.playYouTubeTrack(t),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }

  Widget _mini(BuildContext context, String label, String value, IconData icon, Color bg, Color fg) {
    return Container(
      height: 79,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Icon(icon, size: 15, color: fg.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(label, style: xpT(11, c: fg.withOpacity(0.8), ls: 0.8, w: FontWeight.w800)),
        ]),
        const SizedBox(height: 2),
        FittedBox(child: Text(value, style: xpT(22, c: fg, w: FontWeight.w900))),
      ]),
    );
  }
}

// ═══════════════════════════════ Player ═══════════════════════════════

const List<(String, String, String, IconData)> kXpPlayerStyles = [
  ('expressive', 'Expressive', 'Shaped art with a spinning shape behind it, big connected buttons, wavy seek bar', Icons.auto_awesome_rounded),
  ('canvas', 'Canvas', 'Art fills the top of the screen and fades into the controls', Icons.wallpaper_rounded),
  ('vinyl', 'Vinyl', 'A record that spins while it plays', Icons.album_rounded),
  ('card', 'Tonal card', 'Art in a tonal card with a big extended play button', Icons.crop_portrait_rounded),
  ('bloom', 'Bloom', 'Living shapes morph and float behind the art', Icons.filter_vintage_rounded),
  ('lyrics', 'Lyrics first', 'Live lyrics up front, compact controls', Icons.lyrics_rounded),
  ('minimal', 'Minimal', 'Just the art, the title and one big morphing button', Icons.radio_button_checked_rounded),
];

String xpPlayerStyleName(String key) =>
    kXpPlayerStyles.firstWhere((s) => s.$1 == key, orElse: () => kXpPlayerStyles.first).$2;

void showXpPlayerStylePicker(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(
      child: Builder(builder: (ctx) {
        final cs = ctx.cs;
        return ListenableBuilder(
          listenable: appState,
          builder: (ctx, _) {
            final cur = appState.str('xp_player', 'expressive');
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text('Player style', style: xpT(24, w: FontWeight.w800)),
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.25,
                    children: [
                      for (var i = 0; i < kXpPlayerStyles.length; i++)
                        XpPopIn(
                          index: i,
                          child: XpPress(
                            onTap: () => appState.setStr('xp_player', kXpPlayerStyles[i].$1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutBack,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cur == kXpPlayerStyles[i].$1 ? cs.primaryContainer : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(cur == kXpPlayerStyles[i].$1 ? 32 : 20),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                XpMorph(
                                  shape: cur == kXpPlayerStyles[i].$1 ? XpShape.cookie9 : XpShape.square,
                                  child: Container(
                                    width: 42,
                                    height: 42,
                                    color: cur == kXpPlayerStyles[i].$1 ? cs.primary : cs.secondaryContainer,
                                    child: Icon(kXpPlayerStyles[i].$4,
                                        color: cur == kXpPlayerStyles[i].$1 ? cs.onPrimary : cs.onSecondaryContainer),
                                  ),
                                ),
                                const Spacer(),
                                Text(kXpPlayerStyles[i].$2,
                                    style: xpT(16,
                                        w: FontWeight.w800,
                                        c: cur == kXpPlayerStyles[i].$1 ? cs.onPrimaryContainer : cs.onSurface)),
                                Text(kXpPlayerStyles[i].$3,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: xpT(11.5,
                                        w: FontWeight.w500,
                                        c: cur == kXpPlayerStyles[i].$1
                                            ? cs.onPrimaryContainer.withOpacity(0.8)
                                            : cs.onSurfaceVariant)),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ]),
              ),
            );
          },
        );
      }),
    ),
  );
}

class XpPlayerScreen extends StatelessWidget {
  const XpPlayerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return XpThemed(
      child: ListenableBuilder(
        listenable: Listenable.merge([appState, audioHandler.currentIndex]),
        builder: (context, _) {
          final t = audioHandler.currentTrack;
          final cs = context.cs;
          if (t == null) {
            return Scaffold(
              backgroundColor: cs.surface,
              body: Center(child: Text('Nothing playing', style: xpT(18, c: cs.onSurfaceVariant))),
            );
          }
          final style = appState.str('xp_player', 'expressive');
          Widget body;
          switch (style) {
            case 'canvas':
              body = _XpCanvasPlayer(track: t);
              break;
            case 'vinyl':
              body = _XpVinylPlayer(track: t);
              break;
            case 'card':
              body = _XpCardPlayer(track: t);
              break;
            case 'bloom':
              body = _XpBloomPlayer(track: t);
              break;
            case 'lyrics':
              body = _XpLyricsPlayer(track: t);
              break;
            case 'minimal':
              body = _XpMinimalPlayer(track: t);
              break;
            default:
              body = _XpExpressivePlayer(track: t);
          }
          return Scaffold(
            backgroundColor: cs.surface,
            body: _XpSwipeDown(
              child: Stack(children: [
                const Positioned.fill(child: _XpPlayerBackdrop()),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: c),
                    ),
                    child: KeyedSubtree(key: ValueKey(style), child: SafeArea(child: body)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Drag the whole player down to close it (with a squish as you pull).
class _XpSwipeDown extends StatefulWidget {
  final Widget child;
  const _XpSwipeDown({required this.child});
  @override
  State<_XpSwipeDown> createState() => _XpSwipeDownState();
}

class _XpSwipeDownState extends State<_XpSwipeDown> with SingleTickerProviderStateMixin {
  late final AnimationController _dy = AnimationController.unbounded(vsync: this, value: 0);
  @override
  void dispose() {
    _dy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return GestureDetector(
      onVerticalDragUpdate: (d) => _dy.value = max(0.0, _dy.value + d.delta.dy),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dy.value > h * 0.22 || v > 900) {
          Navigator.of(context).maybePop();
        } else {
          _dy.animateWith(SpringSimulation(
              const SpringDescription(mass: 1, stiffness: 400, damping: 22), _dy.value, 0, v / 500));
        }
      },
      child: AnimatedBuilder(
        animation: _dy,
        builder: (context, child) {
          final k = (_dy.value / h).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(0, _dy.value),
            child: Transform.scale(
              scale: 1 - k * 0.12,
              child: ClipRRect(borderRadius: BorderRadius.circular(40 * min(1.0, k * 6)), child: child),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Slowly drifting colour wash from the song's colours.
class _XpPlayerBackdrop extends StatefulWidget {
  const _XpPlayerBackdrop();
  @override
  State<_XpPlayerBackdrop> createState() => _XpPlayerBackdropState();
}

class _XpPlayerBackdropState extends State<_XpPlayerBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = _c.value * 2 * pi;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.6 * sin(a), -0.7 + 0.25 * cos(a)),
              radius: 1.25,
              colors: [cs.primaryContainer, cs.surface],
              stops: const [0, 0.85],
            ),
          ),
        );
      },
    );
  }
}

/// Album art: tap to switch between the cookie shape and a normal rounded
/// square (it morphs), swipe sideways to change song (it squishes),
/// double-tap to like.
class XpPlayerArt extends StatefulWidget {
  final TrackItem track;
  final double size;
  final bool spin;
  final XpShape? forceShape;
  const XpPlayerArt({super.key, required this.track, required this.size, this.spin = false, this.forceShape});
  @override
  State<XpPlayerArt> createState() => _XpPlayerArtState();
}

class _XpPlayerArtState extends State<XpPlayerArt> with TickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this, value: 0);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));
  late final AnimationController _heart =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  StreamSubscription<bool>? _sub;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    _sub = audioHandler.player.playingStream.listen((p) {
      if (!mounted || !widget.spin) return;
      p ? _spin.repeat() : _spin.stop();
    });
    if (widget.spin && audioHandler.player.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(XpPlayerArt old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id && !_changing) {
      _dx.value = 60;
      _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 300, damping: 20), 60, 0, 0));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dx.dispose();
    _spin.dispose();
    _heart.dispose();
    super.dispose();
  }

  Future<void> _end(double v) async {
    final w = widget.size;
    final x = _dx.value;
    if (x.abs() > w * 0.25 || v.abs() > 800) {
      _changing = true;
      HapticFeedback.mediumImpact();
      final dir = x != 0 ? x.sign : v.sign;
      await _dx.animateTo(dir * w * 1.2, duration: const Duration(milliseconds: 160), curve: Curves.easeIn);
      if (dir < 0) {
        await audioHandler.skipToNext();
      } else {
        await audioHandler.skipToPrevious();
      }
      _dx.value = -dir * w * 0.8;
      _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 260, damping: 18), _dx.value, 0, 0));
      _changing = false;
    } else {
      _dx.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 16), x, 0, v / 400));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final square = appState.str('xp_art_shape', 'cookie') == 'square';
    final shape = widget.forceShape ?? (square ? XpShape.square : XpShape.cookie9);
    return GestureDetector(
      onTap: widget.forceShape != null
          ? null
          : () {
              HapticFeedback.lightImpact();
              appState.setStr('xp_art_shape', square ? 'cookie' : 'square');
            },
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        if (!appState.isLiked(widget.track.id)) appState.toggleLike(widget.track.id);
        _heart.forward(from: 0);
      },
      onHorizontalDragUpdate: (d) => _dx.value += d.delta.dx,
      onHorizontalDragEnd: (d) => _end(d.primaryVelocity ?? 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_dx, _spin, _heart]),
        builder: (context, child) {
          final k = (_dx.value.abs() / widget.size).clamp(0.0, 1.0);
          final hv = _heart.value;
          return Transform.translate(
            offset: Offset(_dx.value, 0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(1 - k * 0.18, 1 - k * 0.06, 1)..rotateZ(_dx.value / widget.size * 0.12),
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: XpMorph(
                    shape: shape,
                    rot: _spin.value * 2 * pi,
                    duration: const Duration(milliseconds: 650),
                    child: child!,
                  ),
                ),
                if (hv > 0 && hv < 1)
                  Opacity(
                    opacity: (1 - hv).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.6 + Curves.easeOutBack.transform(min(1.0, hv * 2)) * 0.8,
                      child: Icon(Icons.favorite_rounded, color: cs.primary, size: widget.size * 0.3,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 20)]),
                    ),
                  ),
              ]),
            ),
          );
        },
        child: Hero(
          tag: 'xp_art',
          child: SizedBox(width: widget.size, height: widget.size, child: xpTrackArt(widget.track, hiRes: true)),
        ),
      ),
    );
  }
}

// ── Shared player pieces ──

Widget _xpTopBar(BuildContext context, TrackItem t, {String? label}) {
  final cs = context.cs;
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: Row(children: [
      IconButton(
        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: cs.onSurface),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      Expanded(
        child: Column(children: [
          Text('PLAYING FROM', style: xpT(10.5, c: cs.onSurfaceVariant, ls: 1, w: FontWeight.w800)),
          Text(label ?? (t.album.isEmpty ? 'Your music' : t.album),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(14, w: FontWeight.w700)),
        ]),
      ),
      IconButton(
        icon: Icon(Icons.more_vert_rounded, color: cs.onSurface),
        onPressed: () => _xpMoreSheet(context, t),
      ),
    ]),
  );
}

void _xpMoreSheet(BuildContext context, TrackItem t) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => XpThemed(
      child: Builder(builder: (ctx) {
        Widget item(IconData i, String l, VoidCallback f) => ListTile(
              leading: Icon(i, color: ctx.cs.onSurface),
              title: Text(l, style: xpT(16, w: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                f();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            item(Icons.style_rounded, 'Player style', () => showXpPlayerStylePicker(context)),
            item(Icons.equalizer_rounded, 'Sound & tools', () => showXpToolsSheet(context)),
            item(Icons.playlist_add_rounded, 'Add to playlist',
                () => t.isYouTube ? showYtAddToPlaylist(context, t) : showAddToPlaylistSheet(context, t)),
            item(Icons.album_rounded, 'Go to album', () => goToAlbum(context, t)),
            item(Icons.person_rounded, 'Go to artist', () => goToArtist(context, t)),
            item(Icons.bedtime_rounded, 'Sleep timer', () => showXpToolsSheet(context, focusSleep: true)),
            item(Icons.share_rounded, 'Share', () => shareTrack(t)),
            const SizedBox(height: 8),
          ]),
        );
      }),
    ),
  );
}

Widget _xpTitle(BuildContext context, TrackItem t, {double size = 26, bool center = false, Widget? trailing}) {
  final cs = context.cs;
  final text = AnimatedSwitcher(
    duration: const Duration(milliseconds: 380),
    transitionBuilder: (c, a) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: c,
      ),
    ),
    child: Column(
      key: ValueKey(t.id),
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: xpT(size, w: FontWeight.w800, h: 1.1)),
        const SizedBox(height: 3),
        GestureDetector(
          onTap: () => goToArtist(context, t),
          child: Text(t.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: xpT(size * 0.6, w: FontWeight.w600, c: cs.onSurfaceVariant)),
        ),
      ],
    ),
  );
  if (trailing == null) return text;
  return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: text), trailing]);
}

/// Like button: shape morphs to a cookie and pops when liked.
class XpLikeButton extends StatelessWidget {
  final TrackItem track;
  final double size;
  const XpLikeButton({super.key, required this.track, this.size = 50});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final liked = appState.isLiked(track.id);
        return XpPress(
          onTap: () => appState.toggleLike(track.id),
          child: XpMorph(
            shape: liked ? XpShape.cookie9 : XpShape.square,
            child: Container(
              width: size,
              height: size,
              color: liked ? cs.primary : cs.surfaceContainerHighest,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
                child: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    key: ValueKey(liked), color: liked ? cs.onPrimary : cs.onSurface, size: size * 0.46),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Previous / Play / Next as one connected group. Pressed button grows.
Widget _xpTransport(BuildContext context, {double height = 84}) {
  final cs = context.cs;
  return _XpTransport(height: height, cs: cs);
}

class _XpTransport extends StatefulWidget {
  final double height;
  final ColorScheme cs;
  const _XpTransport({required this.height, required this.cs});
  @override
  State<_XpTransport> createState() => _XpTransportState();
}

class _XpTransportState extends State<_XpTransport> with TickerProviderStateMixin {
  late final List<AnimationController> _p = [
    for (var i = 0; i < 3; i++) AnimationController.unbounded(vsync: this, value: 0)
  ];
  @override
  void dispose() {
    for (final c in _p) {
      c.dispose();
    }
    super.dispose();
  }

  void _down(int i) => _p[i].animateTo(1, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  void _up(int i) => _p[i].animateWith(
      SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 12), _p[i].value, 0, -3));

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final h = widget.height;
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? audioHandler.player.playing;
        return LayoutBuilder(builder: (context, c) {
          return AnimatedBuilder(
            animation: Listenable.merge(_p),
            builder: (context, _) {
              final ws = [1 + 0.3 * _p[0].value, 1.7 + 0.25 * _p[1].value, 1 + 0.3 * _p[2].value];
              final sum = ws[0] + ws[1] + ws[2];
              final avail = c.maxWidth - 12;
              Widget btn(int i, Widget child, Color bg, BorderRadius r, VoidCallback f, double hh) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _down(i),
                    onTapUp: (_) => _up(i),
                    onTapCancel: () => _up(i),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      f();
                    },
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1, 1 - 0.08 * _p[i].value, 1),
                      child: Container(
                        width: avail * ws[i] / sum,
                        height: hh,
                        decoration: BoxDecoration(color: bg, borderRadius: r),
                        alignment: Alignment.center,
                        child: child,
                      ),
                    ),
                  );
              final side = h * 0.84;
              final rr = side / 2;
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                btn(
                    0,
                    Icon(Icons.skip_previous_rounded, size: 34, color: cs.onSecondaryContainer),
                    cs.secondaryContainer,
                    BorderRadius.horizontal(left: Radius.circular(rr), right: Radius.circular(12 + 20 * _p[0].value)),
                    audioHandler.skipToPrevious,
                    side),
                const SizedBox(width: 6),
                btn(
                    1,
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
                      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey(playing), size: 44, color: cs.onPrimary),
                    ),
                    cs.primary,
                    BorderRadius.circular(playing ? 26 + 10 * _p[1].value : h / 2),
                    () => playing ? audioHandler.pause() : audioHandler.play(),
                    h),
                const SizedBox(width: 6),
                btn(
                    2,
                    Icon(Icons.skip_next_rounded, size: 34, color: cs.onSecondaryContainer),
                    cs.secondaryContainer,
                    BorderRadius.horizontal(right: Radius.circular(rr), left: Radius.circular(12 + 20 * _p[2].value)),
                    audioHandler.skipToNext,
                    side),
              ]);
            },
          );
        });
      },
    );
  }
}

/// Shuffle · Lyrics · Speed · Queue · Repeat
Widget _xpActions(BuildContext context, TrackItem t, {bool showLyrics = true}) {
  final cs = context.cs;
  return StreamBuilder<PlaybackState>(
    stream: audioHandler.playbackState,
    builder: (context, snap) {
      final shuffle = snap.data?.shuffleMode == AudioServiceShuffleMode.all;
      final repeat = snap.data?.repeatMode ?? AudioServiceRepeatMode.none;
      Widget b(IconData i, bool on, VoidCallback f, String tip) => Tooltip(
            message: tip,
            child: XpPress(
              onTap: f,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                width: on ? 56 : 46,
                height: 46,
                decoration: BoxDecoration(
                  color: on ? cs.tertiaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(on ? 16 : 23),
                ),
                child: Icon(i, size: 24, color: on ? cs.onTertiaryContainer : cs.onSurfaceVariant),
              ),
            ),
          );
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        b(Icons.shuffle_rounded, shuffle, () {
          audioHandler.setShuffleMode(shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
        }, 'Shuffle'),
        if (showLyrics)
          b(Icons.lyrics_outlined, false, () => Navigator.of(context).push(xpRoute(XpLyricsPage(track: t))), 'Lyrics'),
        b(Icons.equalizer_rounded, false, () => showXpToolsSheet(context), 'Sound & tools'),
        b(Icons.queue_music_rounded, false, () => showXpQueueSheet(context), 'Queue'),
        b(repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            repeat != AudioServiceRepeatMode.none, () {
          final next = switch (repeat) {
            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          };
          audioHandler.setRepeatMode(next);
        }, 'Repeat'),
      ]);
    },
  );
}

// ── Style 1: Expressive ──
class _XpExpressivePlayer extends StatefulWidget {
  final TrackItem track;
  const _XpExpressivePlayer({required this.track});
  @override
  State<_XpExpressivePlayer> createState() => _XpExpressivePlayerState();
}

class _XpExpressivePlayerState extends State<_XpExpressivePlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _rot = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  @override
  void dispose() {
    _rot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = widget.track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 56, c.maxHeight * 0.42);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(),
        Stack(alignment: Alignment.center, children: [
          AnimatedBuilder(
            animation: _rot,
            builder: (context, _) => Transform.rotate(
              angle: _rot.value * 2 * pi,
              child: XpShaped(
                shape: XpShape.cookie12,
                size: art + 26,
                child: ColoredBox(color: cs.primary.withOpacity(0.28)),
              ),
            ),
          ),
          XpPlayerArt(track: t, size: art),
        ]),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _xpTitle(context, t,
              trailing: Row(children: [
                XpIconBtn(Icons.playlist_add_rounded, size: 50,
                    onTap: () => t.isYouTube ? showYtAddToPlaylist(context, t) : showAddToPlaylistSheet(context, t)),
                const SizedBox(width: 8),
                XpLikeButton(track: t),
              ])),
        ),
        const SizedBox(height: 14),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpTransport(context)),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ── Style 2: Canvas ──
class _XpCanvasPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpCanvasPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final artH = c.maxHeight * 0.52;
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: artH,
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -500) audioHandler.skipToNext();
              if (v > 500) audioHandler.skipToPrevious();
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: SizedBox.expand(key: ValueKey(t.id), child: xpTrackArt(t, hiRes: true)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: artH * 0.45,
          height: artH * 0.56,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.surface.withOpacity(0), cs.surface],
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, top: 0, child: _xpTopBar(context, t)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: artH - 70,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _xpTitle(context, t, size: 30, trailing: XpLikeButton(track: t, size: 54)),
            ),
            const Spacer(),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              XpIconBtn(Icons.skip_previous_rounded, size: 62, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
                  onTap: audioHandler.skipToPrevious),
              const XpPlayButton(size: 92),
              XpIconBtn(Icons.skip_next_rounded, size: 62, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
                  onTap: audioHandler.skipToNext),
            ]),
            const Spacer(),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
            const SizedBox(height: 12),
          ]),
        ),
      ]);
    });
  }
}

// ── Style 3: Vinyl ──
class _XpVinylPlayer extends StatefulWidget {
  final TrackItem track;
  const _XpVinylPlayer({required this.track});
  @override
  State<_XpVinylPlayer> createState() => _XpVinylPlayerState();
}

class _XpVinylPlayerState extends State<_XpVinylPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  StreamSubscription<bool>? _sub;
  @override
  void initState() {
    super.initState();
    _sub = audioHandler.player.playingStream.listen((p) {
      if (!mounted) return;
      p ? _spin.repeat() : _spin.stop();
    });
    if (audioHandler.player.playing) _spin.repeat();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = widget.track;
    return LayoutBuilder(builder: (context, c) {
      final d = min(c.maxWidth - 40, c.maxHeight * 0.46);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(),
        GestureDetector(
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v < -500) audioHandler.skipToNext();
            if (v > 500) audioHandler.skipToPrevious();
          },
          onTap: () => audioHandler.player.playing ? audioHandler.pause() : audioHandler.play(),
          child: AnimatedBuilder(
            animation: _spin,
            builder: (context, child) => Transform.rotate(angle: _spin.value * 2 * pi, child: child),
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF111111),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 14))],
                gradient: SweepGradient(colors: [
                  const Color(0xFF151515),
                  const Color(0xFF2A2A2A),
                  const Color(0xFF151515),
                  const Color(0xFF262626),
                  const Color(0xFF151515),
                ]),
              ),
              child: Stack(alignment: Alignment.center, children: [
                for (var r = 0.95; r > 0.5; r -= 0.07)
                  Container(
                    width: d * r,
                    height: d * r,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
                    ),
                  ),
                ClipOval(child: SizedBox(width: d * 0.46, height: d * 0.46, child: xpTrackArt(t, hiRes: true))),
                Container(
                  width: d * 0.06,
                  height: d * 0.06,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface),
                ),
              ]),
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _xpTitle(context, t, trailing: XpLikeButton(track: t)),
        ),
        const SizedBox(height: 14),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
        const SizedBox(height: 14),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpTransport(context, height: 76)),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ── Style 4: Tonal card ──
class _XpCardPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpCardPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 80, c.maxHeight * 0.38);
      return Column(children: [
        _xpTopBar(context, t),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(40)),
            child: Column(children: [
              XpPlayerArt(track: t, size: art),
              const Spacer(),
              _xpTitle(context, t, size: 24, trailing: XpLikeButton(track: t, size: 48)),
              const Spacer(),
              const XpWaveSeek(),
              const Spacer(),
              Row(children: [
                XpIconBtn(Icons.skip_previous_rounded, size: 56, onTap: audioHandler.skipToPrevious),
                const SizedBox(width: 10),
                Expanded(child: _XpExtendedPlay()),
                const SizedBox(width: 10),
                XpIconBtn(Icons.skip_next_rounded, size: 56, onTap: audioHandler.skipToNext),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

class _XpExtendedPlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? audioHandler.player.playing;
        return XpPress(
          onTap: () => playing ? audioHandler.pause() : audioHandler.play(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutBack,
            height: 68,
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(playing ? 22 : 34)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.onPrimary, size: 32),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(playing ? 'Pause' : 'Play',
                    key: ValueKey(playing), style: xpT(18, c: cs.onPrimary, w: FontWeight.w800)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ── Style 5: Bloom (living shapes) ──
class _XpBloomPlayer extends StatefulWidget {
  final TrackItem track;
  const _XpBloomPlayer({required this.track});
  @override
  State<_XpBloomPlayer> createState() => _XpBloomPlayerState();
}

class _XpBloomPlayerState extends State<_XpBloomPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = widget.track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 90, c.maxHeight * 0.36);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(),
        SizedBox(
          width: c.maxWidth,
          height: art + 90,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = _c.value * 2 * pi;
                Widget blob(XpShape a, XpShape b, double size, Color col, double dx, double dy, double sp) {
                  final m = 0.5 + 0.5 * sin(v * sp);
                  return Transform.translate(
                    offset: Offset(dx * cos(v * sp), dy * sin(v * sp)),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: ClipPath(clipper: XpShapeClipper(a, b, m, v * 0.5 * sp), child: ColoredBox(color: col)),
                    ),
                  );
                }

                return Stack(alignment: Alignment.center, children: [
                  blob(XpShape.clover, XpShape.flower, art * 0.75, cs.tertiaryContainer, art * 0.38, art * 0.25, 1),
                  blob(XpShape.burst, XpShape.cookie6, art * 0.6, cs.secondaryContainer, -art * 0.4, art * 0.3, 1.3),
                  blob(XpShape.ghost, XpShape.clover, art * 0.55, cs.primaryContainer, art * 0.2, -art * 0.42, 0.8),
                ]);
              },
            ),
            XpPlayerArt(track: t, size: art),
          ]),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _xpTitle(context, t, center: true, size: 26),
        ),
        const SizedBox(height: 12),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          XpLikeButton(track: t, size: 54),
          XpIconBtn(Icons.skip_previous_rounded, size: 60, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
              onTap: audioHandler.skipToPrevious),
          const XpPlayButton(size: 84, pausedShape: XpShape.flower, playingShape: XpShape.cookie9),
          XpIconBtn(Icons.skip_next_rounded, size: 60, bg: cs.secondaryContainer, fg: cs.onSecondaryContainer,
              onTap: audioHandler.skipToNext),
          XpIconBtn(Icons.queue_music_rounded, size: 54, onTap: () => showXpQueueSheet(context)),
        ]),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ── Style 6: Lyrics first ──
class _XpLyricsPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpLyricsPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = track;
    return Column(children: [
      _xpTopBar(context, t),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(children: [
          XpPlayerArt(track: t, size: 76),
          const SizedBox(width: 14),
          Expanded(child: _xpTitle(context, t, size: 20)),
          XpLikeButton(track: t, size: 46),
        ]),
      ),
      Expanded(child: XpLyricsView(track: t, compact: true)),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: XpWaveSeek()),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpTransport(context, height: 70)),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _xpActions(context, t, showLyrics: false)),
      const SizedBox(height: 10),
    ]);
  }
}

// ── Style 7: Minimal ──
class _XpMinimalPlayer extends StatelessWidget {
  final TrackItem track;
  const _XpMinimalPlayer({required this.track});
  @override
  Widget build(BuildContext context) {
    final t = track;
    return LayoutBuilder(builder: (context, c) {
      final art = min(c.maxWidth - 120, c.maxHeight * 0.34);
      return Column(children: [
        _xpTopBar(context, t),
        const Spacer(flex: 2),
        XpPlayerArt(track: t, size: art),
        const Spacer(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: _xpTitle(context, t, center: true, size: 30)),
        const Spacer(),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: XpWaveSeek(height: 22, stroke: 4)),
        const Spacer(),
        const XpPlayButton(size: 104),
        const Spacer(flex: 2),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _xpActions(context, t)),
        const SizedBox(height: 12),
      ]);
    });
  }
}

// ═══════════════════════════════ Lyrics ═══════════════════════════════

class XpLyricsPage extends StatelessWidget {
  final TrackItem track;
  const XpLyricsPage({super.key, required this.track});
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, Color.lerp(cs.primaryContainer, cs.surface, 0.6)!, cs.surface],
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: audioHandler.currentIndex,
            builder: (context, _, __) {
              final t = audioHandler.currentTrack ?? track;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: cs.onPrimaryContainer),
                      onPressed: () => Navigator.pop(context),
                    ),
                    XpShaped(shape: XpShape.cookie9, size: 42, child: xpTrackArt(t)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: xpT(15, c: cs.onPrimaryContainer)),
                        Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: xpT(13, w: FontWeight.w500, c: cs.onPrimaryContainer.withOpacity(0.75))),
                      ]),
                    ),
                  ]),
                ),
                Expanded(child: XpLyricsView(track: t)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 16),
                  child: Row(children: [
                    const Expanded(child: XpWaveSeek(height: 22, stroke: 4)),
                    const SizedBox(width: 14),
                    XpPlayButton(size: 60),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Synced lyrics that scroll to the live line; the live line grows and glows.
/// Tap any line to jump there.
class XpLyricsView extends StatefulWidget {
  final TrackItem track;
  final bool compact;
  const XpLyricsView({super.key, required this.track, this.compact = false});
  @override
  State<XpLyricsView> createState() => _XpLyricsViewState();
}

class _XpLyricsViewState extends State<XpLyricsView> {
  final ScrollController _sc = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _cur = -1;
  bool _userScrolling = false;
  Timer? _resume;

  @override
  void dispose() {
    _sc.dispose();
    _resume?.cancel();
    super.dispose();
  }

  void _scrollTo(int i) {
    if (_userScrolling) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.35, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final big = widget.compact ? 24.0 : 30.0;
    final small = widget.compact ? 20.0 : 25.0;
    return FutureBuilder<LyricsResult?>(
      future: fetchLyrics(widget.track),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: XpLoading());
        final r = snap.data;
        if (r == null || r.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              XpShaped(
                shape: XpShape.flower,
                size: 70,
                child: Container(color: cs.secondaryContainer, child: Icon(Icons.lyrics_outlined, color: cs.onSecondaryContainer)),
              ),
              const SizedBox(height: 12),
              Text('No lyrics for this song', style: xpT(16, c: cs.onSurfaceVariant)),
            ]),
          );
        }
        if (r.synced.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [Text(r.plain!.trim(), style: xpT(small, w: FontWeight.w800, h: 1.35))],
          );
        }
        final lines = r.synced;
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              _userScrolling = true;
              _resume?.cancel();
              _resume = Timer(const Duration(seconds: 3), () => _userScrolling = false);
            }
            return false;
          },
          child: StreamBuilder<Duration>(
            stream: audioHandler.player.positionStream,
            builder: (context, s) {
              final pos = (s.data ?? audioHandler.player.position) + const Duration(milliseconds: 250);
              var cur = -1;
              for (var i = 0; i < lines.length; i++) {
                if (lines[i].$1 <= pos) {
                  cur = i;
                } else {
                  break;
                }
              }
              if (cur != _cur) {
                _cur = cur;
                if (cur >= 0) _scrollTo(cur);
              }
              return ListView.builder(
                controller: _sc,
                padding: EdgeInsets.fromLTRB(24, widget.compact ? 20 : 80, 24, 240),
                itemCount: lines.length,
                itemBuilder: (context, i) {
                  final on = i == cur;
                  final past = i < cur;
                  final key = _keys.putIfAbsent(i, () => GlobalKey());
                  final txt = lines[i].$2.trim().isEmpty ? '♪' : lines[i].$2;
                  return GestureDetector(
                    key: key,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _userScrolling = false;
                      audioHandler.seek(lines[i].$1);
                    },
                    child: AnimatedScale(
                      scale: on ? 1.0 : 0.96,
                      alignment: Alignment.centerLeft,
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        style: xpT(on ? big : small, w: FontWeight.w900, h: 1.2).copyWith(
                          color: on
                              ? cs.onSurface
                              : cs.onSurface.withOpacity(past ? 0.35 : 0.5),
                          shadows: on ? [Shadow(color: cs.primary.withOpacity(0.6), blurRadius: 22)] : const [],
                        ),
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Text(txt)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════ Sound & tools ═══════════════════════════════

/// Equalizer on the main player (created in main.dart).
Future<void> xpEqRestore() async {
  try {
    final on = appState.b('xp_eq_on');
    await xpEqualizer.setEnabled(on);
    if (!on) return;
    final p = await xpEqualizer.parameters.timeout(const Duration(seconds: 6));
    for (var i = 0; i < p.bands.length; i++) {
      await p.bands[i].setGain(appState.d('xp_eq_$i', 0));
    }
  } catch (_) {}
}

const Map<String, List<double>> kXpEqPresets = {
  'Flat': [0, 0, 0, 0, 0],
  'Bass boost': [0.75, 0.45, 0, 0, 0.1],
  'Vocal': [-0.2, 0, 0.45, 0.35, 0],
  'Treble': [0, 0, 0.1, 0.45, 0.75],
  'Loud': [0.5, 0.25, 0, 0.25, 0.5],
};

void showXpToolsSheet(BuildContext context, {bool focusSleep = false}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(child: _XpToolsSheet(focusSleep: focusSleep)),
  );
}

class _XpToolsSheet extends StatefulWidget {
  final bool focusSleep;
  const _XpToolsSheet({required this.focusSleep});
  @override
  State<_XpToolsSheet> createState() => _XpToolsSheetState();
}

class _XpToolsSheetState extends State<_XpToolsSheet> {
  AndroidEqualizerParameters? _eq;
  List<double> _gains = [];
  String _preset = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await xpEqualizer.parameters.timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() {
        _eq = p;
        _gains = [for (var i = 0; i < p.bands.length; i++) appState.d('xp_eq_$i', 0)];
        _preset = appState.str('xp_eq_preset', 'Flat');
      });
    } catch (_) {}
  }

  Future<void> _setGain(int i, double g) async {
    final p = _eq;
    if (p == null) return;
    final clamped = g.clamp(p.minDecibels, p.maxDecibels);
    setState(() {
      _gains[i] = clamped;
      _preset = 'Custom';
    });
    appState.setD('xp_eq_$i', clamped);
    appState.setStr('xp_eq_preset', 'Custom');
    if (!appState.b('xp_eq_on')) {
      appState.setB('xp_eq_on', true);
      await xpEqualizer.setEnabled(true);
    }
    try {
      await p.bands[i].setGain(clamped);
    } catch (_) {}
  }

  Future<void> _applyPreset(String name) async {
    final p = _eq;
    if (p == null) return;
    final shape = kXpEqPresets[name]!;
    final n = p.bands.length;
    for (var i = 0; i < n; i++) {
      final f = n == 1 ? 0.0 : i / (n - 1) * (shape.length - 1);
      final lo = f.floor(), hi = min(shape.length - 1, lo + 1);
      final v = shape[lo] + (shape[hi] - shape[lo]) * (f - lo);
      final g = v * p.maxDecibels;
      _gains[i] = g;
      appState.setD('xp_eq_$i', g);
      try {
        await p.bands[i].setGain(g);
      } catch (_) {}
    }
    appState.setStr('xp_eq_preset', name);
    final on = name != 'Flat';
    appState.setB('xp_eq_on', on);
    await xpEqualizer.setEnabled(on);
    if (mounted) setState(() => _preset = name);
  }

  String _hz(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)}k' : f.round().toString();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: Listenable.merge([appState, audioHandler.sleepLabel]),
      builder: (context, _) {
        final crossOn = appState.b('crossfade_on');
        final cross = appState.d('crossfade_secs', 6.0);
        final speed = appState.speed;
        final sleep = audioHandler.sleepLabel.value;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: widget.focusSleep ? 0.6 : 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, sc) => ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
            children: [
              Text('Sound & tools', style: xpT(26, w: FontWeight.w800)),
              const SizedBox(height: 14),
              // Sleep timer
              _card(context, 'SLEEP TIMER', sleep ?? 'Off', Icons.bedtime_rounded, child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in [15, 30, 45, 60, 90])
                  XpChip(
                    label: '$m min',
                    selected: false,
                    onTap: () {
                      audioHandler.setSleepTimer(Duration(minutes: m));
                      xpSnack(context, 'Stopping in $m minutes');
                    },
                  ),
                XpChip(label: 'End of song', selected: false, onTap: () => audioHandler.setSleepTimer(null, endOfSong: true)),
                if (sleep != null) XpChip(label: 'Turn off', selected: false, onTap: () => audioHandler.setSleepTimer(null)),
              ])),
              const SizedBox(height: 10),
              // Equalizer
              _card(
                context,
                'EQUALIZER',
                appState.b('xp_eq_on') ? _preset : 'Off',
                Icons.equalizer_rounded,
                child: _eq == null
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text('Play a song to use the equalizer.', style: xpT(13.5, c: cs.onSurfaceVariant)),
                      )
                    : Column(children: [
                        SizedBox(
                          height: 38,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final name in kXpEqPresets.keys)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: XpChip(label: name, selected: _preset == name, onTap: () => _applyPreset(name)),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 170,
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                            for (var i = 0; i < _eq!.bands.length; i++)
                              _XpEqBand(
                                value: (_gains[i] - _eq!.minDecibels) / (_eq!.maxDecibels - _eq!.minDecibels),
                                label: _hz(_eq!.bands[i].centerFrequency),
                                onChanged: (v) => _setGain(i, _eq!.minDecibels + v * (_eq!.maxDecibels - _eq!.minDecibels)),
                              ),
                          ]),
                        ),
                      ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _card(context, 'CROSSFADE', crossOn ? '${cross.round()} s' : 'Off', Icons.compare_arrows_rounded,
                      child: Column(children: [
                        Switch(
                          value: crossOn,
                          onChanged: (v) => appState.setB('crossfade_on', v),
                        ),
                        Slider(
                          value: cross.clamp(1, 12),
                          min: 1,
                          max: 12,
                          divisions: 11,
                          onChanged: crossOn ? (v) => appState.setD('crossfade_secs', v) : null,
                        ),
                      ])),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _card(context, 'SPEED', '${speed.toStringAsFixed(2)}×', Icons.speed_rounded,
                      child: Column(children: [
                        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                          for (final v in [0.75, 1.0, 1.25, 1.5])
                            XpChip(
                              label: '$v×',
                              selected: (speed - v).abs() < 0.01,
                              onTap: () {
                                appState.setSpeed(v);
                                audioHandler.setSpeed(v);
                              },
                            ),
                        ]),
                      ])),
                ),
              ]),
              const SizedBox(height: 10),
              _card(context, 'PITCH', appState.pitch.toStringAsFixed(2), Icons.graphic_eq_rounded,
                  child: Slider(
                    value: appState.pitch.clamp(0.5, 1.5),
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
                    onChanged: (v) {
                      appState.setPitch(v);
                      audioHandler.setSpeed(appState.speed);
                    },
                  )),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: XpPress(
                    onTap: () => appState.setB('skip_silence', !appState.b('skip_silence')),
                    child: _pill(context, Icons.fast_forward_rounded, 'Skip silence', appState.b('skip_silence')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: XpPress(
                    onTap: () {
                      Navigator.pop(context);
                      startOrStepAiDj(openInPlayer: context);
                    },
                    child: _pill(context, Icons.graphic_eq_rounded, 'AI DJ', false, tertiary: true),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(BuildContext context, IconData icon, String label, bool on, {bool tertiary = false}) {
    final cs = context.cs;
    final bg = tertiary ? cs.tertiaryContainer : (on ? cs.primaryContainer : cs.surfaceContainerHigh);
    final fg = tertiary ? cs.onTertiaryContainer : (on ? cs.onPrimaryContainer : cs.onSurface);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      height: 64,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(on ? 32 : 22)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: fg),
        const SizedBox(width: 8),
        Text(label, style: xpT(15, c: fg, w: FontWeight.w700)),
      ]),
    );
  }

  Widget _card(BuildContext context, String label, String value, IconData icon, {required Widget child}) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800))),
        ]),
        const SizedBox(height: 2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: Text(value, key: ValueKey(value), style: xpT(22, w: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

/// A fat vertical EQ slider (pill track with a fill that squishes while dragged).
class _XpEqBand extends StatefulWidget {
  final double value;
  final String label;
  final ValueChanged<double> onChanged;
  const _XpEqBand({required this.value, required this.label, required this.onChanged});
  @override
  State<_XpEqBand> createState() => _XpEqBandState();
}

class _XpEqBandState extends State<_XpEqBand> {
  bool _drag = false;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(children: [
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight;
          void set(double y) => widget.onChanged((1 - y / h).clamp(0.0, 1.0));
          return GestureDetector(
            onVerticalDragStart: (d) {
              setState(() => _drag = true);
              HapticFeedback.selectionClick();
              set(d.localPosition.dy);
            },
            onVerticalDragUpdate: (d) => set(d.localPosition.dy),
            onVerticalDragEnd: (_) => setState(() => _drag = false),
            onTapDown: (d) => set(d.localPosition.dy),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              width: _drag ? 40 : 32,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.antiAlias,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: max(10.0, h * widget.value.clamp(0.0, 1.0)),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(16)),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(widget.label, style: xpT(11, c: cs.onSurfaceVariant)),
    ]);
  }
}

// ═══════════════════════════════ Queue ═══════════════════════════════

void showXpQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => XpThemed(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListenableBuilder(
          listenable: Listenable.merge([audioHandler.currentIndex, audioHandler.upNextRevision]),
          builder: (ctx, _) {
            final cs = ctx.cs;
            final queued = audioHandler.upNext;
            final all = audioHandler.tracks;
            final at = audioHandler.index;
            final cur = audioHandler.currentTrack;
            final after = [for (var i = at + 1; i < all.length && i < at + 80; i++) i];
            return ListView(
              controller: sc,
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                  child: Row(children: [
                    Expanded(child: Text('Queue', style: xpT(26, w: FontWeight.w800))),
                    if (queued.isNotEmpty)
                      TextButton(onPressed: audioHandler.clearQueue, child: Text('Clear', style: xpT(14, c: cs.primary))),
                  ]),
                ),
                if (cur != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                    child: Text('NOW PLAYING', style: xpT(11.5, c: cs.primary, ls: 0.8, w: FontWeight.w800)),
                  ),
                  XpSongRow(track: cur, shape: XpShape.cookie9, onTap: () {}),
                ],
                if (queued.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('UP NEXT', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800)),
                  ),
                  for (var q = 0; q < queued.length; q++)
                    Dismissible(
                      key: ValueKey('q${queued[q].id}_$q'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: cs.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
                      ),
                      onDismissed: (_) => audioHandler.removeFromQueue(q),
                      child: XpSongRow(track: queued[q], onTap: () {}),
                    ),
                ],
                if (after.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('LATER', style: xpT(11.5, c: cs.onSurfaceVariant, ls: 0.8, w: FontWeight.w800)),
                  ),
                for (final i in after) XpSongRow(track: all[i], onTap: () => audioHandler.playIndex(i)),
              ],
            );
          },
        ),
      ),
    ),
  );
}
