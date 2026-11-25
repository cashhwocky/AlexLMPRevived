import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';

// ── Shared GPM + Spotify Palette ─────────────────────────────────────────────
const Color _kBg = Color(0xFF0A0A0C);
const Color _kCard = Color(0xFF16161B);
const Color _kCardHigh = Color(0xFF202027);
const Color _kLine = Color(0xFF282832);
const Color _kOrange = Color(0xFFFF5722); // Google Play Music orange
const Color _kOrangeLight = Color(0xFFFF8A50);
const Color _kSub = Color(0xFF9C9CAA);

// ═════════════════════════════════════════════════════════════════════════════
// 1. REDESIGNED SETUP SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class RevivedSetupScreen extends StatefulWidget {
  const RevivedSetupScreen({super.key});

  @override
  State<RevivedSetupScreen> createState() => _RevivedSetupScreenState();
}

class _RevivedSetupScreenState extends State<RevivedSetupScreen> {
  bool _granted = false;
  bool _busy = false;

  Future<void> _grantAccess() async {
    setState(() => _busy = true);
    final ok = await ensureMediaPermissions();
    if (!mounted) return;
    setState(() {
      _granted = ok;
      _busy = false;
    });
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    appState.setB('setup_done', true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AlexLmpRoot()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.2,
            colors: [Color(0x44FF5722), _kBg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 32, 26, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _kOrange,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: _kOrange.withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 28),
                const Text(
                  'AlexLMP\nRevived',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Stream YouTube Music and play your local library in one fast, clean player.',
                  style: TextStyle(color: _kSub, fontSize: 16, height: 1.4),
                ),
                const Spacer(),
                _setupTile(
                  icon: _granted ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                  title: _granted ? 'Storage Access Granted' : 'Allow Music Access',
                  subtitle: 'Scan MP3/FLAC/M4A files on your device',
                  accent: _granted ? Colors.greenAccent : _kOrange,
                  onTap: _busy ? null : _grantAccess,
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<YtAccount>(
                  valueListenable: ytAccount,
                  builder: (_, acc, __) => _setupTile(
                    icon: acc.signedIn ? Icons.verified_user_rounded : Icons.play_circle_fill_rounded,
                    title: acc.signedIn ? 'Signed in as ${acc.name ?? "YouTube"}' : 'Sign in to YouTube Music',
                    subtitle: 'Optional — syncs your playlists & likes',
                    accent: acc.signedIn ? Colors.greenAccent : _kOrangeLight,
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    onPressed: _finish,
                    child: const Text(
                      'Start Listening',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kLine),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: _kSub, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _kSub),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. REDESIGNED APP SHELL (Google Play Music + Spotify Hybrid)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedAppShell extends StatefulWidget {
  final List<TrackItem> tracks;
  final Widget Function(AppPalette pal) aiChatBuilder;

  const RevivedAppShell({
    super.key,
    required this.tracks,
    required this.aiChatBuilder,
  });

  @override
  State<RevivedAppShell> createState() => _RevivedAppShellState();
}

class _RevivedAppShellState extends State<RevivedAppShell> {
  int _tab = 0; // 0 = Home, 1 = Search, 2 = Library, 3 = AI DJ
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
    final pal = appState.palette;
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _buildHome(context),
                _buildSearch(context),
                _buildLibrary(context),
                widget.aiChatBuilder(pal),
              ],
            ),
          ),
          _buildMiniPlayer(context),
          _buildBottomNav(),
        ],
      ),
    );
  }

  // ── HOME TAB ──────────────────────────────────────────────────────────────
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
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, top + 12, 16, 28),
        children: [
          // Top App Bar
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  greet,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              _iconBtn(Icons.person_outline_rounded, () => showYtAccountSheet(context)),
              const SizedBox(width: 8),
              _iconBtn(Icons.settings_outlined, () => openRevivedSettings(context)),
            ],
          ),
          const SizedBox(height: 14),
          // Source Pills
          Row(
            children: [
              _pill('YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
              const SizedBox(width: 8),
              _pill('On Device', !yt, () => appState.setStr('home_mode', 'local')),
            ],
          ),
          const SizedBox(height: 16),
          // Spotify-style 2-column quick grid
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
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFF6A1B9A),
                  label: 'AI DJ',
                  onTap: () => setState(() => _tab = 3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Google Play Music "Listen Now" Hero Card
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
                        style: TextStyle(
                          color: _kOrangeLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt ? 'I\'m Feeling Lucky Mix' : 'Your Device Mix',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt
                            ? 'Instant station from YouTube Music'
                            : '${local.length} local tracks ready to play',
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
                              onTap: () => openYtShelfItem(context, it),
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
                                    Text(
                                      it.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      it.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: _kSub, fontSize: 12),
                                    ),
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

  // ── SEARCH TAB ────────────────────────────────────────────────────────────
  Widget _buildSearch(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
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
                                  _searchCtrl.text = g.$1;
                                  _runSearch(g.$1);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: g.$2,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    g.$1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
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

  // ── LIBRARY TAB ───────────────────────────────────────────────────────────
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
                child: Text(
                  'Your Library',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                ),
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

  // ── MINI PLAYER & BOTTOM NAV ──────────────────────────────────────────────
  Widget _buildMiniPlayer(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: audioHandler.currentIndex,
      builder: (context, _, __) {
        final t = audioHandler.currentTrack;
        if (t == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => openPlayer(context),
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
                            onPressed: () => playing ? audioHandler.pause() : audioHandler.play(),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 26),
                        onPressed: () => audioHandler.skipToNext(),
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
      (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'AI DJ'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kLine, width: 0.8)),
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
                        Icon(_tab == i ? items[i].$2 : items[i].$1, color: _tab == i ? _kOrange : _kSub, size: 24),
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
        onTap: onTap,
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
        child: Container(
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
              onPressed: () => setState(() => appState.toggleLike(t.id)),
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
// 3. REDESIGNED FULL-SCREEN PLAYER (GPM + Spotify Unified Player)
// ═════════════════════════════════════════════════════════════════════════════
class RevivedPlayerScreen extends StatelessWidget {
  const RevivedPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: ValueListenableBuilder<int>(
        valueListenable: audioHandler.currentIndex,
        builder: (context, _, __) {
          final track = audioHandler.currentTrack;
          if (track == null) {
            return const Center(child: Text('Nothing playing', style: TextStyle(color: _kSub)));
          }
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF33140A), _kBg, _kBg],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                child: Column(
                  children: [
                    // Top bar
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                          onPressed: () => Navigator.of(context).pop(),
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
                          icon: const Icon(Icons.tune_rounded, color: Colors.white70),
                          onPressed: () => openRevivedSettings(context),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Artwork
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 30, offset: const Offset(0, 14)),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CustomAlbumArtwork(track: track),
                      ),
                    ),
                    const Spacer(),
                    // Title, artist, like
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
                              icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: liked ? _kOrange : Colors.white70, size: 28),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                appState.toggleLike(track.id);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Seek bar
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
                    const SizedBox(height: 12),
                    // Transport Controls
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
                              onPressed: () => audioHandler.setShuffleMode(
                                shuf ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 38),
                              onPressed: () => audioHandler.skipToPrevious(),
                            ),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                playing ? audioHandler.pause() : audioHandler.play();
                              },
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    color: Colors.white, size: 38),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 38),
                              onPressed: () => audioHandler.skipToNext(),
                            ),
                            IconButton(
                              icon: Icon(
                                rep == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                color: rep == AudioServiceRepeatMode.none ? Colors.white60 : _kOrange,
                                size: 24,
                              ),
                              onPressed: () {
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
            ),
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. REDESIGNED SETTINGS SCREEN (Clean, zero style clutter)
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
          backgroundColor: _kBg,
          appBar: AppBar(
            backgroundColor: _kBg,
            elevation: 0,
            title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: ListView(
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
                    subtitle: Text(acc.signedIn ? 'Connected' : 'Sync playlists & likes',
                        style: const TextStyle(color: _kSub)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: _kSub),
                    onTap: () => showYtAccountSheet(context),
                  ),
                ),
                const Divider(color: _kLine, height: 1),
                SwitchListTile(
                  activeColor: _kOrange,
                  title: const Text('Default to YouTube Music', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Show YouTube Music feed on Home', style: TextStyle(color: _kSub)),
                  value: appState.homeMode == 'youtube',
                  onChanged: (v) => appState.setStr('home_mode', v ? 'youtube' : 'local'),
                ),
              ]),
              const SizedBox(height: 20),
              _section('PLAYBACK'),
              _card([
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Speed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text('${appState.speed.toStringAsFixed(2)}x', style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Slider(
                  activeColor: _kOrange,
                  min: 0.5,
                  max: 2.0,
                  value: appState.speed.clamp(0.5, 2.0),
                  onChanged: (v) {
                    appState.setSpeed(v);
                    audioHandler.setSpeed(v);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pitch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text('${appState.pitch.toStringAsFixed(2)}x', style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Slider(
                  activeColor: _kOrange,
                  min: 0.5,
                  max: 2.0,
                  value: appState.pitch.clamp(0.5, 2.0),
                  onChanged: (v) {
                    appState.setPitch(v);
                    audioHandler.setPitch(v);
                  },
                ),
                const Divider(color: _kLine, height: 1),
                SwitchListTile(
                  activeColor: _kOrange,
                  title: const Text('Stop when app is closed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  value: appState.stopOnTaskClear,
                  onChanged: (v) => appState.setStopOnTaskClear(v),
                ),
              ]),
              const SizedBox(height: 20),
              _section('LIBRARY'),
              _card([
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: _kOrange),
                  title: const Text('Scan Device Music', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () => scanDeviceAudio(),
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
              _section('ABOUT'),
              _card([
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded, color: _kSub),
                  title: const Text('Re-run Setup Screen', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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