import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';

// ── GPM + Spotify Palette ────────────────────────────────────────────────────
const Color _kBg = Color(0xFF08080A);
const Color _kPureBlack = Color(0xFF000000);
const Color _kCard = Color(0xFF15151A);
const Color _kCardHigh = Color(0xFF1E1E25);
const Color _kLine = Color(0xFF282833);
const Color _kOrange = Color(0xFFFF5722);
const Color _kOrangeLight = Color(0xFFFF8A50);
const Color _kSub = Color(0xFF9C9CAA);

Color get _bg => appState.b('pure_black') ? _kPureBlack : _kBg;

// ═════════════════════════════════════════════════════════════════════════════
// 1. COMPLETE SETUP SCREEN (Requires YouTube Music Sign-In)
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
    return Scaffold(
      backgroundColor: _bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.75),
            radius: 1.25,
            colors: [_kOrange.withOpacity(0.28), _bg],
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<YtAccount>(
            valueListenable: ytAccount,
            builder: (context, acc, _) {
              final signedIn = acc.signedIn;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _kOrange,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _kOrange.withOpacity(0.45),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WELCOME TO',
                              style: TextStyle(
                                color: _kOrangeLight,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              'AlexLMP Revived',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Let\'s get you set up.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in with your YouTube Music account to unlock streaming, playlists, and likes.',
                      style: TextStyle(color: _kSub, fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    // STEP 1: REQUIRED SIGN-IN
                    _stepCard(
                      step: 'STEP 1 · REQUIRED',
                      icon: signedIn ? Icons.check_circle_rounded : Icons.play_circle_fill_rounded,
                      iconColor: signedIn ? Colors.greenAccent : _kOrange,
                      title: signedIn ? 'Signed in as ${acc.name ?? "YouTube User"}' : 'Sign in to YouTube Music',
                      subtitle: signedIn
                          ? 'Your account is connected and ready'
                          : 'Required to stream & sync your library',
                      busy: _signingIn,
                      done: signedIn,
                      onTap: signedIn ? null : _signIn,
                    ),
                    const SizedBox(height: 14),
                    // STEP 2: OPTIONAL LOCAL STORAGE
                    _stepCard(
                      step: 'STEP 2 · OPTIONAL',
                      icon: _storageGranted ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                      iconColor: _storageGranted ? Colors.greenAccent : _kOrangeLight,
                      title: _storageGranted ? 'Device Music Enabled' : 'Allow Local Music Access',
                      subtitle: _storageGranted
                          ? 'Ready to scan local audio files'
                          : 'Play MP3, FLAC, and M4A files on your phone',
                      busy: _checkingStorage,
                      done: _storageGranted,
                      onTap: _storageGranted ? null : _grantStorage,
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: signedIn ? 1.0 : 0.45,
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: signedIn ? _kOrange : _kCardHigh,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          ),
                          onPressed: signedIn ? _finish : null,
                          child: Text(
                            signedIn ? 'Start Listening' : 'Sign in to Continue',
                            style: TextStyle(
                              color: signedIn ? Colors.white : _kSub,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _stepCard({
    required String step,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool busy,
    required bool done,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: done ? Colors.greenAccent.withOpacity(0.08) : _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: done ? Colors.greenAccent.withOpacity(0.45) : _kLine,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            busy
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: _kOrange),
                  )
                : Icon(icon, color: iconColor, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step,
                    style: TextStyle(
                      color: done ? Colors.greenAccent : _kOrangeLight,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: _kSub, fontSize: 12.5)),
                ],
              ),
            ),
            if (!done && !busy) const Icon(Icons.chevron_right_rounded, color: _kSub),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. MAIN APP SHELL (GPM + Spotify — No AI DJ)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedAppShell extends StatefulWidget {
  final List<TrackItem> tracks;
  final Widget Function(AppPalette pal)? aiChatBuilder; // kept for main.dart compatibility

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
  final TextEditingController _searchCtrl = TextEditingController();
  List<TrackItem> _searchResults = [];
  bool _searching = false;
  String? _searchErr;
  Timer? _debounce;
  Future<List<YtShelf>>? _ytFeedFuture;

  static const _quickGenres = [
    ('Hip-Hop', Color(0xFFD84315)),
    ('Underground', Color(0xFF6A1B9A)),
    ('Chill', Color(0xFF00695C)),
    ('Gym Hype', Color(0xFFC62828)),
    ('Late Night', Color(0xFF283593)),
    ('Throwbacks', Color(0xFFEF6C00)),
  ];

  @override
  void initState() {
    super.initState();
    _ytFeedFuture = YouTubeMusic.homeFeed();
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
        _searchResults = [];
        _searching = false;
        _searchErr = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _searchErr = null;
    });
    try {
      final res = await YouTubeMusic.search(query);
      if (!mounted) return;
      setState(() {
        _searchResults = res;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchErr = 'Search failed. Check your connection.';
      });
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
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _tab == 0
                    ? _buildHome(context)
                    : (_tab == 1 ? _buildSearch(context) : _buildLibrary(context)),
              ),
            ),
          ),
          _buildMiniPlayer(context),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildHome(BuildContext context) {
    final yt = appState.homeMode == 'youtube';
    final local = widget.tracks.where((t) => !t.isYouTube).toList();
    final top = MediaQuery.of(context).padding.top;
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');

    return RefreshIndicator(
      color: _kOrange,
      backgroundColor: _kCardHigh,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, top + 12, 16, 28),
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  greet,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
              ),
              _iconBtn(Icons.person_outline_rounded, () => showYtAccountSheet(context)),
              const SizedBox(width: 8),
              _iconBtn(Icons.settings_outlined, () => openRevivedSettings(context)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _pill('YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
              const SizedBox(width: 8),
              _pill('On Device', !yt, () => appState.setStr('home_mode', 'local')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _quickGridTile(
                  icon: Icons.favorite_rounded,
                  color: _kOrange,
                  label: 'Liked Songs',
                  onTap: () => yt ? openYtLikedMusic(context) : setState(() { _tab = 2; _libTab = 2; }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickGridTile(
                  icon: Icons.shuffle_rounded,
                  color: const Color(0xFF2E7D32),
                  label: 'Shuffle All',
                  onTap: () {
                    final pool = yt ? widget.tracks : local;
                    if (pool.isEmpty) {
                      setState(() => _tab = 1);
                    } else {
                      _shuffleAll(pool);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _quickGridTile(
                  icon: Icons.download_done_rounded,
                  color: const Color(0xFF1565C0),
                  label: 'Downloads',
                  onTap: () => openDownloads(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickGridTile(
                  icon: Icons.speed_rounded,
                  color: const Color(0xFFAD1457),
                  label: 'Speed & Pitch',
                  onTap: () => showSpeedPitchSheet(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3A160B), _kCard],
              ),
              border: Border.all(color: _kOrange.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LISTEN NOW',
                        style: TextStyle(color: _kOrangeLight, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt ? 'I\'m Feeling Lucky Mix' : 'Your Device Mix',
                        style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt ? 'Instant station from YouTube Music' : '${local.length} local tracks ready',
                        style: const TextStyle(color: _kSub, fontSize: 13),
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
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (yt)
            FutureBuilder<List<YtShelf>>(
              future: _ytFeedFuture,
              initialData: YouTubeMusic.cachedHomeFeed(),
              builder: (context, snap) {
                final shelves = snap.data ?? const [];
                if (shelves.isEmpty && snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: _kOrange)),
                  );
                }
                if (shelves.isEmpty) {
                  return _emptyCard('Search YouTube Music to start listening', 'Open Search', () => setState(() => _tab = 1));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      _sectionTitle(shelf.title.isEmpty ? 'Recommended' : shelf.title),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 190,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: shelf.items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final it = shelf.items[i];
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                openYtShelfItem(context, it);
                              },
                              child: SizedBox(
                                width: 136,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: YtNetworkImage(url: it.thumbnail, size: 136),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                    Text(it.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: _kSub, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                );
              },
            )
          else if (local.isEmpty)
            _emptyCard('No local audio files found', 'Add Music', () => showAddMusicSheet(context))
          else ...[
            _sectionTitle('Jump Back In'),
            const SizedBox(height: 8),
            for (var i = 0; i < min(15, local.length); i++)
              _trackTile(local[i], () => _playList(local, i)),
          ],
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Search',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: const TextStyle(color: Colors.black, fontSize: 15.5, fontWeight: FontWeight.w600),
              cursorColor: _kOrange,
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                hintStyle: const TextStyle(color: Colors.black54),
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
          const SizedBox(height: 14),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: _kOrange))
                : _searchErr != null
                    ? Center(child: Text(_searchErr!, style: const TextStyle(color: _kSub)))
                    : _searchResults.isEmpty
                        ? GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.85,
                            ),
                            itemCount: _quickGenres.length,
                            itemBuilder: (_, i) {
                              final g = _quickGenres[i];
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _searchCtrl.text = g.$1;
                                  _runSearch(g.$1);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(color: g.$2, borderRadius: BorderRadius.circular(12)),
                                  alignment: Alignment.topLeft,
                                  child: Text(g.$1,
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                                ),
                              );
                            },
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: _searchResults.length,
                            itemBuilder: (_, i) {
                              final t = _searchResults[i];
                              return _trackTile(t, () {
                                HapticFeedback.selectionClick();
                                audioHandler.playYouTubeTrack(t);
                                openPlayer(context);
                              });
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrary(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final songs = widget.tracks;
    final liked = songs.where((t) => appState.isLiked(t.id)).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Your Library',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
              ),
              _iconBtn(Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
              const SizedBox(width: 8),
              _iconBtn(Icons.folder_open_rounded, () => showAddMusicSheet(context)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _pill('Songs (${songs.length})', _libTab == 0, () => setState(() => _libTab = 0)),
              const SizedBox(width: 8),
              _pill('Playlists', _libTab == 1, () => setState(() => _libTab = 1)),
              const SizedBox(width: 8),
              _pill('Liked (${liked.length})', _libTab == 2, () => setState(() => _libTab = 2)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _libTab == 0
                ? (songs.isEmpty
                    ? _emptyCard('No tracks yet', 'Add Music', () => showAddMusicSheet(context))
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: songs.length,
                        itemBuilder: (_, i) => _trackTile(songs[i], () => _playList(songs, i)),
                      ))
                : _libTab == 1
                    ? ListView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          for (final pl in appState.playlists)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              leading: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.queue_music_rounded, color: _kOrange),
                              ),
                              title: Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              subtitle: Text('${pl.trackIds.length} songs', style: const TextStyle(color: _kSub)),
                              trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: pl.id)),
                              ),
                            ),
                        ],
                      )
                    : (liked.isEmpty
                        ? _emptyCard('No liked songs yet', 'Open YouTube Likes', () => openYtLikedMusic(context))
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: liked.length,
                            itemBuilder: (_, i) => _trackTile(liked[i], () => _playList(liked, i)),
                          )),
          ),
        ],
      ),
    );
  }

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
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _kCardHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kLine),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _kSub, fontSize: 12)),
                          ],
                        ),
                      ),
                      StreamBuilder<PlaybackState>(
                        stream: audioHandler.playbackState,
                        builder: (context, snap) {
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
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 26),
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
                    final frac = dur.inMilliseconds > 0
                        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0;
                    return LinearProgressIndicator(
                      value: frac,
                      minHeight: 2.5,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(_kOrange),
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

  Widget _buildBottomNav() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.search_rounded, Icons.search_rounded, 'Search'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: const Border(top: BorderSide(color: _kLine, width: 0.8)),
      ),
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
                        AnimatedScale(
                          scale: _tab == i ? 1.12 : 1.0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(_tab == i ? items[i].$2 : items[i].$1, color: _tab == i ? _kOrange : _kSub, size: 24),
                        ),
                        const SizedBox(height: 2),
                        Text(items[i].$3,
                            style: TextStyle(
                              color: _tab == i ? _kOrange : _kSub,
                              fontSize: 11,
                              fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500,
                            )),
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

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: _kCardHigh, shape: BoxShape.circle, border: Border.all(color: _kLine)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _pill(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _kOrange : _kCardHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(color: active ? Colors.white : _kSub, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _quickGridTile({required IconData icon, required Color color, required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 54,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: _kCardHigh, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              Container(width: 54, height: 54, color: color, child: Icon(icon, color: Colors.white, size: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      );

  Widget _trackTile(TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 50, height: 50, child: CustomAlbumArtwork(track: t)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? _kOrange : Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kSub, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                appState.isLiked(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: appState.isLiked(t.id) ? _kOrange : _kSub,
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

  Widget _emptyCard(String msg, String btn, VoidCallback onTap) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kLine)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: const TextStyle(color: _kSub, fontSize: 14.5)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kOrange),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. FULL-SCREEN PLAYER (Swipe Down to Close + Carousel Track Swipe + Speed/Pitch)
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
    final track = audioHandler.currentTrack;
    final prevTrack = audioHandler.peekPrevious;
    final nextTrack = audioHandler.peekNext;
    final scale = (1.0 - (_dragY / 2600)).clamp(0.90, 1.0);
    final radius = (_dragY / 10).clamp(0.0, 28.0);

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
              colors: [const Color(0xFF3A160B), _bg, _bg],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: track == null
              ? const Center(child: Text('Nothing playing', style: TextStyle(color: _kSub)))
              : SafeArea(
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      // Drag handle pill
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Top bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop();
                              },
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text('NOW PLAYING',
                                      style: TextStyle(color: _kSub, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                                  Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.speed_rounded, color: Colors.white70),
                              tooltip: 'Speed & Pitch',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                showSpeedPitchSheet(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Carousel Artwork (Swipe Left = Next, Swipe Right = Previous)
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
                                double p = 1.0;
                                if (_carousel.position.haveDimensions) {
                                  p = (_carousel.page ?? 1.0) - index;
                                } else {
                                  p = (1 - index).toDouble();
                                }
                                final s = (1.0 - p.abs() * 0.14).clamp(0.84, 1.0);
                                final o = (1.0 - p.abs() * 0.45).clamp(0.45, 1.0);
                                return Transform.scale(
                                  scale: s,
                                  child: Opacity(opacity: o, child: child),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.55),
                                        blurRadius: 26,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: item != null
                                      ? CustomAlbumArtwork(track: item)
                                      : Container(
                                          color: _kCardHigh,
                                          child: const Icon(Icons.music_note_rounded, color: _kSub, size: 64),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const Spacer(),
                      // Bottom Controls
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
                                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                                      const SizedBox(height: 3),
                                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: _kSub, fontSize: 15.5, fontWeight: FontWeight.w500)),
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
                                        color: liked ? _kOrange : Colors.white70,
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
                                        trackHeight: 4,
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                        activeTrackColor: _kOrange,
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
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(formatDuration(pos), style: const TextStyle(color: _kSub, fontSize: 12)),
                                          Text(formatDuration(dur), style: const TextStyle(color: _kSub, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 10),
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
                                      icon: Icon(Icons.shuffle_rounded, color: shuf ? _kOrange : Colors.white60, size: 24),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        audioHandler.setShuffleMode(
                                          shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 38),
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
                                        width: 68,
                                        height: 68,
                                        decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                                        child: Icon(
                                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 38,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 38),
                                      onPressed: () {
                                        HapticFeedback.mediumImpact();
                                        audioHandler.skipToNext();
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                        color: rep == AudioServiceRepeatMode.none ? Colors.white60 : _kOrange,
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
// 4. SLOWED / SPED UP — SPEED & PITCH BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════
void showSpeedPitchSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _kCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.speed_rounded, color: _kOrange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Speed & Pitch',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    TextButton(
                      onPressed: () => applyBoth(1.0, 1.0),
                      child: const Text('Reset', style: TextStyle(color: _kOrange, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Quick Presets
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetChip('Slowed (0.85x)', (appState.speed - 0.85).abs() < 0.02, () => applyBoth(0.85, 0.85)),
                    _presetChip('Normal (1.0x)', (appState.speed - 1.0).abs() < 0.02 && (appState.pitch - 1.0).abs() < 0.02, () => applyBoth(1.0, 1.0)),
                    _presetChip('Sped Up (1.2x)', (appState.speed - 1.2).abs() < 0.02, () => applyBoth(1.2, 1.2)),
                    _presetChip('Nightcore (1.3x)', (appState.speed - 1.3).abs() < 0.02, () => applyBoth(1.3, 1.3)),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: _kOrange,
                  title: const Text('Link Speed & Pitch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Classic tape / vinyl slowed & sped up sound', style: TextStyle(color: _kSub, fontSize: 12.5)),
                  value: appState.linkSpeedAndPitch,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    appState.setLinkSpeedAndPitch(v);
                    if (v) applyBoth(appState.speed, appState.speed);
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Speed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text('${appState.speed.toStringAsFixed(2)}x', style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  activeColor: _kOrange,
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
                    const Text('Pitch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text('${appState.pitch.toStringAsFixed(2)}x', style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w800)),
                  ],
                ),
                Slider(
                  activeColor: _kOrange,
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

Widget _presetChip(String label, bool active, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _kOrange : _kCardHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? _kOrange : _kLine),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.white : _kSub, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );

// ═════════════════════════════════════════════════════════════════════════════
// 5. EXPANDED SETTINGS SCREEN
// ═════════════════════════════════════════════════════════════════════════════
void openRevivedSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const RevivedSettingsScreen()),
  );
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
            title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _section('ACCOUNT & STREAMING'),
              _card([
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => ListTile(
                    leading: const Icon(Icons.play_circle_fill_rounded, color: _kOrange),
                    title: Text(acc.signedIn ? (acc.name ?? 'YouTube Music') : 'Sign in to YouTube Music',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes', style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                const Divider(color: _kLine, height: 1),
                _toggle('Default to YouTube Music', 'Show YouTube Music feed on Home',
                    appState.homeMode == 'youtube', (v) => appState.setStr('home_mode', v ? 'youtube' : 'local')),
                const Divider(color: _kLine, height: 1),
                _toggle('YouTube Data Saver', 'Use lower bitrate audio on mobile data',
                    appState.b('yt_data_saver'), (v) {
                  appState.setB('yt_data_saver', v);
                  applyNativeSettings();
                }),
                const Divider(color: _kLine, height: 1),
                _toggle('Prefetch Next Song', 'Preload upcoming track for instant skips',
                    appState.b('prefetch_next', true), (v) => appState.setB('prefetch_next', v)),
              ]),
              const SizedBox(height: 20),
              _section('AUDIO EFFECTS — SLOWED & SPED UP'),
              _card([
                ListTile(
                  leading: const Icon(Icons.speed_rounded, color: _kOrange),
                  title: const Text('Speed & Pitch Controls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'Speed ${appState.speed.toStringAsFixed(2)}x · Pitch ${appState.pitch.toStringAsFixed(2)}x',
                    style: const TextStyle(color: _kSub),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                  onTap: () => showSpeedPitchSheet(context),
                ),
                const Divider(color: _kLine, height: 1),
                _toggle('Link Speed & Pitch', 'Pitch shifts automatically when changing speed',
                    appState.linkSpeedAndPitch, (v) => appState.setLinkSpeedAndPitch(v)),
              ]),
              const SizedBox(height: 20),
              _section('PLAYBACK'),
              _card([
                _toggle('Crossfade', 'Smoothly blend the end of one song into the next',
                    appState.b('crossfade_on'), (v) => appState.setB('crossfade_on', v)),
                if (appState.b('crossfade_on'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        const Text('Duration', style: TextStyle(color: _kSub, fontSize: 13)),
                        Expanded(
                          child: Slider(
                            activeColor: _kOrange,
                            min: 2,
                            max: 12,
                            divisions: 10,
                            value: appState.d('crossfade_secs', 6.0).clamp(2.0, 12.0),
                            onChanged: (v) => appState.setD('crossfade_secs', v),
                          ),
                        ),
                        Text('${appState.d('crossfade_secs', 6.0).round()}s',
                            style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                const Divider(color: _kLine, height: 1),
                _toggle('Smooth Play / Pause Fade', 'Fade volume gently when pausing or resuming',
                    appState.b('smooth_fade'), (v) => appState.setB('smooth_fade', v)),
                const Divider(color: _kLine, height: 1),
                _toggle('Skip Silence', 'Trim dead air between tracks',
                    appState.b('skip_silence'), (v) {
                  appState.setB('skip_silence', v);
                  audioHandler.player.setSkipSilenceEnabled(v);
                }),
                const Divider(color: _kLine, height: 1),
                _toggle('Pause on Disconnect', 'Pause when headphones or Bluetooth unplug',
                    appState.b('pause_on_unplug', true), (v) => appState.setB('pause_on_unplug', v)),
                const Divider(color: _kLine, height: 1),
                _toggle('Autoplay Radio', 'Queue similar songs when your playlist ends',
                    appState.b('autoplay_radio'), (v) => appState.setB('autoplay_radio', v)),
                const Divider(color: _kLine, height: 1),
                _toggle('Resume Last Session', 'Remember your song and position on restart',
                    appState.b('resume_last', true), (v) => appState.setB('resume_last', v)),
                const Divider(color: _kLine, height: 1),
                _toggle('Stop When App Closed', 'End playback when swiped from recents',
                    appState.stopOnTaskClear, (v) => appState.setStopOnTaskClear(v)),
              ]),
              const SizedBox(height: 20),
              _section('DISPLAY & PERFORMANCE'),
              _card([
                _toggle('Pure AMOLED Black', 'Use #000000 backgrounds everywhere',
                    appState.b('pure_black'), (v) => appState.setB('pure_black', v)),
                const Divider(color: _kLine, height: 1),
                _toggle('High Refresh Rate (120Hz)', 'Keep animations ultra-smooth',
                    appState.b('high_refresh', true), (v) {
                  appState.setB('high_refresh', v);
                  applyNativeSettings();
                }),
                const Divider(color: _kLine, height: 1),
                _toggle('Keep Screen On', 'Prevent screen sleep while app is open',
                    appState.b('keep_screen_on'), (v) {
                  appState.setB('keep_screen_on', v);
                  applyNativeSettings();
                }),
              ]),
              const SizedBox(height: 20),
              _section('LOCAL LIBRARY'),
              _card([
                _toggle('Auto-Scan on Launch', 'Check for new audio files when opening app',
                    appState.b('auto_scan', true), (v) => appState.setB('auto_scan', v)),
                const Divider(color: _kLine, height: 1),
                _toggle('Hide Short Tracks (<30s)', 'Filter out voice memos and sound clips',
                    appState.b('hide_short_tracks'), (v) => appState.setB('hide_short_tracks', v)),
                const Divider(color: _kLine, height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: _kOrange),
                  title: const Text('Scan Device Music Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    scanDeviceAudio();
                  },
                ),
                const Divider(color: _kLine, height: 1),
                ListTile(
                  leading: const Icon(Icons.audio_file_rounded, color: _kOrange),
                  title: const Text('Import Audio Files', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () => pickLocalFiles(),
                ),
                const Divider(color: _kLine, height: 1),
                ListTile(
                  leading: const Icon(Icons.download_done_rounded, color: _kOrange),
                  title: const Text('Downloaded Songs', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () => openDownloads(context),
                ),
              ]),
              const SizedBox(height: 20),
              _section('SETUP & SYSTEM'),
              _card([
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded, color: _kSub),
                  title: const Text('Re-run Setup Screen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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

  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        activeColor: _kOrange,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: _kSub, fontSize: 12.5)),
        value: value,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          onChanged(v);
        },
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title,
            style: const TextStyle(color: _kOrangeLight, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kLine)),
        child: Column(children: children),
      );
}