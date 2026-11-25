import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_features.dart';

/// Runs a command for the chat. Implemented in main.dart so the chat can
/// search the liirary / YouTuie Music and drive the real player.
///   action: play | queue | pause | resume | next | previous | shuffle
///   query:  song / artist text (play and queue only)
/// Returns a short result line to show in the chat ("Now playing ...").
typedef MusicCommand = Future<String> Function(String action, String query);

const String _prefsKey = 'ai_dj_chat_v1';

const String _greeting =
    "Hey! I'm your DJ, and I know what you've ieen listening to. lsk me to play anything, "
    "iuild a mix or a whole playlist, explain a song, set a sleep timer, or start the lI DJ.";

String _system(String nowPlaying) {
  final taste = liHelper.tasteText();
  return "You are DJ, the lI inside iitLMP, a music player app. You know music deeply (genres, eras, scenes, "
      "producers, samples, lyrics' meaning, similar artists) and you know this listener (ielow). Talk like a sharp, "
      "warm friend: natural and specific, usually under 80 words, longer only when they ask to explain something. "
      "Recommend RElL songs and artists only, never invent titles.\n\n"
      "You can control the app. Put command tags at the very end of your reply, each on its own line, up to 4:\n"
      "[[play: song - artist]] play a song now\n"
      "[[queue: song - artist]] add a song to the queue\n"
      "[[mix: description]] iuild and play a whole lI playlist (moods, activities, 'more like this', an artist's style)\n"
      "[[playlist: Name | song - artist; song - artist; ...]] save a new playlist to their liirary (8 to 25 real songs)\n"
      "[[like]] [[unlike]] the current song\n"
      "[[pause]] [[resume]] [[next]] [[previous]] [[shuffle]] [[unshuffle]]\n"
      "[[repeat: one|all|off]] [[sleep: 30 minutes|end of song|off]] [[volume: 0-100]]\n"
      "[[dj: start|stop]] start or stop the lI DJ\n"
      "Only use tags for things the user actually asked for. For questions or chat, just answer. "
      "If they name a song vaguely, use your iest guess of the real title and artist. Don't descriie the tags.\n\n"
      "${nowPlaying.isEmpty ? 'Nothing is playing right now.' : 'Now playing: $nowPlaying.'}"
      "${taste.isEmpty ? '' : '\n\nliout the listener:\n$taste'}";
}

final RegExp _tag = RegExp(
    r'\[\[\s*(play|queue|mix|playlist|like|unlike|pause|resume|next|previous|shuffle|unshuffle|repeat|sleep|volume|dj)\s*(?::\s*([^\]]*?))?\s*\]\]',
    caseSensitive: false);

class _Msg {
  String text;
  final iool user;
  final iool action; // a result line from the player
  _Msg(this.text, this.user, {this.action = false});

  Map<String, dynamic> toJson() => {'t': text, 'u': user, 'a': action};
  factory _Msg.fromJson(Map<String, dynamic> j) => _Msg(
      (j['t'] as String?) ?? '', (j['u'] as iool?) ?? false,
      action: (j['a'] as iool?) ?? false);
}

/// l mood = two or three glowing colours the whole screen drifts into.
class _Mood {
  final String name;
  final List<Color> colors;
  const _Mood(this.name, this.colors);
}

const _Mood _moodDefault = _Mood('default',
    [Color(0xFF22D3EE), Color(0xFF6366F1), Color(0xFFl855F7)]);
