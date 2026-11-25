import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'main.dart';

// ── Material 3 Tonal Color Scheme (No Liquid Glass, No Harsh Borders) ────────
ColorScheme _m3() {
  final seed = appState.wallpaperColor ?? const Color(0xFF7B88D8);
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  if (appState.b('pure_black_dark', false)) {
    return base.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0E0E11),
      surfaceContainer: const Color(0xFF16161B),
      surfaceContainerHigh: const Color(0xFF1F1F26),
      surfaceContainerHighest: const Color(0xFF2A2A33),
    );
  }
  return base;
}

const Color _kBrandCrimson = Color(0xFFFF2A5F);

/// Instant in-memory cache for Liked Music so it opens immediately
YtAlbumPage? _memLikedPage;

/// Smooth Material 3 slide + fade route transition
Route<T> _revivedRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    );


/// In-memory caches for exact album dates & artist listener counts
final Map<String, Map<String, String>> _albumMetaCache = {};
final Map<String, String> _artistListenersCache = {};

const List<String> _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatTotalDuration(List<TrackItem> tracks) {
  final totalSec = tracks.fold<int>(0, (sum, t) => sum + t.durationSeconds);
  if (totalSec <= 0) return '';
  final mins = totalSec ~/ 60;
  if (mins >= 60) {
    final hrs = mins ~/ 60;
    final rem = mins % 60;
    return rem > 0 ? '$hrs hr $rem min' : '$hrs hr';
  }
  return '$mins min';
}

Future<Map<String, String>> _fetchAlbumMeta(String artist, String title) async {
  final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
  if (_albumMetaCache.containsKey(key)) return _albumMetaCache[key]!;
  try {
    final q = Uri.encodeQueryComponent('$artist $title');
    final res = await http
        .get(Uri.parse('https://itunes.apple.com/search?term=$q&entity=album&limit=3'))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (json['results'] as List? ?? const []).whereType();
      Map? best;
      final tLow = title.toLowerCase();
      for (final r in results) {
        final col = (r['collectionName'] ?? '').toString().toLowerCase();
        if (col.contains(tLow) || tLow.contains(col)) {
          best = r;
          break;
        }
      }
      best ??= results.isNotEmpty ? results.first : null;
      if (best != null) {
        final out = <String, String>{};
        final rawDate = (best['releaseDate'] ?? '').toString();
        final dt = DateTime.tryParse(rawDate);
        if (dt != null) {
          out['date'] = '${_kMonths[dt.month - 1]} ${dt.day}, ${dt.year}';
        }
        final genre = (best['primaryGenreName'] ?? '').toString().trim();
        if (genre.isNotEmpty) out['genre'] = genre;
        final copy = (best['copyright'] ?? '').toString().trim();
        if (copy.isNotEmpty) out['copyright'] = copy;
        _albumMetaCache[key] = out;
        return out;
      }
    }
  } catch (_) {}
  _albumMetaCache[key] = const {};
  return const {};
}

Future<String?> _fetchArtistListeners(String url, String name) async {
  if (_artistListenersCache.containsKey(url)) return _artistListenersCache[url];
  try {
    final page = await YouTubeMusic.artist(url, name);
    final txt = page.subscribersText?.trim();
    if (txt != null && txt.isNotEmpty) {
      _artistListenersCache[url] = txt;
      return txt;
    }
  } catch (_) {}
  return null;
}

/// Seamless hero backdrop that NEVER leaves a 1px horizontal seam at the bottom
List<Widget> _seamlessHeroLayers(ColorScheme cs, Widget backdrop, {double topOpacity = 0.5}) => [
      Positioned(top: 0, left: 0, right: 0, bottom: 2, child: backdrop),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.40, 0.78, 0.94, 1.0],
              colors: [
                cs.surface.withOpacity(topOpacity),
                cs.surface.withOpacity(0.12),
                cs.surface.withOpacity(0.88),
                cs.surface,
                cs.surface,
              ],
            ),
          ),
        ),
      ),
      Positioned(left: 0, right: 0, bottom: -1, height: 5, child: ColoredBox(color: cs.surface)),
    ];

/// Edge-to-edge artwork helper that NEVER letterboxes or crops weirdly

/// Animated Heart Button with spring bounce, shockwave ring, and radial sparkle burst
class _AnimatedHeartButton extends StatefulWidget {
  final bool liked;
  final Color activeColor;
  final Color inactiveColor;
  final double size;
  final VoidCallback onTap;

  const _AnimatedHeartButton({
    required this.liked,
    required this.activeColor,
    required this.inactiveColor,
    this.size = 26,
    required this.onTap,
  });

  @override
  State<_AnimatedHeartButton> createState() => _AnimatedHeartButtonState();
}

class _AnimatedHeartButtonState extends State<_AnimatedHeartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.72).chain(CurveTween(curve: Curves.easeIn)), weight: 16),
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.38).chain(CurveTween(curve: Curves.easeOutBack)), weight: 36),
      TweenSequenceItem(tween: Tween(begin: 1.38, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 48),
    ]).animate(_ctrl);
  }

  @override
  void didUpdateWidget(covariant _AnimatedHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liked && !oldWidget.liked) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.liked) {
      HapticFeedback.mediumImpact();
      _ctrl.forward(from: 0.0);
    } else {
      HapticFeedback.selectionClick();
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (widget.liked && _ctrl.isAnimating)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _HeartBurstPainter(
                        progress: _ctrl.value,
                        color: widget.activeColor,
                      ),
                    ),
                  ),
                Transform.scale(
                  scale: widget.liked ? _scale.value : 1.0,
                  child: Icon(
                    widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: widget.liked ? widget.activeColor : widget.inactiveColor,
                    size: widget.size,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeartBurstPainter extends CustomPainter {
  final double progress;
  final Color color;

  _HeartBurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;
    final center = Offset(size.width / 2, size.height / 2);

    final ringP = (progress / 0.62).clamp(0.0, 1.0);
    if (ringP < 1.0) {
      final eased = Curves.easeOutCubic.transform(ringP);
      final ringPaint = Paint()
        ..color = color.withOpacity((1.0 - ringP) * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * (1.0 - ringP) + 0.5;
      canvas.drawCircle(center, 6.0 + 20.0 * eased, ringPaint);
    }

    final partP = ((progress - 0.10) / 0.90).clamp(0.0, 1.0);
    if (partP > 0.0) {
      final eased = Curves.easeOutCubic.transform(partP);
      final fade = (1.0 - partP).clamp(0.0, 1.0);
      final softColor = Color.lerp(color, Colors.white, 0.55) ?? Colors.white;
      for (var i = 0; i < 8; i++) {
        final angle = (i * pi / 4) - (pi / 2) + (i.isOdd ? 0.14 : 0.0);
        final dist = 9.0 + (i.isEven ? 18.0 : 14.0) * eased;
        final pos = Offset(center.dx + cos(angle) * dist, center.dy + sin(angle) * dist);
        final r = (i.isEven ? 3.1 : 2.1) * fade;
        final dotPaint = Paint()..color = (i.isEven ? color : softColor).withOpacity(fade);
        canvas.drawCircle(pos, r, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeartBurstPainter old) =>
      old.progress != progress || old.color != color;
}

Widget _coverArt(TrackItem track, {double? size}) {
  final url = track.artworkUrl;
  if (url != null && url.isNotEmpty) {
    return Image.network(
      url,
      width: size ?? double.infinity,
      height: size ?? double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: size ?? 200, height: size ?? 200, child: CustomAlbumArtwork(track: track)),
      ),
    );
  }
  return FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(width: size ?? 200, height: size ?? 200, child: CustomAlbumArtwork(track: track)),
  );
}

/// Original AlexLMP Revived Liked Cover
Widget _likedCover(ColorScheme cs, {double iconSize = 24}) => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.favorite_rounded, color: cs.onPrimaryContainer, size: iconSize)),
    );

/// Custom navigation helpers so Artist / Album ALWAYS stay inside Revived UI
Future<void> revivedGoToArtist(BuildContext context, TrackItem t) async {
  HapticFeedback.selectionClick();
  if (!t.isYouTube) {
    final local = audioHandler.tracks.where((x) => !x.isYouTube && x.artist == t.artist).toList();
    if (local.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.custom(title: t.artist, subtitle: 'Artist', tracks: local)));
    }
    return;
  }
  try {
    final links = await YouTubeMusic.trackLinks(t.ytVideoId!);
    if (!context.mounted) return;
    if (links.artistUrl != null && links.artistUrl!.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: links.artistUrl!, name: links.artistName ?? t.artist)));
      return;
    }
    final found = await YouTubeMusic.searchArtists(t.artist);
    if (!context.mounted) return;
    if (found.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: found.first.url, name: found.first.name, initialThumb: found.first.thumbnail)));
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open artist page')));
  }
}

