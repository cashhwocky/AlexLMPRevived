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

// ── Canvas Stack Palette (Exact Concept 1 Colors) ────────────────────────────
const Color _kBg = Color(0xFF0D0D11);
const Color _kBgPure = Color(0xFF000000);
const Color _kCard = Color(0xFF16161D);
const Color _kCardAlt = Color(0xFF17171F);
const Color _kDock = Color(0xFF181820);
const Color _kBorder = Color(0x18FFFFFF);
const Color _kText = Color(0xFFF5F5F8);
const Color _kSub = Color(0xFF9394A6);
const Color _kSubLight = Color(0xFFC9CAD6);
const Color _kCrimson = Color(0xFFFF2A5F);
const Color _kCrimsonSoft = Color(0xFFFF6B91);

Color get _bg => appState.b('pure_black_dark', false) ? _kBgPure : _kBg;

/// Instant in-memory cache for Liked Music so it opens immediately
YtAlbumPage? _memLikedPage;

/// Original AlexLMP Revived Crimson Liked Cover
Widget _likedCover({double iconSize = 24}) => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3A0B1B), Color(0xFFB81441)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(Icons.favorite_rounded, color: Colors.white, size: iconSize)),
    );

/// Custom navigation helpers so Artist / Album ALWAYS stay inside Canvas Stack UI
Future<void> revivedGoToArtist(BuildContext context, TrackItem t) async {
  HapticFeedback.selectionClick();
  if (!t.isYouTube) {
    final local = audioHandler.tracks.where((x) => !x.isYouTube && x.artist == t.artist).toList();
    if (local.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedPlaylistPage.custom(title: t.artist, subtitle: 'Artist', tracks: local),
      ));
    }
    return;
  }
  try {
    final links = await YouTubeMusic.trackLinks(t.ytVideoId!);
    if (!context.mounted) return;
    if (links.artistUrl != null && links.artistUrl!.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedArtistPage(url: links.artistUrl!, name: links.artistName ?? t.artist),
      ));
      return;
    }
    final found = await YouTubeMusic.searchArtists(t.artist);
    if (!context.mounted) return;
    if (found.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedArtistPage(url: found.first.url, name: found.first.name, initialThumb: found.first.thumbnail),
      ));
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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedPlaylistPage.custom(title: t.album, subtitle: t.artist, tracks: local),
      ));
    }
    return;
  }
  try {
    final links = await YouTubeMusic.trackLinks(t.ytVideoId!);
    if (!context.mounted) return;
    final ref = links.albumBrowseId ?? links.albumUrl;
    if (ref != null && ref.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RevivedAlbumPage(
          url: ref,
          initialTitle: links.albumTitle ?? t.album,
          initialThumb: links.albumThumbnail ?? t.artworkUrl,
        ),
      ));
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
        : (variant == 'bitlmp' ? const Color(0xFFD4D4D8) : _kCrimson);
    final b4 = variant == 'bloom'
        ? const Color(0xFF3B82F6)
        : (variant == 'bitlmp' ? const Color(0xFFA1A1AA) : _kCrimson);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white12),
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

/// Canvas Stack Track Context Menu
void showRevivedTrackMenu(BuildContext context, TrackItem track) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 16),
            Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 52, height: 52, child: CustomAlbumArtwork(track: track))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w700)),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kSub, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(appState.isLiked(track.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: appState.isLiked(track.id) ? _kCrimson : Colors.white),
                  onPressed: () {
                    appState.toggleLike(track.id);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: _kBorder),
            _menuItem(Icons.queue_play_next_rounded, 'Play next', () {
              audioHandler.addToQueue([track], next: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing "${track.title}" next')));
            }),
            _menuItem(Icons.add_to_queue_rounded, 'Add to queue', () {
              audioHandler.addToQueue([track]);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${track.title}" to queue')));
            }),
            _menuItem(Icons.playlist_add_rounded, 'Add to playlist', () {
              Navigator.pop(ctx);
              track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track);
            }),
            if (track.isYouTube)
              _menuItem(
                OfflineStore.isDownloaded(track) ? Icons.download_done_rounded : Icons.download_for_offline_rounded,
                OfflineStore.isDownloaded(track) ? 'Remove download' : 'Download for offline',
                () {
                  Navigator.pop(ctx);
                  toggleOffline(track);
                },
              ),
            _menuItem(Icons.lyrics_outlined, 'View lyrics', () {
              Navigator.pop(ctx);
              showLyricsSheet(context, track);
            }),
            _menuItem(Icons.person_outline_rounded, 'Go to artist', () {
              Navigator.pop(ctx);
              revivedGoToArtist(context, track);
            }),
            _menuItem(Icons.album_outlined, 'Go to album', () {
              Navigator.pop(ctx);
              revivedGoToAlbum(context, track);
            }),
            _menuItem(Icons.share_rounded, 'Share', () {
              Navigator.pop(ctx);
              shareTrack(track);
            }),
            _menuItem(Icons.edit_outlined, 'Edit details', () {
              Navigator.pop(ctx);
              showEditTrackDialog(context, track);
            }),
            _menuItem(Icons.info_outline_rounded, 'Track info', () {
              Navigator.pop(ctx);
              showTrackInfoDialog(context, track);
            }),
          ],
        ),
      ),
    ),
  );
}

Widget _menuItem(IconData icon, String title, VoidCallback onTap) => ListTile(
      dense: true,
      leading: Icon(icon, color: _kSubLight, size: 22),
      title: Text(title, style: const TextStyle(color: _kText, fontSize: 14.5, fontWeight: FontWeight.w600)),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );

