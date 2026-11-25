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

// ── Clean Dark Spotify-Like Palette (No Material You, No Kinetic) ────────────
const Color _kBg = Color(0xFF121212);
const Color _kBgPure = Color(0xFF000000);
const Color _kCard = Color(0xFF1E1E1E);
const Color _kCardHigh = Color(0xFF282828);
const Color _kDivider = Color(0xFF2A2A2A);
const Color _kText = Color(0xFFFFFFFF);
const Color _kSub = Color(0xFFB3B3B3);
const Color _kAccent = Color(0xFFFF2A5F);
const Color _kTidalCyan = Color(0xFF00FFFF);

Color get _bg => appState.b('pure_black_dark', false) ? _kBgPure : _kBg;
String get _playerStyle => appState.str('revived_player_style', 'classic'); // 'classic' | 'tidal'

/// The 4-bar AlexLMP Revived brand icon widget
class RevivedBrandMark extends StatelessWidget {
  final double size;
  const RevivedBrandMark({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0D),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _bar(size * 0.10, size * 0.22, const Color(0xFFD4D4DC)),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.46, _kAccent),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.58, Colors.white),
            SizedBox(width: size * 0.06),
            _bar(size * 0.10, size * 0.30, _kAccent),
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

/// Pro Track Context Menu (Long-press or 3-dots on any track)
void showRevivedTrackMenu(BuildContext context, TrackItem track) {
  HapticFeedback.lightImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Row(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 50, height: 50, child: CustomAlbumArtwork(track: track))),
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
                      color: appState.isLiked(track.id) ? _kAccent : Colors.white),
                  onPressed: () {
                    appState.toggleLike(track.id);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: _kDivider),
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
              goToArtist(context, track);
            }),
            _menuItem(Icons.album_outlined, 'Go to album', () {
              Navigator.pop(ctx);
              goToAlbum(context, track);
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
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: _kText, fontSize: 14.5, fontWeight: FontWeight.w500)),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );

// ═════════════════════════════════════════════════════════════════════════════
// 1. 3-SCREEN SETUP WIZARD (Permissions -> Player Style ONLY -> Sign In)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSetupScreen extends StatefulWidget {
  const RevivedSetupScreen({super.key});
  @override
  State<RevivedSetupScreen> createState() => _RevivedSetupScreenState();
}

