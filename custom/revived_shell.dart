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
  // Default is rich M3E tonal dark (NOT flat AMOLED black)
  if (appState.b('m3e_pure_black', false)) {
    return base.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0C0C0F),
    );
  }
  return base;
}

Widget _m3eGroup(ColorScheme cs, List<Widget> children) {
  if (children.isEmpty) return const SizedBox.shrink();
  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            Divider(height: 1, indent: 72, endIndent: 16, color: cs.outlineVariant.withOpacity(0.25)),
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
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(22)),
                    child: Icon(Icons.graphic_eq_rounded, color: cs.onPrimaryContainer, size: 34),
                  ),
                  const SizedBox(height: 24),
                  Text('AlexLMP\nRevived',
                      style: TextStyle(color: cs.onSurface, fontSize: 42, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -1.4)),
                  const SizedBox(height: 10),
                  Text('Sign in to YouTube Music to get started. Everything adapts to your colors.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15.5, height: 1.4)),
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
                      child: Text(signedIn ? 'Start Listening' : 'Sign in to Continue',
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
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
                  Text(badge, style: TextStyle(color: cs.primary, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
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
// 2. MAIN APP SHELL (M3E Home, Smart Search with Top Result, Spotify Library)
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
  int _libTab = 0; // 0 = Playlists, 1 = Artists, 2 = Albums, 3 = Songs
  bool _libGrid = false;
  int _searchTab = 0; // 0 = All (Top Result), 1 = Songs, 2 = Artists, 3 = Albums, 4 = Playlists

  final TextEditingController _searchCtrl = TextEditingController();
  List<TrackItem> _songRes = [];
  List<YtArtist> _artistRes = [];
  List<YtAlbum> _albumRes = [];
  List<YtPlaylistRef> _playlistRes = [];
  bool _searching = false;
  Timer? _debounce;
  Future<List<YtShelf>>? _ytFeedFuture;
  Future<List<YtPlaylistRef>>? _ytPlFuture;

  @override
  void initState() {
    super.initState();
    _ytFeedFuture = YouTubeMusic.homeFeed();
    _ytPlFuture = YouTubeMusic.libraryPlaylists();
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
        // Fetch Artists, Songs, and Albums in parallel for a rich Top Result view
        final results = await Future.wait([
          YouTubeMusic.searchArtists(query).catchError((_) => <YtArtist>[]),
          YouTubeMusic.search(query).catchError((_) => <TrackItem>[]),
          YouTubeMusic.searchAlbums(query).catchError((_) => <YtAlbum>[]),
        ]);
        if (mounted) {
          setState(() {
            _artistRes = results[0] as List<YtArtist>;
            _songRes = results[1] as List<TrackItem>;
            _albumRes = results[2] as List<YtAlbum>;
          });
        }
      } else if (_searchTab == 1) {
        final r = await YouTubeMusic.search(query);
        if (mounted) setState(() => _songRes = r);
      } else if (_searchTab == 2) {
        final r = await YouTubeMusic.searchArtists(query);
        if (mounted) setState(() => _artistRes = r);
      } else if (_searchTab == 3) {
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

  // ── HOME PAGE (Profile Pic Avatar, No Speed/Pitch Clutter) ────────────────
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
              _profileAvatarBtn(cs),
              const SizedBox(width: 8),
              _tonalIconBtn(cs, Icons.settings_outlined, () => openRevivedSettings(context)),
            ],
          ),
          const SizedBox(height: 16),
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
                      Text(yt ? 'Quick Mix' : 'Device Shuffle',
                          style: TextStyle(color: cs.onPrimaryContainer, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(yt ? 'Jump straight into your rotation' : '${local.length} tracks on this phone',
                          style: TextStyle(color: cs.onPrimaryContainer.withOpacity(0.78), fontSize: 13.5)),
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
          // Clean 2-button Quick Row (Liked + Offline — no Speed/Pitch)
          Row(
            children: [
              Expanded(
                child: _actionCapsule(
                  cs,
                  Icons.favorite_rounded,
                  'Liked Songs',
                  () => yt
                      ? Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                        ))
                      : setState(() {
                          _tab = 2;
                          _libTab = 3;
                        }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _actionCapsule(cs, Icons.download_done_rounded, 'Downloads', () => openDownloads(context))),
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
                      Text(shelf.title.isEmpty ? 'For you' : shelf.title,
                          style: TextStyle(color: cs.onSurface, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
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
                                      borderRadius: BorderRadius.circular(isArtist ? 70 : 22),
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

  Widget _profileAvatarBtn(ColorScheme cs) {
    return ValueListenableBuilder<YtAccount>(
      valueListenable: ytAccount,
      builder: (_, acc, __) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          showYtAccountSheet(context);
        },
        child: Container(
          width: 42,
          height: 42,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
            border: Border.all(color: cs.primary.withOpacity(0.5), width: 1.5),
          ),
          child: acc.signedIn && acc.photo != null && acc.photo!.isNotEmpty
              ? Image.network(
                  acc.photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: cs.onPrimaryContainer, size: 22),
                )
              : Icon(Icons.person_rounded, color: cs.onPrimaryContainer, size: 22),
        ),
      ),
    );
  }

  // ── SMART SEARCH PAGE (Top Result Artist Card + Songs + Albums) ───────────
  Widget _buildSearch(BuildContext context, ColorScheme cs) {
    final top = MediaQuery.of(context).padding.top;
    const cats = ['All', 'Songs', 'Artists', 'Albums', 'Playlists'];
    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search', style: TextStyle(color: cs.onSurface, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: TextStyle(color: cs.onSurface, fontSize: 16),
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
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                            Text('Search any artist, song, or album',
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
    // ALL TAB: Top Result Hero Card (Artist) -> Songs -> Albums
    if (_searchTab == 0) {
      if (_artistRes.isEmpty && _songRes.isEmpty && _albumRes.isEmpty) {
        return Center(child: Text('No results found', style: TextStyle(color: cs.onSurfaceVariant)));
      }
      final topArtist = _artistRes.isNotEmpty ? _artistRes.first : null;
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (topArtist != null) ...[
            Text('Top Result', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedArtistPage(url: topArtist.url, name: topArtist.name, initialThumb: topArtist.thumbnail),
                ));
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    YtNetworkImage(url: topArtist.thumbnail, size: 76, circle: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                            child: Text('ARTIST',
                                style: TextStyle(color: cs.onPrimary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ),
                          const SizedBox(height: 6),
                          Text(topArtist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: cs.onSecondaryContainer, fontSize: 22, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: cs.onSecondaryContainer.withOpacity(0.7), size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_songRes.isNotEmpty) ...[
            Text('Songs', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _m3eGroup(cs, [
              for (final t in _songRes.take(8))
                _trackTile(cs, t, () {
                  HapticFeedback.selectionClick();
                  audioHandler.playYouTubeTrack(t);
                  openPlayer(context);
                }),
            ]),
            const SizedBox(height: 20),
          ],
          if (_albumRes.isNotEmpty) ...[
            Text('Albums', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            SizedBox(
              height: 192,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _albumRes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final al = _albumRes[i];
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail),
                    )),
                    child: SizedBox(
                      width: 136,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(20), child: YtNetworkImage(url: al.thumbnail, size: 136)),
                          const SizedBox(height: 6),
                          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text(al.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
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
    }
    if (_searchTab == 1) {
      if (_songRes.isEmpty) return Center(child: Text('No songs found', style: TextStyle(color: cs.onSurfaceVariant)));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: _songRes.length,
        itemBuilder: (_, i) => _trackTile(cs, _songRes[i], () {
          HapticFeedback.selectionClick();
          audioHandler.playYouTubeTrack(_songRes[i]);
          openPlayer(context);
        }),
      );
    }
    if (_searchTab == 2) {
      if (_artistRes.isEmpty) return Center(child: Text('No artists found', style: TextStyle(color: cs.onSurfaceVariant)));
      return ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          _m3eGroup(cs, [
            for (final a in _artistRes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: YtNetworkImage(url: a.thumbnail, size: 52, circle: true),
                title: Text(a.name, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                subtitle: Text('Artist', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail),
                )),
              ),
          ]),
        ],
      );
    }
    if (_searchTab == 3) {
      if (_albumRes.isEmpty) return Center(child: Text('No albums found', style: TextStyle(color: cs.onSurfaceVariant)));
      return ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          _m3eGroup(cs, [
            for (final al in _albumRes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: ClipRRect(borderRadius: BorderRadius.circular(14), child: YtNetworkImage(url: al.thumbnail, size: 52)),
                title: Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                subtitle: Text(al.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail),
                )),
              ),
          ]),
        ],
      );
    }
    if (_playlistRes.isEmpty) return Center(child: Text('No playlists found', style: TextStyle(color: cs.onSurfaceVariant)));
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        _m3eGroup(cs, [
          for (final pl in _playlistRes)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: ClipRRect(borderRadius: BorderRadius.circular(14), child: YtNetworkImage(url: pl.thumbnail, size: 52)),
              title: Text(pl.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
              subtitle: Text(pl.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RevivedPlaylistPage.youtube(playlistId: pl.playlistId, title: pl.title, thumbnail: pl.thumbnail),
              )),
            ),
        ]),
      ],
    );
  }

  // ── SPOTIFY-STYLE LIBRARY PAGE ────────────────────────────────────────────
  Widget _buildLibrary(BuildContext context, ColorScheme cs) {
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
              _profileAvatarBtn(cs),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Your Library',
                    style: TextStyle(color: cs.onSurface, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              ),
              _tonalIconBtn(cs, _libGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  () => setState(() => _libGrid = !_libGrid)),
              const SizedBox(width: 8),
              _tonalIconBtn(cs, Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < filters.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filters[i]),
                      selected: _libTab == i,
                      selectedColor: cs.primaryContainer,
                      backgroundColor: cs.surfaceContainerHigh,
                      labelStyle: TextStyle(
                        color: _libTab == i ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide.none,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _libTab = i);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildLibraryContent(cs, songs)),
        ],
      ),
    );
  }

  Widget _buildLibraryContent(ColorScheme cs, List<TrackItem> songs) {
    // 0: Playlists (Pinned Liked Songs + Downloads + YouTube Playlists + Local Playlists)
    if (_libTab == 0) {
      return FutureBuilder<List<YtPlaylistRef>>(
        future: _ytPlFuture,
        initialData: YouTubeMusic.cachedLibrary(),
        builder: (context, snap) {
          final ytPls = snap.data ?? const <YtPlaylistRef>[];
          final items = <Widget>[
            _libEntry(
              cs: cs,
              title: 'Liked Songs',
              subtitle: 'Pinned · YouTube Music',
              pinned: true,
              cover: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Icon(Icons.favorite_rounded, color: cs.onPrimary, size: 28),
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
              )),
            ),
            _libEntry(
              cs: cs,
              title: 'Downloads',
              subtitle: 'Pinned · Offline audio',
              pinned: true,
              cover: Container(
                color: cs.secondaryContainer,
                child: Icon(Icons.download_done_rounded, color: cs.onSecondaryContainer, size: 28),
              ),
              onTap: () => openDownloads(context),
            ),
            for (final pl in appState.playlists)
              _libEntry(
                cs: cs,
                title: pl.name,
                subtitle: 'Playlist · ${pl.trackIds.length} songs',
                cover: Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.queue_music_rounded, color: cs.primary, size: 28),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedPlaylistPage.local(playlist: pl),
                )),
              ),
            for (final ypl in ytPls)
              _libEntry(
                cs: cs,
                title: ypl.title,
                subtitle: ypl.subtitle.isEmpty ? 'Playlist · YouTube Music' : ypl.subtitle,
                cover: YtNetworkImage(url: ypl.thumbnail, size: 60),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedPlaylistPage.youtube(
                    playlistId: ypl.playlistId,
                    title: ypl.title,
                    thumbnail: ypl.thumbnail,
                  ),
                )),
              ),
          ];

          if (_libGrid) {
            return GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.85,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => items[i],
            );
          }
          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => items[i],
          );
        },
      );
    }

    // 1: Artists
    if (_libTab == 1) {
      final byArtist = <String, List<TrackItem>>{};
      for (final t in songs) {
        byArtist.putIfAbsent(t.artist, () => []).add(t);
      }
      final list = byArtist.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      if (list.isEmpty) return _emptyCard(cs, 'No artists in your library yet', 'Search Music', () => setState(() => _tab = 1));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final e = list[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipOval(child: SizedBox(width: 52, height: 52, child: CustomAlbumArtwork(track: e.value.first))),
            title: Text(e.key, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
            subtitle: Text('Artist · ${e.value.length} songs', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            onTap: () => _playList(e.value, 0),
          );
        },
      );
    }

    // 2: Albums
    if (_libTab == 2) {
      final byAlbum = <String, List<TrackItem>>{};
      for (final t in songs) {
        byAlbum.putIfAbsent(t.album, () => []).add(t);
      }
      final list = byAlbum.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      if (list.isEmpty) return _emptyCard(cs, 'No albums in your library yet', 'Search Music', () => setState(() => _tab = 1));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final e = list[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 52, height: 52, child: CustomAlbumArtwork(track: e.value.first)),
            ),
            title: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
            subtitle: Text('${e.value.first.artist} · ${e.value.length} songs',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            onTap: () => _playList(e.value, 0),
          );
        },
      );
    }

    // 3: Songs (Lazy ListView.builder for 120fps)
    if (songs.isEmpty) return _emptyCard(cs, 'No songs yet', 'Add Music', () => showAddMusicSheet(context));
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: songs.length,
      itemBuilder: (_, i) => _trackTile(cs, songs[i], () => _playList(songs, i)),
    );
  }

  Widget _libEntry({
    required ColorScheme cs,
    required String title,
    required String subtitle,
    required Widget cover,
    required VoidCallback onTap,
    bool pinned = false,
  }) {
    if (_libGrid) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox.expand(child: cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
            Row(
              children: [
                if (pinned) ...[
                  Icon(Icons.push_pin_rounded, size: 12, color: cs.primary),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 60, height: 60, child: cover)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (pinned) ...[
                        Icon(Icons.push_pin_rounded, size: 13, color: cs.primary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── MINI PLAYER & FLOATING M3E NAV ────────────────────────────────────────
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
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)),
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
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(32)),
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
                        Icon(_tab == i ? items[i].$2 : items[i].$1,
                            color: _tab == i ? cs.onPrimaryContainer : cs.onSurfaceVariant, size: 22),
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
            decoration: BoxDecoration(color: active ? cs.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(20)),
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
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: cs.onSurface, fontSize: 13.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _trackTile(ColorScheme cs, TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
// 3. FAST LAZY ALBUM, ARTIST, AND PLAYLIST PAGES (Zero Lag!)
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
          final page = snap.data;
          if (page == null) {
            return Center(child: Text('Could not load album', style: TextStyle(color: cs.onSurfaceVariant)));
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: YtNetworkImage(url: page.thumbnail ?? widget.initialThumb, size: 220),
                      ),
                      const SizedBox(height: 16),
                      Text(page.title, textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurface, fontSize: 25, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('${page.artist}${page.year != null ? " · ${page.year}" : ""}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14.5, fontWeight: FontWeight.w600)),
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
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w800)),
                              onPressed: () {
                                if (page.tracks.isEmpty) return;
                                audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                                audioHandler.playYouTubeList(page.tracks, Random().nextInt(page.tracks.length), lockToScope: true);
                                openPlayer(context);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: page.tracks.length,
                itemBuilder: (_, i) {
                  final t = page.tracks[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: Text('${i + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      audioHandler.playYouTubeList(page.tracks, i, lockToScope: true);
                      openPlayer(context);
                    },
                  );
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
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
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(backgroundColor: cs.surface, elevation: 0, iconTheme: IconThemeData(color: cs.onSurface)),
      body: FutureBuilder<YtArtistPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }
          final page = snap.data;
          if (page == null) {
            return Center(child: Text('Could not load artist', style: TextStyle(color: cs.onSurfaceVariant)));
          }
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 36),
            children: [
              Center(child: YtNetworkImage(url: page.thumbnail ?? widget.initialThumb, size: 156, circle: true)),
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

/// Instant-loading, zero-lag Playlist Page using cachedPlaylistPage + SliverList.builder
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
  YtAlbumPage? _cached;

  @override
  void initState() {
    super.initState();
    if (widget.ytPlaylistId != null) {
      _cached = YouTubeMusic.cachedPlaylistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail);
      _ytFuture = YouTubeMusic.playlistPage(widget.ytPlaylistId!, title: widget.title, thumbnail: widget.thumbnail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = _m3();
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
        final refreshing = snap.connectionState == ConnectionState.waiting;
        if (page == null) {
          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(backgroundColor: cs.surface, elevation: 0, iconTheme: IconThemeData(color: cs.onSurface)),
            body: Center(
              child: refreshing
                  ? CircularProgressIndicator(color: cs.primary)
                  : Text('Could not load playlist', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          );
        }
        return _scaffold(cs, page.title, '${page.tracks.length} tracks', page.thumbnail ?? widget.thumbnail, page.tracks, refreshing);
      },
    );
  }

  Widget _scaffold(ColorScheme cs, String name, String sub, String? thumb, List<TrackItem> tracks, bool refreshing) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          if (refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
            ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(28)),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: thumb != null
                              ? YtNetworkImage(url: thumb, size: 88)
                              : Container(
                                  width: 88,
                                  height: 88,
                                  color: cs.primaryContainer,
                                  child: Icon(Icons.favorite_rounded, color: cs.onPrimaryContainer, size: 40),
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
                  const SizedBox(height: 14),
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
                ],
              ),
            ),
          ),
          // Lazy SliverList.builder so 500+ liked songs scroll at 120fps with zero lag
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 48, height: 48, child: CustomAlbumArtwork(track: t)),
                ),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                onTap: () {
                  HapticFeedback.selectionClick();
                  audioHandler.playYouTubeList(tracks, i);
                  openPlayer(context);
                },
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. REPLICATED PLAYER (Matches Screenshot + Swipe Down + Less-Sensitive Skip)
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

  // Deliberately less sensitive horizontal swipe (requires >125px drag or >750px/s fling)
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
    final track = audioHandler.currentTrack;
    final scaleY = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
    final radius = (_dragY / 10).clamp(0.0, 28.0);
    final bgTop = Color.lerp(cs.surfaceContainerHigh, const Color(0xFF141417), 0.55)!;
    final bgBot = Color.lerp(cs.surface, const Color(0xFF0A0A0C), 0.65)!;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity((1.0 - _dragY / 600).clamp(0.2, 1.0)),
      body: GestureDetector(
        onVerticalDragUpdate: _onVertUpdate,
        onVerticalDragEnd: _onVertEnd,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _draggingY ? 0 : 240),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translate(0.0, _dragY)
            ..scale(scaleY, scaleY),
          transformAlignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, bgBot],
            ),
          ),
          child: track == null
              ? const Center(child: Text('Nothing playing', style: TextStyle(color: Colors.white54)))
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                    child: Column(
                      children: [
                        // Top bar (Chevron Down | NOW PLAYING + Album/Playlist | 3-dots)
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop();
                              },
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text('NOW PLAYING',
                                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                                  const SizedBox(height: 2),
                                  Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                              onPressed: () => openRevivedSettings(context),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Large Square Album Art with Less-Sensitive Carousel Swipe
                        GestureDetector(
                          onHorizontalDragUpdate: _onHorizUpdate,
                          onHorizontalDragEnd: _onHorizEnd,
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: _draggingX ? 0 : 240),
                            curve: Curves.easeOutBack,
                            transform: Matrix4.identity()
                              ..translate(_dragX, 0.0)
                              ..scale((1.0 - _dragX.abs() / 1600).clamp(0.92, 1.0)),
                            transformAlignment: Alignment.center,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 28, offset: const Offset(0, 14)),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: CustomAlbumArtwork(track: track),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Title + Artist + (+) Add + Heart
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                                  const SizedBox(height: 4),
                                  Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 26),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                track.isYouTube
                                    ? showYtAddToPlaylist(context, track)
                                    : showAddToPlaylistSheet(context, track);
                              },
                            ),
                            ListenableBuilder(
                              listenable: appState,
                              builder: (_, __) {
                                final liked = appState.isLiked(track.id);
                                return IconButton(
                                  icon: Icon(
                                    liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                    color: liked ? cs.primary : Colors.white,
                                    size: 26,
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
                        const SizedBox(height: 12),
                        // Sleek White Progress Bar + Timestamps
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
                                    trackHeight: 3.5,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                    activeTrackColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: Colors.white,
                                  ),
                                  child: Slider(
                                    value: curMs,
                                    max: maxMs,
                                    onChanged: (v) => audioHandler.seek(Duration(milliseconds: v.round())),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(formatDuration(pos), style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                                      Text(formatDuration(dur), style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        // Transport Controls (Shuffle | Prev | Big White Play Circle | Next | Repeat)
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
                                  icon: Icon(Icons.shuffle_rounded, color: shuf ? cs.primary : Colors.white, size: 24),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    audioHandler.setShuffleMode(
                                      shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                                    );
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
                                    child: Icon(
                                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 38,
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
                                  icon: Icon(
                                    rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                    color: rep == AudioServiceRepeatMode.none ? Colors.white : cs.primary,
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
                        const SizedBox(height: 16),
                        // Bottom Utility Row matching screenshot: (Info, Headphones/Speed, Lyrics) --- (Add, Queue)
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 22),
                              onPressed: () => _showSleepTimerSheet(context, cs),
                            ),
                            IconButton(
                              icon: const Icon(Icons.headphones_outlined, color: Colors.white70, size: 22),
                              onPressed: () => showSpeedPitchSheet(context),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 21),
                              onPressed: () => showSpeedPitchSheet(context),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 24),
                              onPressed: () {
                                track.isYouTube
                                    ? showYtAddToPlaylist(context, track)
                                    : showAddToPlaylistSheet(context, track);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 24),
                              onPressed: () => _showQueueSheet(context, cs),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _showQueueSheet(BuildContext context, ColorScheme cs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) {
        final list = audioHandler.tracks;
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Up Next (${list.length})', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final t = list[i];
                    final active = audioHandler.currentTrack?.id == t.id;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t)),
                      ),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: active ? cs.primary : cs.onSurface, fontWeight: FontWeight.w700)),
                      subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      onTap: () {
                        audioHandler.playIndex(i);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void _showSleepTimerSheet(BuildContext context, ColorScheme cs) {
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
            Text('Sleep Timer', style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final opt in [
              ('Off', null, false),
              ('15 minutes', const Duration(minutes: 15), false),
              ('30 minutes', const Duration(minutes: 30), false),
              ('45 minutes', const Duration(minutes: 45), false),
              ('1 hour', const Duration(hours: 1), false),
              ('End of current song', null, true),
            ])
              ListTile(
                title: Text(opt.$1, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
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
// 5. SPEED & PITCH SHEET (Slowed / Sped Up)
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
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.speed_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Speed & Pitch', style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w800))),
                    TextButton(onPressed: () => applyBoth(1.0, 1.0), child: Text('Reset', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700))),
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
            style: TextStyle(color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );

// ═════════════════════════════════════════════════════════════════════════════
// 6. REVAMPED M3E SETTINGS SCREEN
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
              _section(cs, 'APPEARANCE & MATERIAL YOU'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(26)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
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
                    const SizedBox(height: 8),
                    _toggle(cs, 'Pure AMOLED Black', 'Override tonal dark surfaces with #000000',
                        appState.b('m3e_pure_black', false), (v) => appState.setB('m3e_pure_black', v)),
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
                _toggle(cs, 'YouTube Data Saver', 'Use lower bitrate audio on mobile data',
                    appState.b('yt_data_saver'), (v) {
                  appState.setB('yt_data_saver', v);
                  applyNativeSettings();
                }),
                _toggle(cs, 'Prefetch Next Song', 'Preload upcoming track for instant skips',
                    appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
                ListTile(
                  leading: Icon(Icons.cleaning_services_rounded, color: cs.primary),
                  title: Text('Clear Stream Cache', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  subtitle: Text('Free up temporary YouTube audio cache', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await const MethodChannel('com.alexlmp.app/ytmusic').invokeMethod('ytClearCache');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio cache cleared.')));
                    }
                  },
                ),
              ]),
              const SizedBox(height: 20),
              _section(cs, 'PLAYBACK & AUDIO'),
              _m3eGroup(cs, [
                ListTile(
                  leading: Icon(Icons.speed_rounded, color: cs.primary),
                  title: Text('Speed & Pitch Controls', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                  subtitle: Text('Speed ${appState.speed.toStringAsFixed(2)}x · Pitch ${appState.pitch.toStringAsFixed(2)}x',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                  onTap: () => showSpeedPitchSheet(context),
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: audioHandler.sleepLabel,
                  builder: (_, lbl, __) => ListTile(
                    leading: Icon(Icons.bedtime_rounded, color: cs.primary),
                    title: Text('Sleep Timer', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    subtitle: Text(lbl ?? 'Off', style: TextStyle(color: cs.onSurfaceVariant)),
                    trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                    onTap: () => _showSleepTimerSheet(context, cs),
                  ),
                ),
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
              ]),
              const SizedBox(height: 20),
              _section(cs, 'SYSTEM & UPDATES'),
              _m3eGroup(cs, [
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
                ListTile(
                  leading: Icon(Icons.system_update_rounded, color: cs.primary),
                  title: Text('Check for Updates', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () => checkRevivedUpdate(context, manual: true),
                ),
                ListTile(
                  leading: Icon(Icons.refresh_rounded, color: cs.primary),
                  title: Text('Scan Device Music', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () => scanDeviceAudio(),
                ),
                ListTile(
                  leading: Icon(Icons.restart_alt_rounded, color: cs.onSurfaceVariant),
                  title: Text('Re-run Setup Screen', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                  onTap: () {
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
        child: Text(title, style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 7. FULL-SCREEN IN-APP UPDATE CHECKER & INSTALLER
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No published releases found yet.')));
      }
      return;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final notes = (data['body'] ?? 'Bug fixes, performance improvements, and UI updates.').toString().trim();
    String? apkUrl;
    for (final a in (data['assets'] as List? ?? const [])) {
      if (a is Map && (a['name'] ?? '').toString().toLowerCase().contains('universal') &&
          (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apkUrl = a['browser_download_url']?.toString();
        break;
      }
    }
    apkUrl ??= (data['assets'] as List? ?? const [])
        .whereType()
        .map((a) => a['browser_download_url']?.toString())
        .firstWhere((u) => u != null && u.toLowerCase().endsWith('.apk'), orElse: () => null);
    if (tag.isEmpty || apkUrl == null) return;

    final installed = appState.str('installed_revived_ver', '0.0.0');
    if (!manual && tag == installed) return;
    if (!context.mounted) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => RevivedUpdateScreen(version: tag, notes: notes, apkUrl: apkUrl!),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  } catch (_) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check for updates right now.')));
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
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
                    child: Icon(Icons.system_update_rounded, color: cs.onPrimaryContainer, size: 32),
                  ),
                  const Spacer(),
                  if (!_downloading)
                    IconButton(icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 24),
              Text('UPDATE AVAILABLE',
                  style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
              const SizedBox(height: 6),
              Text('AlexLMP Revived\nv${widget.version}',
                  style: TextStyle(color: cs.onSurface, fontSize: 36, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -1.1)),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(widget.notes, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, height: 1.45)),
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