Future<void> revivedGoToAlbum(BuildContext context, TrackItem t) async {
  HapticFeedback.selectionClick();
  if (!t.isYouTube) {
    final local = audioHandler.tracks.where((x) => !x.isYouTube && x.album == t.album).toList();
    if (local.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.custom(title: t.album, subtitle: t.artist, tracks: local)));
    }
    return;
  }
  try {
    final links = await YouTubeMusic.trackLinks(t.ytVideoId!);
    if (!context.mounted) return;
    final ref = links.albumBrowseId ?? links.albumUrl;
    if (ref != null && ref.isNotEmpty) {
      Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(
          url: ref,
          initialTitle: links.albumTitle ?? t.album,
          initialThumb: links.albumThumbnail ?? t.artworkUrl,
        )));
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No album found for this track')));
  }
}

/// The 4-bar AlexLMP Revived brand mark (Crimson default, Midnight, Stealth)
class RevivedBrandMark extends StatelessWidget {
  final double size;
  final String variant;
  const RevivedBrandMark({super.key, this.size = 44, this.variant = 'default'});

  @override
  Widget build(BuildContext context) {
    final bg = variant == 'bloom'
        ? const Color(0xFF0B1020)
        : (variant == 'bitlmp' ? Colors.black : const Color(0xFF0A0A0D));
    final b1 = variant == 'bloom'
        ? const Color(0xFF94A3B8)
        : (variant == 'bitlmp' ? const Color(0xFF71717A) : const Color(0xFFD4D4DC));
    final b2 = variant == 'bloom'
        ? const Color(0xFF3B82F6)
        : (variant == 'bitlmp' ? const Color(0xFFD4D4D8) : _kBrandCrimson);
    final b4 = variant == 'bloom'
        ? const Color(0xFF3B82F6)
        : (variant == 'bitlmp' ? const Color(0xFFA1A1AA) : _kBrandCrimson);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _bar(size * 0.10, size * 0.22, b1),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.46, b2),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.58, Colors.white),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.30, b4),
          ],
        ),
      ),
    );
  }

  Widget _bar(double w, double h, Color c) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(w)),
      );
}

/// Material 3 Track Context Menu
void showRevivedTrackMenu(BuildContext context, TrackItem track) {
  final cs = _m3();
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: cs.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 52, height: 52, child: _coverArt(track, size: 52))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurface, fontSize: 15.5, fontWeight: FontWeight.w700)),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: appState,
                  builder: (_, __) => _AnimatedHeartButton(
                    liked: appState.isLiked(track.id),
                    activeColor: cs.primary,
                    inactiveColor: cs.onSurface,
                    size: 24,
                    onTap: () => appState.toggleLike(track.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: cs.outlineVariant.withOpacity(0.3)),
            _menuItem(cs, Icons.queue_play_next_rounded, 'Play next', () {
              audioHandler.addToQueue([track], next: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing "${track.title}" next')));
            }),
            _menuItem(cs, Icons.add_to_queue_rounded, 'Add to queue', () {
              audioHandler.addToQueue([track]);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${track.title}" to queue')));
            }),
            _menuItem(cs, Icons.playlist_add_rounded, 'Add to playlist', () {
              Navigator.pop(ctx);
              track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track);
            }),
            if (track.isYouTube)
              _menuItem(
                cs,
                OfflineStore.isDownloaded(track) ? Icons.download_done_rounded : Icons.download_for_offline_rounded,
                OfflineStore.isDownloaded(track) ? 'Remove download' : 'Download for offline',
                () {
                  Navigator.pop(ctx);
                  toggleOffline(track);
                },
              ),
            _menuItem(cs, Icons.lyrics_outlined, 'View lyrics', () {
              Navigator.pop(ctx);
              showLyricsSheet(context, track);
            }),
            _menuItem(cs, Icons.person_outline_rounded, 'Go to artist', () {
              Navigator.pop(ctx);
              revivedGoToArtist(context, track);
            }),
            _menuItem(cs, Icons.album_outlined, 'Go to album', () {
              Navigator.pop(ctx);
              revivedGoToAlbum(context, track);
            }),
            _menuItem(cs, Icons.share_rounded, 'Share', () {
              Navigator.pop(ctx);
              shareTrack(track);
            }),
            _menuItem(cs, Icons.edit_outlined, 'Edit details', () {
              Navigator.pop(ctx);
              showEditTrackDialog(context, track);
            }),
            _menuItem(cs, Icons.info_outline_rounded, 'Track info', () {
              Navigator.pop(ctx);
              showTrackInfoDialog(context, track);
            }),
          ],
        ),
      ),
    ),
  );
}

Widget _menuItem(ColorScheme cs, IconData icon, String title, VoidCallback onTap) => ListTile(
      dense: true,
      leading: Icon(icon, color: cs.onSurfaceVariant, size: 22),
      title: Text(title, style: TextStyle(color: cs.onSurface, fontSize: 14.5, fontWeight: FontWeight.w500)),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );

// ═════════════════════════════════════════════════════════════════════════════
// 1. 2-STEP SETUP WIZARD (Permissions -> Sign in)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSetupScreen extends StatefulWidget {
  const RevivedSetupScreen({super.key});
  @override
  State<RevivedSetupScreen> createState() => _RevivedSetupScreenState();
}