class _RevivedSetupScreenState extends State<RevivedSetupScreen> {
  final PageController _pageCtrl = PageController();
  int _step = 0; // 0 = Permissions, 1 = Player Style, 2 = Sign In
  bool _storageOk = false;
  bool _signingIn = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < 2) {
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
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Row(
                  children: [
                    if (_step > 0)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        onPressed: _back,
                      )
                    else
                      const RevivedBrandMark(size: 32),
                    const SizedBox(width: 14),
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          height: 4,
                          margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: i <= _step ? Colors.white : Colors.white24,
                            borderRadius: BorderRadius.circular(2),
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
                  children: [
                    _buildPermissionsStep(),
                    _buildPlayerStyleStep(),
                    _buildSignInStep(),
                  ],
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
          const Text('Step 1 of 3', style: TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Music & notifications',
              style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          const Text('Allow access so AlexLMP Revived can scan local audio files and show lock-screen media controls.',
              style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
          const SizedBox(height: 28),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _storageOk ? null : _grantStorage,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _storageOk ? Colors.white : _kDivider),
              ),
              child: Row(
                children: [
                  Icon(_storageOk ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                      color: _storageOk ? Colors.white : _kSub, size: 28),
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
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              onPressed: _next,
              child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerStyleStep() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 2 of 3', style: TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Choose your player',
              style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 8),
          const Text('Pick how the full-screen Now playing view looks. You can switch anytime in Settings.',
              style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
          const SizedBox(height: 24),
          _playerOptionCard(
            title: 'Classic',
            subtitle: 'Clean dark layout with white circular play button and full bottom utility bar',
            selected: _playerStyle == 'classic',
            previewAccent: Colors.white,
            onTap: () => appState.setStr('revived_player_style', 'classic'),
          ),
          const SizedBox(height: 14),
          _playerOptionCard(
            title: 'Tidal',
            subtitle: 'Minimalist hi-fi layout with cover glow, quality tag, and tabbed bottom controls',
            selected: _playerStyle == 'tidal',
            previewAccent: _kTidalCyan,
            onTap: () => appState.setStr('revived_player_style', 'tidal'),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              onPressed: _next,
              child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerOptionCard({
    required String title,
    required String subtitle,
    required bool selected,
    required Color previewAccent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? _kCardHigh : _kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.white : _kDivider, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.play_arrow_rounded, color: previewAccent, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: _kText, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: _kSub, fontSize: 12.5, height: 1.3)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? Colors.white : _kSub),
          ],
        ),
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
              const Text('Step 3 of 3', style: TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('Sign in to YouTube Music',
                  style: TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const SizedBox(height: 8),
              const Text('Connect your account to stream music and sync your liked songs and playlists.',
                  style: TextStyle(color: _kSub, fontSize: 15, height: 1.4)),
              const SizedBox(height: 28),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: (signedIn || _signingIn) ? null : _signIn,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: signedIn ? Colors.white : _kDivider),
                  ),
                  child: Row(
                    children: [
                      _signingIn
                          ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : Icon(signedIn ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                              color: signedIn ? Colors.white : _kAccent, size: 30),
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
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: signedIn ? Colors.white : _kCardHigh,
                    foregroundColor: signedIn ? Colors.black : _kSub,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
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
// 2. SPOTIFY-LIKE MAIN APP SHELL (Home, Search, Library + All Pro Features)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedAppShell extends StatefulWidget {
  final List<TrackItem> tracks;
  final Widget Function(AppPalette pal)? aiChatBuilder;
  const RevivedAppShell({super.key, required this.tracks, this.aiChatBuilder});

  @override
  State<RevivedAppShell> createState() => _RevivedAppShellState();
}

class _RevivedAppShellState extends State<RevivedAppShell> {
  int _tab = 0; // 0=Home, 1=Search, 2=Library
  int _libTab = 0; // 0=Playlists, 1=Artists, 2=Albums, 3=Songs
  bool _libGrid = false;
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
    appState.setB('update_check', true);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkRevivedUpdate(context));
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
      listenable: Listenable.merge([appState, OfflineStore.revision, LibraryStore.revision]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: _bg,
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _buildHome(context),
                    _buildSearch(context),
                    _buildLibrary(context),
                  ],
                ),
              ),
              _buildMiniPlayer(context),
              _buildBottomNav(),
            ],
          ),
        );
      },
    );
  }

  // ── SPOTIFY-STYLE HOME ────────────────────────────────────────────────────
  Widget _buildHome(BuildContext context) {
    final yt = appState.homeMode == 'youtube';
    final local = widget.tracks.where((t) => !t.isYouTube).toList();
    final recent = appState.recent.map(audioHandler.trackById).whereType<TrackItem>().take(8).toList();
    final top = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: _kCardHigh,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, top + 12, 16, 24),
        children: [
          Row(
            children: [
              _profileAvatarBtn(),
              const SizedBox(width: 10),
              _filterPill('YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
              const SizedBox(width: 8),
              _filterPill('On device', !yt, () => appState.setStr('home_mode', 'local')),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 22),
                onPressed: () => openListeningStats(context),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 22),
                onPressed: () => openRevivedSettings(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 3.0,
            children: [
              _compactGridTile(
                title: 'Liked songs',
                cover: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
                ),
                onTap: () => yt
                    ? Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
                      ))
                    : setState(() {
                        _tab = 2;
                        _libTab = 3;
                      }),
              ),
              _compactGridTile(
                title: 'Downloads',
                cover: Container(color: const Color(0xFF1E3A5F), child: const Icon(Icons.download_done_rounded, color: Colors.white, size: 22)),
                onTap: () => openDownloads(context),
              ),
              _compactGridTile(
                title: 'Shuffle all',
                cover: Container(color: const Color(0xFF1F4E3D), child: const Icon(Icons.shuffle_rounded, color: Colors.white, size: 22)),
                onTap: () => _shuffleAll(yt ? widget.tracks : local),
              ),
              _compactGridTile(
                title: 'Shared likes',
                cover: Container(color: const Color(0xFF4A2545), child: const Icon(Icons.favorite_border_rounded, color: Colors.white, size: 22)),
                onTap: () => openSharedLikes(context),
              ),
              for (final r in recent.take(2))
                _compactGridTile(
                  title: r.title,
                  cover: CustomAlbumArtwork(track: r),
                  onTap: () => _playList(recent, recent.indexOf(r)),
                ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Jump back in', style: TextStyle(color: _kText, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 12),
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final t = recent[i];
                  return GestureDetector(
                    onTap: () => _playList(recent, i),
                    onLongPress: () => showRevivedTrackMenu(context, t),
                    child: SizedBox(
                      width: 136,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 136, height: 136, child: CustomAlbumArtwork(track: t))),
                          const SizedBox(height: 8),
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (yt)
            FutureBuilder<List<YtShelf>>(
              future: _ytFeedFuture,
              initialData: YouTubeMusic.cachedHomeFeed(),
              builder: (context, snap) {
                final shelves = snap.data ?? const [];
                if (shelves.isEmpty && snap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: Colors.white)));
                }
                if (shelves.isEmpty) {
                  return _emptyCard('Search YouTube Music to start listening', 'Open search', () => setState(() => _tab = 1));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      Text(shelf.title.isEmpty ? 'Recommended for you' : shelf.title,
                          style: const TextStyle(color: _kText, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 192,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: shelf.items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                                      borderRadius: BorderRadius.circular(isArtist ? 70 : 6),
                                      child: YtNetworkImage(url: it.thumbnail, size: 140, circle: isArtist),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                    Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kSub, fontSize: 12)),
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
            _emptyCard('No local audio files found', 'Add music', () => showAddMusicSheet(context))
          else ...[
            const Text('On this device', style: TextStyle(color: _kText, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (var i = 0; i < min(20, local.length); i++) _trackTile(local[i], () => _playList(local, i)),
          ],
        ],
      ),
    );
  }

  Widget _compactGridTile({required String title, required Widget cover, required VoidCallback onTap}) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              SizedBox(width: 56, height: double.infinity, child: cover),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kText, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
                ),
              ),
            ],
          ),
        ),
      );

  // ── SPOTIFY-STYLE SEARCH ──────────────────────────────────────────────────
  Widget _buildSearch(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    const cats = ['All', 'Songs', 'Artists', 'Albums', 'Playlists', 'Videos'];
    final history = _searchHistory;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _profileAvatarBtn(),
              const SizedBox(width: 12),
              const Text('Search', style: TextStyle(color: _kText, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600),
              cursorColor: Colors.black,
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                hintStyle: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.black87),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.black54),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < cats.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _filterPill(cats[i], _searchTab == i, () {
                      setState(() => _searchTab = i);
                      if (_searchCtrl.text.trim().isNotEmpty) _runSearch(_searchCtrl.text.trim());
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _searchCtrl.text.trim().isEmpty
                    ? (history.isEmpty
                        ? const Center(child: Text('Search artists, songs, albums, or playlists', style: TextStyle(color: _kSub, fontSize: 14)))
                        : ListView(
                            physics: const BouncingScrollPhysics(),
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
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.history_rounded, color: _kSub),
                                  title: Text(h, style: const TextStyle(color: _kText, fontSize: 15)),
                                  onTap: () {
                                    _searchCtrl.text = h;
                                    _runSearch(h);
                                  },
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
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (topArtist != null) ...[
            const Text('Top result', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedArtistPage(url: topArtist.url, name: topArtist.name, initialThumb: topArtist.thumbnail),
                ));
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    YtNetworkImage(url: topArtist.thumbnail, size: 68, circle: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(topArtist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          const Text('Artist', style: TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _kSub),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (_songRes.isNotEmpty) ...[
            const Text('Songs', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final t in _songRes.take(8))
              _trackTile(t, () {
                HapticFeedback.selectionClick();
                audioHandler.playYouTubeTrack(t);
                openPlayer(context);
              }),
            const SizedBox(height: 18),
          ],
          if (_albumRes.isNotEmpty) ...[
            const Text('Albums & singles', style: TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            SizedBox(
              height: 188,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _albumRes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                          ClipRRect(borderRadius: BorderRadius.circular(6), child: YtNetworkImage(url: al.thumbnail, size: 136)),
                          const SizedBox(height: 6),
                          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
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
        itemCount: _songRes.length,
        itemBuilder: (_, i) => _trackTile(_songRes[i], () {
          audioHandler.playYouTubeTrack(_songRes[i]);
          openPlayer(context);
        }),
      );
    }
    if (_searchTab == 2) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: _artistRes.length,
        itemBuilder: (_, i) {
          final a = _artistRes[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: YtNetworkImage(url: a.thumbnail, size: 52, circle: true),
            title: Text(a.name, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
            subtitle: const Text('Artist', style: TextStyle(color: _kSub)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RevivedArtistPage(url: a.url, name: a.name, initialThumb: a.thumbnail),
            )),
          );
        },
      );
    }
    if (_searchTab == 3) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: _albumRes.length,
        itemBuilder: (_, i) {
          final al = _albumRes[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: YtNetworkImage(url: al.thumbnail, size: 52)),
            title: Text(al.title, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
            subtitle: Text(al.artist, style: const TextStyle(color: _kSub)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RevivedAlbumPage(url: al.url, initialTitle: al.title, initialThumb: al.thumbnail),
            )),
          );
        },
      );
    }
    if (_searchTab == 4) {
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: _playlistRes.length,
        itemBuilder: (_, i) {
          final pl = _playlistRes[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: YtNetworkImage(url: pl.thumbnail, size: 52)),
            title: Text(pl.title, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
            subtitle: Text(pl.subtitle, style: const TextStyle(color: _kSub)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RevivedPlaylistPage.youtube(playlistId: pl.playlistId, title: pl.title, thumbnail: pl.thumbnail),
            )),
          );
        },
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _videoRes.length,
      itemBuilder: (_, i) => _trackTile(_videoRes[i].track, () {
        audioHandler.playYouTubeTrack(_videoRes[i].track);
        openPlayer(context);
      }),
    );
  }

  // ── SPOTIFY-STYLE LIBRARY ─────────────────────────────────────────────────
  Widget _buildLibrary(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    const filters = ['Playlists', 'Artists', 'Albums', 'Songs'];
    final songs = widget.tracks;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _profileAvatarBtn(),
              const SizedBox(width: 12),
              const Expanded(child: Text('Your library', style: TextStyle(color: _kText, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5))),
              IconButton(
                icon: const Icon(Icons.file_download_outlined, color: Colors.white),
                tooltip: 'Import from Spotify',
                onPressed: () => openSpotifyImport(context),
              ),
              IconButton(
                icon: Icon(_libGrid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Colors.white),
                onPressed: () => setState(() => _libGrid = !_libGrid),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                onPressed: () => showCreateOrEditPlaylistDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < filters.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _filterPill(filters[i], _libTab == i, () => setState(() => _libTab = i)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: _buildLibraryBody(songs)),
        ],
      ),
    );
  }

  Widget _buildLibraryBody(List<TrackItem> songs) {
    if (_libTab == 0) {
      return FutureBuilder<List<YtPlaylistRef>>(
        future: _ytPlFuture,
        initialData: YouTubeMusic.cachedLibrary(),
        builder: (context, snap) {
          final ytPls = snap.data ?? const <YtPlaylistRef>[];
          final items = <Widget>[
            _libEntry(
              title: 'Liked songs',
              subtitle: 'Playlist • YouTube Music',
              pinned: true,
              cover: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 28),
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RevivedPlaylistPage.youtube(playlistId: 'LM', title: 'Liked Music'),
              )),
            ),
            _libEntry(
              title: 'Downloads',
              subtitle: '${OfflineStore.count} offline songs • ${OfflineStore.formatBytes(OfflineStore.totalBytes)}',
              pinned: true,
              cover: Container(color: const Color(0xFF1E3A5F), child: const Icon(Icons.download_done_rounded, color: Colors.white, size: 28)),
              onTap: () => openDownloads(context),
            ),
            for (final pl in appState.playlists)
              _libEntry(
                title: pl.name,
                subtitle: 'Playlist • ${pl.trackIds.length} songs',
                cover: Container(color: _kCardHigh, child: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 28)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RevivedPlaylistPage.local(playlist: pl))),
              ),
            for (final ypl in ytPls)
              _libEntry(
                title: ypl.title,
                subtitle: ypl.subtitle.isEmpty ? 'Playlist • YouTube Music' : ypl.subtitle,
                cover: YtNetworkImage(url: ypl.thumbnail, size: 60),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RevivedPlaylistPage.youtube(playlistId: ypl.playlistId, title: ypl.title, thumbnail: ypl.thumbnail),
                )),
              ),
          ];
          if (_libGrid) {
            return GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 14, childAspectRatio: 0.85),
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
    if (_libTab == 1) {
      final byArtist = <String, List<TrackItem>>{};
      for (final t in songs) {
        byArtist.putIfAbsent(t.artist, () => []).add(t);
      }
      final list = byArtist.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipOval(child: SizedBox(width: 54, height: 54, child: CustomAlbumArtwork(track: list[i].value.first))),
          title: Text(list[i].key, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
          subtitle: Text('Artist • ${list[i].value.length} songs', style: const TextStyle(color: _kSub)),
          onTap: () => _playList(list[i].value, 0),
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
        itemCount: list.length,
        itemBuilder: (_, i) => ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 54, height: 54, child: CustomAlbumArtwork(track: list[i].value.first))),
          title: Text(list[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
          subtitle: Text('${list[i].value.first.artist} • ${list[i].value.length} songs', style: const TextStyle(color: _kSub)),
          onTap: () => _playList(list[i].value, 0),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: songs.length,
      itemBuilder: (_, i) => _trackTile(songs[i], () => _playList(songs, i)),
    );
  }

  // ── SPOTIFY-STYLE MINI PLAYER & BOTTOM NAV ────────────────────────────────
  Widget _buildMiniPlayer(BuildContext context) {
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
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -300) openPlayer(context);
          },
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -380) {
              HapticFeedback.mediumImpact();
              audioHandler.skipToNext();
            } else if (v > 380) {
              HapticFeedback.mediumImpact();
              audioHandler.skipToPreviousTrack();
            }
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(8)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
                  child: Row(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 42, height: 42, child: CustomAlbumArtwork(track: t))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w700)),
                            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
                          ],
                        ),
                      ),
                      StreamBuilder<PlaybackState>(
                        stream: audioHandler.playbackState,
                        builder: (_, snap) {
                          final playing = snap.data?.playing ?? audioHandler.player.playing;
                          return IconButton(
                            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              playing ? audioHandler.pause() : audioHandler.play();
                            },
                          );
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
                    return LinearProgressIndicator(value: frac, minHeight: 2, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.search_rounded, Icons.search_rounded, 'Search'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Your library'),
    ];
    return Container(
      decoration: BoxDecoration(color: _bg, border: const Border(top: BorderSide(color: _kDivider, width: 0.6))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_tab == i ? items[i].$2 : items[i].$1, color: _tab == i ? Colors.white : _kSub, size: 25),
                        const SizedBox(height: 2),
                        Text(items[i].$3, style: TextStyle(color: _tab == i ? Colors.white : _kSub, fontSize: 11, fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileAvatarBtn() => ValueListenableBuilder<YtAccount>(
        valueListenable: ytAccount,
        builder: (_, acc, __) => GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            showYtAccountSheet(context);
          },
          child: Container(
            width: 34,
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(color: _kCardHigh, shape: BoxShape.circle),
            child: acc.signedIn && acc.photo != null && acc.photo!.isNotEmpty
                ? Image.network(acc.photo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white, size: 20))
                : const Icon(Icons.person_rounded, color: Colors.white, size: 20),
          ),
        ),
      );

  Widget _filterPill(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: active ? Colors.white : _kCardHigh, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(color: active ? Colors.black : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _trackTile(TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    final downloaded = OfflineStore.isDownloaded(t);
    return InkWell(
      onTap: onTap,
      onLongPress: () => showRevivedTrackMenu(context, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 48, height: 48, child: CustomAlbumArtwork(track: t))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? _kAccent : _kText, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (downloaded) ...[
                        const Icon(Icons.download_done_rounded, size: 13, color: _kAccent),
                        const SizedBox(width: 4),
                      ],
                      Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 13))),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 20), onPressed: () => showRevivedTrackMenu(context, t)),
          ],
        ),
      ),
    );
  }

  Widget _libEntry({required String title, required String subtitle, required Widget cover, required VoidCallback onTap, bool pinned = false}) {
    if (_libGrid) {
      return GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox.expand(child: cover))),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12)),
          ],
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 60, height: 60, child: cover)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (pinned) ...[const Icon(Icons.push_pin_rounded, size: 13, color: _kAccent), const SizedBox(width: 4)],
                      Expanded(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 13))),
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

  Widget _emptyCard(String msg, String btn, VoidCallback onTap) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: const TextStyle(color: _kSub, fontSize: 14)),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. SPOTIFY-STYLE ALBUM / SINGLE PAGE, ARTIST PAGE, AND PLAYLIST PAGE
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
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<YtAlbumPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final page = snap.data;
          if (page == null) return const Center(child: Text('Could not load release', style: TextStyle(color: _kSub)));
          final isSingle = (page.kind ?? '').toLowerCase() == 'single' || page.tracks.length <= 2;
          final typeLabel = isSingle ? 'Single' : (page.kind ?? 'Album');

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                backgroundColor: _bg,
                elevation: 0,
                pinned: true,
                iconTheme: const IconThemeData(color: Colors.white),
                title: Text(page.title, style: const TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [const Color(0xFF2B2B2B), _bg],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 28, offset: const Offset(0, 12))]),
                          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: YtNetworkImage(url: page.thumbnail ?? widget.initialThumb, size: 224)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(page.title, style: const TextStyle(color: _kText, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      const SizedBox(height: 6),
                      Text(page.artist, style: const TextStyle(color: _kText, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('$typeLabel${page.year != null ? " • ${page.year}" : ""} • ${page.tracks.length} ${page.tracks.length == 1 ? "song" : "songs"}',
                          style: const TextStyle(color: _kSub, fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download_for_offline_outlined, color: _kSub, size: 26),
                            onPressed: () => OfflineStore.downloadAll(page.tracks),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.shuffle_rounded, color: _kSub, size: 26),
                            onPressed: () {
                              if (page.tracks.isEmpty) return;
                              audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                              audioHandler.playYouTubeList(page.tracks, Random().nextInt(page.tracks.length), lockToScope: true);
                              openPlayer(context);
                            },
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              if (page.tracks.isEmpty) return;
                              HapticFeedback.mediumImpact();
                              audioHandler.playYouTubeList(page.tracks, 0, lockToScope: true);
                              openPlayer(context);
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 32),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                    trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 20), onPressed: () => showRevivedTrackMenu(context, t)),
                    onTap: () {
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
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<YtArtistPage>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final page = snap.data;
          if (page == null) return const Center(child: Text('Could not load artist', style: TextStyle(color: _kSub)));
          final img = page.banner ?? page.thumbnail ?? widget.initialThumb;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                backgroundColor: _bg,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  title: Text(page.name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (img != null) Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _kCardHigh)) else Container(color: _kCardHigh),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black26, _bg.withOpacity(0.85), _bg],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                  child: Row(
                    children: [
                      Expanded(child: Text(page.subscribersText ?? 'Artist', style: const TextStyle(color: _kSub, fontSize: 13.5))),
                      IconButton(
                        icon: const Icon(Icons.shuffle_rounded, color: _kSub, size: 26),
                        onPressed: () {
                          if (page.songs.isEmpty) return;
                          audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                          audioHandler.playYouTubeList(page.songs, Random().nextInt(page.songs.length), lockToScope: true);
                          openPlayer(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (page.songs.isEmpty) return;
                          HapticFeedback.mediumImpact();
                          audioHandler.playYouTubeList(page.songs, 0, lockToScope: true);
                          openPlayer(context);
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (page.songs.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Text('Popular', style: TextStyle(color: _kText, fontSize: 19, fontWeight: FontWeight.w800)),
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
                          SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: _kSub, fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t))),
                        ],
                      ),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                      subtitle: Text(page.plays[t.id] ?? t.artist, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                      trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 20), onPressed: () => showRevivedTrackMenu(context, t)),
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
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sh.title.isEmpty ? 'Discography' : sh.title, style: const TextStyle(color: _kText, fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 188,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: sh.items.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                                      ClipRRect(borderRadius: BorderRadius.circular(6), child: YtNetworkImage(url: it.thumbnail, size: 136)),
                                      const SizedBox(height: 6),
                                      Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontSize: 13.5, fontWeight: FontWeight.w600)),
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
  final String? thumbnail;

  const RevivedPlaylistPage.local({super.key, required Playlist playlist})
      : localPlaylist = playlist, ytPlaylistId = null, title = null, thumbnail = null;

  const RevivedPlaylistPage.youtube({super.key, required String playlistId, this.title, this.thumbnail})
      : localPlaylist = null, ytPlaylistId = playlistId;

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
        final refreshing = snap.connectionState == ConnectionState.waiting;
        if (page == null) {
          return Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(backgroundColor: _bg, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
            body: Center(child: refreshing ? const CircularProgressIndicator(color: Colors.white) : const Text('Could not load playlist', style: TextStyle(color: _kSub))),
          );
        }
        return _scaffold(page.title, '${page.tracks.length} songs', page.thumbnail ?? widget.thumbnail, page.tracks, refreshing);
      },
    );
  }

  Widget _scaffold(String name, String sub, String? thumb, List<TrackItem> tracks, bool refreshing) {
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: _bg,
            elevation: 0,
            pinned: true,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(name, style: const TextStyle(color: _kText, fontSize: 16, fontWeight: FontWeight.w700)),
            actions: [
              if (refreshing)
                const Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF282828), _bg]),
              ),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: thumb != null
                          ? YtNetworkImage(url: thumb, size: 210)
                          : Container(
                              width: 210,
                              height: 210,
                              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)])),
                              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 64),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(name, style: const TextStyle(color: _kText, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(height: 4),
                  Text('Playlist • $sub', style: const TextStyle(color: _kSub, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.download_for_offline_outlined, color: _kSub, size: 26), onPressed: () => OfflineStore.downloadAll(tracks)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.shuffle_rounded, color: _kSub, size: 26),
                        onPressed: () {
                          if (tracks.isEmpty) return;
                          audioHandler.setShuffleMode(AudioServiceShuffleMode.all);
                          audioHandler.playYouTubeList(tracks, Random().nextInt(tracks.length));
                          openPlayer(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (tracks.isEmpty) return;
                          HapticFeedback.mediumImpact();
                          audioHandler.playYouTubeList(tracks, 0);
                          openPlayer(context);
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 32),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 48, height: 48, child: CustomAlbumArtwork(track: t))),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: _kSub, size: 20), onPressed: () => showRevivedTrackMenu(context, t)),
                onTap: () {
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
// 4. DUAL PLAYER SCREEN (Classic & Tidal — Swipe Down, Carousel, Double-Tap Like)
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
        final isTidal = _playerStyle == 'tidal';
        final scaleY = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
        final radius = (_dragY / 10).clamp(0.0, 24.0);

        return FutureBuilder<Color>(
          future: track != null ? artSeedFor(track) : null,
          initialData: track != null ? artSeedNow(track) : null,
          builder: (context, artSnap) {
            final artTint = artSnap.data ?? const Color(0xFF282828);
            final bgColors = isTidal
                ? [Color.lerp(const Color(0xFF0A0A0C), artTint, 0.28)!, const Color(0xFF000000)]
                : [Color.lerp(const Color(0xFF1F1E1C), artTint, 0.14)!, const Color(0xFF0D0D0E)];

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
                      ? const Center(child: Text('Nothing playing', style: TextStyle(color: _kSub)))
                      : SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                            child: isTidal ? _buildTidalPlayer(context, track) : _buildClassicPlayer(context, track),
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

  Widget _buildClassicPlayer(BuildContext context, TrackItem track) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30), onPressed: () => Navigator.of(context).pop()),
            Expanded(
              child: Column(
                children: [
                  const Text('Now playing', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
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
              child: GestureDetector(
                onTap: () => goToArtist(context, track),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 15)),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 26),
              onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track),
            ),
            _likeBtn(track, _kAccent),
          ],
        ),
        const SizedBox(height: 12),
        _seekSlider(track, Colors.white, Colors.white24, 3.5),
        const SizedBox(height: 14),
        _transportRow(isTidal: false),
        const SizedBox(height: 14),
        Row(
          children: [
            IconButton(icon: const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 22), onPressed: () => showTrackInfoDialog(context, track)),
            IconButton(icon: const Icon(Icons.headphones_outlined, color: Colors.white70, size: 22), onPressed: () => showPlaybackSheet(context)),
            IconButton(icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 21), onPressed: () => showLyricsSheet(context, track)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.playlist_add_rounded, color: Colors.white70, size: 24), onPressed: () => track.isYouTube ? showYtAddToPlaylist(context, track) : showAddToPlaylistSheet(context, track)),
            IconButton(icon: const Icon(Icons.queue_music_rounded, color: Colors.white70, size: 24), onPressed: () => _showProQueueSheet(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildTidalPlayer(BuildContext context, TrackItem track) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30), onPressed: () => Navigator.of(context).pop()),
            Expanded(
              child: Column(
                children: [
                  const Text('Playing from', style: TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w500)),
                  Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_horiz_rounded, color: Colors.white), onPressed: () => showRevivedTrackMenu(context, track)),
          ],
        ),
        const Spacer(),
        _swipeableArt(track, 6),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => goToArtist(context, track),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _kSub, fontSize: 14.5)),
                  ],
                ),
              ),
            ),
            _likeBtn(track, _kTidalCyan),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _kTidalCyan.withOpacity(0.14), borderRadius: BorderRadius.circular(4), border: Border.all(color: _kTidalCyan.withOpacity(0.5))),
              child: Text(track.isYouTube ? 'High' : 'Lossless', style: const TextStyle(color: _kTidalCyan, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => showPlaybackSheet(context),
              child: const Text('Audio effects', style: TextStyle(color: _kSub, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _seekSlider(track, _kTidalCyan, Colors.white12, 2.5),
        const SizedBox(height: 14),
        _transportRow(isTidal: true),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _tidalTab('Lyrics', () => showLyricsSheet(context, track)),
            _tidalTab('Up next', () => _showProQueueSheet(context)),
            _tidalTab('Sleep timer', () => _showSleepTimerSheet(context)),
          ],
        ),
      ],
    );
  }

  Widget _tidalTab(String label, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      );

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
                  child: CustomAlbumArtwork(track: track),
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
          return IconButton(
            icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: liked ? activeColor : Colors.white, size: 26),
            onPressed: () {
              HapticFeedback.lightImpact();
              appState.toggleLike(track.id);
            },
          );
        },
      );

  Widget _seekSlider(TrackItem track, Color active, Color inactive, double height) => StreamBuilder<Duration>(
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
                  trackHeight: height,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: active,
                  inactiveTrackColor: inactive,
                  thumbColor: active,
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

  Widget _transportRow({required bool isTidal}) {
    final activeCol = isTidal ? _kTidalCyan : _kAccent;
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
              icon: Icon(Icons.shuffle_rounded, color: shuf ? activeCol : Colors.white70, size: 24),
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
                decoration: BoxDecoration(
                  color: isTidal ? Colors.transparent : Colors.white,
                  shape: BoxShape.circle,
                  border: isTidal ? Border.all(color: Colors.white, width: 2) : null,
                ),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: isTidal ? Colors.white : Colors.black, size: 38),
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
                  color: rep == AudioServiceRepeatMode.none ? Colors.white70 : activeCol, size: 24),
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

  void _showProQueueSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('Queue (${list.length})', style: const TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w800))),
                        if (upNext.isNotEmpty)
                          TextButton(onPressed: () => audioHandler.clearQueue(), child: const Text('Clear up next', style: TextStyle(color: _kAccent))),
                      ],
                    ),
                  ),
                  if (upNext.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 6, bottom: 4),
                            child: Text('Up next (${upNext.length})', style: const TextStyle(color: _kSub, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          for (var q = 0; q < min(4, upNext.length); q++)
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                              leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 38, height: 38, child: CustomAlbumArtwork(track: upNext[q]))),
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
                          leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t))),
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? _kAccent : _kText, fontWeight: FontWeight.w600)),
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
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
// 5. SPOTIFY-STYLE SETTINGS SCREEN (Classic / Tidal Player Picker, No App Styles)
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
        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            title: const Text('Settings', style: TextStyle(color: _kText, fontWeight: FontWeight.w800)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _section('Player style'),
              Row(
                children: [
                  Expanded(child: _pickBtn('Classic', _playerStyle == 'classic', () => appState.setStr('revived_player_style', 'classic'))),
                  const SizedBox(width: 10),
                  Expanded(child: _pickBtn('Tidal', _playerStyle == 'tidal', () => appState.setStr('revived_player_style', 'tidal'))),
                ],
              ),
              const SizedBox(height: 18),
              _section('Tools & library'),
              _card([
                ListTile(
                  leading: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
                  title: const Text('Listening stats', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Top songs, artists, daily streak & 24h clock', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openListeningStats(context),
                ),
                const Divider(color: _kDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_rounded, color: Colors.white70),
                  title: const Text('Import from Spotify', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Bring playlists over from Exportify CSV', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => openSpotifyImport(context),
                ),
                const Divider(color: _kDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.download_done_rounded, color: Colors.white70),
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
                  leading: const Icon(Icons.waves_rounded, color: Colors.white70),
                  title: const Text('Speed, pitch & reverb', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Slowed + reverb, nightcore, sped up & pitch', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => showPlaybackSheet(context),
                ),
                const Divider(color: _kDivider, height: 1),
                ValueListenableBuilder<String?>(
                  valueListenable: audioHandler.sleepLabel,
                  builder: (_, lbl, __) => ListTile(
                    leading: const Icon(Icons.bedtime_rounded, color: Colors.white70),
                    title: const Text('Sleep timer', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(lbl ?? 'Off', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => _showSleepTimerSheet(context),
                  ),
                ),
                const Divider(color: _kDivider, height: 1),
                _toggle('Crossfade', 'Smoothly blend between songs', appState.b('crossfade_on'), (v) => appState.setB('crossfade_on', v)),
                const Divider(color: _kDivider, height: 1),
                _toggle('Smooth play & pause fade', 'Fade volume gently on pause and resume', appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                const Divider(color: _kDivider, height: 1),
                _toggle('Skip silence', 'Trim dead air between tracks', appState.b('skip_silence'), (v) {
                  appState.setB('skip_silence', v);
                  audioHandler.player.setSkipSilenceEnabled(v);
                }),
                const Divider(color: _kDivider, height: 1),
                _toggle('Pause on disconnect', 'Pause when headphones unplug', appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                const Divider(color: _kDivider, height: 1),
                _toggle('Autoplay radio', 'Queue similar songs when playlist ends', appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                const Divider(color: _kDivider, height: 1),
                _toggle('Word-by-word lyrics', 'Highlight each word live in synced lyrics', appState.b('word_lyrics', true), (v) => appState.setB('word_lyrics', v)),
              ]),
              const SizedBox(height: 18),
              _section('Account & system'),
              _card([
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => ListTile(
                    leading: const Icon(Icons.play_circle_fill_rounded, color: _kAccent),
                    title: Text(acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music', style: const TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                const Divider(color: _kDivider, height: 1),
                _toggle('Pure black background', 'Use #000000 instead of charcoal #121212', appState.b('pure_black_dark', false), (v) => appState.setB('pure_black_dark', v)),
                const Divider(color: _kDivider, height: 1),
                _toggle('Data saver', 'Lower bitrate on mobile data', appState.b('yt_data_saver'), (v) {
                  appState.setB('yt_data_saver', v);
                  applyNativeSettings();
                }),
                const Divider(color: _kDivider, height: 1),
                _toggle('Prefetch next song', 'Preload upcoming track for instant skips', appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
                const Divider(color: _kDivider, height: 1),
                _toggle('High refresh rate (120Hz)', 'Keep scrolling and animations smooth', appState.b('high_refresh', true), (v) {
                  appState.setB('high_refresh', v);
                  applyNativeSettings();
                }),
                const Divider(color: _kDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Colors.white70),
                  title: const Text('Clear stream cache', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    await const MethodChannel('com.alexlmp.app/ytmusic').invokeMethod('ytClearCache');
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio cache cleared')));
                  },
                ),
                const Divider(color: _kDivider, height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_rounded, color: Colors.white70),
                  title: const Text('Check for updates', style: TextStyle(color: _kText, fontWeight: FontWeight.w600)),
                  subtitle: Text(const String.fromEnvironment('APP_BUILD_VER', defaultValue: 'v1.0.0'), style: const TextStyle(color: _kSub)),
                  onTap: () => checkRevivedUpdate(context, manual: true),
                ),
                const Divider(color: _kDivider, height: 1),
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

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: const TextStyle(color: _kSub, fontSize: 13, fontWeight: FontWeight.w700)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(12)),
        child: Column(children: children),
      );

  Widget _pickBtn(String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : _kCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? Colors.white : _kDivider),
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.black : _kText, fontSize: 14.5, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        activeColor: Colors.white,
        activeTrackColor: _kAccent,
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
// 6. FULL-SCREEN IN-APP UPDATE CHECKER (Clean Dark Style, Baked-In Version)
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
              const Text('Update available', style: TextStyle(color: _kAccent, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('AlexLMP Revived\nv${widget.version}',
                  style: const TextStyle(color: _kText, fontSize: 34, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(14)),
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
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, backgroundColor: _kCardHigh, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
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