// ═════════════════════════════════════════════════════════════════════════════
// 1. CANVAS STACK 2-STEP SETUP WIZARD (Permissions -> Sign in)
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
    return Scaffold(
      backgroundColor: _bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.9),
            radius: 1.1,
            colors: [_kCrimson.withOpacity(0.16), _bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Row(
                  children: [
                    if (_step > 0)
                      GestureDetector(
                        onTap: _back,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(color: _kCard, shape: BoxShape.circle, border: Border.all(color: _kBorder)),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                        ),
                      )
                    else
                      const RevivedBrandMark(size: 38),
                    const SizedBox(width: 14),
                    for (var i = 0; i < 2; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          height: 4,
                          margin: EdgeInsets.only(right: i < 1 ? 8 : 0),
                          decoration: BoxDecoration(
                            color: i <= _step ? _kCrimson : Colors.white12,
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
                  children: [_buildPermissionsStep(), _buildSignInStep()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 1 of 2', style: TextStyle(color: _kCrimsonSoft, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Music & notifications',
              style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          const Text('Allow access so AlexLMP Revived can scan local audio files and show lock-screen controls.',
              style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
          const SizedBox(height: 28),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _storageOk ? null : _grantStorage,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _storageOk ? _kCrimson : _kBorder),
              ),
              child: Row(
                children: [
                  Icon(_storageOk ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                      color: _storageOk ? _kCrimson : _kSubLight, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_storageOk ? 'Permissions granted' : 'Grant media permissions',
                            style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('Audio storage & playback notifications', style: TextStyle(color: _kSub, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (!_storageOk) const Icon(Icons.chevron_right_rounded, color: _kSub),
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
                backgroundColor: Colors.white,
                foregroundColor: _kBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: _next,
              child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInStep() {
    return ValueListenableBuilder<YtAccount>(
      valueListenable: ytAccount,
      builder: (context, acc, _) {
        final signedIn = acc.signedIn;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Step 2 of 2', style: TextStyle(color: _kCrimsonSoft, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Sign in to YouTube Music',
                  style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const SizedBox(height: 8),
              const Text('Connect your account to stream music and sync your liked songs and playlists.',
                  style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
              const SizedBox(height: 28),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: (signedIn || _signingIn) ? null : _signIn,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: signedIn ? _kCrimson : _kBorder),
                  ),
                  child: Row(
                    children: [
                      _signingIn
                          ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: _kCrimson))
                          : Icon(signedIn ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                              color: signedIn ? _kCrimson : _kCrimson, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(signedIn ? 'Signed in as ${acc.name ?? "YouTube user"}' : 'Connect YouTube Music',
                                style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(signedIn ? 'Ready to listen' : 'Tap to sign in with Google',
                                style: const TextStyle(color: _kSub, fontSize: 13)),
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
                    backgroundColor: signedIn ? _kCrimson : _kCard,
                    foregroundColor: signedIn ? Colors.white : _kSub,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: signedIn ? _finish : null,
                  child: Text(signedIn ? 'Start listening' : 'Sign in to continue',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. CANVAS STACK MAIN APP SHELL (Home, Discover, Collection + Floating Orb Dock)
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
    return ListenableBuilder(
      listenable: Listenable.merge([appState, OfflineStore.revision, LibraryStore.revision, audioHandler.currentIndex]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _buildHome(context),
                    _buildDiscover(context),
                    _buildCollection(context),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildFloatingOrbDock(context),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 1. CANVAS STACK HOME (Full-Bleed Cover Story Hero + Pills + Rotation Cards) ─
  Widget _buildHome(BuildContext context) {
    final yt = appState.homeMode == 'youtube';
    final local = widget.tracks.where((t) => !t.isYouTube).toList();
    final recent = appState.recent.map(audioHandler.trackById).whereType<TrackItem>().take(10).toList();
    final heroTrack = audioHandler.currentTrack ?? (recent.isNotEmpty ? recent.first : (widget.tracks.isNotEmpty ? widget.tracks.first : null));
    final top = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      color: _kCrimson,
      backgroundColor: _kCard,
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
          // Full-Bleed Visual Cover Story Hero (bleeds behind status bar!)
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
              height: 324 + top,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (heroTrack != null)
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.18), BlendMode.darken),
                      child: CustomAlbumArtwork(track: heroTrack),
                    )
                  else
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF441022), _kBg], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.36, 0.82, 1.0],
                        colors: [_bg.withOpacity(0.45), _bg.withOpacity(0.08), _bg.withOpacity(0.92), _bg],
                      ),
                    ),
                  ),
                  // Top floating controls
                  Positioned(
                    top: top + 10,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        _profileAvatarBtn(),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            appState.setStr('home_mode', yt ? 'local' : 'youtube');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Text(yt ? 'YouTube Music' : 'On device',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const Spacer(),
                        _glassCircleBtn(Icons.bar_chart_rounded, () => openListeningStats(context)),
                        const SizedBox(width: 8),
                        _glassCircleBtn(Icons.settings_outlined, () => openRevivedSettings(context)),
                      ],
                    ),
                  ),
                  // Bottom Hero Metadata + Rounded-Square White Play Button
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.48), borderRadius: BorderRadius.circular(99)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: _kCrimson, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              const Text('Continue listening', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          heroTrack?.title ?? 'AlexLMP Revived',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kText, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.7, height: 1.1),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                heroTrack != null ? '${heroTrack.artist} • ${heroTrack.album}' : 'Tap to explore your music',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _kSubLight, fontSize: 13.5, fontWeight: FontWeight.w500),
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
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                                    child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: _kBg, size: 28),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Horizontal Pill Chips Row (Exact Canvas Stack chips)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _cvPill('All', true, () {}),
                const SizedBox(width: 8),
                _cvPill('Liked songs', false, () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                  ));
                }),
                const SizedBox(width: 8),
                _cvPill('Downloads', false, () => openDownloads(context)),
                const SizedBox(width: 8),
                _cvPill('Shared likes', false, () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RevivedSharedLikesPage()));
                }),
                const SizedBox(width: 8),
                _cvPill('Mix', false, () => _shuffleAll(yt ? widget.tracks : local)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Your Rotation (Rounded #16161D Track Cards)
          if (recent.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text('Your rotation', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  for (var i = 0; i < min(5, recent.length); i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _cvTrackCard(recent[i], () => _playList(recent, i)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // YouTube Music Shelves or Local Tracks
          if (yt)
            FutureBuilder<List<YtShelf>>(
              future: _ytFeedFuture,
              initialData: YouTubeMusic.cachedHomeFeed(),
              builder: (context, snap) {
                final shelves = snap.data ?? const [];
                if (shelves.isEmpty && snap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: _kCrimson)));
                }
                if (shelves.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _emptyCard('Search YouTube Music to start listening', 'Open discover', () => setState(() => _tab = 1)),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                        child: Text(shelf.title.isEmpty ? 'For you' : shelf.title,
                            style: const TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
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
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(isArtist ? 69 : 18),
                                        border: Border.all(color: _kBorder),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: YtNetworkImage(url: it.thumbnail, size: 138, circle: isArtist),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                    Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kSub, fontSize: 12)),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _emptyCard('No local audio files found', 'Add music', () => showAddMusicSheet(context)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('On this device', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < min(20, local.length); i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _cvTrackCard(local[i], () => _playList(local, i)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 2. CANVAS STACK DISCOVER (Search + Full-Bleed Top Artist Banner) ──────
  Widget _buildDiscover(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    const cats = ['All', 'Songs', 'Artists', 'Albums', 'Playlists', 'Videos'];
    final history = _searchHistory;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Discover', style: TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _kCardAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kBorder),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: const TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w500),
              cursorColor: _kCrimson,
              decoration: InputDecoration(
                hintText: 'Artists, songs, albums, playlists…',
                hintStyle: const TextStyle(color: _kSub),
                prefixIcon: const Icon(Icons.search_rounded, color: _kCrimson),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: _kSub),
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
              itemBuilder: (_, i) => _cvPill(cats[i], _searchTab == i, () {
                setState(() => _searchTab = i);
                if (_searchCtrl.text.trim().isNotEmpty) _runSearch(_searchCtrl.text.trim());
              }),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: _kCrimson))
                : _searchCtrl.text.trim().isEmpty
                    ? (history.isEmpty
                        ? const Center(child: Text('Search artists, songs, albums, or playlists', style: TextStyle(color: _kSub, fontSize: 14)))
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 112),
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Recent searches', style: TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w700)),
                                  TextButton(
                                    onPressed: () {
                                      YouTubeMusic.prefs?.remove('search_history');
                                      setState(() {});
                                    },
                                    child: const Text('Clear', style: TextStyle(color: _kSub)),
                                  ),
                                ],
                              ),
                              for (final h in history)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      _searchCtrl.text = h;
                                      _runSearch(h);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.history_rounded, color: _kSub, size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(child: Text(h, style: const TextStyle(color: _kText, fontSize: 14.5, fontWeight: FontWeight.w600))),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ))
                    : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchTab == 0) {
      if (_artistRes.isEmpty && _songRes.isEmpty && _albumRes.isEmpty) {
        return const Center(child: Text('No results found', style: TextStyle(color: _kSub)));
      }
      final topArtist = _artistRes.isNotEmpty ? _artistRes.first : null;
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          // Full-Bleed Artist Spotlight Banner (Exact Concept 1 Search!)
          if (topArtist != null) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedArtistPage(url: topArtist.url, name: topArtist.name, initialThumb: topArtist.thumbnail),
                ));
              },
              child: Container(
                height: 152,
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBorder),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (topArtist.thumbnail != null)
                      Image.network(topArtist.thumbnail!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _kCard)),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, _kBg.withOpacity(0.92)],
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
                          const Text('Top artist', style: TextStyle(color: _kCrimsonSoft, fontSize: 11.5, fontWeight: FontWeight.w700)),
                          Text(topArtist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_songRes.isNotEmpty) ...[
            for (final t in _songRes.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _cvTrackCard(t, () {
                  HapticFeedback.selectionClick();
                  audioHandler.playYouTubeTrack(t);
                  openPlayer(context);
                }),
              ),
            const SizedBox(height: 14),
          ],
          if (_albumRes.isNotEmpty) ...[
            const Text('Albums & singles', style: TextStyle(color: _kText, fontSize: 17, fontWeight: FontWeight.w800)),
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
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail),
                    )),
                    child: SizedBox(
                      width: 134,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(16), child: YtNetworkImage(url: al.thumbnail, size: 134)),
                          const SizedBox(height: 6),
                          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text(al.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
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
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _cvTrackCard(_songRes[i], () {
            audioHandler.playYouTubeTrack(_songRes[i]);
            openPlayer(context);
          }),
        ),
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
            child: _cvPhotoBannerCard(
              title: a.name,
              subtitle: 'Artist',
              thumb: a.thumbnail,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail),
              )),
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
            child: _cvPhotoBannerCard(
              title: al.title,
              subtitle: al.artist,
              thumb: al.thumbnail,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail),
              )),
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
            child: _cvPhotoBannerCard(
              title: pl.title,
              subtitle: pl.subtitle,
              thumb: pl.thumbnail,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RevivedPlaylistPage.youtube(playlistId: pl.playlistId, title: pl.title, thumbnail: pl.thumbnail),
              )),
            ),
          );
        },
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 112),
      itemCount: _videoRes.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _cvTrackCard(_videoRes[i].track, () {
          audioHandler.playYouTubeTrack(_videoRes[i].track);
          openPlayer(context);
        }),
      ),
    );
  }

  // ── 3. CANVAS STACK COLLECTION (Stacked Visual Photo Cards) ───────────────
  Widget _buildCollection(BuildContext context) {
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
              const Expanded(child: Text('Collection', style: TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6))),
              _glassCircleBtn(Icons.file_download_outlined, () => openSpotifyImport(context)),
              const SizedBox(width: 8),
              _glassCircleBtn(Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _cvPill(filters[i], _libTab == i, () => setState(() => _libTab = i)),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildCollectionBody(songs)),
        ],
      ),
    );
  }

  Widget _buildCollectionBody(List<TrackItem> songs) {
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
              _cvPhotoBannerCard(
                title: 'Liked songs',
                subtitle: 'Synced • YouTube Music',
                customBg: _likedCover(iconSize: 42),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                )),
              ),
              const SizedBox(height: 10),
              _cvPhotoBannerCard(
                title: 'Downloads',
                subtitle: '${OfflineStore.count} offline tracks • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
                customBg: Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF172B47), Color(0xFF0E1420)])),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 22),
                  child: Icon(Icons.download_done_rounded, color: Colors.white.withOpacity(0.16), size: 64),
                ),
                onTap: () => openDownloads(context),
              ),
              const SizedBox(height: 10),
              for (final pl in appState.playlists) ...[
                _cvPhotoBannerCard(
                  title: pl.name,
                  subtitle: '${pl.trackIds.length} tracks • Local',
                  customBg: Container(color: _kCardAlt),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RevivedPlaylistPage.local(playlist: pl))),
                ),
                const SizedBox(height: 10),
              ],
              for (final ypl in ytPls) ...[
                _cvPhotoBannerCard(
                  title: ypl.title,
                  subtitle: ypl.subtitle.isEmpty ? 'Playlist • YouTube Music' : ypl.subtitle,
                  thumb: ypl.thumbnail,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RevivedPlaylistPage.youtube(playlistId: ypl.playlistId, title: ypl.title, thumbnail: ypl.thumbnail),
                  )),
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
          child: _cvPhotoBannerCard(
            title: list[i].key,
            subtitle: 'Artist • ${list[i].value.length} songs',
            customBg: CustomAlbumArtwork(track: list[i].value.first),
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
          child: _cvPhotoBannerCard(
            title: list[i].key,
            subtitle: '${list[i].value.first.artist} • ${list[i].value.length} songs',
            customBg: CustomAlbumArtwork(track: list[i].value.first),
            onTap: () => _playList(list[i].value, 0),
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 112),
      itemCount: songs.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _cvTrackCard(songs[i], () => _playList(songs, i)),
      ),
    );
  }

  // ── FLOATING PILL DOCK + CIRCULAR CRIMSON-RINGED ALBUM ART ORB ────────────
  Widget _buildFloatingOrbDock(BuildContext context) {
    const labels = ['Home', 'Discover', 'Library'];
    final cur = audioHandler.currentTrack;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bg.withOpacity(0.0), _bg.withOpacity(0.92), _bg],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kDock,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 28, offset: const Offset(0, 12))],
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
                        color: _tab == i ? Colors.white.withOpacity(0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          color: _tab == i ? Colors.white : const Color(0xFF8F90A2),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              // Floating Circular Album Art Orb with 2px Crimson Ring!
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _kCrimson, width: 2),
                    color: _kCard,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: cur != null
                      ? CustomAlbumArtwork(track: cur)
                      : const Icon(Icons.music_note_rounded, color: Colors.white70, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CANVAS STACK REUSABLE WIDGETS ─────────────────────────────────────────
  Widget _cvPill(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : _kCardAlt,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: active ? Colors.white : Colors.white.withOpacity(0.12)),
          ),
          child: Text(label, style: TextStyle(color: active ? _kBg : const Color(0xFFD4D4E0), fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _cvTrackCard(TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    final downloaded = OfflineStore.isDownloaded(t);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      onLongPress: () => showRevivedTrackMenu(context, t),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? _kCrimson.withOpacity(0.5) : _kBorder),
        ),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 48, height: 48, child: CustomAlbumArtwork(track: t))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? _kCrimsonSoft : _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (downloaded) ...[
                        const Icon(Icons.download_done_rounded, size: 13, color: _kCrimson),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5))),
                    ],
                  ),
                ],
              ),
            ),
            if (t.durationSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(formatDuration(Duration(seconds: t.durationSeconds)), style: const TextStyle(color: Color(0xFF7E7F91), fontSize: 11.5)),
              ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 18),
              onPressed: () => showRevivedTrackMenu(context, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cvPhotoBannerCard({required String title, required String subtitle, String? thumb, Widget? customBg, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 108,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorder),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumb != null)
              ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.45), BlendMode.darken),
                child: Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _kCard)),
              )
            else if (customBg != null)
              ColorFiltered(
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.35), BlendMode.darken),
                child: customBg,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_kBg.withOpacity(0.88), _kBg.withOpacity(0.22)],
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
                      style: const TextStyle(color: _kText, fontSize: 18.5, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kSubLight, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassCircleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle, border: Border.all(color: Colors.white12)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _profileAvatarBtn() => ValueListenableBuilder<YtAccount>(
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
            decoration: BoxDecoration(color: _kCard, shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.5)),
            child: acc.signedIn && acc.photo != null && acc.photo!.isNotEmpty
                ? Image.network(acc.photo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 20))
                : const Icon(Icons.person_rounded, color: Colors.white, size: 20),
          ),
        ),
      );

  Widget _emptyCard(String msg, String btn, VoidCallback onTap) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: _kBorder)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: const TextStyle(color: _kSub, fontSize: 14)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _kBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. CANVAS STACK ALBUM, ARTIST, PLAYLIST, AND SHARED LIKES PAGES
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
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<YtAlbumPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kCrimson));
          }
          final page = snap.data;
          if (page == null) return const Center(child: Text('Could not load release', style: TextStyle(color: _kSub)));
          final isSingle = (page.kind ?? '').toLowerCase() == 'single' || page.tracks.length <= 2;
          final typeLabel = isSingle ? 'Single' : (page.kind ?? 'Album');
          final artUrl = page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Full-bleed Canvas Stack Album Hero
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 320 + top,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (artUrl != null)
                            Image.network(artUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _kCard))
                          else
                            Container(color: _kCard),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.45, 0.85, 1.0],
                                colors: [_bg.withOpacity(0.45), Colors.transparent, _bg.withOpacity(0.9), _bg],
                              ),
                            ),
                          ),
                          Positioned(
                            top: top + 8,
                            left: 14,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
                                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
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
                                Text('$typeLabel${page.year != null ? " • ${page.year}" : ""}',
                                    style: const TextStyle(color: _kCrimsonSoft, fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(page.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.1)),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () {
                                    if (page.artistUrl != null) {
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => RevivedArtistPage(url: page.artistUrl!, name: page.artist),
                                      ));
                                    }
                                  },
                                  child: Text('${page.artist} • ${page.tracks.length} ${page.tracks.length == 1 ? "song" : "songs"}',
                                      style: const TextStyle(color: _kSubLight, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                ),
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
                                backgroundColor: _kCrimson,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                                backgroundColor: _kCard,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: _kBorder)),
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
                          const SizedBox(width: 8),
                          IconButton(icon: const Icon(Icons.download_for_offline_outlined, color: _kSubLight), onPressed: () => OfflineStore.downloadAll(page.tracks)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
                sliver: SliverList.builder(
                  itemCount: page.tracks.length,
                  itemBuilder: (_, i) {
                    final t = page.tracks[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          audioHandler.playYouTubeList(page.tracks, i, lockToScope: true);
                          openPlayer(context);
                        },
                        onLongPress: () => showRevivedTrackMenu(context, t),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                          decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
                          child: Row(
                            children: [
                              SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: _kCrimsonSoft, fontWeight: FontWeight.w700, fontSize: 13.5))),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                                    Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                                  ],
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 18), onPressed: () => showRevivedTrackMenu(context, t)),
                            ],
                          ),
                        ),
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
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<YtArtistPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kCrimson));
          }
          final page = snap.data;
          if (page == null) return const Center(child: Text('Could not load artist', style: TextStyle(color: _kSub)));
          final img = page.banner ?? page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Seamless Full-Bleed Canvas Stack Artist Hero (Zero seam!)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 318 + top,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (img != null)
                            Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _kCard))
                          else
                            Container(color: _kCard),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.0, 0.5, 0.85, 1.0],
                                colors: [_bg.withOpacity(0.4), Colors.transparent, _bg.withOpacity(0.88), _bg],
                              ),
                            ),
                          ),
                          Positioned(
                            top: top + 8,
                            left: 14,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
                                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
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
                                Text(page.subscribersText ?? 'Artist', style: const TextStyle(color: _kCrimsonSoft, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(page.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.08)),
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
                                backgroundColor: _kCrimson,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                              backgroundColor: _kCard,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: _kBorder)),
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
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 4, 18, 10),
                    child: Text('Popular', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList.builder(
                    itemCount: min(10, page.songs.length),
                    itemBuilder: (_, i) {
                      final t = page.songs[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            audioHandler.playYouTubeList(page.songs, i, lockToScope: true);
                            openPlayer(context);
                          },
                          onLongPress: () => showRevivedTrackMenu(context, t),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                            decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
                            child: Row(
                              children: [
                                SizedBox(width: 22, child: Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(color: _kCrimsonSoft, fontWeight: FontWeight.w700, fontSize: 13))),
                                const SizedBox(width: 8),
                                ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t))),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                                      Text(page.plays[t.id] ?? t.artist, style: const TextStyle(color: _kSub, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 18), onPressed: () => showRevivedTrackMenu(context, t)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              for (final sh in page.shelves.where((s) => s.kind == 'album'))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sh.title.isEmpty ? 'Discography' : sh.title, style: const TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
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
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => RevivedAlbumPage(url: it.id, initialTitle: it.title, initialThumb: it.thumbnail),
                                )),
                                child: SizedBox(
                                  width: 136,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(borderRadius: BorderRadius.circular(16), child: YtNetworkImage(url: it.thumbnail, size: 136)),
                                      const SizedBox(height: 6),
                                      Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                      Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
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
    if (widget.customTracks != null) {
      return _scaffold(widget.title ?? 'Playlist', widget.subtitle ?? '${widget.customTracks!.length} songs', null, widget.customTracks!, widget.isLikedStyle);
    }
    if (widget.localPlaylist != null) {
      final pl = widget.localPlaylist!;
      final tracks = pl.trackIds.map(audioHandler.trackById).whereType<TrackItem>().toList();
      return _scaffold(pl.name, '${tracks.length} songs', null, tracks, false);
    }
    return FutureBuilder<YtAlbumPage>(
      future: _ytFuture,
      initialData: _cached,
      builder: (context, snap) {
        final page = snap.data;
        if (page == null) {
          return Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(backgroundColor: _bg, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator(color: _kCrimson)
                  : const Text('Could not load playlist', style: TextStyle(color: _kSub)),
            ),
          );
        }
        final isLiked = widget.ytPlaylistId == 'LM';
        return _scaffold(page.title, '${page.tracks.length} songs', isLiked ? null : (page.thumbnail ?? widget.thumbnail), page.tracks, isLiked);
      },
    );
  }

  Widget _scaffold(String name, String sub, String? thumb, List<TrackItem> tracks, bool isLiked) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 290 + top,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (thumb != null)
                        Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _likedCover(iconSize: 72))
                      else
                        _likedCover(iconSize: 72),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.4, 0.85, 1.0],
                            colors: [_bg.withOpacity(0.45), Colors.transparent, _bg.withOpacity(0.9), _bg],
                          ),
                        ),
                      ),
                      Positioned(
                        top: top + 8,
                        left: 14,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
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
                            Text('Playlist • $sub', style: const TextStyle(color: _kCrimsonSoft, fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
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
                            backgroundColor: _kCrimson,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                            backgroundColor: _kCard,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: _kBorder)),
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
                      const SizedBox(width: 8),
                      IconButton(icon: const Icon(Icons.download_for_offline_outlined, color: _kSubLight), onPressed: () => OfflineStore.downloadAll(tracks)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
            sliver: SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (_, i) {
                final t = tracks[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      audioHandler.playYouTubeList(tracks, i);
                      openPlayer(context);
                    },
                    onLongPress: () => showRevivedTrackMenu(context, t),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                      decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
                      child: Row(
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 48, height: 48, child: CustomAlbumArtwork(track: t))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                                Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 18), onPressed: () => showRevivedTrackMenu(context, t)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. CANVAS STACK NOW PLAYING (Full-Bleed Top Art + Floating #16161D Card + Crimson Play)
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
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final track = audioHandler.currentTrack;
        final scaleY = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
        final radius = (_dragY / 10).clamp(0.0, 28.0);
        final screenH = MediaQuery.of(context).size.height;

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
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(radius)),
              child: track == null
                  ? const Center(child: Text('Nothing playing', style: TextStyle(color: _kSub)))
                  : Stack(
                      children: [
                        // Full-Bleed Top Album Art fading seamlessly into #0D0D11
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: screenH * 0.62,
                          child: GestureDetector(
                            onDoubleTap: () => _doubleTapLike(track),
                            onHorizontalDragUpdate: _onHorizUpdate,
                            onHorizontalDragEnd: _onHorizEnd,
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: _draggingX ? 0 : 240),
                              curve: Curves.easeOutBack,
                              transform: Matrix4.identity()..translate(_dragX * 0.4, 0.0),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CustomAlbumArtwork(track: track),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: const [0.0, 0.42, 1.0],
                                        colors: [_bg.withOpacity(0.48), _bg.withOpacity(0.06), _bg],
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: AnimatedOpacity(
                                      duration: const Duration(milliseconds: 220),
                                      opacity: _showHeartPop ? 1.0 : 0.0,
                                      child: AnimatedScale(
                                        duration: const Duration(milliseconds: 220),
                                        scale: _showHeartPop ? 1.15 : 0.6,
                                        child: const Icon(Icons.favorite_rounded, color: _kCrimson, size: 84, shadows: [Shadow(color: Colors.black54, blurRadius: 20)]),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Foreground Controls
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                            child: Column(
                              children: [
                                // Top Floating Overlay Row (Down | Album Pill | Heart)
                                Row(
                                  children: [
                                    _playerGlassBtn(Icons.keyboard_arrow_down_rounded, () => Navigator.of(context).pop()),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Center(
                                        child: GestureDetector(
                                          onTap: () => revivedGoToAlbum(context, track),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(99)),
                                            child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ListenableBuilder(
                                      listenable: appState,
                                      builder: (_, __) {
                                        final liked = appState.isLiked(track.id);
                                        return _playerGlassBtn(
                                          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                          () => appState.toggleLike(track.id),
                                          color: liked ? _kCrimson : Colors.white,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // Floating #16161D Canvas Stack Control Card
                                Container(
                                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                                  decoration: BoxDecoration(
                                    color: _kCard,
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: Colors.white.withOpacity(0.09)),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.65), blurRadius: 44, offset: const Offset(0, 20))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                GestureDetector(
                                                  onTap: () => revivedGoToAlbum(context, track),
                                                  child: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: _kText, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                                                ),
                                                const SizedBox(height: 3),
                                                GestureDetector(
                                                  onTap: () => revivedGoToArtist(context, track),
                                                  child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(color: Color(0xFF9D9EB0), fontSize: 14, fontWeight: FontWeight.w500)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.more_vert_rounded, color: _kSubLight),
                                            onPressed: () => showRevivedTrackMenu(context, track),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      // Crimson Seek Slider
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
                                                  trackHeight: 4,
                                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                                  activeTrackColor: _kCrimson,
                                                  inactiveTrackColor: Colors.white12,
                                                  thumbColor: Colors.white,
                                                ),
                                                child: Slider(value: curMs, max: maxMs, onChanged: (v) => audioHandler.seek(Duration(milliseconds: v.round()))),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(formatDuration(pos), style: const TextStyle(color: _kSub, fontSize: 11.5)),
                                                    Text(formatDuration(dur), style: const TextStyle(color: _kSub, fontSize: 11.5)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      // Main Transport Row (Lyrics | Prev | Rounded-Square Crimson Play | Next | Queue)
                                      StreamBuilder<PlaybackState>(
                                        stream: audioHandler.playbackState,
                                        builder: (context, snap) {
                                          final st = snap.data ?? audioHandler.playbackState.value;
                                          final playing = st.playing;
                                          final shuf = st.shuffleMode == AudioServiceShuffleMode.all;
                                          final rep = st.repeatMode;
                                          return Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF9D9EB0), size: 21),
                                                    onPressed: () => showLyricsSheet(context, track),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 34),
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
                                                      width: 60,
                                                      height: 60,
                                                      decoration: BoxDecoration(color: _kCrimson, borderRadius: BorderRadius.circular(22)),
                                                      child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 34),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 34),
                                                    onPressed: () {
                                                      HapticFeedback.mediumImpact();
                                                      audioHandler.skipToNext();
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.queue_music_rounded, color: Color(0xFF9D9EB0), size: 24),
                                                    onPressed: () => _showProQueueSheet(context),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              // Subtle Secondary Utility Row (Shuffle, Speed/Reverb, Playlist Add, Repeat)
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                                children: [
                                                  IconButton(
                                                    icon: Icon(Icons.shuffle_rounded, color: shuf ? _kCrimson : _kSub, size: 20),
                                                    onPressed: () {
                                                      HapticFeedback.selectionClick();
                                                      audioHandler.setShuffleMode(shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.headphones_outlined, color: _kSub, size: 20),
                                                    onPressed: () => showPlaybackSheet(context),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.playlist_add_rounded, color: _kSub, size: 22),
                                                    onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                                        color: rep == AudioServiceRepeatMode.none ? _kSub : _kCrimson, size: 20),
                                                    onPressed: () {
                                                      HapticFeedback.selectionClick();
                                                      final next = rep == AudioServiceRepeatMode.none
                                                          ? AudioServiceRepeatMode.all
                                                          : (rep == AudioServiceRepeatMode.all ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none);
                                                      audioHandler.setRepeatMode(next);
                                                    },
                                                  ),
                                                ],
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
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _playerGlassBtn(IconData icon, VoidCallback onTap, {Color color = Colors.white}) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
      );

  void _showProQueueSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
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
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('Queue (${list.length})', style: const TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800))),
                        if (upNext.isNotEmpty)
                          TextButton(onPressed: () => audioHandler.clearQueue(), child: const Text('Clear up next', style: TextStyle(color: _kCrimson))),
                      ],
                    ),
                  ),
                  if (upNext.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _kDock, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 4),
                            child: Text('Up next (${upNext.length})', style: const TextStyle(color: _kCrimsonSoft, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          for (var q = 0; q < min(4, upNext.length); q++)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 38, height: 38, child: CustomAlbumArtwork(track: upNext[q]))),
                              title: Text(upNext[q].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                              trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: _kSub), onPressed: () => audioHandler.removeFromQueue(q)),
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
                          leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t))),
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? _kCrimsonSoft : _kText, fontWeight: FontWeight.w600)),
                          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                          trailing: const Icon(Icons.drag_handle_rounded, color: _kSub),
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
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sleep timer', style: TextStyle(color: _kText, fontSize: 19, fontWeight: FontWeight.w800)),
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
                title: Text(opt.$1, style: const TextStyle(color: _kText, fontWeight: FontWeight.w500)),
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
// 5. CANVAS STACK SETTINGS SCREEN (App Icons + Crossfade Slider + All Pro Tools)
// ═════════════════════════════════════════════════════════════════════════════
void openRevivedSettings(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RevivedSettingsScreen()));
}

