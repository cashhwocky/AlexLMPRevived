import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';

// ── Material 3 Expressive (M3E / Material You) Dynamic Scheme ────────────────
const Map<String, Color> _kSeeds = {
  'Wallpaper': Color(0xFF7C6AE6),
  'Coral': Color(0xFFE06D53),
  'Sage': Color(0xFF4E9A74),
  'Sky': Color(0xFF4A8FE7),
  'Lilac': Color(0xFF8E72E8),
  'Amber': Color(0xFFD9943B),
};

ColorScheme _m3() {
  final choice = appState.str('m3e_seed', 'Wallpaper');
  final seed = (choice == 'Wallpaper' && appState.wallpaperColor != null)
      ? appState.wallpaperColor!
      : (_kSeeds[choice] ?? const Color(0xFF7C6AE6));
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  if (appState.b('pure_black')) {
    return base.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0C0C0F),
    );
  }
  return base;
}

/// Expressive M3E grouped list container (rounded outer corners, subtle inner dividers).
Widget _m3eGroup(ColorScheme cs, List<Widget> children) {
  if (children.isEmpty) return const SizedBox.shrink();
  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            Divider(height: 1, indent: 72, endIndent: 16, color: cs.outlineVariant.withOpacity(0.28)),
        ],
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. M3E SETUP SCREEN (Requires YouTube Music Sign-In)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSetupScreen extends StatefulWidget {
  const RevivedSetupScreen({super.key});

  @override
  State<RevivedSetupScreen> createState() => _RevivedSetupScreenState();
}

class _RevivedSetupScreenState extends State<RevivedSetupScreen> {
  bool _storageGranted = false;
  bool _signingIn = false;
  bool _checkingStorage = false;

  Future<void> _signIn() async {
    HapticFeedback.lightImpact();
    setState(() => _signingIn = true);
    try {
      await YouTubeMusic.signIn();
    } catch (_) {}
    if (mounted) setState(() => _signingIn = false);
  }