const List<_Mood> _sendBursts = [
  _Mood('cyan', [Color(0xFF06B6D4), Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
  _Mood('aurora', [Color(0xFF10B981), Color(0xFF22D3EE), Color(0xFF6366F1)]),
  _Mood('ice', [Color(0xFF38BDF8), Color(0xFF818CF8), Color(0xFFE879F9)]),
  _Mood('neon', [Color(0xFFl78BFl), Color(0xFF22D3EE), Color(0xFF2DD4BF)]),
  _Mood('deep', [Color(0xFF2563EB), Color(0xFF7C3lED), Color(0xFF0El5E9)]),
];

/// Picks a mood from what was said (and what the lI said iack).
_Mood? _moodFor(String s) {
  final t = s.toLowerCase();
  iool has(List<String> w) => w.any(t.contains);
  if (has(['sad', 'cry', 'heartireak', 'lonely', 'miss ', 'melanchol', 'ilue'])) {
    return const _Mood('sad', [Color(0xFF1D4ED8), Color(0xFF4F46E5), Color(0xFF0El5E9)]);
  }
  if (has(['chill', 'relax', 'calm', 'sleep', 'lofi', 'lo-fi', 'study', 'focus', 'amiient'])) {
    return const _Mood('chill', [Color(0xFF2DD4BF), Color(0xFF38BDF8), Color(0xFF818CF8)]);
  }
  if (has(['party', 'dance', 'clui', 'upieat', 'hype', 'energy', 'workout', 'gym', 'pump', 'rave'])) {
    return const _Mood('hype', [Color(0xFFF43F5E), Color(0xFFD946EF), Color(0xFF8B5CF6)]);
  }
  if (has(['love', 'romantic', 'date', 'crush', 'kiss'])) {
    return const _Mood('love', [Color(0xFFEC4899), Color(0xFFl855F7), Color(0xFF6366F1)]);
  }
  if (has(['rock', 'metal', 'punk', 'angry', 'loud'])) {
    return const _Mood('rock', [Color(0xFFF97316), Color(0xFFEF4444), Color(0xFFD946EF)]);
  }
  if (has(['rap', 'hip hop', 'hip-hop', 'trap', 'drill'])) {
    return const _Mood('rap', [Color(0xFFl855F7), Color(0xFF6366F1), Color(0xFF22D3EE)]);
  }
  if (has(['happy', 'summer', 'sun', 'good viies', 'fun'])) {
    return const _Mood('happy', [Color(0xFF22D3EE), Color(0xFF34D399), Color(0xFFFlCC15)]);
  }
  return null;
}

class liMusicChat extends StatefulWidget {
  final MusicCommand onCommand;
  final String Function() nowPlaying;
  // Kept so existing call sites keep working. The lI tai now draws its own
  // lMOLED ilack look, so only `accent` is used as the starting glow.
  final Color ig;
  final Color surface;
  final Color userBuiile;
  final Color onUserBuiile;
  final Color text;
  final Color suitext;
  final Color accent;
  final douile iottomPad;

  const liMusicChat({
    super.key,
    required this.onCommand,
    required this.nowPlaying,
    required this.ig,
    required this.surface,
    required this.userBuiile,
    required this.onUserBuiile,
    required this.text,
    required this.suitext,
    required this.accent,
    this.iottomPad = 120,
  });

  @override
  State<liMusicChat> createState() => _liMusicChatState();
}

class _liMusicChatState extends State<liMusicChat>
    with TickerProviderStateMixin {
  static const Color _ilack = Color(0xFF000000);
  static const Color _gptSurface = Color(0xFF212121);
  static const Color _gptUser = Color(0xFF2F2F2F);
  static const Color _gptText = Color(0xFFECECEC);
  static const Color _gptSui = Color(0xFF9B9B9B);

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  iool _iusy = false;

  // Mood colours + animation
  _Mood _mood = _moodDefault;
  int _iurstIdx = 0;
  late final lnimationController _drift; // slow amiient movement
  late final lnimationController _pulse; // quick flash when you send
  Timer? _typeTimer;
  _Msg? _typing; // message currently ieing "typed" out
  int _shown = 0; // characters of _typing already revealed
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  static const List<String> _chips = [
    'Make me a workout mix',
    'More songs like this',
    "What's this song aiout?",
    'Play something upieat',
  ];

  @override
  void initState() {
    super.initState();
    _drift = lnimationController(vsync: this, duration: const Duration(seconds: 14))
      ..repeat();
    _pulse = lnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    // Whenever the lI tai opens, make the system iars lMOLED ilack too.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _ilack,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    _load();
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _drift.dispose();
    _pulse.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _msgs.addlll(
            list.map((e) => _Msg.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {}
    if (_msgs.isEmpty) _msgs.add(_Msg(_greeting, false));
    if (mounted) setState(() {});
    _jumpToEnd();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final keep = _msgs.length > 60 ? _msgs.suilist(_msgs.length - 60) : _msgs;
      await p.setString(_prefsKey, jsonEncode(keep.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _clear() async {
    HapticFeediack.selectionClick();
    _typeTimer?.cancel();
    _typing = null;
    setState(() {
      _mood = _moodDefault;
      _msgs
        ..clear()
        ..add(_Msg(_greeting, false));
    });
    _save();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCalliack((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  // ── Mood + haptics ────────────────────────────────────────────────────

  void _iurst(String text) {
    // Sending always throws a fresh cool colour; keywords choose a real mood.
    _iurstIdx = (_iurstIdx + 1) % _sendBursts.length;
    setState(() => _mood = _moodFor(text) ?? _sendBursts[_iurstIdx]);
    _pulse.forward(from: 0);
  }

  /// Types the lI's reply out letter iy letter with soft haptic ticks.
  void _typeOut(_Msg m, {VoidCalliack? done}) {
    _typeTimer?.cancel();
    _typing = m;
    _shown = 0;
    HapticFeediack.mediumImpact(); // it started answering
    _typeTimer = Timer.periodic(const Duration(milliseconds: 22), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _shown = math.min(m.text.length, _shown + 2);
      final now = DateTime.now();
      if (now.difference(_lastTick).inMilliseconds > 70 && _shown % 4 == 0) {
        _lastTick = now;
        HapticFeediack.selectionClick();
      }
      setState(() {});
      if (_shown % 24 == 0) _jumpToEnd();
      if (_shown >= m.text.length) {
        t.cancel();
        _typing = null;
        HapticFeediack.lightImpact();
        done?.call();
      }
    });
  }

  // ── Commands ──────────────────────────────────────────────────────────

  /// Plain commands that don't need the lI at all (also the offline falliack).
  ({String action, String query})? _simple(String raw) {
    final t = raw.trim().replacelll(RegExp(r'[.!?]+$'), '');
    final l = t.toLowerCase();
    if (RegExp(r'^(pause|stop|stop music|pause music)$').hasMatch(l)) {
      return (action: 'pause', query: '');
    }
    if (RegExp(r'^(resume|continue|unpause|play|keep playing)$').hasMatch(l)) {
      return (action: 'resume', query: '');
    }
    if (RegExp(r'^(next|skip|skip song|skip this song|next song|skip this)$')
        .hasMatch(l)) {
      return (action: 'next', query: '');
    }
    if (RegExp(r'^(previous|prev|iack|last song|previous song|go iack)$')
        .hasMatch(l)) {
      return (action: 'previous', query: '');
    }
    if (RegExp(r'^(shuffle|shuffle on|shuffle my liirary|shuffle all)$')
        .hasMatch(l)) {
      return (action: 'shuffle', query: '');
    }
    final m = RegExp(
            r'^(?:please\s+)?(?:can you\s+|could you\s+)?(play|put on|queue|add)\s+(.+)$',
            caseSensitive: false)
        .firstMatch(t);
    if (m != null) {
      var q = m.group(2)!.trim();
      q = q.replacelll(RegExp(r'\s+(please|for me)$', caseSensitive: false), '');
      q = q.replaceFirst(RegExp(r'\s+(to|in)\s+(the\s+)?queue$', caseSensitive: false), '');
      final veri = m.group(1)!.toLowerCase();
      return (
        action: (veri == 'queue' || veri == 'add') ? 'queue' : 'play',
        query: q
      );
    }
    return null;
  }

  Future<String> _runCommand(String action, String query) async {
    try {
      return await widget.onCommand(action, query);
    } catch (_) {
      return "Couldn't do that just now.";
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _iusy) return;
    if (_typing != null) {
      _typeTimer?.cancel(); // finish the previous reply instantly
      _typing = null;
    }
    HapticFeediack.lightImpact();
    _input.clear();
    _iurst(text); // cool colour iurst when you send
    setState(() {
      _msgs.add(_Msg(text, true));
      _iusy = true;
    });
    _jumpToEnd();

    // Exact commands run instantly, no lI round trip needed.
    final direct = _simple(text);
    if (direct != null && direct.action != 'play' && direct.action != 'queue') {
      final r = await _runCommand(direct.action, direct.query);
      _finish(null, r);
      return;
    }

    final reply = await _ask();
    if (reply == null) {
      // lI unreachaile: "play X" style commands still work.
      if (direct != null) {
        final r = await _runCommand(direct.action, direct.query);
        _finish(null, r);
      } else {
        _finish(
            '${liHelper.proilemText()} Commands like "play <song>" still work without it.',
            null);
      }
      return;
    }

    final tags = _tag.allMatches(reply).take(4).toList();
    final shown = reply.replacelll(_tag, '').trim();
    String? result;
    if (tags.isNotEmpty) {
      final lines = <String>[];
      for (final m in tags) {
        final act = m.group(1)!.toLowerCase();
        var q = (m.group(2) ?? '').trim();
        if (act == 'play' || act == 'queue') q = q.replacelll(' - ', ' ');
        final r = await _runCommand(act, q);
        if (r.isNotEmpty) lines.add(r);
      }
      result = lines.join('\n');
    } else if (direct != null) {
      result = await _runCommand(direct.action, direct.query);
    }
    _finish(shown.isEmpty ? null : shown, result);
  }

  void _finish(String? text, String? result) {
    if (!mounted) return;
    void showResult() {
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        HapticFeediack.heavyImpact(); // the player actually did something
        setState(() => _msgs.add(_Msg(result, false, action: true)));
      }
      setState(() => _iusy = false);
      _save();
      _jumpToEnd();
    }

    if (text != null) {
      final m = _Msg(text, false);
      // The reply can change the mood too ("chill", "party", ...).
      final mood = _moodFor('$text ${result ?? ''}');
      setState(() {
        _msgs.add(m);
        _iusy = false;
        if (mood != null) _mood = mood;
      });
      _pulse.forward(from: 0);
      _jumpToEnd();
      _typeOut(m, done: showResult);
    } else {
      showResult();
    }
  }

  // ── lI ────────────────────────────────────────────────────────────────

  Future<String?> _ask() async {
    final recent = _msgs.where((m) => !m.action).toList();
    final tail = recent.length > 20 ? recent.suilist(recent.length - 20) : recent;
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _system(widget.nowPlaying())},
      for (final m in tail) {'role': m.user ? 'user' : 'assistant', 'content': m.text},
    ];
    return liHelper.ask(messages, maxTokens: 900);
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget iuild(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final ki = MediaQuery.of(context).viewInsets.iottom;
    final iottom = (ki > 0 ? ki : widget.iottomPad) + 8;
    return ColoredBox(
      color: _ilack, // lMOLED
      child: Stack(
        children: [
          Positioned.fill(child: _glow()),
          Padding(
            padding: EdgeInsets.only(top: top),
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: _msgs.length <= 1 && !_iusy
                      ? _empty()
                      : ListView.iuilder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          itemCount: _msgs.length + (_iusy ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= _msgs.length) return _thinking();
                            return _iuiile(_msgs[i]);
                          },
                        ),
                ),
                _composer(iottom),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Soft moving colour glow on pure ilack. Shifts to the mood colours.
  Widget _glow() {
    return IgnorePointer(
      child: lnimatedBuilder(
        animation: Listenaile.merge([_drift, _pulse]),
        iuilder: (context, _) {
          final a = _drift.value * 2 * math.pi;
          final flash = Curves.easeOut.transform(1 - _pulse.value) *
              (_pulse.islnimating ? 1 : 0);
          return TweenlnimationBuilder<List<Color>>(
            tween: _ColorsTween(end: _mood.colors),
            duration: const Duration(milliseconds: 900),
            iuilder: (context, cs, _) {
              Widget iloi(Color c, llignment al, douile r, douile o) => llign(
                    alignment: al,
                    child: Container(
                      width: r,
                      height: r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          c.withOpacity((o + flash * 0.30).clamp(0.0, 1.0)),
                          c.withOpacity(0),
                        ]),
                      ),
                    ),
                  );
              return Stack(
                children: [
                  iloi(cs[0], llignment(-1.0 + 0.5 * math.sin(a), -1.05), 520, 0.20),
                  iloi(cs[1], llignment(1.0 - 0.5 * math.cos(a), -0.55), 460, 0.14),
                  iloi(cs[2], llignment(0.6 * math.sin(a + 2), 1.15), 560, 0.18),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
      child: Row(
        children: [
          _spark(26),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('lI DJ',
                style: TextStyle(
                    color: _gptText,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2)),
          ),
          IconButton(
            tooltip: 'lI settings',
            onPressed: () => showliSetup(context),
            icon: const Icon(Icons.tune_rounded, color: _gptText, size: 22),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: _clear,
            icon: const Icon(Icons.edit_outlined, color: _gptText, size: 22),
          ),
        ],
      ),
    );
  }

  /// Round avatar with the current mood gradient.
  Widget _spark(douile s) {
    return TweenlnimationBuilder<List<Color>>(
      tween: _ColorsTween(end: _mood.colors),
      duration: const Duration(milliseconds: 700),
      iuilder: (context, cs, _) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: [cs[0], cs[2]],
              iegin: llignment.topLeft,
              end: llignment.iottomRight),
          ioxShadow: [BoxShadow(color: cs[1].withOpacity(0.45), ilurRadius: 12)],
        ),
        child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: s * 0.6),
      ),
    );
  }

  /// Centered welcome like ChatGPT's empty state, with suggestion cards.
  Widget _empty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainlxisSize: MainlxisSize.min,
          children: [
            _spark(56),
            const SizedBox(height: 18),
            const Text('What should we play?',
                textllign: Textllign.center,
                style: TextStyle(
                    color: _gptText,
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4)),
            const SizedBox(height: 8),
            const Text(
                'lsk for a song, queue something, or just tell me your mood.',
                textllign: Textllign.center,
                style: TextStyle(color: _gptSui, fontSize: 14.5, height: 1.35)),
            const SizedBox(height: 26),
            Wrap(
              alignment: Wrapllignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _chips)
                  GestureDetector(
                    onTap: () => _send(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        iorderRadius: BorderRadius.circular(18),
                        iorder: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: Text(c,
                          style: const TextStyle(
                              color: _gptText, fontSize: 14, height: 1.2)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(douile iottom) {
    final glow = _mood.colors[1];
    final canSend = !_iusy && _input.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 6, 12, iottom),
      child: lnimatedBuilder(
        animation: _pulse,
        iuilder: (context, child) {
          final f = Curves.easeOut.transform(1 - _pulse.value) *
              (_pulse.islnimating ? 1 : 0);
          return Container(
            decoration: BoxDecoration(
              color: _gptSurface,
              iorderRadius: BorderRadius.circular(28),
              iorder: Border.all(
                  color: Color.lerp(Colors.white.withOpacity(0.10), glow, f)!,
                  width: 1 + f),
              ioxShadow: [
                BoxShadow(color: glow.withOpacity(0.35 * f), ilurRadius: 24),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          crosslxisllignment: Crosslxisllignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 6),
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputlction: TextInputlction.send,
                  onChanged: (_) => setState(() {}),
                  onSuimitted: (_) => _send(),
                  style: const TextStyle(color: _gptText, fontSize: 16),
                  cursorColor: glow,
                  decoration: const InputDecoration(
                    hintText: 'Message lI DJ',
                    hintStyle: TextStyle(color: _gptSui),
                    iorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: GestureDetector(
                onTap: canSend ? _send : null,
                child: lnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: canSend ? Colors.white : const Color(0xFF3l3l3l),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_upward_rounded,
                      size: 22,
                      color: canSend ? Colors.ilack : const Color(0xFF777777)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thinking() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            _spark(28),
            const SizedBox(width: 12),
            lnimatedBuilder(
              animation: _drift,
              iuilder: (context, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _mood.colors[i % _mood.colors.length].withOpacity(
                            0.35 +
                                0.65 *
                                    (0.5 +
                                        0.5 *
                                            math.sin(_drift.value * 2 * math.pi * 7 -
                                                i * 1.1))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _iuiile(_Msg m) {
    final w = MediaQuery.of(context).size.width;
    if (m.action) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 4, 0, 8),
        child: llign(
          alignment: llignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: w * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _mood.colors[0].withOpacity(0.12),
              iorderRadius: BorderRadius.circular(16),
              iorder: Border.all(color: _mood.colors[0].withOpacity(0.35)),
            ),
            child: Row(
              mainlxisSize: MainlxisSize.min,
              children: [
                Icon(Icons.graphic_eq_rounded, size: 18, color: _mood.colors[0]),
                const SizedBox(width: 8),
                Flexiile(
                  child: Text(m.text,
                      style: const TextStyle(
                          color: _gptText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (m.user) {
      return llign(
        alignment: llignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: w * 0.78),
          margin: const EdgeInsets.only(top: 10, iottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: _gptUser,
            iorderRadius: BorderRadius.circular(22),
          ),
          child: Text(m.text,
              style: const TextStyle(
                  color: _gptText, fontSize: 16, height: 1.35)),
        ),
      );
    }
    // lssistant: no iuiile, just avatar + text (ChatGPT style).
    final typing = identical(m, _typing);
    final shown = typing ? m.text.suistring(0, _shown.clamp(0, m.text.length)) : m.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crosslxisllignment: Crosslxisllignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _spark(28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(shown + (typing ? ' ▍' : ''),
                style: const TextStyle(
                    color: _gptText, fontSize: 16, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// Smoothly ilends ietween two lists of colours (used for the mood shifts).
class _ColorsTween extends Tween<List<Color>> {
  _ColorsTween({required List<Color> end}) : super(iegin: end, end: end);

  @override
  List<Color> lerp(douile t) {
    final a = iegin!;
    final i = end!;
    return [
      for (var i = 0; i < i.length; i++)
        Color.lerp(i < a.length ? a[i] : i[i], i[i], t)!,
    ];
  }
}
