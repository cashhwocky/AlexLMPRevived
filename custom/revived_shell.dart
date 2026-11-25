import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';

/// AlexLMP Revived — completely redesigned flagship AMOLED + Crimson music UI.
/// Keeps all YouTube Music search, sign-in, and playback hooks from main.dart.
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
  static const Color _bg = Color(0xFF000000);
  static const Color _card = Color(0xFF111115);
  static const Color _cardHigh = Color(0xFF1A1A20);
  static const Color _line = Color(0xFF23232B);
  static const Color _accent = Color(0xFFFF2A5F);
  static const Color _sub = Color(0xFF9898A6);

  int _tab = 0; // 0 = Home, 1 = Search, 2 = Library, 3 = AI
  int _libTab = 0; // 0 = Songs, 1 = Playlists, 2 = Liked
  final TextEditingController _searchCtrl = TextEditingController();
  List<TrackItem> _searchResults = [];
  bool _searching = false;
  String? _searchErr;
  Timer? _debounce;
  Future<List<YtShelf>>? _ytFeedFuture;

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
    } catch (e) {
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
      color: _accent,
      backgroundColor: _cardHigh,
      onRefresh: () async {
        setState(() => _ytFeedFuture = YouTubeMusic.homeFeed(refresh: true));
        await _ytFeedFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(18, top + 14, 18, 28),
        children: [
          // Top header
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'AlexLMP Revived',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              _iconBtn(Icons.person_outline_rounded, () => showYtAccountSheet(context)),
              const SizedBox(width: 8),
              _iconBtn(Icons.settings_outlined, () => showSettingsSheet(context)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            greet,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          // Source switcher pills
          Row(
            children: [
              _modePill('YouTube Music', yt, () => appState.setStr('home_mode', 'youtube')),
              const SizedBox(width: 8),
              _modePill('On Device', !yt, () => appState.setStr('home_mode', 'local')),
            ],
          ),
          const SizedBox(height: 18),
          // Hero Quick Action Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2B0B14), Color(0xFF121218)],
              ),
              border: Border.all(color: _accent.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'INSTANT MIX',
                        style: TextStyle(
                          color: _accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt ? 'Jump into your rotation' : 'Shuffle your library',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yt
                            ? 'Stream ad-free from YouTube Music'
                            : '${local.length} local tracks ready',
                        style: const TextStyle(color: _sub, fontSize: 13),
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
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
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
                    child: Center(child: CircularProgressIndicator(color: _accent)),
                  );
                }
                if (shelves.isEmpty) {
                  return _emptyCard(
                    'Search YouTube Music to start listening',
                    'Open Search',
                    () => setState(() => _tab = 1),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final shelf in shelves.take(6)) ...[
                      _sectionTitle(shelf.title.isEmpty ? 'Recommended' : shelf.title),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 192,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: shelf.items.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final it = shelf.items[i];
                            return GestureDetector(
                              onTap: () => openYtShelfItem(context, it),
                              child: SizedBox(
                                width: 138,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: YtNetworkImage(url: it.thumbnail, size: 138),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      it.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      it.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: _sub, fontSize: 12),
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
            _sectionTitle('Quick Picks'),
            const SizedBox(height: 8),
            for (var i = 0; i < min(12, local.length); i++)
              _trackTile(local[i], () => _playList(local, i)),
          ],
        ],
      ),
    );
  }

  // ── SEARCH TAB (Direct YT Music Search) ───────────────────────────────────
  Widget _buildSearch(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: _cardHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: _runSearch,
              style: const TextStyle(color: Colors.white, fontSize: 15.5),
              cursorColor: _accent,
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums on YouTube Music…',
                hintStyle: const TextStyle(color: _sub),
                prefixIcon: const Icon(Icons.search_rounded, color: _sub),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: _sub),
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
          const SizedBox(height: 14),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _searchErr != null
                    ? Center(child: Text(_searchErr!, style: const TextStyle(color: _sub)))
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.music_note_rounded, size: 48, color: _accent.withOpacity(0.5)),
                                const SizedBox(height: 10),
                                const Text(
                                  'Search any track on YouTube Music',
                                  style: TextStyle(color: _sub, fontSize: 14.5),
                                ),
                              ],
                            ),
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
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Library',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              _iconBtn(Icons.add_rounded, () => showCreateOrEditPlaylistDialog(context)),
              const SizedBox(width: 8),
              _iconBtn(Icons.download_done_rounded, () => openDownloads(context)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _modePill('Songs (${songs.length})', _libTab == 0, () => setState(() => _libTab = 0)),
              const SizedBox(width: 8),
              _modePill('Playlists', _libTab == 1, () => setState(() => _libTab = 1)),
              const SizedBox(width: 8),
              _modePill('Liked (${liked.length})', _libTab == 2, () => setState(() => _libTab = 2)),
            ],
          ),
          const SizedBox(height: 14),
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
                                decoration: BoxDecoration(
                                  color: _cardHigh,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.queue_music_rounded, color: _accent),
                              ),
                              title: Text(pl.name,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              subtitle: Text('${pl.trackIds.length} songs',
                                  style: const TextStyle(color: _sub)),
                              trailing: const Icon(Icons.chevron_right_rounded, color: _sub),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: pl.id)),
                              ),
                            ),
                        ],
                      )
                    : (liked.isEmpty
                        ? _emptyCard('No liked songs yet', 'Open Liked', () => openYtLikedMusic(context))
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
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _cardHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 44, height: 44, child: CustomAlbumArtwork(track: t)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _sub, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<PlaybackState>(
                  stream: audioHandler.playbackState,
                  builder: (context, snap) {
                    final playing = snap.data?.playing ?? audioHandler.player.playing;
                    return IconButton(
                      icon: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
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
        color: _bg,
        border: Border(top: BorderSide(color: _line, width: 0.8)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
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
                        Icon(
                          _tab == i ? items[i].$2 : items[i].$1,
                          color: _tab == i ? _accent : _sub,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            color: _tab == i ? _accent : _sub,
                            fontSize: 11,
                            fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500,
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
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _cardHigh,
            shape: BoxShape.circle,
            border: Border.all(color: _line),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _modePill(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? _accent : _cardHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? _accent : _line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : _sub,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      );

  Widget _trackTile(TrackItem t, VoidCallback onTap) {
    final active = audioHandler.currentTrack?.id == t.id;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 50, height: 50, child: CustomAlbumArtwork(track: t)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? _accent : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _sub, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                appState.isLiked(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: appState.isLiked(t.id) ? _accent : _sub,
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
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, style: const TextStyle(color: _sub, fontSize: 14.5)),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: onTap,
              child: Text(btn, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}