  Future<void> _grantStorage() async {
    HapticFeedback.lightImpact();
    setState(() => _checkingStorage = true);
    final ok = await ensureMediaPermissions();
    if (!mounted) return;
    setState(() {
      _storageGranted = ok;
      _checkingStorage = false;
    });
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    appState.setB('setup_done', true);
    appState.setStr('home_mode', 'youtube');
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
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
        child: ValueListenableBuilder<YtAccount>(
          valueListenable: ytAccount,
          builder: (context, acc, _) {
            final signedIn = acc.signedIn;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(Icons.graphic_eq_rounded, color: cs.onPrimaryContainer, size: 34),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'AlexLMP\nRevived',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 42,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in to YouTube Music to get started. Everything adapts to your colors.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15.5, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  _stepTile(
                    cs: cs,
                    badge: 'REQUIRED',
                    icon: signedIn ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                    title: signedIn ? 'Signed in as ${acc.name ?? "YouTube"}' : 'Sign in to YouTube Music',
                    subtitle: signedIn ? 'Connected and ready' : 'Required to stream & sync your library',
                    busy: _signingIn,
                    done: signedIn,
                    onTap: signedIn ? null : _signIn,
                  ),
                  const SizedBox(height: 12),
                  _stepTile(
                    cs: cs,
                    badge: 'OPTIONAL',
                    icon: _storageGranted ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                    title: _storageGranted ? 'Local Music Enabled' : 'Allow Local Music Access',
                    subtitle: _storageGranted ? 'Ready to scan device audio' : 'Play MP3, FLAC, and M4A files',
                    busy: _checkingStorage,
                    done: _storageGranted,
                    onTap: _storageGranted ? null : _grantStorage,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: signedIn ? cs.primary : cs.surfaceContainerHighest,
                        foregroundColor: signedIn ? cs.onPrimary : cs.onSurfaceVariant,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(29)),
                      ),
                      onPressed: signedIn ? _finish : null,
                      child: Text(
                        signedIn ? 'Start Listening' : 'Sign in to Continue',
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
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

  Widget _stepTile({
    required ColorScheme cs,
    required String badge,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool busy,
    required bool done,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: done ? cs.primaryContainer.withOpacity(0.55) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          children: [
            busy
                ? SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary))
                : Icon(icon, color: done ? cs.primary : cs.onSurfaceVariant, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(badge,
                      style: TextStyle(color: cs.primary, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Text(title, style: TextStyle(color: cs.onSurface, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            if (!done && !busy) Icon(Icons.arrow_forward_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. M3E MAIN APP SHELL (Home, Search, Library — Unique Tonal Layout)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedAppShell extends StatefulWidget {
  final List<TrackItem> tracks;
  final Widget Function(AppPalette pal)? aiChatBuilder;

  const RevivedAppShell({
    super.key,
    required this.tracks,
    this.aiChatBuilder,
  });

  @override
  State<RevivedAppShell> createState() => _RevivedAppShellState();
}

class _RevivedAppShellState extends State<RevivedAppShell> {
  int _tab = 0; // 0 = Home, 1 = Search, 2 = Library
  int _libTab = 0; // 0 = Songs, 1 = Playlists, 2 = Liked
  int _searchTab = 0; // 0 = Songs, 1 = Artists, 2 = Albums, 3 = Playlists

  final TextEditingController _searchCtrl = TextEditingController();
  List<TrackItem> _songRes = [];
  List<YtArtist> _artistRes = [];
  List<YtAlbum> _albumRes = [];
  List<YtPlaylistRef> _playlistRes = [];
  bool _searching = false;
  Timer? _debounce;
  Future<List<YtShelf>>? _ytFeedFuture;

  @override
  void initState() {
    super.initState();
    _ytFeedFuture = YouTubeMusic.homeFeed();
    appState.setB('update_check', true);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkRevivedUpdate(context));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
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
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 360), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      if (_searchTab == 0) {
        final r = await YouTubeMusic.search(query);
        if (mounted) setState(() => _songRes = r);
      } else if (_searchTab == 1) {
        final r = await YouTubeMusic.searchArtists(query);
        if (mounted) setState(() => _artistRes = r);
      } else if (_searchTab == 2) {
        final r = await YouTubeMusic.searchAlbums(query);
        if (mounted) setState(() => _albumRes = r);
      } else {
        final r = await YouTubeMusic.searchPlaylists(query);
        if (mounted) setState(() => _playlistRes = r);
      }
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _openShelfItem(YtShelfItem it) {
    HapticFeedback.selectionClick();
    if (it.kind == 'album') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail),
      ));
    } else if (it.kind == 'artist') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedArtistPage(url: it.id, name: it.title, initialThumb: it.thumbnail),
      ));
    } else if (it.kind == 'playlist') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedPlaylistPage.youtube(playlistId: it.id, title: it.title, thumbnail: it.thumbnail),
      ));
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
    final cs = _m3();
    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _tab == 0
                    ? _buildHome(context, cs)
                    : (_tab == 1 ? _buildSearch(context, cs) : _buildLibrary(context, cs)),
              ),
            ),
          ),
          _buildMiniPlayer(context, cs),
          _buildFloatingNav(cs),
        ],
      ),
    );
  }

  // ── HOME PAGE (M3E Tonal Cards & Expressive Header) ───────────────────────
  Widget _buildHome(BuildContext context, ColorScheme cs) {
    final yt = appState.homeMode == 'youtube';
    final local = widget.tracks.where((t) => !t.isYouTube).toList();
    final top = MediaQuery.of(context).padding.top;
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');

    return RefreshIndicator(
      color: cs.primary,
      backgroundColor: cs.surfaceContainerHigh,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(18, top + 14, 18, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ALEXLMP REVIVED',
                        style: TextStyle(color: cs.primary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    Text(greet,
                        style: TextStyle(color: cs.onSurface, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
                  ],
                ),
              ),
              _tonalIconBtn(cs, Icons.person_outline_rounded, () => showYtAccountSheet(context)),
              const SizedBox(width: 8),
              _tonalIconBtn(cs, Icons.settings_outlined, () => openRevivedSettings(context)),
            ],
          ),
          const SizedBox(height: 16),
          // M3E Segmented Source Pill
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                _segBtn(cs, 'YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
                _segBtn(cs, 'On Device', !yt, () => appState.setStr('home_mode', 'local')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Expressive M3E Hero Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        yt ? 'Quick Mix' : 'Device Shuffle',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt ? 'Jump straight into your rotation' : '${local.length} tracks on this phone',
                        style: TextStyle(color: cs.onPrimaryContainer.withOpacity(0.78), fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    final pool = yt ? widget.tracks : local;
                    if (pool.isEmpty) {
                      setState(() => _tab = 1);
                    } else {
                      _shuffleAll(pool);
                    }
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(20)),
                    child: Icon(Icons.play_arrow_rounded, color: cs.onPrimary, size: 32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Quick Action Capsules
          Row(
            children: [
              Expanded(
                child: _actionCapsule(
                  cs,
                  Icons.favorite_rounded,
                  'Liked',
                  () => yt
                      ? Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                        ))
                      : setState(() {
                          _tab = 2;
                          _libTab = 2;
                        }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _actionCapsule(cs, Icons.speed_rounded, 'Speed/Pitch', () => showSpeedPitchSheet(context))),
              const SizedBox(width: 10),
              Expanded(child: _actionCapsule(cs, Icons.download_done_rounded, 'Offline', () => openDownloads(context))),
            ],
          ),
          const SizedBox(height: 22),
          if (yt)
            FutureBuilder<List<YtShelf>>(
              future: _ytFeedFuture,
              initialData: YouTubeMusic.cachedHomeFeed(),
              builder: (context, snap) {
                final shelves = snap.data ?? const [];
                if (shelves.isEmpty && snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: cs.primary)),
                  );
                }
                if (shelves.isEmpty) {
                  return _emptyCard(cs, 'Search YouTube Music to start listening', 'Open Search', () => setState(() => _tab = 1));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      Text(
                        shelf.title.isEmpty ? 'For you' : shelf.title,
                        style: TextStyle(color: cs.onSurface, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 196,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: shelf.items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final it = shelf.items[i];
                            final isArtist = it.kind == 'artist';
                            return GestureDetector(
                              onTap: () => _openShelfItem(it),
                              child: SizedBox(
                                width: 140,
                                child: Column(
                                  crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(isArtist ? 70 : 24),
                                      child: YtNetworkImage(url: it.thumbnail, size: 140, circle: isArtist),
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
                      const SizedBox(height: 20),
                    ],
                  ],
                );
              },
            )
          else if (local.isEmpty)
            _emptyCard(cs, 'No local audio files found', 'Add Music', () => showAddMusicSheet(context))
          else ...[
            Text('Quick Picks', style: TextStyle(color: cs.onSurface, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _m3eGroup(cs, [
              for (var i = 0; i < min(12, local.length); i++) _trackTile(cs, local[i], () => _playList(local, i)),
            ]),
          ],
        ],
      ),
    );
  }

  // ── UNIQUE M3E SEARCH PAGE (Songs / Artists / Albums / Playlists) ─────────
  Widget _buildSearch(BuildContext context, ColorScheme cs) {
    final top = MediaQuery.of(context).padding.top;
    const cats = ['Songs', 'Artists', 'Albums', 'Playlists'];
    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search',
              style: TextStyle(color: cs.onSurface, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums, playlists…',
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
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Category filter pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < cats.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cats[i]),
                      selected: _searchTab == i,
                      selectedColor: cs.primaryContainer,
                      backgroundColor: cs.surfaceContainerHigh,
                      labelStyle: TextStyle(
                        color: _searchTab == i ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide.none,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _searchTab = i);
                        if (_searchCtrl.text.trim().isNotEmpty) _runSearch(_searchCtrl.text.trim());
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _searching
                ? Center(child: CircularProgressIndicator(color: cs.primary))
                : _searchCtrl.text.trim().isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(26)),
                              child: Icon(Icons.search_rounded, color: cs.onSecondaryContainer, size: 36),
                            ),
                            const SizedBox(height: 14),
                            Text('Find anything on YouTube Music',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    : _buildSearchResults(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    if (_searchTab == 0) {
      if (_songRes.isEmpty) return Center(child: Text('No songs found', style: TextStyle(color: cs.onSurfaceVariant)));
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _m3eGroup(cs, [
            for (final t in _songRes)
              _trackTile(cs, t, () {
                HapticFeedback.selectionClick();
                audioHandler.playYouTubeTrack(t);
                openPlayer(context);
              }),
          ]),
        ],
      );
    }
    if (_searchTab == 1) {
      if (_artistRes.isEmpty) return Center(child: Text('No artists found', style: TextStyle(color: cs.onSurfaceVariant)));
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _m3eGroup(cs, [
            for (final a in _artistRes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: YtNetworkImage(url: a.thumbnail, size: 52, circle: true),
                title: Text(a.name, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                subtitle: Text('Artist', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail),
                  ));
                },
              ),
          ]),
        ],
      );
    }
    if (_searchTab == 2) {
      if (_albumRes.isEmpty) return Center(child: Text('No albums found', style: TextStyle(color: cs.onSurfaceVariant)));
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _m3eGroup(cs, [
            for (final al in _albumRes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: YtNetworkImage(url: al.thumbnail, size: 52),
                ),
                title: Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                subtitle: Text(al.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail),
                  ));
                },
              ),
          ]),
        ],
      );
    }
    if (_playlistRes.isEmpty) return Center(child: Text('No playlists found', style: TextStyle(color: cs.onSurfaceVariant)));
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        _m3eGroup(cs, [
          for (final pl in _playlistRes)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: YtNetworkImage(url: pl.thumbnail, size: 52),
              ),
              title: Text(pl.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
              subtitle: Text(pl.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedPlaylistPage.youtube(
                    playlistId: pl.playlistId,
                    title: pl.title,
                    thumbnail: pl.thumbnail,
                  ),
                ));
              },
            ),
        ]),
      ],
    );
  }

  // ── LIBRARY PAGE ──────────────────────────────────────────────────────────
  Widget _buildLibrary(BuildContext context, ColorScheme cs) {
    final top = MediaQuery.of(context).padding.top;
    final songs = widget.tracks;
    final liked = songs.where((t) => appState.isLiked(t.id)).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Library',
                    style: TextStyle(color: cs.onSurface, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
              ),
              _tonalIconBtn(cs, Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
              const SizedBox(width: 8),
              _tonalIconBtn(cs, Icons.folder_open_rounded, () => showAddMusicSheet(context)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                _segBtn(cs, 'Songs', _libTab == 0, () => setState(() => _libTab = 0)),
                _segBtn(cs, 'Playlists', _libTab == 1, () => setState(() => _libTab = 1)),
                _segBtn(cs, 'Liked', _libTab == 2, () => setState(() => _libTab = 2)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _libTab == 0
                ? (songs.isEmpty
                    ? _emptyCard(cs, 'No songs yet', 'Add Music', () => showAddMusicSheet(context))
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 20),
                        children: [
                          _m3eGroup(cs, [
                            for (var i = 0; i < songs.length; i++) _trackTile(cs, songs[i], () => _playList(songs, i)),
                          ]),
                        ],
                      ))
                : _libTab == 1
                    ? ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 20),
                        children: [
                          _m3eGroup(cs, [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
                                child: Icon(Icons.favorite_rounded, color: cs.onPrimaryContainer),
                              ),
                              title: Text('Liked on YouTube', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                              subtitle: Text('Auto playlist', style: TextStyle(color: cs.onSurfaceVariant)),
                              trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                              )),
                            ),
                            for (final pl in appState.playlists)
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                leading: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(16)),
                                  child: Icon(Icons.queue_music_rounded, color: cs.onSecondaryContainer),
                                ),
                                title: Text(pl.name, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                                subtitle: Text('${pl.trackIds.length} songs', style: TextStyle(color: cs.onSurfaceVariant)),
                                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => RevivedPlaylistPage.local(playlist: pl),
                                )),
                              ),
                          ]),
                        ],
                      )
                    : (liked.isEmpty
                        ? _emptyCard(cs, 'No liked songs yet', 'Open YouTube Likes', () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                            ));
                          })
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 20),
                            children: [
                              _m3eGroup(cs, [
                                for (var i = 0; i < liked.length; i++) _trackTile(cs, liked[i], () => _playList(liked, i)),
                              ]),
                            ],
                          )),
          ),
        ],
      ),
    );
  }

  // ── MINI PLAYER & FLOATING M3E NAV PILL ───────────────────────────────────
  Widget _buildMiniPlayer(BuildContext context, ColorScheme cs) {
    return ValueListenableBuilder<int>(
      valueListenable: audioHandler.currentIndex,
      builder: (context, _, __) {
        final t = audioHandler.currentTrack;
        if (t == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            openPlayer(context);
          },
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -250) {
              HapticFeedback.mediumImpact();
              audioHandler.skipToNext();
            } else if (v > 250) {
              HapticFeedback.mediumImpact();
              audioHandler.skipToPreviousTrack();
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      StreamBuilder<PlaybackState>(
                        stream: audioHandler.playbackState,
                        builder: (context, snap) {
                          final playing = snap.data?.playing ?? audioHandler.player.playing;
                          return IconButton(
                            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.primary, size: 28),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              playing ? audioHandler.pause() : audioHandler.play();
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next_rounded, color: cs.onSurfaceVariant, size: 26),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          audioHandler.skipToNext();
                        },
                      ),
                    ],
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: audioHandler.player.positionStream,
                  builder: (_, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final dur = audioHandler.player.duration ?? Duration.zero;
                    final frac = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
                    return LinearProgressIndicator(
                      value: frac,
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingNav(ColorScheme cs) {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.search_rounded, Icons.search_rounded, 'Search'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _tab = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _tab == i ? cs.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _tab == i ? items[i].$2 : items[i].$1,
                          color: _tab == i ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          size: 22,
                        ),
                        if (_tab == i) ...[
                          const SizedBox(width: 6),
                          Text(items[i].$3,
                              style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13, fontWeight: FontWeight.w800)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── SHARED UI HELPERS ─────────────────────────────────────────────────────
  Widget _tonalIconBtn(ColorScheme cs, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
          child: Icon(icon, color: cs.onSurface, size: 21),
        ),
      );

  Widget _segBtn(ColorScheme cs, String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? cs.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                  color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                )),
          ),
        ),
      );

  Widget _actionCapsule(ColorScheme cs, IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
          child: Column(
            children: [
              Icon(icon, color: cs.primary, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _trackTile(ColorScheme cs, TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(width: 48, height: 48, child: CustomAlbumArtwork(track: t)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? cs.primary : cs.onSurface, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                appState.isLiked(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: appState.isLiked(t.id) ? cs.primary : cs.onSurfaceVariant,
                size: 20,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => appState.toggleLike(t.id));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(ColorScheme cs, String msg, String btn, VoidCallback onTap) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14.5)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. UNIQUE M3E ALBUM PAGE
// ═════════════════════════════════════════════════════════════════════════════
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
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(backgroundColor: cs.surface, elevation: 0, iconTheme: IconThemeData(color: cs.onSurface)),
      body: FutureBuilder<YtAlbumPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('Could not load album', style: TextStyle(color: cs.onSurfaceVariant)));
          }
          final page = snap.data!;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 36),
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: YtNetworkImage(url: page.thumbnail ?? widget.initialThumb, size: 220),
                ),
              ),
              const SizedBox(height: 18),
              Text(page.title, textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              const SizedBox(height: 4),
              Text(
                '${page.artist}${page.year != null ? " · ${page.year}" : ""}',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w800)),
                      onPressed: () {
                        if (page.tracks.isEmpty) return;
                        HapticFeedback.mediumImpact();
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w800)),
                      onPressed: () {
                        if (page.tracks.isEmpty) return;
                        HapticFeedback.mediumImpact();
                        audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                        audioHandler.playYouTubeList(page.tracks, Random().nextInt(page.tracks.length), lockToScope: true);
                        openPlayer(context);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _m3eGroup(cs, [
                for (var i = 0; i < page.tracks.length; i++)
                  ListTile(
                    leading: Text('${i + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                    title: Text(page.tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    subtitle: Text(page.tracks[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      audioHandler.playYouTubeList(page.tracks, i, lockToScope: true);
                      openPlayer(context);
                    },
                  ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. UNIQUE M3E ARTIST PAGE
// ═════════════════════════════════════════════════════════════════════════════
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
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(backgroundColor: cs.surface, elevation: 0, iconTheme: IconThemeData(color: cs.onSurface)),
      body: FutureBuilder<YtArtistPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }
          if (snap.hasError || !snap.hasData) {
            return Center(child: Text('Could not load artist', style: TextStyle(color: cs.onSurfaceVariant)));
          }
          final page = snap.data!;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 36),
            children: [
              Center(
                child: YtNetworkImage(url: page.thumbnail ?? widget.initialThumb, size: 156, circle: true),
              ),
              const SizedBox(height: 16),
              Text(page.name, textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              if (page.subscribersText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(page.subscribersText!, textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
                ),
              const SizedBox(height: 18),
              if (page.songs.isNotEmpty) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play Top Songs', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    audioHandler.playYouTubeList(page.songs, 0, lockToScope: true);
                    openPlayer(context);
                  },
                ),
                const SizedBox(height: 22),
                Text('Top Songs', style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _m3eGroup(cs, [
                  for (var i = 0; i < min(10, page.songs.length); i++)
                    ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(width: 46, height: 46, child: CustomAlbumArtwork(track: page.songs[i])),
                      ),
                      title: Text(page.songs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                      subtitle: Text(page.plays[page.songs[i].id] ?? page.songs[i].artist,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        audioHandler.playYouTubeList(page.songs, i, lockToScope: true);
                        openPlayer(context);
                      },
                    ),
                ]),
              ],
              for (final sh in page.shelves.where((s) => s.kind == 'album')) ...[
                const SizedBox(height: 24),
                Text(sh.title.isEmpty ? 'Releases' : sh.title,
                    style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: sh.items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final it = sh.items[i];
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail),
                        )),
                        child: SizedBox(
                          width: 136,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(borderRadius: BorderRadius.circular(22), child: YtNetworkImage(url: it.thumbnail, size: 136)),
                              const SizedBox(height: 6),
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
              ],
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. UNIQUE M3E PLAYLIST PAGE (Local & YouTube Music)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedPlaylistPage extends StatefulWidget {
  final Playlist? localPlaylist;
  final String? ytPlaylistId;
  final String? title;
  final String? thumbnail;

  const RevivedPlaylistPage.local({super.key, required Playlist playlist})
      : localPlaylist = playlist,
        ytPlaylistId = null,
        title = null,
        thumbnail = null;

  const RevivedPlaylistPage.youtube({super.key, required String playlistId, this.title, this.thumbnail})
      : localPlaylist = null,
        ytPlaylistId = playlistId;

  @override
  State<RevivedPlaylistPage> createState() => _RevivedPlaylistPageState();
}

class _RevivedPlaylistPageState extends State<RevivedPlaylistPage> {
  Future<YtAlbumPage>? _ytFuture;

  @override
  void initState() {
    super.initState();
    if (widget.ytPlaylistId != null) {
      _ytFuture = YouTubeMusic.playlistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    if (widget.localPlaylist != null) {
      final pl = widget.localPlaylist!;
      final tracks = pl.trackIds.map(audioHandler.trackById).whereType<TrackItem>().toList();
      return _scaffold(cs, pl.name, '${tracks.length} songs', null, tracks);
    }
    return FutureBuilder<YtAlbumPage>(
      future: _ytFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(backgroundColor: cs.surface, elevation: 0),
            body: Center(child: CircularProgressIndicator(color: cs.primary)),
          );
        }
        final page = snap.data;
        if (page == null) {
          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(backgroundColor: cs.surface, elevation: 0),
            body: Center(child: Text('Could not load playlist', style: TextStyle(color: cs.onSurfaceVariant))),
          );
        }
        return _scaffold(cs, page.title, '${page.tracks.length} tracks', page.thumbnail ?? widget.thumbnail, page.tracks);
      },
    );
  }

  Widget _scaffold(ColorScheme cs, String name, String sub, String? thumb, List<TrackItem> tracks) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(backgroundColor: cs.surface, elevation: 0, iconTheme: IconThemeData(color: cs.onSurface)),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(32)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: thumb != null
                      ? YtNetworkImage(url: thumb, size: 96)
                      : Container(
                          width: 96,
                          height: 96,
                          color: cs.primaryContainer,
                          child: Icon(Icons.queue_music_rounded, color: cs.onPrimaryContainer, size: 42),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSecondaryContainer, fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(sub, style: TextStyle(color: cs.onSecondaryContainer.withOpacity(0.75), fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () {
                    if (tracks.isEmpty) return;
                    HapticFeedback.mediumImpact();
                    audioHandler.playYouTubeList(tracks, 0);
                    openPlayer(context);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh,
                    foregroundColor: cs.onSurface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () {
                    if (tracks.isEmpty) return;
                    HapticFeedback.mediumImpact();
                    audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                    audioHandler.playYouTubeList(tracks, Random().nextInt(tracks.length));
                    openPlayer(context);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _m3eGroup(cs, [
            for (var i = 0; i < tracks.length; i++)
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 46, height: 46, child: CustomAlbumArtwork(track: tracks[i])),
                ),
                title: Text(tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                subtitle: Text(tracks[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  audioHandler.playYouTubeList(tracks, i);
                  openPlayer(context);
                },
              ),
          ]),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 6. M3E FULL-SCREEN PLAYER (Swipe Down + Carousel Swipe + Speed/Pitch)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedPlayerScreen extends StatefulWidget {
  const RevivedPlayerScreen({super.key});

  @override
  State<RevivedPlayerScreen> createState() => _RevivedPlayerScreenState();
}

class _RevivedPlayerScreenState extends State<RevivedPlayerScreen> {
  double _dragY = 0;
  bool _dragging = false;
  late PageController _carousel;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _carousel = PageController(initialPage: 1, viewportFraction: 0.86);
    audioHandler.currentIndex.addListener(_onTrackChanged);
  }

  void _onTrackChanged() {
    if (!mounted || !_carousel.hasClients) return;
    if (_carousel.page?.round() != 1) {
      _resetting = true;
      _carousel.jumpToPage(1);
      _resetting = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    audioHandler.currentIndex.removeListener(_onTrackChanged);
    _carousel.dispose();
    super.dispose();
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    if (d.delta.dy < 0 && _dragY <= 0) return;
    setState(() {
      _dragging = true;
      _dragY = (_dragY + d.delta.dy).clamp(0.0, 500.0);
    });
  }

  void _onVerticalEnd(DragEndDetails d) {
    final vel = d.primaryVelocity ?? 0;
    if (_dragY > 110 || vel > 650) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragging = false;
        _dragY = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
    final track = audioHandler.currentTrack;
    final prevTrack = audioHandler.peekPrevious;
    final nextTrack = audioHandler.peekNext;
    final scale = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
    final radius = (_dragY / 10).clamp(0.0, 32.0);

    return Scaffold(
      backgroundColor: Colors.black.withOpacity((1.0 - _dragY / 600).clamp(0.2, 1.0)),
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalUpdate,
        onVerticalDragEnd: _onVerticalEnd,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _dragging ? 0 : 240),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translate(0.0, _dragY)
            ..scale(scale, scale),
          transformAlignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.primaryContainer.withOpacity(0.55), cs.surface, cs.surface],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: track == null
              ? Center(child: Text('Nothing playing', style: TextStyle(color: cs.onSurfaceVariant)))
              : SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.24), borderRadius: BorderRadius.circular(2)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurface, size: 32),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop();
                              },
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text('NOW PLAYING',
                                      style: TextStyle(color: cs.primary, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                                  Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.speed_rounded, color: cs.onSurfaceVariant),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                showSpeedPitchSheet(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: MediaQuery.of(context).size.width * 0.84,
                        child: PageView.builder(
                          controller: _carousel,
                          physics: const BouncingScrollPhysics(),
                          itemCount: 3,
                          onPageChanged: (page) {
                            if (_resetting) return;
                            if (page == 2) {
                              HapticFeedback.mediumImpact();
                              audioHandler.skipToNext();
                            } else if (page == 0) {
                              HapticFeedback.mediumImpact();
                              audioHandler.skipToPreviousTrack();
                            }
                          },
                          itemBuilder: (context, index) {
                            final item = index == 0 ? prevTrack : (index == 1 ? track : nextTrack);
                            return AnimatedBuilder(
                              animation: _carousel,
                              builder: (context, child) {
                                final p = _carousel.position.haveDimensions
                                    ? (_carousel.page ?? 1.0) - index
                                    : (1 - index).toDouble();
                                final s = (1.0 - p.abs() * 0.14).clamp(0.84, 1.0);
                                final o = (1.0 - p.abs() * 0.45).clamp(0.45, 1.0);
                                return Transform.scale(scale: s, child: Opacity(opacity: o, child: child));
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 12)),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: item != null
                                      ? CustomAlbumArtwork(track: item)
                                      : Container(
                                          color: cs.surfaceContainerHigh,
                                          child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant, size: 64),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: cs.onSurface, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                      const SizedBox(height: 3),
                                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15.5, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                ListenableBuilder(
                                  listenable: appState,
                                  builder: (_, __) {
                                    final liked = appState.isLiked(track.id);
                                    return IconButton(
                                      icon: Icon(
                                        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                        color: liked ? cs.primary : cs.onSurfaceVariant,
                                        size: 28,
                                      ),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        appState.toggleLike(track.id);
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            StreamBuilder<Duration>(
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
                                        trackHeight: 5,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                        activeTrackColor: cs.primary,
                                        inactiveTrackColor: cs.surfaceContainerHighest,
                                        thumbColor: cs.primary,
                                      ),
                                      child: Slider(
                                        value: curMs,
                                        max: maxMs,
                                        onChanged: (v) => audioHandler.seek(Duration(milliseconds: v.round())),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(formatDuration(pos), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                          Text(formatDuration(dur), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            StreamBuilder<PlaybackState>(
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
                                      icon: Icon(Icons.shuffle_rounded, color: shuf ? cs.primary : cs.onSurfaceVariant, size: 24),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        audioHandler.setShuffleMode(
                                          shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.skip_previous_rounded, color: cs.onSurface, size: 38),
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
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 220),
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer,
                                          borderRadius: BorderRadius.circular(playing ? 24 : 36),
                                        ),
                                        child: Icon(
                                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: cs.onPrimaryContainer,
                                          size: 38,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.skip_next_rounded, color: cs.onSurface, size: 38),
                                      onPressed: () {
                                        HapticFeedback.mediumImpact();
                                        audioHandler.skipToNext();
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                        color: rep == AudioServiceRepeatMode.none ? cs.onSurfaceVariant : cs.primary,
                                        size: 24,
                                      ),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        final next = rep == AudioServiceRepeatMode.none
                                            ? AudioServiceRepeatMode.all
                                            : (rep == AudioServiceRepeatMode.all
                                                ? AudioServiceRepeatMode.one
                                                : AudioServiceRepeatMode.none);
                                        audioHandler.setRepeatMode(next);
                                      },
                                    ),
                                  ],
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
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 7. SPEED & PITCH SHEET (Slowed / Sped Up)
// ═════════════════════════════════════════════════════════════════════════════
void showSpeedPitchSheet(BuildContext context) {
  final cs = _m3();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => ListenableBuilder(
      listenable: appState,
      builder: (ctx, _) {
        void applyBoth(double s, double p) {
          HapticFeedback.selectionClick();
          appState.setSpeed(s);
          appState.setPitch(p);
          audioHandler.setSpeed(s);
          audioHandler.setPitch(p);
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: cs.onSurfaceVariant.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.speed_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Speed & Pitch',
                          style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    TextButton(
                      onPressed: () => applyBoth(1.0, 1.0),
                      child: Text('Reset', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetChip(cs, 'Slowed (0.85x)', (appState.speed - 0.85).abs() < 0.02, () => applyBoth(0.85, 0.85)),
                    _presetChip(cs, 'Normal (1.0x)', (appState.speed - 1.0).abs() < 0.02 && (appState.pitch - 1.0).abs() < 0.02, () => applyBoth(1.0, 1.0)),
                    _presetChip(cs, 'Sped Up (1.2x)', (appState.speed - 1.2).abs() < 0.02, () => applyBoth(1.2, 1.2)),
                    _presetChip(cs, 'Nightcore (1.3x)', (appState.speed - 1.3).abs() < 0.02, () => applyBoth(1.3, 1.3)),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: cs.primary,
                  title: Text('Link Speed & Pitch', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text('Classic tape / vinyl slowed & sped up sound', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  value: appState.linkSpeedAndPitch,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    appState.setLinkSpeedAndPitch(v);
                    if (v) applyBoth(appState.speed, appState.speed);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Speed', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    Text('${appState.speed.toStringAsFixed(2)}x', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  activeColor: cs.primary,
                  min: 0.5,
                  max: 2.0,
                  value: appState.speed.clamp(0.5, 2.0),
                  onChanged: (v) {
                    appState.setSpeed(v);
                    audioHandler.setSpeed(v);
                    if (appState.linkSpeedAndPitch) {
                      appState.setPitch(v);
                      audioHandler.setPitch(v);
                    }
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pitch', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    Text('${appState.pitch.toStringAsFixed(2)}x', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  activeColor: cs.primary,
                  min: 0.5,
                  max: 2.0,
                  value: appState.pitch.clamp(0.5, 2.0),
                  onChanged: (v) {
                    appState.setPitch(v);
                    audioHandler.setPitch(v);
                    if (appState.linkSpeedAndPitch) {
                      appState.setSpeed(v);
                      audioHandler.setSpeed(v);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _presetChip(ColorScheme cs, String label, bool active, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            )),
      ),
    );

// ═════════════════════════════════════════════════════════════════════════════
// 8. EXPANDED M3E SETTINGS SCREEN (With Material You Color Seed Picker)
// ═════════════════════════════════════════════════════════════════════════════
void openRevivedSettings(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RevivedSettingsScreen()));
}

class RevivedSettingsScreen extends StatelessWidget {
  const RevivedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final cs = _m3();
        final currentSeed = appState.str('m3e_seed', 'Wallpaper');
        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            elevation: 0,
            title: Text('Settings', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900)),
            iconTheme: IconThemeData(color: cs.onSurface),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            children: [
              _section(cs, 'MATERIAL YOU COLOR'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(26)),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in _kSeeds.entries)
                      ChoiceChip(
                        label: Text(entry.key),
                        selected: currentSeed == entry.key,
                        selectedColor: cs.primaryContainer,
                        backgroundColor: cs.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: currentSeed == entry.key ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        side: BorderSide.none,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          appState.setStr('m3e_seed', entry.key);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _section(cs, 'ACCOUNT & STREAMING'),
              _m3eGroup(cs, [
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => ListTile(
                    leading: Icon(Icons.play_circle_fill_rounded, color: cs.primary),
                    title: Text(acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music',
                        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes', style: TextStyle(color: cs.onSurfaceVariant)),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                _toggle(cs, 'Default to YouTube Music', 'Show YouTube Music feed on Home',
                    appState.homeMode == 'youtube', (v) => appState.setStr('home_mode', v ? 'youtube' : 'local')),
                _toggle(cs, 'YouTube Data Saver', 'Use lower bitrate audio on mobile data',
                    appState.b('yt_data_saver'), (v) {
                  appState.setB('yt_data_saver', v);
                  applyNativeSettings();
                }),
                _toggle(cs, 'Prefetch Next Song', 'Preload upcoming track for instant skips',
                    appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
              ]),
              const SizedBox(height: 20),
              _section(cs, 'AUDIO EFFECTS'),
              _m3eGroup(cs, [
                ListTile(
                  leading: Icon(Icons.speed_rounded, color: cs.primary),
                  title: Text('Speed & Pitch Controls', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'Speed ${appState.speed.toStringAsFixed(2)}x · Pitch ${appState.pitch.toStringAsFixed(2)}x',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => showSpeedPitchSheet(context),
                ),
                _toggle(cs, 'Link Speed & Pitch', 'Shift pitch automatically with speed',
                    appState.linkSpeedAndPitch, (v) => appState.setLinkSpeedAndPitch(v)),
              ]),
              const SizedBox(height: 20),
              _section(cs, 'PLAYBACK'),
              _m3eGroup(cs, [
                _toggle(cs, 'Crossfade', 'Smoothly blend the end of one song into the next',
                    appState.b('crossfade_on'), (v) => appState.setB('crossfade_on', v)),
                if (appState.b('crossfade_on'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Text('Duration', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        Expanded(
                          child: Slider(
                            activeColor: cs.primary,
                            min: 2,
                            max: 12,
                            divisions: 10,
                            value: appState.d('crossfade_secs', 6.0).clamp(2.0, 12.0),
                            onChanged: (v) => appState.setD('crossfade_secs', v),
                          ),
                        ),
                        Text('${appState.d('crossfade_secs', 6.0).round()}s',
                            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                _toggle(cs, 'Smooth Play / Pause Fade', 'Fade volume gently when pausing or resuming',
                    appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                _toggle(cs, 'Skip Silence', 'Trim dead air between tracks',
                    appState.b('skip_silence'), (v) {
                  appState.setB('skip_silence', v);
                  audioHandler.player.setSkipSilenceEnabled(v);
                }),
                _toggle(cs, 'Pause on Disconnect', 'Pause when headphones or Bluetooth unplug',
                    appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                _toggle(cs, 'Autoplay Radio', 'Queue similar songs when your playlist ends',
                    appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                _toggle(cs, 'Resume Last Session', 'Remember your song and position on restart',
                    appState.b('resume_last', true), (v) => appState.setB('resume_last', v)),
                _toggle(cs, 'Stop When App Closed', 'End playback when swiped from recents',
                    appState.stopOnTaskClear, (v) => appState.setStopOnTaskClear(v)),
              ]),
              const SizedBox(height: 20),
              _section(cs, 'DISPLAY & PERFORMANCE'),
              _m3eGroup(cs, [
                _toggle(cs, 'Pure AMOLED Black', 'Use #000000 backgrounds everywhere',
                    appState.b('pure_black'), (v) => appState.setB('pure_black', v)),
                _toggle(cs, 'High Refresh Rate (120Hz)', 'Keep animations ultra-smooth',
                    appState.b('high_refresh', true), (v) {
                  appState.setB('high_refresh', v);
                  applyNativeSettings();
                }),
                _toggle(cs, 'Keep Screen On', 'Prevent screen sleep while app is open',
                    appState.b('keep_screen_on'), (v) {
                  appState.setB('keep_screen_on', v);
                  applyNativeSettings();
                }),
              ]),
              const SizedBox(height: 20),
              _section(cs, 'LOCAL LIBRARY & SYSTEM'),
              _m3eGroup(cs, [
                _toggle(cs, 'Auto-Scan on Launch', 'Check for new audio files when opening app',
                    appState.b('auto_scan', true), (v) => appState.setB('auto_scan', v)),
                _toggle(cs, 'Hide Short Tracks (<30s)', 'Filter out voice memos and sound clips',
                    appState.b('hide_short_tracks'), (v) => appState.setB('hide_short_tracks', v)),
                ListTile(
                  leading: Icon(Icons.refresh_rounded, color: cs.primary),
                  title: Text('Scan Device Music Now', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    scanDeviceAudio();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.audio_file_rounded, color: cs.primary),
                  title: Text('Import Audio Files', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () => pickLocalFiles(),
                ),
                ListTile(
                  leading: Icon(Icons.download_done_rounded, color: cs.primary),
                  title: Text('Downloaded Songs', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () => openDownloads(context),
                ),
                ListTile(
                  leading: Icon(Icons.restart_alt_rounded, color: cs.onSurfaceVariant),
                  title: Text('Check for Updates', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () => checkRevivedUpdate(context, manual: true),
                ),
                ListTile(
                  leading: Icon(Icons.restart_alt_rounded, color: cs.onSurfaceVariant),
                  title: Text('Re-run Setup Screen', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    appState.setB('setup_done', false);
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const RevivedSetupScreen()),
                      (_) => false,
                    );
                  },
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _toggle(ColorScheme cs, String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        activeColor: cs.primary,
        title: Text(title, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        value: value,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          onChanged(v);
        },
      );

  Widget _section(ColorScheme cs, String title) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(title,
            style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 9. FULL-SCREEN IN-APP UPDATE CHECKER & INSTALLER
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No published releases found yet.')),
        );
      }
      return;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final notes = (data['body'] ?? 'Bug fixes, performance improvements, and UI updates.').toString().trim();
    String? apkUrl;
    for (final a in (data['assets'] as List? ?? const [])) {
      if (a is Map && (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apkUrl = a['browser_download_url']?.toString();
        break;
      }
    }
    if (tag.isEmpty || apkUrl == null) return;

    final installed = appState.str('installed_revived_ver', '0.0.0');
    if (!manual && tag == installed) return;
    if (!context.mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => RevivedUpdateScreen(
          version: tag,
          notes: notes,
          apkUrl: apkUrl!,
        ),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check for updates right now.')),
      );
    }
  }
}

class RevivedUpdateScreen extends StatefulWidget {
  final String version;
  final String notes;
  final String apkUrl;

  const RevivedUpdateScreen({
    super.key,
    required this.version,
    required this.notes,
    required this.apkUrl,
  });

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
        if (total > 0 && mounted) {
          setState(() => _progress = (received / total).clamp(0.0, 1.0));
        }
      }
      await sink.close();
      if (!mounted) return;
      setState(() => _status = 'Opening Android installer…');
      appState.setStr('installed_revived_ver', widget.version);
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
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(Icons.system_update_rounded, color: cs.onPrimaryContainer, size: 32),
                  ),
                  const Spacer(),
                  if (!_downloading)
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'UPDATE AVAILABLE',
                style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                'AlexLMP Revived\nv${widget.version}',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 36,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(
                      widget.notes,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, height: 1.45),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_status.isNotEmpty) ...[
                Text(_status, style: TextStyle(color: cs.primary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
              ],
              if (_downloading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 10,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: _downloadAndInstall,
                        child: const Text('Update Now', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Not Now', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                      ),
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