class RevivedSettingsScreen extends StatelessWidget {
  const RevivedSettingsScreen({super.key});

  Future<void> _applyAppIcon(BuildContext context, String id, String label) async {
    HapticFeedback.selectionClick();
    appState.setStr('app_icon', id);
    try {
      await _kRevivedMediaCh.invokeMethod('setAppIcon', {'icon': id, 'name': id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('App icon changed to $label')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected $label icon')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final crossfadeOn = appState.b('crossfade_on');
        final crossfadeSecs = appState.d('crossfade_secs', 6.0).clamp(1.0, 12.0);
        final currentIcon = appState.str('app_icon', 'default');

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: const Text('Settings', style: TextStyle(color: _kText, fontWeight: FontWeight.w800)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            children: [
              _section('App icon'),
              Row(
                children: [
                  Expanded(child: _iconTile(context, 'default', 'Crimson', currentIcon == 'default')),
                  const SizedBox(width: 10),
                  Expanded(child: _iconTile(context, 'bloom', 'Midnight', currentIcon == 'bloom')),
                  const SizedBox(width: 10),
                  Expanded(child: _iconTile(context, 'bitlmp', 'Stealth', currentIcon == 'bitlmp')),
                ],
              ),
              const SizedBox(height: 18),
              _section('Tools & library'),
              _card([
                ListTile(
                  leading: const Icon(Icons.bar_chart_rounded, color: _kCrimsonSoft),
                  title: const Text('Listening stats', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Top songs, artists, daily streak & 24h clock', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openListeningStats(context),
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_rounded, color: _kCrimsonSoft),
                  title: const Text('Import from Spotify', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Bring playlists over from Exportify CSV', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openSpotifyImport(context),
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.download_done_rounded, color: _kCrimsonSoft),
                  title: const Text('Offline downloads', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: Text('${OfflineStore.count} songs • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}', style: const TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openDownloads(context),
                ),
              ]),
              const SizedBox(height: 18),
              _section('Playback & audio'),
              _card([
                ListTile(
                  leading: const Icon(Icons.waves_rounded, color: _kCrimsonSoft),
                  title: const Text('Speed, pitch & reverb', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Slowed + reverb, nightcore, sped up & pitch', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => showPlaybackSheet(context),
                ),
                const Divider(color: _kBorder, height: 1),
                ValueListenableBuilder<String?>(
                  valueListenable: audioHandler.sleepLabel,
                  builder: (_, lbl, __) => ListTile(
                    leading: const Icon(Icons.bedtime_rounded, color: _kCrimsonSoft),
                    title: const Text('Sleep timer', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(lbl ?? 'Off', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => _showSleepTimerSheet(context),
                  ),
                ),
                const Divider(color: _kBorder, height: 1),
                _toggle('Crossfade', 'Smoothly blend between songs', crossfadeOn, (v) => appState.setB('crossfade_on', v)),
                if (crossfadeOn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        const Text('Duration', style: TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Slider(
                            activeColor: _kCrimson,
                            inactiveColor: Colors.white12,
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
                              style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                const Divider(color: _kBorder, height: 1),
                _toggle('Smooth play & pause fade', 'Fade volume gently on pause and resume', appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Skip silence', 'Trim dead air between tracks', appState.b('skip_silence'), (v) {
                  appState.setB('skip_silence', v);
                  audioHandler.player.setSkipSilenceEnabled(v);
                }),
                const Divider(color: _kBorder, height: 1),
                _toggle('Pause on disconnect', 'Pause when headphones unplug', appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Autoplay radio', 'Queue similar songs when playlist ends', appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Word-by-word lyrics', 'Highlight each word live in synced lyrics', appState.b('word_lyrics', true), (v) => appState.setB('word_lyrics', v)),
              ]),
              const SizedBox(height: 18),
              _section('Account & system'),
              _card([
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => ListTile(
                    leading: const Icon(Icons.play_circle_fill_rounded, color: _kCrimson),
                    title: Text(acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music', style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                const Divider(color: _kBorder, height: 1),
                _toggle('Pure black background', 'Use #000000 instead of #0D0D11', appState.b('pure_black_dark', false), (v) => appState.setB('pure_black_dark', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('Data saver', 'Lower bitrate on mobile data', appState.b('yt_data_saver'), (v) {
                  appState.setB('yt_data_saver', v);
                  applyNativeSettings();
                }),
                const Divider(color: _kBorder, height: 1),
                _toggle('Prefetch next song', 'Preload upcoming track for instant skips', appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
                const Divider(color: _kBorder, height: 1),
                _toggle('High refresh rate (120Hz)', 'Keep scrolling and animations smooth', appState.b('high_refresh', true), (v) {
                  appState.setB('high_refresh', v);
                  applyNativeSettings();
                }),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: _kSubLight),
                  title: const Text('Clear stream cache', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    await const MethodChannel('com.alexlmp.app/ytmusic').invokeMethod('ytClearCache');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio cache cleared')));
                  },
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: _kSubLight),
                  title: const Text('Check for updates', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: Text(const String.fromEnvironment('APP_BUILD_VER', defaultValue: 'v1.0.0'), style: const TextStyle(color: _kSub)),
                  onTap: () => checkRevivedUpdate(context, manual: true),
                ),
                const Divider(color: _kBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded, color: _kSub),
                  title: const Text('Re-run setup screen', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  onTap: () {
                    appState.setB('setup_done', false);
                    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const RevivedSetupScreen()), (_) => false);
                  },
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _iconTile(BuildContext context, String id, String label, bool selected) => GestureDetector(
        onTap: () => _applyAppIcon(context, id, label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? _kCrimson : _kBorder, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              RevivedBrandMark(size: 46, variant: id),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: selected ? Colors.white : _kSub, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: const TextStyle(color: _kCrimsonSoft, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: _kBorder)),
        child: Column(children: children),
      );

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        activeColor: Colors.white,
        activeTrackColor: _kCrimson,
        title: Text(title, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: _kSub, fontSize: 12.5)),
        value: value,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          onChanged(v);
        },
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 6. FULL-SCREEN CANVAS STACK IN-APP UPDATE CHECKER
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
    return Scaffold(
      backgroundColor: _bg,
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
                    IconButton(icon: const Icon(Icons.close_rounded, color: _kSub), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Update available', style: TextStyle(color: _kCrimsonSoft, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('AlexLMP Revived\nv${widget.version}',
                  style: const TextStyle(color: _kText, fontSize: 34, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: _kBorder)),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Text(widget.notes, style: const TextStyle(color: _kSub, fontSize: 14.5, height: 1.45)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_status.isNotEmpty) ...[
                Text(_status, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              if (_downloading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, backgroundColor: _kCard, valueColor: const AlwaysStoppedAnimation<Color>(_kCrimson)),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _kCrimson, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                        onPressed: _downloadAndInstall,
                        child: const Text('Update now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now', style: TextStyle(color: _kSub, fontWeight: FontWeight.w600))),
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