class _RevivedSetupScreenState extends State<RevivedSetupScreen> {
  final PageController _pageCtrl = PageController();
  int _step = 0;
  bool _storageOk = false;
  bool _signingIn = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < 1) {
      setState(() => _step++);
      _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _grantStorage() async {
    HapticFeedback.lightImpact();
    final ok = await ensureMediaPermissions();
    if (mounted) setState(() => _storageOk = ok);
  }

  Future<void> _signIn() async {
    HapticFeedback.lightImpact();
    setState(() => _signingIn = true);
    try {
      await YouTubeMusic.signIn();
    } catch (_) {}
    if (mounted) setState(() => _signingIn = false);
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    appState.setB('setup_done', true);
    appState.setStr('home_mode', 'youtube');
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, __, ___) => const AlexLmpRoot(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                      onPressed: _back,
                    )
                  else
                    const RevivedBrandMark(size: 36),
                  const SizedBox(width: 14),
                  for (var i = 0; i < 2; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        height: 4,
                        margin: EdgeInsets.only(right: i < 1 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: i <= _step ? cs.primary : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [_buildPermissionsStep(cs), _buildSignInStep(cs)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsStep(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step 1 of 2', style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Music & notifications',
              style: TextStyle(color: cs.onSurface, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          Text('Allow access so AlexLMP Revived can scan local audio files and show lock-screen controls.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, height: 1.4)),
          const SizedBox(height: 28),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _storageOk ? null : _grantStorage,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _storageOk ? cs.primaryContainer : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(_storageOk ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                      color: _storageOk ? cs.onPrimaryContainer : cs.primary, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_storageOk ? 'Permissions granted' : 'Grant media permissions',
                            style: TextStyle(color: _storageOk ? cs.onPrimaryContainer : cs.onSurface, fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Audio storage & playback notifications',
                            style: TextStyle(color: _storageOk ? cs.onPrimaryContainer.withOpacity(0.8) : cs.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (!_storageOk) Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              onPressed: _next,
              child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInStep(ColorScheme cs) {
    return ValueListenableBuilder<YtAccount>(
      valueListenable: ytAccount,
      builder: (context, acc, _) {
        final signedIn = acc.signedIn;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Step 2 of 2', style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Sign in to YouTube Music',
                  style: TextStyle(color: cs.onSurface, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const SizedBox(height: 8),
              Text('Connect your account to stream music and sync your liked songs and playlists.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, height: 1.4)),
              const SizedBox(height: 28),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: (signedIn || _signingIn) ? null : _signIn,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: signedIn ? cs.primaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _signingIn
                          ? SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary))
                          : Icon(signedIn ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                              color: signedIn ? cs.onPrimaryContainer : cs.primary, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(signedIn ? 'Signed in as ${acc.name ?? "YouTube user"}' : 'Connect YouTube Music',
                                style: TextStyle(color: signedIn ? cs.onPrimaryContainer : cs.onSurface, fontSize: 15.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(signedIn ? 'Ready to listen' : 'Tap to sign in with Google',
                                style: TextStyle(color: signedIn ? cs.onPrimaryContainer.withOpacity(0.8) : cs.onSurfaceVariant, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: signedIn ? cs.primary : cs.surfaceContainerHighest,
                    foregroundColor: signedIn ? cs.onPrimary : cs.onSurfaceVariant,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  onPressed: signedIn ? _finish : null,
                  child: Text(signedIn ? 'Start listening' : 'Sign in to continue',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
              if (!signedIn) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: _finish,
                    child: Text('Skip for now', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. MATERIAL 3 TONAL APP SHELL (Home, Discover, Library + Fixed Orb Dock)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedAppShell extends StatefulWidget {
  final List<TrackItem> tracks;
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const RevivedAppShell({super.key, required this.tracks, this.aiChatBuilder});

  @override
  State<RevivedAppShell> createState() => _RevivedAppShellState();
}

class _RevivedAppShellState extends State<RevivedAppShell> {
  int _tab = 0; // 0=Home, 1=Discover, 2=Library
  int _libTab = 0; // 0=Playlists, 1=Artists, 2=Albums, 3=Songs
  int _searchTab = 0; // 0=All, 1=Songs, 2=Artists, 3=Albums, 4=Playlists, 5=Videos

  final TextEditingController _searchCtrl = TextEditingController();
  List<TrackItem> _songRes = [];
  List<YtArtist> _artistRes = [];
  List<YtAlbum> _albumRes = [];
  List<YtPlaylistRef> _playlistRes = [];
  List<YtVideoResult> _videoRes = [];
  bool _searching = false;
  Timer? _debounce;
  Future<List<YtShelf>>? _ytFeedFuture;
  Future<List<YtPlaylistRef>>? _ytPlFuture;

  @override
  void initState() {
    super.initState();
    _ytFeedFuture = YouTubeMusic.homeFeed();
    _ytPlFuture = YouTubeMusic.libraryPlaylists();
    _preloadLikedMusic();
    appState.setB('update_check', true);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkRevivedUpdate(context));
  }

  Future<void> _preloadLikedMusic() async {
    _memLikedPage ??= YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music');
    try {
      final fresh = await YouTubeMusic.playlistPage('LM', title: 'Liked Music');
      _memLikedPage = fresh;
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _searchHistory {
    try {
      return YouTubeMusic.prefs?.getStringList('search_history') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  void _saveSearchHistory(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    final list = [trimmed, ..._searchHistory.where((x) => x.toLowerCase() != trimmed.toLowerCase())].take(10).toList();
    YouTubeMusic.prefs?.setStringList('search_history', list);
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _songRes = [];
        _artistRes = [];
        _albumRes = [];
        _playlistRes = [];
        _videoRes = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _saveSearchHistory(q);
    setState(() => _searching = true);
    try {
      if (_searchTab == 0) {
        final results = await Future.wait([
          YouTubeMusic.searchArtists(q).catchError((_) => <YtArtist>[]),
          YouTubeMusic.search(q).catchError((_) => <TrackItem>[]),
          YouTubeMusic.searchAlbums(q).catchError((_) => <YtAlbum>[]),
        ]);
        if (mounted) {
          setState(() {
            _artistRes = results[0] as List<YtArtist>;
            _songRes = results[1] as List<TrackItem>;
            _albumRes = results[2] as List<YtAlbum>;
          });
        }
      } else if (_searchTab == 1) {
        final r = await YouTubeMusic.search(q);
        if (mounted) setState(() => _songRes = r);
      } else if (_searchTab == 2) {
        final r = await YouTubeMusic.searchArtists(q);
        if (mounted) setState(() => _artistRes = r);
      } else if (_searchTab == 3) {
        final r = await YouTubeMusic.searchAlbums(q);
        if (mounted) setState(() => _albumRes = r);
      } else if (_searchTab == 4) {
        final r = await YouTubeMusic.searchPlaylists(q);
        if (mounted) setState(() => _playlistRes = r);
      } else {
        final r = await YouTubeMusic.searchVideos(q);
        if (mounted) setState(() => _videoRes = r);
      }
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _openShelfItem(YtShelfItem it) {
    HapticFeedback.selectionClick();
    if (it.kind == 'album') {
      Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail)));
    } else if (it.kind == 'artist') {
      Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: it.id, name: it.title, initialThumb: it.thumbnail)));
    } else if (it.kind == 'playlist') {
      Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.youtube(playlistId: it.id, title: it.title, thumbnail: it.thumbnail)));
    } else {
      final t = YouTubeMusic.trackFromShelf(it, it.subtitle);
      audioHandler.playYouTubeTrack(t);
      openPlayer(context);
    }
  }

  void _playList(List<TrackItem> list, int index) {
    if (list.isEmpty) return;
    HapticFeedback.selectionClick();
    audioHandler.playYouTubeList(list, index);
    openPlayer(context);
  }

  void _shuffleAll(List<TrackItem> list) {
    if (list.isEmpty) return;
    HapticFeedback.mediumImpact();
    audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
    _playList(list, Random().nextInt(list.length));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, OfflineStore.revision, LibraryStore.revision, audioHandler.currentIndex]),
      builder: (context, _) {
        final cs = _m3();
        return Scaffold(
          backgroundColor: cs.surface,
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: _tab == 0
                        ? _buildHome(context, cs)
                        : (_tab == 1 ? _buildDiscover(context, cs) : _buildCollection(context, cs)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildMaterialDock(context, cs),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 1. CLEAN MATERIAL 3 HOME (Zero seam, no glass borders, no AI badges) ──
  Widget _buildHome(BuildContext context, ColorScheme cs) {
    final yt = appState.homeMode == 'youtube';
    final local = widget.tracks.where((t) => !t.isYouTube).toList();
    final recent = appState.recent.map(audioHandler.trackById).whereType<TrackItem>().take(8).toList();
    final heroTrack = audioHandler.currentTrack ?? (recent.isNotEmpty ? recent.first : (widget.tracks.isNotEmpty ? widget.tracks.first : null));
    final top = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      color: cs.primary,
      backgroundColor: cs.surfaceContainerHigh,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        _preloadLikedMusic();
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          // Seamless Full-Bleed Hero Header
          GestureDetector(
            onTap: () {
              if (heroTrack != null) {
                if (audioHandler.currentTrack == null) {
                  audioHandler.playYouTubeTrack(heroTrack);
                }
                openPlayer(context);
              } else {
                setState(() => _tab = 1);
              }
            },
            child: SizedBox(
              height: 300 + top,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ..._seamlessHeroLayers(
                    cs,
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
                      child: KeyedSubtree(
                        key: ValueKey(heroTrack?.id ?? 'none'),
                        child: heroTrack != null ? _coverArt(heroTrack) : ColoredBox(color: cs.surfaceContainerHigh),
                      ),
                    ),
                    topOpacity: 0.55,
                  ),
                  // Top Material Tonal Bar (no liquid glass!)
                  Positioned(
                    top: top + 10,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        _profileAvatarBtn(cs),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            appState.setStr('home_mode', yt ? 'local' : 'youtube');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              yt ? 'YouTube Music' : 'On device',
                              style: TextStyle(color: cs.onSurface, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const Spacer(),
                        _tonalCircleBtn(cs, Icons.bar_chart_rounded, () => openListeningStats(context)),
                        const SizedBox(width: 8),
                        _tonalCircleBtn(cs, Icons.settings_outlined, () => openRevivedSettings(context)),
                      ],
                    ),
                  ),
                  // Hero Track Info + Material Primary Play/Pause Button
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                heroTrack?.title ?? 'AlexLMP Revived',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurface, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                heroTrack != null ? '${heroTrack.artist} • ${heroTrack.album}' : 'Tap to search your music',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        StreamBuilder<PlaybackState>(
                          stream: audioHandler.playbackState,
                          builder: (_, snap) {
                            final playing = snap.data?.playing ?? audioHandler.player.playing;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                if (heroTrack == null) {
                                  setState(() => _tab = 1);
                                  return;
                                }
                                if (audioHandler.currentTrack == null) {
                                  audioHandler.playYouTubeTrack(heroTrack);
                                } else {
                                  playing ? audioHandler.pause() : audioHandler.play();
                                }
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      key: ValueKey(playing), color: cs.onPrimaryContainer, size: 28),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Material 3 Tonal Filter Pills (No glass borders)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _m3Pill(cs, 'Liked songs', false, () {
                  Navigator.of(context).push(_revivedRoute(const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music')));
                }),
                const SizedBox(width: 8),
                _m3Pill(cs, 'Downloads', false, () => openDownloads(context)),
                const SizedBox(width: 8),
                _m3Pill(cs, 'Shared likes', false, () {
                  Navigator.of(context).push(_revivedRoute(const RevivedSharedLikesPage()));
                }),
                const SizedBox(width: 8),
                _m3Pill(cs, 'Shuffle mix', false, () => _shuffleAll(yt ? widget.tracks : local)),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Recently played (only shown if there are at least 2 recent tracks so it never looks empty/awkward)
          if (recent.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text('Recently played', style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    for (var i = 0; i < min(4, recent.length); i++) ...[
                      _m3TrackRow(cs, recent[i], () => _playList(recent, i)),
                      if (i < min(4, recent.length) - 1)
                        Divider(height: 1, indent: 70, endIndent: 14, color: cs.outlineVariant.withOpacity(0.2)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],

          // YouTube Music Shelves or Local Tracks
          if (yt)
            FutureBuilder<List<YtShelf>>(
              future: _ytFeedFuture,
              initialData: YouTubeMusic.cachedHomeFeed(),
              builder: (context, snap) {
                final shelves = snap.data ?? const [];
                if (shelves.isEmpty && snap.connectionState == ConnectionState.waiting) {
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: cs.primary)));
                }
                if (shelves.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _emptyCard(cs, 'Search YouTube Music to start listening', 'Open discover', () => setState(() => _tab = 1)),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                        child: Text(shelf.title.isEmpty ? 'For you' : shelf.title,
                            style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      ),
                      SizedBox(
                        height: 192,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          itemCount: shelf.items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final it = shelf.items[i];
                            final isArtist = it.kind == 'artist';
                            return GestureDetector(
                              onTap: () => _openShelfItem(it),
                              child: SizedBox(
                                width: 138,
                                child: Column(
                                  crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(isArtist ? 69 : 16),
                                      child: YtNetworkImage(url: it.thumbnail, size: 138, circle: isArtist),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                    Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ],
                );
              },
            )
          else if (local.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _emptyCard(cs, 'No local audio files found', 'Add music', () => showAddMusicSheet(context)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('On this device', style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      children: [
                        for (var i = 0; i < min(25, local.length); i++) ...[
                          _m3TrackRow(cs, local[i], () => _playList(local, i)),
                          if (i < min(25, local.length) - 1)
                            Divider(height: 1, indent: 70, endIndent: 14, color: cs.outlineVariant.withOpacity(0.2)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 2. DISCOVER / SEARCH ──────────────────────────────────────────────────
  Widget _buildDiscover(BuildContext context, ColorScheme cs) {
    final top = MediaQuery.of(context).padding.top;
    const cats = ['All', 'Songs', 'Artists', 'Albums', 'Playlists', 'Videos'];
    final history = _searchHistory;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Discover', style: TextStyle(color: cs.onSurface, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: 'Artists, songs, albums, playlists…',
                hintStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _m3Pill(cs, cats[i], _searchTab == i, () {
                setState(() => _searchTab = i);
                if (_searchCtrl.text.trim().isNotEmpty) _runSearch(_searchCtrl.text.trim());
              }),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _searching
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : _searchCtrl.text.trim().isEmpty
                    ? (history.isEmpty
                        ? Center(child: Text('Search artists, songs, albums, or playlists', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)))
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 112),
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Recent searches', style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
                                  TextButton(
                                    onPressed: () {
                                      YouTubeMusic.prefs?.remove('search_history');
                                      setState(() {});
                                    },
                                    child: Text('Clear', style: TextStyle(color: cs.onSurfaceVariant)),
                                  ),
                                ],
                              ),
                              for (final h in history)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.history_rounded, color: cs.onSurfaceVariant, size: 20),
                                  title: Text(h, style: TextStyle(color: cs.onSurface, fontSize: 15)),
                                  onTap: () {
                                    _searchCtrl.text = h;
                                    _runSearch(h);
                                  },
                                ),
                            ],
                          ))
                    : _buildSearchResults(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    if (_searchTab == 0) {
      if (_artistRes.isEmpty && _songRes.isEmpty && _albumRes.isEmpty) {
        return Center(child: Text('No results found', style: TextStyle(color: cs.onSurfaceVariant)));
      }
      final topArtist = _artistRes.isNotEmpty ? _artistRes.first : null;
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          if (topArtist != null) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: topArtist.url, name: topArtist.name, initialThumb: topArtist.thumbnail)));
              },
              child: Container(
                height: 152,
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (topArtist.thumbnail != null)
                      Image.network(topArtist.thumbnail!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: cs.surfaceContainerHigh)),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, cs.surface.withOpacity(0.92)],
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
                          Text('Top artist', style: TextStyle(color: cs.primary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                          Text(topArtist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                          FutureBuilder<String?>(
                            future: _fetchArtistListeners(topArtist.url, topArtist.name),
                            initialData: _artistListenersCache[topArtist.url],
                            builder: (_, lSnap) {
                              final txt = lSnap.data;
                              if (txt == null || txt.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(txt, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_songRes.isNotEmpty) ...[
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  for (var i = 0; i < min(8, _songRes.length); i++) ...[
                    _m3TrackRow(cs, _songRes[i], () {
                      HapticFeedback.selectionClick();
                      audioHandler.playYouTubeTrack(_songRes[i]);
                      openPlayer(context);
                    }),
                    if (i < min(8, _songRes.length) - 1)
                      Divider(height: 1, indent: 70, endIndent: 14, color: cs.outlineVariant.withOpacity(0.2)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_albumRes.isNotEmpty) ...[
            Text('Albums & singles', style: TextStyle(color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _albumRes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final al = _albumRes[i];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail))),
                    child: SizedBox(
                      width: 134,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(16), child: YtNetworkImage(url: al.thumbnail, size: 134)),
                          const SizedBox(height: 6),
                          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text(al.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
    }
    if (_searchTab == 1) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: _songRes.length,
        itemBuilder: (_, i) => _m3TrackRow(cs, _songRes[i], () {
          audioHandler.playYouTubeTrack(_songRes[i]);
          openPlayer(context);
        }),
      );
    }
    if (_searchTab == 2) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: _artistRes.length,
        itemBuilder: (_, i) {
          final a = _artistRes[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FutureBuilder<String?>(
              future: _fetchArtistListeners(a.url, a.name),
              initialData: _artistListenersCache[a.url],
              builder: (_, lSnap) => _photoBannerCard(
                cs: cs,
                title: a.name,
                subtitle: lSnap.data ?? 'Artist',
                thumb: a.thumbnail,
                onTap: () => Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail))),
              ),
            ),
          );
        },
      );
    }
    if (_searchTab == 3) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: _albumRes.length,
        itemBuilder: (_, i) {
          final al = _albumRes[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _photoBannerCard(
              cs: cs,
              title: al.title,
              subtitle: al.artist,
              thumb: al.thumbnail,
              onTap: () => Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail))),
            ),
          );
        },
      );
    }
    if (_searchTab == 4) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: _playlistRes.length,
        itemBuilder: (_, i) {
          final pl = _playlistRes[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _photoBannerCard(
              cs: cs,
              title: pl.title,
              subtitle: pl.subtitle,
              thumb: pl.thumbnail,
              onTap: () => Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.youtube(playlistId: pl.playlistId, title: pl.title, thumbnail: pl.thumbnail))),
            ),
          );
        },
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 112),
      itemCount: _videoRes.length,
      itemBuilder: (_, i) => _m3TrackRow(cs, _videoRes[i].track, () {
        audioHandler.playYouTubeTrack(_videoRes[i].track);
        openPlayer(context);
      }),
    );
  }

  // ── 3. COLLECTION / LIBRARY ───────────────────────────────────────────────
  Widget _buildCollection(BuildContext context, ColorScheme cs) {
    final top = MediaQuery.of(context).padding.top;
    const filters = ['Playlists', 'Artists', 'Albums', 'Songs'];
    final songs = widget.tracks;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Library', style: TextStyle(color: cs.onSurface, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6))),
              _tonalCircleBtn(cs, Icons.file_download_outlined, () => openSpotifyImport(context)),
              const SizedBox(width: 8),
              _tonalCircleBtn(cs, Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _m3Pill(cs, filters[i], _libTab == i, () => setState(() => _libTab = i)),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildCollectionBody(cs, songs)),
        ],
      ),
    );
  }

  Widget _buildCollectionBody(ColorScheme cs, List<TrackItem> songs) {
    if (_libTab == 0) {
      return FutureBuilder<List<YtPlaylistRef>>(
        future: _ytPlFuture,
        initialData: YouTubeMusic.cachedLibrary(),
        builder: (context, snap) {
          final ytPls = snap.data ?? const <YtPlaylistRef>[];
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 112),
            children: [
              _photoBannerCard(
                cs: cs,
                title: 'Liked songs',
                subtitle: 'Synced • YouTube Music',
                customBg: _likedCover(cs, iconSize: 42),
                onTap: () => Navigator.of(context).push(_revivedRoute(const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'))),
              ),
              const SizedBox(height: 10),
              _photoBannerCard(
                cs: cs,
                title: 'Downloads',
                subtitle: '${OfflineStore.count} offline tracks • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
                customBg: Container(
                  color: cs.secondaryContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 22),
                  child: Icon(Icons.download_done_rounded, color: cs.onSecondaryContainer.withOpacity(0.25), size: 60),
                ),
                onTap: () => openDownloads(context),
              ),
              const SizedBox(height: 10),
              for (final pl in appState.playlists) ...[
                _photoBannerCard(
                  cs: cs,
                  title: pl.name,
                  subtitle: '${pl.trackIds.length} tracks • Local',
                  customBg: Container(color: cs.surfaceContainerHigh),
                  onTap: () => Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.local(playlist: pl))),
                ),
                const SizedBox(height: 10),
              ],
              for (final ypl in ytPls) ...[
                _photoBannerCard(
                  cs: cs,
                  title: ypl.title,
                  subtitle: ypl.subtitle.isEmpty ? 'Playlist • YouTube Music' : ypl.subtitle,
                  thumb: ypl.thumbnail,
                  onTap: () => Navigator.of(context).push(_revivedRoute(RevivedPlaylistPage.youtube(playlistId: ypl.playlistId, title: ypl.title, thumbnail: ypl.thumbnail))),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      );
    }
    if (_libTab == 1) {
      final byArtist = <String, List<TrackItem>>{};
      for (final t in songs) {
        byArtist.putIfAbsent(t.artist, () => []).add(t);
      }
      final list = byArtist.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: list.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _photoBannerCard(
            cs: cs,
            title: list[i].key,
            subtitle: 'Artist • ${list[i].value.length} songs',
            customBg: _coverArt(list[i].value.first),
            onTap: () => _playList(list[i].value, 0),
          ),
        ),
      );
    }
    if (_libTab == 2) {
      final byAlbum = <String, List<TrackItem>>{};
      for (final t in songs) {
        byAlbum.putIfAbsent(t.album, () => []).add(t);
      }
      final list = byAlbum.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        itemCount: list.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _photoBannerCard(
            cs: cs,
            title: list[i].key,
            subtitle: '${list[i].value.first.artist} • ${list[i].value.length} songs',
            customBg: _coverArt(list[i].value.first),
            onTap: () => _playList(list[i].value, 0),
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 112),
      itemCount: songs.length,
      itemBuilder: (_, i) => _m3TrackRow(cs, songs[i], () => _playList(songs, i)),
    );
  }

  // ── MATERIAL 3 FLOATING PILL DOCK + FIXED FULL-BLEED CIRCULAR ORB ─────────
  Widget _buildMaterialDock(BuildContext context, ColorScheme cs) {
    const labels = ['Home', 'Discover', 'Library'];
    final cur = audioHandler.currentTrack;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.surface.withOpacity(0.0), cs.surface.withOpacity(0.94), cs.surface],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.42), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _tab = i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tab == i ? cs.secondaryContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          color: _tab == i ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              // Fixed Circular Mini-Player Orb (Zero cropping/black bars!)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (cur != null) {
                    openPlayer(context);
                  } else {
                    setState(() => _tab = 1);
                  }
                },
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -300) {
                    HapticFeedback.mediumImpact();
                    audioHandler.skipToNext();
                  } else if (v > 300) {
                    HapticFeedback.mediumImpact();
                    audioHandler.skipToPreviousTrack();
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                  ),
                  child: ClipOval(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: cur != null
                          ? KeyedSubtree(key: ValueKey(cur.id), child: _coverArt(cur, size: 40))
                          : Container(
                              key: const ValueKey('empty_orb'),
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant, size: 20),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── MATERIAL 3 UI HELPERS ─────────────────────────────────────────────────
  Widget _m3Pill(ColorScheme cs, String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: TextStyle(color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _m3TrackRow(ColorScheme cs, TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    final downloaded = OfflineStore.isDownloaded(t);
    return InkWell(
      onTap: onTap,
      onLongPress: () => showRevivedTrackMenu(context, t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 46, height: 46, child: _coverArt(t, size: 46))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? cs.primary : cs.onSurface, fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (downloaded) ...[
                        Icon(Icons.download_done_rounded, size: 13, color: cs.primary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant, size: 19),
              onPressed: () => showRevivedTrackMenu(context, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoBannerCard({required ColorScheme cs, required String title, required String subtitle, String? thumb, Widget? customBg, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 102,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.42), BlendMode.darken),
                child: Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: cs.surfaceContainerHigh)),
              )
            else if (customBg != null)
              ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.32), BlendMode.darken),
                child: customBg,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [cs.surface.withOpacity(0.86), cs.surface.withOpacity(0.18)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tonalCircleBtn(ColorScheme cs, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
          child: Icon(icon, color: cs.onSurface, size: 20),
        ),
      );

  Widget _profileAvatarBtn(ColorScheme cs) => ValueListenableBuilder<YtAccount>(
        valueListenable: ytAccount,
        builder: (_, acc, __) => GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            showYtAccountSheet(context);
          },
          child: Container(
            width: 38,
            height: 38,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
            child: acc.signedIn && acc.photo != null && acc.photo!.isNotEmpty
                ? Image.network(acc.photo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: cs.onSurface, size: 20))
                : Icon(Icons.person_rounded, color: cs.onSurface, size: 20),
          ),
        ),
      );

  Widget _emptyCard(ColorScheme cs, String msg, String btn, VoidCallback onTap) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. MATERIAL 3 ALBUM, ARTIST, PLAYLIST, AND SHARED LIKES PAGES
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSharedLikesPage extends StatefulWidget {
  const RevivedSharedLikesPage({super.key});
  @override
  State<RevivedSharedLikesPage> createState() => _RevivedSharedLikesPageState();
}

class _RevivedSharedLikesPageState extends State<RevivedSharedLikesPage> {
  Future<YtAlbumPage>? _ytFuture;

  @override
  void initState() {
    super.initState();
    _ytFuture = YouTubeMusic.playlistPage('LM', title: 'Liked Music').then((p) {
      _memLikedPage = p;
      return p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localLiked = audioHandler.tracks.where((t) => !t.isYouTube && appState.isLiked(t.id)).toList();
    return FutureBuilder<YtAlbumPage>(
      future: _ytFuture,
      initialData: _memLikedPage ?? YouTubeMusic.cachedPlaylistPage('LM', title: 'Liked Music'),
      builder: (context, snap) {
        final ytTracks = snap.data?.tracks ?? const <TrackItem>[];
        final seen = <String>{};
        final combined = <TrackItem>[];
        for (final t in [...localLiked, ...ytTracks]) {
          if (seen.add(t.id)) combined.add(t);
        }
        return RevivedPlaylistPage.custom(
          title: 'Shared likes',
          subtitle: '${localLiked.length} on device • ${ytTracks.length} on YouTube Music',
          tracks: combined,
          isLikedStyle: true,
        );
      },
    );
  }
}

class RevivedAlbumPage extends StatefulWidget {
  final String url;
  final String? initialTitle;
  final String? initialThumb;
  const RevivedAlbumPage({super.key, required this.url, this.initialTitle, this.initialThumb});
  @override
  State<RevivedAlbumPage> createState() => _RevivedAlbumPageState();
}

class _RevivedAlbumPageState extends State<RevivedAlbumPage> {
  late Future<YtAlbumPage> _future;
  @override
  void initState() {
    super.initState();
    _future = YouTubeMusic.album(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: cs.surface,
      body: FutureBuilder<YtAlbumPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }
          final page = snap.data;
          if (page == null) return Center(child: Text('Could not load release', style: TextStyle(color: cs.onSurfaceVariant)));
          final isSingle = (page.kind ?? '').toLowerCase() == 'single' || page.tracks.length <= 2;
          final typeLabel = isSingle ? 'Single' : (page.kind ?? 'Album');
          final artUrl = page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 310 + top,
                      width: double.infinity,
                      child: FutureBuilder<Map<String, String>>(
                        future: _fetchAlbumMeta(page.artist, page.title),
                        initialData: _albumMetaCache['${page.artist.toLowerCase()}|${page.title.toLowerCase()}'],
                        builder: (_, metaSnap) {
                          final meta = metaSnap.data ?? const {};
                          final dateStr = meta['date'] ?? (page.year != null ? '${page.year}' : '');
                          final genreStr = meta['genre'] ?? '';
                          final durStr = _formatTotalDuration(page.tracks);
                          final topMeta = [typeLabel, if (dateStr.isNotEmpty) dateStr, if (genreStr.isNotEmpty) genreStr].join(' • ');
                          final subMeta = [
                            page.artist,
                            '${page.tracks.length} ${page.tracks.length == 1 ? "song" : "songs"}',
                            if (durStr.isNotEmpty) durStr,
                          ].join(' • ');

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ..._seamlessHeroLayers(
                                cs,
                                artUrl != null
                                    ? Image.network(artUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: cs.surfaceContainerHigh))
                                    : ColoredBox(color: cs.surfaceContainerHigh),
                                topOpacity: 0.45,
                              ),
                              Positioned(
                                top: top + 8,
                                left: 14,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                                    child: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 22),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 18,
                                right: 18,
                                bottom: 14,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(topMeta, style: TextStyle(color: cs.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text(page.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: cs.onSurface, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1)),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () {
                                        if (page.artistUrl != null) {
                                          Navigator.of(context).push(_revivedRoute(RevivedArtistPage(url: page.artistUrl!, name: page.artist)));
                                        }
                                      },
                                      child: Text(subMeta, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w800)),
                              onPressed: () {
                                if (page.tracks.isEmpty) return;
                                audioHandler.playYouTubeList(page.tracks, 0, lockToScope: true);
                                openPlayer(context);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.secondaryContainer,
                                foregroundColor: cs.onSecondaryContainer,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w700)),
                              onPressed: () {
                                if (page.tracks.isEmpty) return;
                                audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                                audioHandler.playYouTubeList(page.tracks, Random().nextInt(page.tracks.length), lockToScope: true);
                                openPlayer(context);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(icon: Icon(Icons.download_for_offline_outlined, color: cs.onSurfaceVariant), onPressed: () => OfflineStore.downloadAll(page.tracks)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SliverList.builder(
                itemCount: page.tracks.length,
                itemBuilder: (_, i) {
                  final t = page.tracks[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    leading: SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 14))),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    trailing: IconButton(icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
                    onTap: () {
                      audioHandler.playYouTubeList(page.tracks, i, lockToScope: true);
                      openPlayer(context);
                    },
                  );
                },
              ),
              SliverToBoxAdapter(
                child: FutureBuilder<Map<String, String>>(
                  future: _fetchAlbumMeta(page.artist, page.title),
                  initialData: _albumMetaCache['${page.artist.toLowerCase()}|${page.title.toLowerCase()}'],
                  builder: (_, metaSnap) {
                    final meta = metaSnap.data ?? const {};
                    final dateStr = meta['date'] ?? (page.year != null ? '${page.year}' : '');
                    final durStr = _formatTotalDuration(page.tracks);
                    final copy = meta['copyright'] ?? '';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (dateStr.isNotEmpty)
                            Text('Released $dateStr', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                            '${page.tracks.length} ${page.tracks.length == 1 ? "song" : "songs"}${durStr.isNotEmpty ? ", $durStr" : ""}',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                          ),
                          if (copy.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(copy, style: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.75), fontSize: 11.5)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RevivedArtistPage extends StatefulWidget {
  final String url;
  final String name;
  final String? initialThumb;
  const RevivedArtistPage({super.key, required this.url, required this.name, this.initialThumb});
  @override
  State<RevivedArtistPage> createState() => _RevivedArtistPageState();
}

class _RevivedArtistPageState extends State<RevivedArtistPage> {
  late Future<YtArtistPage> _future;
  @override
  void initState() {
    super.initState();
    _future = YouTubeMusic.artist(widget.url, widget.name);
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: cs.surface,
      body: FutureBuilder<YtArtistPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }
          final page = snap.data;
          if (page == null) return Center(child: Text('Could not load artist', style: TextStyle(color: cs.onSurfaceVariant)));
          final img = page.banner ?? page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 310 + top,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ..._seamlessHeroLayers(
                            cs,
                            img != null
                                ? Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: cs.surfaceContainerHigh))
                                : ColoredBox(color: cs.surfaceContainerHigh),
                            topOpacity: 0.42,
                          ),
                          Positioned(
                            top: top + 8,
                            left: 14,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                                child: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 22),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 12,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(page.subscribersText ?? 'Artist', style: TextStyle(color: cs.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(page.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: cs.onSurface, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.08)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.primary,
                                foregroundColor: cs.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Play top songs', style: TextStyle(fontWeight: FontWeight.w800)),
                              onPressed: () {
                                if (page.songs.isEmpty) return;
                                audioHandler.playYouTubeList(page.songs, 0, lockToScope: true);
                                openPlayer(context);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.secondaryContainer,
                              foregroundColor: cs.onSecondaryContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            onPressed: () {
                              if (page.songs.isEmpty) return;
                              audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                              audioHandler.playYouTubeList(page.songs, Random().nextInt(page.songs.length), lockToScope: true);
                              openPlayer(context);
                            },
                            child: const Icon(Icons.shuffle_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (page.songs.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                    child: Text('Popular', style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                ),
                SliverList.builder(
                  itemCount: min(10, page.songs.length),
                  itemBuilder: (_, i) {
                    final t = page.songs[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 44, height: 44, child: _coverArt(t, size: 44))),
                        ],
                      ),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                      subtitle: Text(page.plays[t.id] ?? t.artist, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      trailing: IconButton(icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
                      onTap: () {
                        audioHandler.playYouTubeList(page.songs, i, lockToScope: true);
                        openPlayer(context);
                      },
                    );
                  },
                ),
              ],
              for (final sh in page.shelves.where((s) => s.kind == 'album'))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sh.title.isEmpty ? 'Discography' : sh.title, style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 188,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 18),
                            itemCount: sh.items.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (_, i) {
                              final it = sh.items[i];
                              return GestureDetector(
                                onTap: () => Navigator.of(context).push(_revivedRoute(RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail))),
                                child: SizedBox(
                                  width: 136,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(16), child: YtNetworkImage(url: it.thumbnail, size: 136)),
                                      const SizedBox(height: 6),
                                      Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                      Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 36)),
            ],
          );
        },
      ),
    );
  }
}

class RevivedPlaylistPage extends StatefulWidget {
  final Playlist? localPlaylist;
  final String? ytPlaylistId;
  final String? title;
  final String? subtitle;
  final String? thumbnail;
  final List<TrackItem>? customTracks;
  final bool isLikedStyle;

  const RevivedPlaylistPage.local({super.key, required Playlist playlist})
      : localPlaylist = playlist, ytPlaylistId = null, title = null, subtitle = null, thumbnail = null, customTracks = null, isLikedStyle = false;

  const RevivedPlaylistPage.youtube({super.key, required String playlistId, this.title, this.thumbnail})
      : localPlaylist = null, ytPlaylistId = playlistId, subtitle = null, customTracks = null, isLikedStyle = false;

  const RevivedPlaylistPage.custom({super.key, required this.title, this.subtitle, required List<TrackItem> tracks, this.isLikedStyle = false})
      : localPlaylist = null, ytPlaylistId = null, thumbnail = null, customTracks = tracks;

  @override
  State<RevivedPlaylistPage> createState() => _RevivedPlaylistPageState();
}

class _RevivedPlaylistPageState extends State<RevivedPlaylistPage> {
  Future<YtAlbumPage>? _ytFuture;
  YtAlbumPage? _cached;

  @override
  void initState() {
    super.initState();
    if (widget.ytPlaylistId != null) {
      if (widget.ytPlaylistId == 'LM' && _memLikedPage != null) {
        _cached = _memLikedPage;
      } else {
        _cached = YouTubeMusic.cachedPlaylistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail);
      }
      _ytFuture = YouTubeMusic.playlistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail).then((p) {
        if (widget.ytPlaylistId == 'LM') _memLikedPage = p;
        return p;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    if (widget.customTracks != null) {
      return _scaffold(cs, widget.title ?? 'Playlist', widget.subtitle ?? '${widget.customTracks!.length} songs', null, widget.customTracks!, widget.isLikedStyle);
    }
    if (widget.localPlaylist != null) {
      final pl = widget.localPlaylist!;
      final tracks = pl.trackIds.map(audioHandler.trackById).whereType<TrackItem>().toList();
      return _scaffold(cs, pl.name, '${tracks.length} songs', null, tracks, false);
    }
    return FutureBuilder<YtAlbumPage>(
      future: _ytFuture,
      initialData: _cached,
      builder: (context, snap) {
        final page = snap.data;
        if (page == null) {
          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(backgroundColor: cs.surface, elevation: 0, iconTheme: IconThemeData(color: cs.onSurface)),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? CircularProgressIndicator(color: cs.primary)
                  : Text('Could not load playlist', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          );
        }
        final isLiked = widget.ytPlaylistId == 'LM';
        return _scaffold(cs, page.title, '${page.tracks.length} songs', isLiked ? null : (page.thumbnail ?? widget.thumbnail), page.tracks, isLiked);
      },
    );
  }

  Widget _scaffold(ColorScheme cs, String name, String sub, String? thumb, List<TrackItem> tracks, bool isLiked) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 280 + top,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ..._seamlessHeroLayers(
                        cs,
                        thumb != null
                            ? Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _likedCover(cs, iconSize: 72))
                            : _likedCover(cs, iconSize: 72),
                        topOpacity: 0.45,
                      ),
                      Positioned(
                        top: top + 8,
                        left: 14,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                            child: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 22),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Playlist • $sub', style: TextStyle(color: cs.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurface, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w800)),
                          onPressed: () {
                            if (tracks.isEmpty) return;
                            audioHandler.playYouTubeList(tracks, 0);
                            openPlayer(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.secondaryContainer,
                            foregroundColor: cs.onSecondaryContainer,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w700)),
                          onPressed: () {
                            if (tracks.isEmpty) return;
                            audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                            audioHandler.playYouTubeList(tracks, Random().nextInt(tracks.length));
                            openPlayer(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(icon: Icon(Icons.download_for_offline_outlined, color: cs.onSurfaceVariant), onPressed: () => OfflineStore.downloadAll(tracks)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 48, height: 48, child: _coverArt(t, size: 48))),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                trailing: IconButton(icon: Icon(Icons.more_vert_rounded, color: cs.onSurfaceVariant, size: 19), onPressed: () => showRevivedTrackMenu(context, t)),
                onTap: () {
                  audioHandler.playYouTubeList(tracks, i);
                  openPlayer(context);
                },
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 36)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. CLASSIC PLAYER SCREEN (Restored — New Floating-Card Player Removed)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedPlayerScreen extends StatefulWidget {
  const RevivedPlayerScreen({super.key});
  @override
  State<RevivedPlayerScreen> createState() => _RevivedPlayerScreenState();
}

class _RevivedPlayerScreenState extends State<RevivedPlayerScreen> {
  double _dragY = 0;
  bool _draggingY = false;
  double _dragX = 0;
  bool _draggingX = false;
  bool _showHeartPop = false;

  @override
  void initState() {
    super.initState();
    audioHandler.currentIndex.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    audioHandler.currentIndex.removeListener(_refresh);
    super.dispose();
  }

  void _doubleTapLike(TrackItem track) {
    HapticFeedback.mediumImpact();
    if (!appState.isLiked(track.id)) appState.toggleLike(track.id);
    setState(() => _showHeartPop = true);
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeartPop = false);
    });
  }

  void _onVertUpdate(DragUpdateDetails d) {
    if (d.delta.dy < 0 && _dragY <= 0) return;
    setState(() {
      _draggingY = true;
      _dragY = (_dragY + d.delta.dy).clamp(0.0, 520.0);
    });
  }

  void _onVertEnd(DragEndDetails d) {
    if (_dragY > 120 || (d.primaryVelocity ?? 0) > 700) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      setState(() {
        _draggingY = false;
        _dragY = 0;
      });
    }
  }

  void _onHorizUpdate(DragUpdateDetails d) {
    setState(() {
      _draggingX = true;
      _dragX = (_dragX + d.delta.dx * 0.65).clamp(-180.0, 180.0);
    });
  }

  void _onHorizEnd(DragEndDetails d) {
    final vel = d.primaryVelocity ?? 0;
    if (_dragX < -125 || vel < -750) {
      HapticFeedback.mediumImpact();
      audioHandler.skipToNext();
    } else if (_dragX > 125 || vel > 750) {
      HapticFeedback.mediumImpact();
      audioHandler.skipToPreviousTrack();
    }
    setState(() {
      _draggingX = false;
      _dragX = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final track = audioHandler.currentTrack;
        final scaleY = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
        final radius = (_dragY / 10).clamp(0.0, 24.0);

        return FutureBuilder<Color>(
          future: track != null ? artSeedFor(track) : null,
          initialData: track != null ? artSeedNow(track) : null,
          builder: (context, artSnap) {
            final artTint = artSnap.data ?? const Color(0xFF282828);
            final bgColors = [Color.lerp(const Color(0xFF1F1E1C), artTint, 0.14)!, const Color(0xFF0D0D0E)];

            return Scaffold(
              backgroundColor: Colors.black.withOpacity((1.0 - _dragY / 600).clamp(0.2, 1.0)),
              body: GestureDetector(
                onVerticalDragUpdate: _onVertUpdate,
                onVerticalDragEnd: _onVertEnd,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: _draggingY ? 0 : 240),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.identity()..translate(0.0, _dragY)..scale(scaleY, scaleY),
                  transformAlignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: bgColors),
                  ),
                  child: track == null
                      ? const Center(child: Text('Nothing playing', style: TextStyle(color: Colors.white60)))
                      : SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30), onPressed: () => Navigator.of(context).pop()),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => revivedGoToAlbum(context, track),
                                        child: Column(
                                          children: [
                                            const Text('Now playing', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                                            Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white), onPressed: () => showRevivedTrackMenu(context, track)),
                                  ],
                                ),
                                const Spacer(),
                                _swipeableArt(track, 12),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          GestureDetector(
                                            onTap: () => revivedGoToAlbum(context, track),
                                            child: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                                          ),
                                          const SizedBox(height: 3),
                                          GestureDetector(
                                            onTap: () => revivedGoToArtist(context, track),
                                            child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB3B3B3), fontSize: 15)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 26),
                                      onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track),
                                    ),
                                    _likeBtn(track, cs.primary),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _seekSlider(track),
                                const SizedBox(height: 14),
                                _transportRow(cs.primary),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    IconButton(icon: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 22), onPressed: () => showTrackInfoDialog(context, track)),
                                    IconButton(icon: const Icon(Icons.headphones_outlined, color: Colors.white70, size: 22), onPressed: () => showPlaybackSheet(context)),
                                    IconButton(icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 21), onPressed: () => showLyricsSheet(context, track)),
                                    const Spacer(),
                                    IconButton(icon: const Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 24), onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track)),
                                    IconButton(icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 24), onPressed: () => _showProQueueSheet(context, cs)),
                                  ],
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
      },
    );
  }

  Widget _swipeableArt(TrackItem track, double radius) => GestureDetector(
        onDoubleTap: () => _doubleTapLike(track),
        onHorizontalDragUpdate: _onHorizUpdate,
        onHorizontalDragEnd: _onHorizEnd,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _draggingX ? 0 : 240),
          curve: Curves.easeOutBack,
          transform: Matrix4.identity()..translate(_dragX, 0.0)..scale((1.0 - _dragX.abs() / 1600).clamp(0.92, 1.0)),
          transformAlignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 28, offset: const Offset(0, 14))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, if (cur != null) cur]),
                    child: KeyedSubtree(key: ValueKey(track.id), child: _coverArt(track)),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _showHeartPop ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    scale: _showHeartPop ? 1.15 : 0.6,
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 84, shadows: [Shadow(color: Colors.black54, blurRadius: 20)]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _likeBtn(TrackItem track, Color activeColor) => ListenableBuilder(
        listenable: appState,
        builder: (_, __) {
          final liked = appState.isLiked(track.id);
          return _AnimatedHeartButton(
            liked: liked,
            activeColor: activeColor,
            inactiveColor: Colors.white,
            size: 26,
            onTap: () => appState.toggleLike(track.id),
          );
        },
      );

  Widget _seekSlider(TrackItem track) => StreamBuilder<Duration>(
        stream: audioHandler.player.positionStream,
        builder: (context, snap) {
          final pos = snap.data ?? Duration.zero;
          final dur = audioHandler.player.duration ?? Duration(seconds: track.durationSeconds);
          final maxMs = max(1, dur.inMilliseconds).toDouble();
          final curMs = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
          return Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(value: curMs, max: maxMs, onChanged: (v) => audioHandler.seek(Duration(milliseconds: v.round()))),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(pos), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    Text(formatDuration(dur), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
            ],
          );
        },
      );

  Widget _transportRow(Color activeColor) {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final st = snap.data ?? audioHandler.playbackState.value;
        final playing = st.playing;
        final shuf = st.shuffleMode == AudioServiceShuffleMode.all;
        final rep = st.repeatMode;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.shuffle_rounded, color: shuf ? activeColor : Colors.white70, size: 24),
              onPressed: () {
                HapticFeedback.selectionClick();
                audioHandler.setShuffleMode(shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
              onPressed: () {
                HapticFeedback.mediumImpact();
                audioHandler.skipToPrevious();
              },
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                playing ? audioHandler.pause() : audioHandler.play();
              },
              child: Container(
                width: 66,
                height: 66,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                  child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(playing), color: Colors.black, size: 38),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
              onPressed: () {
                HapticFeedback.mediumImpact();
                audioHandler.skipToNext();
              },
            ),
            IconButton(
              icon: Icon(rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: rep == AudioServiceRepeatMode.none ? Colors.white70 : activeColor, size: 24),
              onPressed: () {
                HapticFeedback.selectionClick();
                final next = rep == AudioServiceRepeatMode.none
                    ? AudioServiceRepeatMode.all
                    : (rep == AudioServiceRepeatMode.all ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none);
                audioHandler.setRepeatMode(next);
              },
            ),
          ],
        );
      },
    );
  }

  void _showProQueueSheet(BuildContext context, ColorScheme cs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (_, __) => ListenableBuilder(
          listenable: Listenable.merge([audioHandler.upNextRevision, audioHandler.libraryRevision, audioHandler.currentIndex]),
          builder: (_, __) {
            final upNext = audioHandler.upNext;
            final list = audioHandler.tracks;
            return SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 36, height: 4, decoration: BoxDecoration(color: cs.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(99))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('Queue (${list.length})', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800))),
                        if (upNext.isNotEmpty)
                          TextButton(onPressed: () => audioHandler.clearQueue(), child: Text('Clear up next', style: TextStyle(color: cs.primary))),
                      ],
                    ),
                  ),
                  if (upNext.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 4),
                            child: Text('Up next (${upNext.length})', style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          for (var q = 0; q < min(4, upNext.length); q++)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 38, height: 38, child: _coverArt(upNext[q], size: 38))),
                              title: Text(upNext[q].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                              trailing: IconButton(icon: Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant), onPressed: () => audioHandler.removeFromQueue(q)),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: list.length,
                      onReorder: (oldIdx, newIdx) {
                        if (newIdx > oldIdx) newIdx -= 1;
                        audioHandler.moveTrack(oldIdx, newIdx);
                      },
                      itemBuilder: (_, i) {
                        final t = list[i];
                        final active = audioHandler.currentTrack?.id == t.id;
                        return ListTile(
                          key: ValueKey('q_${t.id}_$i'),
                          leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 44, height: 44, child: _coverArt(t, size: 44))),
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? cs.primary : cs.onSurface, fontWeight: FontWeight.w600)),
                          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                          trailing: Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant),
                          onTap: () {
                            audioHandler.playIndex(i);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

void _showSleepTimerSheet(BuildContext context) {
  final cs = _m3();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sleep timer', style: TextStyle(color: cs.onSurface, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final opt in [
              ('Off', null, false),
              ('15 minutes', const Duration(minutes: 15), false),
              ('30 minutes', const Duration(minutes: 30), false),
              ('45 minutes', const Duration(minutes: 45), false),
              ('1 hour', const Duration(hours: 1), false),
              ('End of current song', null, true),
            ])
              ListTile(
                title: Text(opt.$1, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  audioHandler.setSleepTimer(opt.$2, endOfSong: opt.$3);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. MATERIAL 3 SETTINGS SCREEN
// ═════════════════════════════════════════════════════════════════════════════
void openRevivedSettings(BuildContext context) {
  Navigator.of(context).push(_revivedRoute(const RevivedSettingsScreen()));
}

class RevivedSettingsScreen extends StatelessWidget {
  const RevivedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final cs = _m3();
        final crossfadeOn = appState.b('crossfade_on');
        final crossfadeSecs = appState.d('crossfade_secs', 6.0).clamp(1.0, 12.0);

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: Text('Settings', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800)),
            iconTheme: IconThemeData(color: cs.onSurface),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            children: [
              _section(cs, 'Tools & library'),
              _card(cs, [
                ListTile(
                  leading: Icon(Icons.bar_chart_rounded, color: cs.primary),
                  title: Text('Listening stats', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text('Top songs, artists, daily streak & 24h clock', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => openListeningStats(context),
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                ListTile(
                  leading: Icon(Icons.file_download_rounded, color: cs.primary),
                  title: Text('Import from Spotify', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text('Bring playlists over from Exportify CSV', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => openSpotifyImport(context),
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                ListTile(
                  leading: Icon(Icons.download_done_rounded, color: cs.primary),
                  title: Text('Offline downloads', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text('${OfflineStore.count} songs • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => openDownloads(context),
                ),
              ]),
              const SizedBox(height: 18),
              _section(cs, 'Playback & audio'),
              _card(cs, [
                ListTile(
                  leading: Icon(Icons.waves_rounded, color: cs.primary),
                  title: Text('Speed, pitch & reverb', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text('Slowed + reverb, nightcore, sped up & pitch', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => showPlaybackSheet(context),
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                ValueListenableBuilder<String?>(
                  valueListenable: audioHandler.sleepLabel,
                  builder: (_, lbl, __) => ListTile(
                    leading: Icon(Icons.bedtime_rounded, color: cs.primary),
                    title: Text('Sleep timer', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                    subtitle: Text(lbl ?? 'Off', style: TextStyle(color: cs.onSurfaceVariant)),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => _showSleepTimerSheet(context),
                  ),
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Crossfade', 'Smoothly blend between songs', crossfadeOn, (v) => appState.setB('crossfade_on', v)),
                if (crossfadeOn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Text('Duration', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Slider(
                            activeColor: cs.primary,
                            inactiveColor: cs.surfaceContainerHighest,
                            min: 1,
                            max: 12,
                            divisions: 11,
                            value: crossfadeSecs,
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              appState.setD('crossfade_secs', v);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 34,
                          child: Text('${crossfadeSecs.round()}s',
                              textAlign: TextAlign.right,
                              style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Smooth play & pause fade', 'Fade volume gently on pause and resume', appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Skip silence', 'Trim dead air between tracks', appState.b('skip_silence'), (v) {
                  appState.setB('skip_silence', v);
                  audioHandler.player.setSkipSilenceEnabled(v);
                }),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Pause on disconnect', 'Pause when headphones unplug', appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Autoplay radio', 'Queue similar songs when playlist ends', appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Word-by-word lyrics', 'Highlight each word live in synced lyrics', appState.b('word_lyrics', true), (v) => appState.setB('word_lyrics', v)),
              ]),
              const SizedBox(height: 18),
              _section(cs, 'Account & system'),
              _card(cs, [
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => ListTile(
                    leading: Icon(Icons.play_circle_fill_rounded, color: cs.primary),
                    title: Text(acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes', style: TextStyle(color: cs.onSurfaceVariant)),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Pure black background', 'Use #000000 instead of Material dark surface', appState.b('pure_black_dark', false), (v) => appState.setB('pure_black_dark', v)),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Data saver', 'Lower bitrate on mobile data', appState.b('yt_data_saver'), (v) {
                  appState.setB('yt_data_saver', v);
                  applyNativeSettings();
                }),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'Prefetch next song', 'Preload upcoming track for instant skips', appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                _toggle(cs, 'High refresh rate (120Hz)', 'Keep scrolling and animations smooth', appState.b('high_refresh', true), (v) {
                  appState.setB('high_refresh', v);
                  applyNativeSettings();
                }),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                ListTile(
                  leading: Icon(Icons.cleaning_services_rounded, color: cs.onSurfaceVariant),
                  title: Text('Clear stream cache', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    await const MethodChannel('com.alexlmp.app/ytmusic').invokeMethod('ytClearCache');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio cache cleared')));
                  },
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                ListTile(
                  leading: Icon(Icons.system_update_rounded, color: cs.onSurfaceVariant),
                  title: Text('Check for updates', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text(const String.fromEnvironment('APP_BUILD_VER', defaultValue: 'v1.0.0'), style: TextStyle(color: cs.onSurfaceVariant)),
                  onTap: () => checkRevivedUpdate(context, manual: true),
                ),
                Divider(color: cs.outlineVariant.withOpacity(0.25), height: 1),
                ListTile(
                  leading: Icon(Icons.restart_alt_rounded, color: cs.onSurfaceVariant),
                  title: Text('Re-run setup screen', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () {
                    appState.setB('setup_done', false);
                    Navigator.of(context).pushAndRemoveUntil(_revivedRoute(const RevivedSetupScreen()), (_) => false);
                  },
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _section(ColorScheme cs, String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _card(ColorScheme cs, List<Widget> children) => Container(
        decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
        child: Column(children: children),
      );

  Widget _toggle(ColorScheme cs, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        activeColor: cs.onPrimary,
        activeTrackColor: cs.primary,
        title: Text(title, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        value: value,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          onChanged(v);
        },
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 6. FULL-SCREEN IN-APP UPDATE CHECKER
// ═════════════════════════════════════════════════════════════════════════════
const String _kUpdateRepo = 'cashhwocky/AlexLMPRevived';
const MethodChannel _kRevivedMediaCh = MethodChannel('com.alexlmp.app/media');

Future<void> checkRevivedUpdate(BuildContext context, {bool manual = false}) async {
  try {
    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/$_kUpdateRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'AlexLMPRevived'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No published releases found yet')));
      }
      return;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final notes = (data['body'] ?? 'Bug fixes, performance improvements, and UI updates.').toString().trim();
    String? apkUrl;
    for (final a in (data['assets'] as List? ?? const [])) {
      if (a is Map && (a['name'] ?? '').toString().toLowerCase().contains('universal') && (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apkUrl = a['browser_download_url']?.toString();
        break;
      }
    }
    apkUrl ??= (data['assets'] as List? ?? const [])
        .whereType()
        .map((a) => a['browser_download_url']?.toString())
        .firstWhere((u) => u != null && u.toLowerCase().endsWith('.apk'), orElse: () => null);
    if (tag.isEmpty || apkUrl == null) return;

    const builtRaw = String.fromEnvironment('APP_BUILD_VER', defaultValue: '0.0.0');
    final installed = builtRaw.replaceFirst(RegExp(r'^[vV]'), '');
    bool isNewer(String latest, String current) {
      final a = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final b = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final len = max(a.length, b.length);
      for (var i = 0; i < len; i++) {
        final av = i < a.length ? a[i] : 0;
        final bv = i < b.length ? b[i] : 0;
        if (av != bv) return av > bv;
      }
      return false;
    }

    if (!isNewer(tag, installed)) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You are already on the latest version (v$installed)')));
      }
      return;
    }
    if (!context.mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => RevivedUpdateScreen(version: tag, notes: notes, apkUrl: apkUrl!),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check for updates right now')));
    }
  }
}

class RevivedUpdateScreen extends StatefulWidget {
  final String version;
  final String notes;
  final String apkUrl;
  const RevivedUpdateScreen({super.key, required this.version, required this.notes, required this.apkUrl});
  @override
  State<RevivedUpdateScreen> createState() => _RevivedUpdateScreenState();
}

class _RevivedUpdateScreenState extends State<RevivedUpdateScreen> {
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  Future<void> _downloadAndInstall() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Downloading AlexLMP Revived v${widget.version}…';
    });
    try {
      final req = http.Request('GET', Uri.parse(widget.apkUrl));
      final streamed = await req.send();
      final total = streamed.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/AlexLMPRevived-${widget.version}.apk');
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) setState(() => _progress = (received / total).clamp(0.0, 1.0));
      }
      await sink.close();
      if (!mounted) return;
      setState(() => _status = 'Opening Android installer…');
      await _kRevivedMediaCh.invokeMethod('installApk', {'path': file.path});
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _status = 'Update failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const RevivedBrandMark(size: 52),
                  const Spacer(),
                  if (!_downloading)
                    IconButton(icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 24),
              Text('Update available', style: TextStyle(color: cs.primary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('AlexLMP Revived\nv${widget.version}',
                  style: TextStyle(color: cs.onSurface, fontSize: 34, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(widget.notes, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14.5, height: 1.45)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_status.isNotEmpty) ...[
                Text(_status, style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              if (_downloading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, backgroundColor: cs.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation<Color>(cs.primary)),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                        onPressed: _downloadAndInstall,
                        child: const Text('Update now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Not now', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}