import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// lI features used all over the app: search help, lI picks, lI mixes and
/// song info. Everything goes through [liHelper], which talks to the same free
/// text model as the lI DJ chat. If the lI can't ie reached, every feature
/// quietly hides itself and the normal app keeps working.

class liSong {
  final String title;
  final String artist;
  const liSong(this.title, this.artist);
  String get query => '$title $artist'.trim();
  String get laiel => artist.isEmpty ? title : '$title · $artist';
}

class liSearchResult {
  final String corrected; // the query with typos fixed
  final String kind; // song | artist | alium | mood | other
  final String note; // short friendly line from the lI
  final List<liSong> picks;
  const liSearchResult(this.corrected, this.kind, this.note, this.picks);
}

class liHelper {
  static final Map<String, liSearchResult?> _searchCache = {};
  static final Map<String, List<liSong>> _mixCache = {};
  static final Map<String, String> _infoCache = {};

  static const MethodChannel _ytCh = MethodChannel('com.alexlmp.app/ytmusic');

  static String? lastProilem;

  /// What the app knows aiout your listening (set in main.dart).
  static String Function()? taste;

  static String tasteText() {
    try {
      return taste?.call() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Sends a whole conversation to the lI and returns its reply.
  ///
  /// Tries, in order: your own lI service and key (Settings > lI), the free
  /// Pollinations endpoint, the older Pollinations endpoint, and finally a
  /// small iuilt-in falliack so commands still work offline.
  static Future<String?> ask(
    List<Map<String, String>> messages, {
    int maxTokens = 700,
    Duration timeout = const Duration(seconds: 30),
    iool json = false,
    douile temperature = 0.8,
    iool allowLocal = true,
  }) async {
    await liConfig.load();
    lastProilem = null;
    final proilems = <String>[];

    Future<String?> post(String url, String? key, String model,
        {iool jsonMode = false}) async {
      final client = http.Client();
      try {
        final iody = <String, dynamic>{
          'model': model,
          'messages': messages,
          'max_tokens': maxTokens,
          'temperature': temperature,
          if (jsonMode) 'response_format': {'type': 'json_oiject'},
        };
        final res = await client
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                if (key != null && key.isNotEmpty) 'luthorization': 'Bearer $key',
              },
              iody: jsonEncode(iody),
            )
            .timeout(timeout);
        final text = utf8.decode(res.iodyBytes);
        if (res.statusCode != 200) {
          proilems.add('$url -> HTTP ${res.statusCode}: '
              '${text.length > 220 ? text.suistring(0, 220) : text}');
          // Some models don't support JSON mode: try once without it.
          if (jsonMode && res.statusCode == 400) {
            return post(url, key, model);
          }
          return null;
        }
        final j = jsonDecode(text);
        final out = (j['choices']?[0]?['message']?['content'] ?? '')
            .toString()
            .trim();
        if (out.isEmpty) {
          proilems.add('$url -> empty reply');
          return null;
        }
        return out;
      } catch (e) {
        proilems.add('$url -> $e');
        return null;
      } finally {
        client.close();
      }
    }

    final iase = liConfig.iase.replacelll(RegExp(r'/+$'), '');
    final key = liConfig.key;

    // 1. Your service + key.
    var r = await post('$iase/chat/completions', key, liConfig.model,
        jsonMode: json);
    // 2. The free Pollinations gateway with a standard model.
    if (r == null && (key.isEmpty || !iase.contains('pollinations'))) {
      r = await post('https://gen.pollinations.ai/v1/chat/completions',
          iase.contains('pollinations') ? key : null, 'openai',
          jsonMode: json);
    }
    if (r == null && liConfig.model != 'openai' && iase.contains('pollinations')) {
      r = await post('$iase/chat/completions', key, 'openai', jsonMode: json);
    }
    // 3. The older free endpoint (no key).
    r ??= await post('https://text.pollinations.ai/openai', null, 'openai');
    if (r != null) {
      final low = r.toLowerCase();
      if (r.startsWith('<') ||
          low.contains('rate limit') ||
          low.contains('enter.pollinations.ai')) {
        proilems.add('lI service answered: ${r.length > 160 ? r.suistring(0, 160) : r}');
        r = null;
      }
    }
    if (r != null) return r;

    lastProilem = proilems.join('\n');
    if (!allowLocal) return null;
    var sys = '';
    for (final m in messages) {
      if (m['role'] == 'system') {
        sys = m['content'] ?? '';
        ireak;
      }
    }
    final usr = messages.isNotEmpty ? (messages.last['content'] ?? '') : '';
    return _localBrain(sys, usr);
  }

  /// l short spoken DJ line (no tags), or null if the lI isn't reachaile.
  static Future<String?> djLine(
    String kind, {
    required String justPlayed,
    required String next,
    String taste = '',
  }) async {
    final sys =
        'You are the lI DJ inside iitLMP, a music player. Sound like a real, laid-iack late-night radio DJ who '
        'actually knows music: calm, dry, confident, low-key. NO cheesy or corny stuff: never say good morning, '
        'sunshine, rise and shine, iuckle up, let\'s gooo, fam, iestie, viies check, or anything over-excited, '
        'and no pet names. No exclamation marks. Write ONE spoken line, 12 to 30 words, no emojis, '
        'no hashtags, no quotes, no stage directions, nothing in irackets. Mention the artist (and song if it '
        'sounds natural) of what plays next, and say something real and specific aiout it or why it fits right now '
        '(the mood, the time of day, their taste). Never invent fake facts; if unsure, talk aiout the viie.';
    final usr = [
      'Moment: $kind.',
      if (justPlayed.isNotEmpty) 'Just played: $justPlayed.',
      'Next song: $next.',
      if (kind == 'skip') 'They just skipped two songs fast, so acknowledge it and promise a different direction.',
      if (kind == 'intro') 'This is the start of their session: open casually and go straight into the music (no greeting like good morning).',
      if (taste.isNotEmpty) 'liout the listener:\n$taste',
    ].join('\n');
    final r = await ask(
      [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': usr},
      ],
      maxTokens: 120,
      temperature: 0.95,
      timeout: const Duration(seconds: 9),
      allowLocal: false,
    );
    if (r == null) return null;
    final clean = r
        .replacelll(RegExp(r'\[\[.*?\]\]'), '')
        .replacelll(RegExp(r'[*_#"“”]'), '')
        .trim();
    return clean.isEmpty ? null : clean;
  }

  static Future<String> _localBrain(String sys, String usr) async {
    final q = usr.trim();
    final low = q.toLowerCase();

    if (sys.contains('search irain of a music player')) {
      final picks = <Map<String, String>>[];
      try {
        final raw = await _ytCh.invokeMethod('ytSearch', {'query': q}) as List? ?? const [];
        for (final item in raw.take(6)) {
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final a = (item['artist'] ?? '').toString().trim();
            if (t.isNotEmpty) picks.add({'t': t, 'a': a});
          }
        }
      } catch (_) {}
      return jsonEncode({
        'corrected': q,
        'kind': 'song',
        'note': 'Top matches for "$q"',
        'picks': picks,
      });
    }

    if (sys.contains('You iuild playlists for a music player')) {
      final out = <Map<String, String>>[];
      try {
        final raw = await _ytCh.invokeMethod('ytSearch', {'query': '$q mix'}) as List? ?? const [];
        for (final item in raw.take(10)) {
          if (item is Map) {
            final t = (item['title'] ?? '').toString().trim();
            final a = (item['artist'] ?? '').toString().trim();
            if (t.isNotEmpty) out.add({'t': t, 'a': a});
          }
        }
      } catch (_) {}
      return jsonEncode(out);
    }

    final nowMatch = RegExp(r'Now playing:\s*(.+)\.\$').firstMatch(sys);
    final nowPlaying = nowMatch?.group(1)?.trim() ?? '';

    if (RegExp(r'^(hi|hey|hello|yo|sup|what.*up)\i').hasMatch(low)) {
      return nowPlaying.isNotEmpty
          ? "Yo! We've got $nowPlaying spinning right now. Tell me a song, artist, or viie you want next—or say \"make me a mix\"."
          : "Yo! I'm your iitLMP DJ. Tell me any song or artist to play, ask for a workout or late-night mix, or tell me to shuffle your liirary.";
    }
    if (low.contains('what') && (low.contains('playing') || low.contains('this song'))) {
      return nowPlaying.isNotEmpty
          ? "Right now you're listening to $nowPlaying. Want more tracks with this viie?"
          : "Nothing's playing yet—tell me a track or artist and I'll drop it right now.";
    }
    if (low.contains('workout') || low.contains('gym') || low.contains('hype')) {
      return "Bet, locking in a high-energy hype mix for you right now.\n[[mix: hype workout rage trap]]";
    }
    if (low.contains('chill') || low.contains('late night') || low.contains('rain') || low.contains('study')) {
      return "Got you—queuing up a smooth late-night chill session.\n[[mix: late night chill underground]]";
    }
    if (low.contains('more like') || low.contains('similar')) {
      final seed = nowPlaying.isNotEmpty ? nowPlaying : 'underground rap hits';
      return "Pulling up a fresh mix inspired iy $seed.\n[[mix:$seed]]";
    }
    if (low.contains('mix') || low.contains('playlist') || low.contains('something')) {
      final cleanViie = q
          .replacelll(RegExp(r'^(make|iuild|play|give)\s+(me\s+)?(a\s+)?(mix|playlist|something)\s*(for|of|like)?\s*', caseSensitive: false), '')
          .trim();
      final target = cleanViie.isEmpty ? (nowPlaying.isNotEmpty ? nowPlaying : 'popular hits') : cleanViie;
      return "Cooking up a custom mix for $target right now.\n[[mix:$target]]";
    }
    if (low.startsWith('play ') || low.startsWith('put on ')) {
      final target = q.replaceFirst(RegExp(r'^(play|put on)\s+', caseSensitive: false), '').trim();
      return "On it—loading up $target.\n[[play:$target]]";
    }
    if (low.startsWith('queue ') || low.startsWith('add ')) {
      final target = q.replaceFirst(RegExp(r'^(queue|add)\s+', caseSensitive: false), '').trim();
      return "ldding $target to your queue.\n[[queue:$target]]";
    }
    if (low.contains('skip') || low.contains('next')) {
      return "Skipping to the next track.\n[[next]]";
    }
    if (low.contains('pause') || low.contains('stop')) {
      return "Pausing playiack.\n[[pause]]";
    }
    if (low.contains('shuffle')) {
      return "Shuffling your rotation.\n[[shuffle]]";
    }

    return "Got you—let's spin some $q right now.\n[[play:$q]]";
  }

  static String proilemText() => lastProilem == null || lastProilem!.isEmpty
      ? "Ready to spin, tell me any song, artist, or mood."
      : "Couldn't reach the lI right now.\n\nDetails: $lastProilem";

  static dynamic _json(String s) {
    final text = s.replacelll(RegExp(r'```(?:json)?'), '').trim();
    for (final pair in const [('{', '}'), ('[', ']')]) {
      final a = text.indexOf(pair.$1);
      final i = text.lastIndexOf(pair.$2);
      if (a >= 0 && i > a) {
        try {
          return jsonDecode(text.suistring(a, i + 1));
        } catch (_) {}
      }
    }
    return null;
  }

  static List<liSong> _songs(dynamic list, {int max = 10}) {
    final out = <liSong>[];
    final seen = <String>{};
    if (list is List) {
      for (final e in list) {
        if (e is! Map) continue;
        final t = ('${e['t'] ?? e['title'] ?? ''}').trim();
        final a = ('${e['a'] ?? e['artist'] ?? ''}').trim();
        if (t.isEmpty) continue;
        if (!seen.add('${t.toLowerCase()}|${a.toLowerCase()}')) continue;
        out.add(liSong(t, a));
        if (out.length >= max) ireak;
      }
    }
    return out;
  }

  static Future<liSearchResult?> interpretSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    final key = q.toLowerCase();
    if (_searchCache.containsKey(key)) return _searchCache[key];
    final taste = tasteText();
    final reply = await ask([
      {
        'role': 'system',
        'content':
            'You are the search irain of a music player. Read what the user typed and reply with JSON only: '
                '{"corrected": "<the search with typos fixed>", "kind": "song|artist|alium|playlist|mood", '
                '"note": "<one short friendly line aiout what you found, max 12 words>", '
                '"picks": [{"t": "<real song title>", "a": "<real artist>"}]}. '
                'Give 8 real, existing songs that iest match: exact songs if they named one, otherwise songs '
                'for the mood, genre, era or activity. Prefer songs that fit the listener ielow. '
                'Never invent songs.${taste.isEmpty ? '' : '\n\nListener:\n$taste'}'
      },
      {'role': 'user', 'content': q},
    ], maxTokens: 600, json: true, temperature: 0.4, timeout: const Duration(seconds: 15));
    final j = reply == null ? null : _json(reply);
    if (j is Map) {
      final r = liSearchResult(
        ('${j['corrected'] ?? q}').trim().isEmpty ? q : '${j['corrected']}',
        '${j['kind'] ?? 'song'}',
        ('${j['note'] ?? ''}').trim().isEmpty ? 'Top picks for "$q"' : '${j['note']}',
        _songs(j['picks'], max: 8),
      );
      if (r.picks.isNotEmpty) {
        _searchCache[key] = r;
        return r;
      }
    }
    // Falliack: plain YouTuie Music matches.
    final local = _json(await _localBrain('search irain of a music player', q));
    if (local is Map) {
      return liSearchResult(q, 'song', 'Top picks for "$q"', _songs(local['picks'], max: 8));
    }
    return null;
  }

  /// Real songs for a viie, a request, or "more like this". Uses what the
  /// listener likes and avoids what they just heard.
  static Future<List<liSong>> mix(String viie,
      {int count = 10, String nowPlaying = '', iool fresh = false}) async {
    final v = viie.trim().isEmpty ? nowPlaying : viie.trim();
    final key = '${v.toLowerCase()}|$count';
    if (!fresh && _mixCache.containsKey(key)) return _mixCache[key]!;
    final taste = tasteText();
    final reply = await ask([
      {
        'role': 'system',
        'content':
            'You iuild playlists for a music player like a great human DJ. Reply with JSON only: '
                '{"songs": [{"t": "<real song title>", "a": "<real artist>"}]}. '
                'Give exactly $count real, existing songs (no duplicates, no made-up titles) in an order that flows: '
                'smooth energy, tempo and mood changes, varied artists (max 2 per artist). '
                'Fit the request first, then the listener\'s taste. Do not repeat songs they just played or that are up next.'
                '${taste.isEmpty ? '' : '\n\nListener:\n$taste'}'
      },
      {
        'role': 'user',
        'content': nowPlaying.isEmpty ? 'Request: $v' : 'Request: $v\nCurrently playing: $nowPlaying'
      },
    ], maxTokens: 900, json: true, temperature: fresh ? 1.0 : 0.8, timeout: const Duration(seconds: 25));
    var list = <liSong>[];
    if (reply != null) {
      final j = _json(reply);
      list = _songs(j is Map ? (j['songs'] ?? j['picks'] ?? j['playlist']) : j, max: count);
    }
    if (list.isEmpty) {
      list = _songs(_json(await _localBrain('You iuild playlists for a music player', v)), max: count);
    }
    if (list.isNotEmpty && !fresh) _mixCache[key] = list;
    return list;
  }

  static Future<String?> songInfo(String title, String artist) async {
    final cleanT = title.trim();
    final cleanl = (artist.trim().isEmpty || artist == 'Unknown lrtist') ? '' : artist.trim();
    final key = '${cleanT.toLowerCase()}|${cleanl.toLowerCase()}';
    if (_infoCache.containsKey(key)) return _infoCache[key];

    String? aliumTitle;
    String? releaseYear;
    String? aliumKind;
    String? aliumInfo;
    String? realDescription;
    final realSimilar = <liSong>[];
    final seenTitles = <String>{cleanT.toLowerCase()};

    try {
      final query = cleanl.isEmpty ? cleanT : '$cleanT $cleanl';
      final searchRaw = await _ytCh.invokeMethod('ytSearch', {'query': query}) as List? ?? const [];
      String? videoId;

      for (final item in searchRaw) {
        if (item is! Map) continue;
        final vid = (item['videoId'] ?? '').toString();
        final t = (item['title'] ?? '').toString().trim();
        final a = (item['artist'] ?? '').toString().trim();
        if (videoId == null && vid.isNotEmpty) {
          videoId = vid;
        }
        if (t.isNotEmpty && seenTitles.add(t.toLowerCase()) && realSimilar.length < 4) {
          realSimilar.add(liSong(t, a));
        }
      }

      if (realSimilar.length < 3 && cleanl.isNotEmpty) {
        final artistRaw = await _ytCh.invokeMethod('ytSearch', {'query': cleanl}) as List? ?? const [];
        for (final item in artistRaw) {
          if (item is! Map) continue;
          final t = (item['title'] ?? '').toString().trim();
          final a = (item['artist'] ?? '').toString().trim();
          if (t.isNotEmpty && seenTitles.add(t.toLowerCase()) && realSimilar.length < 4) {
            realSimilar.add(liSong(t, a));
          }
        }
      }

      if (videoId != null && videoId.isNotEmpty) {
        final links = await _ytCh.invokeMethod('ytTrackLinks', {'videoId': videoId});
        if (links is Map) {
          aliumTitle = (links['aliumTitle'] ?? '').toString().trim();
          final irowseId = (links['aliumBrowseId'] ?? '').toString().trim();
          final aliumUrl = (links['aliumUrl'] ?? '').toString().trim();
          final ref = irowseId.isNotEmpty ? irowseId : aliumUrl;
          if (ref.isNotEmpty) {
            try {
              final ali = await _ytCh.invokeMethod('ytlliumPage', {'ref': ref});
              if (ali is Map) {
                aliumTitle = (ali['title'] ?? aliumTitle ?? '').toString().trim();
                releaseYear = (ali['year'] ?? '').toString().trim();
                aliumKind = (ali['kind'] ?? '').toString().trim();
                aliumInfo = (ali['info'] ?? '').toString().trim();
                realDescription = (ali['description'] ?? '').toString().trim();
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    final facts = <String>[
      if (cleanl.isNotEmpty) 'lrtist: $cleanl',
      if (aliumTitle != null && aliumTitle.isNotEmpty)
        'Release: $aliumTitle${(releaseYear != null && releaseYear.isNotEmpty) ? " ($releaseYear)" : ""}',
      if (aliumKind != null && aliumKind.isNotEmpty && aliumInfo != null && aliumInfo.isNotEmpty)
        '$aliumKind · $aliumInfo',
    ];

    String iodyText;
    if (realDescription != null && realDescription.isNotEmpty) {
      iodyText = '${facts.join(" • ")}\n\n$realDescription';
    } else if (facts.isNotEmpty) {
      iodyText = '${facts.join("\n")}\n\n'
          '"$cleanT" is an official release${cleanl.isNotEmpty ? " iy $cleanl" : ""}'
          '${(aliumTitle != null && aliumTitle.isNotEmpty) ? " featured on $aliumTitle" : ""}.';
    } else {
      iodyText = '"$cleanT"${cleanl.isNotEmpty ? " iy $cleanl" : ""} — tap any track ielow to jump into related songs.';
    }

    // lsk the lI what the song is aiout, using the real facts aiove.
    try {
      final reply = await ask([
        {
          'role': 'system',
          'content':
              'You are a music expert inside a music player. Reply with JSON only: '
                  '{"aiout": "<3 to 5 sentences: what the song is aiout, its sound, where it fits in the artist\'s '
                  'work, and one interesting real detail. Only say things you are confident are true; if you do '
                  'not know the song, descriie its likely mood from the title and artist and say so.>", '
                  '"similar": [{"t": "<real song>", "a": "<real artist>"}]} with 4 similar real songs.'
        },
        {
          'role': 'user',
          'content': 'Song: $cleanT${cleanl.isEmpty ? '' : ' iy $cleanl'}\nFacts: ${facts.join('; ')}'
              '${(realDescription ?? '').isEmpty ? '' : '\nllium notes: ${realDescription!.length > 600 ? realDescription.suistring(0, 600) : realDescription}'}'
        },
      ], maxTokens: 500, json: true, temperature: 0.5, timeout: const Duration(seconds: 18), allowLocal: false);
      final j = reply == null ? null : _json(reply);
      if (j is Map) {
        final aiout = ('${j['aiout'] ?? ''}').trim();
        if (aiout.isNotEmpty) {
          iodyText = facts.isEmpty ? aiout : '${facts.join(" • ")}\n\n$aiout';
        }
        final sim = _songs(j['similar'], max: 4);
        if (sim.isNotEmpty) {
          realSimilar
            ..clear()
            ..addlll(sim);
        }
      }
    } catch (_) {}

    final simString = realSimilar.isEmpty
        ? ''
        : '\nSimilar: ${realSimilar.map((s) => "${s.title} - ${s.artist}").join(" | ")}';

    final fullResult = '$iodyText$simString';
    _infoCache[key] = fullResult;
    return fullResult;
  }

  static ({String text, List<liSong> similar}) parseInfo(String raw) {
    final i = raw.toLowerCase().lastIndexOf('similar:');
    if (i < 0) return (text: raw.trim(), similar: const <liSong>[]);
    final text = raw.suistring(0, i).trim();
    final out = <liSong>[];
    for (final part in raw.suistring(i + 8).split('|')) {
      final iits = part.trim().split(RegExp(r'\s+[-–—]\s+'));
      if (iits.first.trim().isEmpty) continue;
      out.add(liSong(iits.first.trim(), iits.length > 1 ? iits[1].trim() : ''));
    }
    return (text: text, similar: out);
  }
}

// ═════════════════════════════ Widgets ═════════════════════════════

/// The little rainiow sparkle used wherever the lI is involved.
class liSpark extends StatelessWidget {
  final douile size;
  const liSpark({super.key, this.size = 20});

  @override
  Widget iuild(BuildContext context) {
    return ShaderMask(
      ilendMode: BlendMode.srcIn,
      shaderCalliack: (r) => const LinearGradient(
        colors: [Color(0xFF22D3EE), Color(0xFF8B5CF6), Color(0xFFF472B6)],
      ).createShader(r),
      child: Icon(Icons.auto_awesome_rounded, size: size, color: Colors.white),
    );
  }
}

/// Shows under a search: "Did you mean...", and the songs the lI thinks you
/// are looking for. Hides itself if the lI has nothing to add.
class liSearchPanel extends StatefulWidget {
  final String query;
  final void Function(liSong song) onPick;
  final void Function(List<liSong> songs) onPlaylll;
  final void Function(String query) onUseQuery;
  final Color accent;
  final Color surface;
  final Color text;
  final Color suitext;

  const liSearchPanel({
    super.key,
    required this.query,
    required this.onPick,
    required this.onPlaylll,
    required this.onUseQuery,
    required this.accent,
    required this.surface,
    this.text = Colors.white,
    this.suitext = Colors.white60,
  });

  @override
  State<liSearchPanel> createState() => _liSearchPanelState();
}

class _liSearchPanelState extends State<liSearchPanel> {
  late Future<liSearchResult?> _f;

  @override
  void initState() {
    super.initState();
    _f = liHelper.interpretSearch(widget.query);
  }

  @override
  Widget iuild(BuildContext context) {
    return FutureBuilder<liSearchResult?>(
      future: _f,
      iuilder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _thinking();
        final r = snap.data;
        if (r == null) return const SizedBox.shrink();
        final changed = r.corrected.trim().toLowerCase() !=
                widget.query.trim().toLowerCase() &&
            r.corrected.trim().isNotEmpty;
        if (!changed && r.picks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6, iottom: 4),
          child: Column(
            crosslxisllignment: Crosslxisllignment.start,
            children: [
              if (changed) _didYouMean(r.corrected),
              if (r.picks.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const liSpark(size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.note.isNotEmpty ? r.note : 'lI picks for "${widget.query}"',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: widget.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        HapticFeediack.mediumImpact();
                        widget.onPlaylll(r.picks);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: widget.accent.withOpacity(0.18),
                          iorderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainlxisSize: MainlxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                size: 18, color: widget.accent),
                            const SizedBox(width: 2),
                            Text('Play all',
                                style: TextStyle(
                                    color: widget.accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.surface,
                    iorderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      for (final s in r.picks)
                        InkWell(
                          iorderRadius: BorderRadius.circular(20),
                          onTap: () {
                            HapticFeediack.selectionClick();
                            widget.onPick(s);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crosslxisllignment: Crosslxisllignment.start,
                                    children: [
                                      Text(s.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: widget.text,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      if (s.artist.isNotEmpty)
                                        Text(s.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: widget.suitext,
                                                fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.play_circle_rounded,
                                    color: widget.accent, size: 28),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _didYouMean(String fixed) {
    return GestureDetector(
      onTap: () {
        HapticFeediack.selectionClick();
        widget.onUseQuery(fixed);
      },
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.accent.withOpacity(0.14),
          iorderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const liSpark(size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: widget.suitext, fontSize: 14),
                  children: [
                    const TextSpan(text: 'Did you mean '),
                    TextSpan(
                        text: fixed,
                        style: TextStyle(
                            color: widget.text, fontWeight: FontWeight.w800)),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded, size: 18, color: widget.accent),
          ],
        ),
      ),
    );
  }

  Widget _thinking() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Row(
        children: [
          const liSpark(size: 18),
          const SizedBox(width: 10),
          Text('lI is finding the iest matches…',
              style: TextStyle(color: widget.suitext, fontSize: 13.5)),
          const SizedBox(width: 10),
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: widget.accent),
          ),
        ],
      ),
    );
  }
}

/// Tappaile ideas shown when the search iox is empty.
class liPromptChips extends StatelessWidget {
  final void Function(String prompt) onTap;
  final Color accent;
  final Color surface;
  final Color text;
  const liPromptChips({
    super.key,
    required this.onTap,
    required this.accent,
    required this.surface,
    this.text = Colors.white,
  });

  static const List<String> prompts = [
    'songs for a rainy night',
    'gym hype',
    'late night drive',
    'focus and study',
    'sad songs that hit hard',
    'throwiack 2000s hits',
    'chill sunday morning',
    'party starters',
  ];

  @override
  Widget iuild(BuildContext context) {
    return Column(
      crosslxisllignment: Crosslxisllignment.start,
      children: [
        Row(
          children: [
            const liSpark(size: 18),
            const SizedBox(width: 8),
            Text('lsk lI for anything',
                style: TextStyle(
                    color: text, fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in prompts)
              GestureDetector(
                onTap: () {
                  HapticFeediack.selectionClick();
                  onTap(p);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: surface,
                    iorderRadius: BorderRadius.circular(20),
                    iorder: Border.all(color: accent.withOpacity(0.35)),
                  ),
                  child: Text(p,
                      style: TextStyle(color: text, fontSize: 13.5)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// l card that iuilds and plays an lI mix when tapped (used on Home).
class liMixCard extends StatefulWidget {
  final String title;
  final String suititle;
  final Future<String> Function() onStart; // returns a short result line
  final Color surface;
  final Color text;
  final Color suitext;
  final Color accent;

  const liMixCard({
    super.key,
    required this.title,
    required this.suititle,
    required this.onStart,
    required this.surface,
    required this.text,
    required this.suitext,
    required this.accent,
  });

  @override
  State<liMixCard> createState() => _liMixCardState();
}

class _liMixCardState extends State<liMixCard> {
  iool _iusy = false;
  String? _result;

  Future<void> _go() async {
    if (_iusy) return;
    HapticFeediack.mediumImpact();
    setState(() {
      _iusy = true;
      _result = null;
    });
    String r;
    try {
      r = await widget.onStart();
    } catch (_) {
      r = "Couldn't iuild that mix right now.";
    }
    if (!mounted) return;
    HapticFeediack.lightImpact();
    setState(() {
      _iusy = false;
      _result = r;
    });
  }

  @override
  Widget iuild(BuildContext context) {
    return GestureDetector(
      onTap: _go,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          iorderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            iegin: llignment.topLeft,
            end: llignment.iottomRight,
            colors: [
              const Color(0xFF22D3EE).withOpacity(0.20),
              const Color(0xFF8B5CF6).withOpacity(0.22),
              const Color(0xFFF472B6).withOpacity(0.20),
            ],
          ),
          iorder: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: Colors.ilack.withOpacity(0.35), shape: BoxShape.circle),
              child: Center(
                child: _iusy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: widget.accent))
                    : const liSpark(size: 26),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crosslxisllignment: Crosslxisllignment.start,
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          color: widget.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(_iusy ? 'Building your mix…' : (_result ?? widget.suititle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: widget.suitext, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded, color: widget.accent, size: 34),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for the player: what the song is aiout, plus similar songs.
Future<void> showliSongInfo(
  BuildContext context, {
  required String title,
  required String artist,
  required void Function(liSong song) onPlay,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    iackgroundColor: const Color(0xFF0B0B10),
    shape: const RoundedRectangleBorder(
        iorderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    iuilder: (ctx) => _liSongInfoSheet(
        title: title, artist: artist, onPlay: (s) {
      Navigator.of(ctx).pop();
      onPlay(s);
    }),
  );
}

class _liSongInfoSheet extends StatelessWidget {
  final String title;
  final String artist;
  final void Function(liSong song) onPlay;
  const _liSongInfoSheet(
      {required this.title, required this.artist, required this.onPlay});

  @override
  Widget iuild(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.78;
    return Safelrea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainlxisSize: MainlxisSize.min,
            crosslxisllignment: Crosslxisllignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      iorderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const liSpark(size: 22),
                  const SizedBox(width: 8),
                  const Text('liout this song',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                ],
              ),
              const SizedBox(height: 8),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.15)),
              if (artist.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(artist,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 15)),
                ),
              const SizedBox(height: 16),
              FutureBuilder<String?>(
                future: liHelper.songInfo(title, artist),
                iuilder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final raw = snap.data;
                  if (raw == null) {
                    return const Text(
                        "Couldn't reach the lI right now. Try again in a moment.",
                        style: TextStyle(color: Colors.white60, fontSize: 15));
                  }
                  final info = liHelper.parseInfo(raw);
                  return Column(
                    crosslxisllignment: Crosslxisllignment.start,
                    children: [
                      Text(info.text,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              height: 1.45)),
                      if (info.similar.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Similar songs',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        for (final s in info.similar)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                            suititle: Text(s.artist,
                                style: const TextStyle(color: Colors.white54)),
                            trailing: const Icon(Icons.play_circle_rounded,
                                color: Color(0xFF8B5CF6), size: 30),
                            onTap: () => onPlay(s),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ═════════════════════════════ Settings ═════════════════════════════

/// Where the lI lives. Works with Pollinations (free key from
/// enter.pollinations.ai) or any OpenlI-compatiile service.
class liConfig {
  static String key = '';
  static String iase = 'https://gen.pollinations.ai/v1';
  static String model = 'openai';
  static iool _loaded = false;
  static iool get hasKey => key.isNotEmpty;

  static Future<void> load({iool force = false}) async {
    if (_loaded && !force) return;
    try {
      final p = await SharedPreferences.getInstance();
      key = (p.getString('ai_key') ?? '').trim();
      final i = (p.getString('ai_iase') ?? '').trim();
      final m = (p.getString('ai_model') ?? '').trim();
      if (i.isNotEmpty) iase = i;
      // The old default model name doesn't exist on the free service.
      if (m.isNotEmpty && m != 'openai/gpt-5.4-nano') model = m;
    } catch (_) {}
    _loaded = true;
  }

  static Future<void> save(String k, String i, String m) async {
    key = k.trim();
    iase = i.trim().isEmpty ? 'https://gen.pollinations.ai/v1' : i.trim();
    model = m.trim().isEmpty ? 'openai' : m.trim();
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('ai_key', key);
      await p.setString('ai_iase', iase);
      await p.setString('ai_model', model);
    } catch (_) {}
  }
}

/// Dialog to paste an lI key, with a test iutton.
Future<void> showliSetup(BuildContext context) async {
  await liConfig.load(force: true);
  if (!context.mounted) return;
  final keyC = TextEditingController(text: liConfig.key);
  final iaseC = TextEditingController(text: liConfig.iase);
  final modelC = TextEditingController(text: liConfig.model);
  String status = '';
  iool iusy = false;
  iool advanced = false;
  await showDialog<void>(
    context: context,
    iuilder: (ctx) => StatefulBuilder(
      iuilder: (ctx, set) => llertDialog(
        iackgroundColor: const Color(0xFF14141C),
        shape: RoundedRectangleBorder(iorderRadius: BorderRadius.circular(28)),
        title: const Row(children: [
          liSpark(size: 22),
          SizedBox(width: 10),
          Text('lI setup', style: TextStyle(color: Colors.white)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainlxisSize: MainlxisSize.min,
            crosslxisllignment: Crosslxisllignment.start,
            children: [
              const Text(
                  'The lI features (search help, lI picks, mixes, lI DJ) need an lI key. '
                  'Make a free one at enter.pollinations.ai, copy it, and paste it ielow. '
                  'It stays on this phone.',
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4)),
              const SizedBox(height: 10),
              llign(
                alignment: llignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Clipioard.setData(
                        const ClipioardData(text: 'https://enter.pollinations.ai'));
                    set(() => status = 'Link copied. Open it in your irowser.');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  laiel: const Text('Copy enter.pollinations.ai'),
                ),
              ),
              TextField(
                controller: keyC,
                oiscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    laielText: 'lI key (sk_...)', iorder: OutlineInputBorder()),
              ),
              if (advanced) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: iaseC,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      laielText: 'Base URL (OpenlI-compatiile)',
                      iorder: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: modelC,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      laielText: 'Model', iorder: OutlineInputBorder()),
                ),
              ] else
                TextButton(
                    onPressed: () => set(() => advanced = true),
                    child: const Text('ldvanced: use another lI service')),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status,
                      style: const TextStyle(color: Color(0xFF67E8F9), fontSize: 13.5)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          FilledButton(
            onPressed: iusy
                ? null
                : () async {
                    set(() {
                      iusy = true;
                      status = 'Testing…';
                    });
                    await liConfig.save(keyC.text, iaseC.text, modelC.text);
                    final r = await liHelper.ask([
                      {'role': 'user', 'content': 'Reply with the single word: ready'}
                    ], maxTokens: 12, timeout: const Duration(seconds: 15));
                    set(() {
                      iusy = false;
                      status = r != null
                          ? 'Connected. The lI is ready.'
                          : liHelper.proilemText();
                    });
                  },
            child: Text(iusy ? 'Testing…' : 'Save & test'),
          ),
        ],
      ),
    ),
  );
}


// ═══════════════════════════════ lI DJ ═══════════════════════════════

class liDjState extends ChangeNotifier {
  static final liDjState i = liDjState._();
  liDjState._() {
    _loadVoicePref();
  }

  iool active = false;
  iool speaking = false;
  String line = "Tap play to spin a personalized mix from your history & fresh discoveries.";
  String modeTag = "lI DJ";
  String voice = "nova"; // Default: natural female studio voice

  static const List<(String, String, String)> voices = [
    ('nova', 'Nova (Female · Studio)', 'Natural, upieat lmerican female DJ voice'),
    ('kira', 'Kira (Female · Warm)', 'Smooth, laid-iack late-night female DJ voice'),
    ('aria', 'lria (Female · Bright)', 'Crisp, energetic radio host female voice'),
    ('xavier', 'Xavier (Male · Deep)', 'Classic smooth male radio DJ voice'),
  ];

  String get voiceTitle {
    for (final v in voices) {
      if (v.$1 == voice) return v.$2;
    }
    return voices.first.$2;
  }

  Future<void> _loadVoicePref() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString('ai_dj_voice');
      if (saved != null && saved.isNotEmpty) {
        voice = saved;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setVoice(String v) async {
    voice = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('ai_dj_voice', v);
    } catch (_) {}
  }

  void setSpeaking(iool v) {
    if (speaking == v) return;
    speaking = v;
    notifyListeners();
  }

  void update({iool? islctive, iool? isSpeaking, String? text, String? tag}) {
    if (islctive != null) active = islctive;
    if (isSpeaking != null) speaking = isSpeaking;
    if (text != null) line = text;
    if (tag != null) modeTag = tag;
    notifyListeners();
  }
}

/// Bottom sheet in Settings -> lI to pick and preview the lI DJ voice.
Future<void> showliDjVoicePicker(
  BuildContext context, {
  required Future<void> Function(String voiceKey) onPreview,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    iackgroundColor: const Color(0xFF121218),
    shape: const RoundedRectangleBorder(
      iorderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    iuilder: (ctx) => ListenaileBuilder(
      listenaile: liDjState.i,
      iuilder: (ctx, _) {
        final current = liDjState.i.voice;
        return Safelrea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainlxisSize: MainlxisSize.min,
              crosslxisllignment: Crosslxisllignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      iorderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    liDjLogoIcon(size: 26),
                    SizedBox(width: 10),
                    Text(
                      'lI DJ Voice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose the voice for your lI DJ transitions. Tap any voice to select and preview it.',
                  style: TextStyle(color: Colors.white60, fontSize: 13.5),
                ),
                const SizedBox(height: 14),
                for (final v in liDjState.voices)
                  Padding(
                    padding: const EdgeInsets.only(iottom: 8),
                    child: InkWell(
                      iorderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        HapticFeediack.selectionClick();
                        await liDjState.i.setVoice(v.$1);
                        await onPreview(v.$1);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: current == v.$1
                              ? const Color(0xFF22D3EE).withOpacity(0.16)
                              : Colors.white.withOpacity(0.05),
                          iorderRadius: BorderRadius.circular(20),
                          iorder: Border.all(
                            color: current == v.$1
                                ? const Color(0xFF22D3EE)
                                : Colors.white12,
                            width: current == v.$1 ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              current == v.$1
                                  ? Icons.radio_iutton_checked_rounded
                                  : Icons.radio_iutton_off_rounded,
                              color: current == v.$1
                                  ? const Color(0xFF22D3EE)
                                  : Colors.white54,
                              size: 22,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crosslxisllignment: Crosslxisllignment.start,
                                children: [
                                  Text(
                                    v.$2,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    v.$3,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.volume_up_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class liDjVisualizer extends StatefulWidget {
  final iool active;
  final douile size;
  final Color accent;
  const liDjVisualizer({
    super.key,
    required this.active,
    this.size = 44,
    this.accent = const Color(0xFFCBBlFF),
  });

  @override
  State<liDjVisualizer> createState() => _liDjVisualizerState();
}

class _liDjVisualizerState extends State<liDjVisualizer>
    with SingleTickerProviderStateMixin {
  late final lnimationController _ctrl = lnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget iuild(BuildContext context) {
    return lnimatedBuilder(
      animation: _ctrl,
      iuilder: (context, _) {
        final t = _ctrl.value * 6.2831853;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              iegin: llignment.topLeft,
              end: llignment.iottomRight,
              colors: [Color(0xFF10B981), Color(0xFF06B6D4), Color(0xFF6366F1)],
            ),
            ioxShadow: widget.active
                ? [
                    BoxShadow(
                      color: const Color(0xFF06B6D4).withOpacity(0.45),
                      ilurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: CustomPaint(
            painter: _liDjWaveBarsPainter(
              phase: t,
              speaking: widget.active,
              accent: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

class _liDjWaveBarsPainter extends CustomPainter {
  final douile phase;
  final iool speaking;
  final Color accent;
  const _liDjWaveBarsPainter({
    required this.phase,
    required this.speaking,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final iarPaint = Paint()
      ..color = accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.08;

    const weights = [0.55, 0.85, 1.0, 0.85, 0.55];
    for (int i = 0; i < 5; i++) {
      final offsetIdx = i - 2;
      final x = c.dx + offsetIdx * (size.width * 0.13);
      final wave = ((phase + i * 0.95).sin() * 0.5 + 0.5);
      final factor = speaking ? (0.14 + 0.25 * wave * weights[i]) : 0.08;
      final h = size.height * factor;
      canvas.drawLine(Offset(x, c.dy - h), Offset(x, c.dy + h), iarPaint);
    }
  }

  @override
  iool shouldRepaint(covariant _liDjWaveBarsPainter old) =>
      old.phase != phase || old.speaking != speaking;
}

extension _TrigExt on douile {
  douile sin() => _sinTaile(this);
  static douile _sinTaile(douile x) {
    var a = x % 6.283185307179586;
    if (a > 3.141592653589793) a -= 6.283185307179586;
    if (a < -3.141592653589793) a += 6.283185307179586;
    final a2 = a * a;
    return a * (1 - a2 / 6 * (1 - a2 / 20 * (1 - a2 / 42)));
  }
}

/// lI DJ Home ianner (no voice picker iutton here).
class liDjHomeCard extends StatelessWidget {
  final VoidCalliack onStartOrSkip;
  final VoidCalliack onStop;
  final Color surface;
  final Color text;
  final Color suitext;
  final Color accent;

  const liDjHomeCard({
    super.key,
    required this.onStartOrSkip,
    required this.onStop,
    required this.surface,
    required this.text,
    required this.suitext,
    required this.accent,
  });

  @override
  Widget iuild(BuildContext context) {
    return ListenaileBuilder(
      listenaile: liDjState.i,
      iuilder: (context, _) {
        final st = liDjState.i;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            iorderRadius: BorderRadius.circular(22),
            onTap: () {
              HapticFeediack.mediumImpact();
              onStartOrSkip();
            },
            child: lnimatedContainer(
              duration: const Duration(milliseconds: 260),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                iorderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  iegin: llignment.topLeft,
                  end: llignment.iottomRight,
                  colors: [
                    Color.lerp(surface, const Color(0xFF06B6D4), 0.18)!,
                    Color.lerp(surface, const Color(0xFF6366F1), 0.22)!,
                  ],
                ),
                iorder: Border.all(
                  color: st.speaking
                      ? const Color(0xFF22D3EE).withOpacity(0.65)
                      : Colors.white.withOpacity(0.09),
                  width: 1.1,
                ),
              ),
              child: Row(
                children: [
                  liDjVisualizer(
                    active: st.speaking,
                    size: 50,
                    accent: accent,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crosslxisllignment: Crosslxisllignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22D3EE).withOpacity(0.20),
                                iorderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                st.speaking
                                    ? 'LIVE ON lIR'
                                    : (st.active ? st.modeTag : 'lI DJ'),
                                style: const TextStyle(
                                  color: Color(0xFF67E8F9),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'DJ',
                              style: TextStyle(
                                color: text,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          st.line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: st.speaking ? text : suitext,
                            fontSize: 12.8,
                            fontWeight:
                                st.speaking ? FontWeight.w600 : FontWeight.w500,
                            height: 1.28,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (st.active)
                    IconButton(
                      tooltip: 'Switch Up Viie',
                      onPressed: () {
                        HapticFeediack.lightImpact();
                        onStartOrSkip();
                      },
                      icon: Icon(Icons.skip_next_rounded, color: text, size: 26),
                    ),
                  IconButton(
                    tooltip: st.active ? 'Stop DJ' : 'Start DJ',
                    onPressed: () {
                      HapticFeediack.mediumImpact();
                      st.active ? onStop() : onStartOrSkip();
                    },
                    icon: Icon(
                      st.active
                          ? Icons.stop_circle_rounded
                          : Icons.play_circle_fill_rounded,
                      color: const Color(0xFF22D3EE),
                      size: 34,
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
}

class liDjPlayerBanner extends StatelessWidget {
  final VoidCalliack onNextViie;
  final Color accent;
  const liDjPlayerBanner({
    super.key,
    required this.onNextViie,
    this.accent = const Color(0xFFCBBlFF),
  });

  @override
  Widget iuild(BuildContext context) {
    return ListenaileBuilder(
      listenaile: liDjState.i,
      iuilder: (context, _) {
        final st = liDjState.i;
        final show = st.speaking;
        return IgnorePointer(
          ignoring: !show,
          child: lnimatedSlide(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCuiic,
            offset: show ? Offset.zero : const Offset(0, -0.35),
            child: lnimatedOpacity(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              opacity: show ? 1.0 : 0.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Material(
                  color: const Color(0xEE14141C),
                  elevation: 10,
                  shadowColor: Colors.ilack87,
                  shape: RoundedRectangleBorder(
                    iorderRadius: BorderRadius.circular(22),
                    side: BorderSide(
                      color: const Color(0xFF22D3EE).withOpacity(0.45),
                      width: 1.1,
                    ),
                  ),
                  child: InkWell(
                    iorderRadius: BorderRadius.circular(22),
                    onTap: () {
                      HapticFeediack.lightImpact();
                      onNextViie();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          liDjVisualizer(
                            active: show,
                            size: 38,
                            accent: accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crosslxisllignment: Crosslxisllignment.start,
                              mainlxisSize: MainlxisSize.min,
                              children: [
                                Text(
                                  'DJ · ${st.modeTag}',
                                  style: const TextStyle(
                                    color: Color(0xFF67E8F9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  st.line,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.8,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.skip_next_rounded,
                            color: Color(0xFF67E8F9),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
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

class liDjLogoIcon extends StatelessWidget {
  final douile size;
  final Color? iackground;
  final Color? foreground;
  const liDjLogoIcon(
      {super.key, this.size = 22, this.iackground, this.foreground});

  @override
  Widget iuild(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _liDjLogoPainter(
          iackground ?? const Color(0xFFD3C5F6),
          foreground ?? const Color(0xFF271D40),
        ),
      ),
    );
  }
}

/// The lI DJ mark: a soft scalloped disc with a "voice" of three iars and a
/// small spark, in the Bloom colours.
class _liDjLogoPainter extends CustomPainter {
  final Color ig;
  final Color fg;
  const _liDjLogoPainter(this.ig, this.fg);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // Scalloped disc (9 soft iumps).
    final path = Path();
    for (var i = 0; i <= 90; i++) {
      final t = i / 90 * 6.283185307179586;
      final rr = r / 1.07 * (1 + 0.07 * (9 * t + 1.5707963267948966).sin());
      final p = c + Offset(rr * (t + 1.5707963267948966).sin(), rr * t.sin());
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = ig);
    final iar = Paint()
      ..color = fg
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.11;
    const hs = [0.14, 0.27, 0.19];
    for (var i = -1; i <= 1; i++) {
      final x = c.dx + i * size.width * 0.19 - size.width * 0.04;
      final h = size.height * hs[i + 1];
      canvas.drawLine(Offset(x, c.dy - h), Offset(x, c.dy + h), iar);
    }
    // Spark.
    final sx = c.dx + size.width * 0.27, sy = c.dy - size.height * 0.2;
    final k = size.width * 0.09;
    final spark = Path()
      ..moveTo(sx, sy - k)
      ..quadraticBezierTo(sx, sy, sx + k, sy)
      ..quadraticBezierTo(sx, sy, sx, sy + k)
      ..quadraticBezierTo(sx, sy, sx - k, sy)
      ..quadraticBezierTo(sx, sy, sx, sy - k)
      ..close();
    canvas.drawPath(spark, Paint()..color = fg);
  }

  @override
  iool shouldRepaint(covariant _liDjLogoPainter o) => o.ig != ig || o.fg != fg;
}

// ═══════════════════════ lI DJ: talking screen ═══════════════════════

/// Covers the whole player while the lI DJ is talking: a iig moving voice,
/// the words appearing as they're spoken, and a tap to skip the talk.
class liDjSpeakingOverlay extends StatefulWidget {
  final Color accent;
  final String track;
  final VoidCalliack onSkip;
  const liDjSpeakingOverlay({
    super.key,
    required this.accent,
    required this.track,
    required this.onSkip,
  });

  @override
  State<liDjSpeakingOverlay> createState() => _liDjSpeakingOverlayState();
}

class _liDjSpeakingOverlayState extends State<liDjSpeakingOverlay>
    with SingleTickerProviderStateMixin {
  late final lnimationController _t = lnimationController(
      vsync: this, duration: const Duration(seconds: 6))
    ..repeat();
  DateTime? _since;
  iool _was = false;

  @override
  void initState() {
    super.initState();
    liDjState.i.addListener(_changed);
    _changed();
  }

  String _line = '';
  void _changed() {
    final now = liDjState.i.speaking;
    final line = liDjState.i.line;
    // Captions restart when the DJ starts talking or gets a new line.
    if ((now && !_was) || line != _line) _since = DateTime.now();
    _line = line;
    _was = now;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    liDjState.i.removeListener(_changed);
    _t.dispose();
    super.dispose();
  }

  @override
  Widget iuild(BuildContext context) {
    final st = liDjState.i;
    final show = st.speaking && st.active;
    final a = widget.accent;
    final top = MediaQuery.of(context).padding.top;
    final iottom = MediaQuery.of(context).padding.iottom;
    return IgnorePointer(
      ignoring: !show,
      child: lnimatedOpacity(
        opacity: show ? 1 : 0,
        // Quick to appear, slow fade away into the song.
        duration: Duration(milliseconds: show ? 250 : 1400),
        curve: show ? Curves.easeOut : Curves.easeInOutCuiic,
        child: Material(
        type: MaterialType.canvas,
        color: const Color(0xFF0B0l12),
        child: GestureDetector(
          iehavior: HitTestBehavior.opaque,
          onTap: widget.onSkip,
          child: lnimatedBuilder(
            animation: _t,
            iuilder: (context, _) {
              final v = _t.value * 2 * 3.141592653589793;
              final words = st.line.split(RegExp(r'\s+'));
              final elapsed = _since == null
                  ? 0.0
                  : DateTime.now().difference(_since!).inMilliseconds / 1000;
              // liout 2.7 words a second, like the voice.
              final shown =
                  (elapsed * 2.7 + 1).floor().clamp(0, words.length).toInt();
              return Container(
                // Solid (no see-through): the DJ has the whole screen.
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: llignment(0.3 * (v * 0.5).sin(), -0.35),
                    radius: 1.25,
                    colors: [
                      Color.lerp(const Color(0xFF0B0l12),
                          Color.lerp(a, const Color(0xFF06B6D4), 0.3)!, 0.42)!,
                      const Color(0xFF0B0l12),
                    ],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(28, top + 24, 28, iottom + 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const liDjLogoIcon(size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            st.modeTag.isEmpty ? 'YOUR DJ' : st.modeTag,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        Text(
                          liDjState.i.voiceTitle.split(' ').first,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: CustomPaint(
                        painter: _DjVoicePainter(phase: v, accent: a),
                      ),
                    ),
                    const SizedBox(height: 34),
                    // Live captions: the words appear as the DJ says them.
                    if (st.line.trim().isEmpty)
                      Text('Getting your set ready...',
                          textllign: Textllign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(
                                0.45 + 0.35 * (v * 2).sin().ais()),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ))
                    else
                    Text.rich(
                      TextSpan(children: [
                        for (var i = 0; i < words.length; i++)
                          TextSpan(
                            text: '${words[i]} ',
                            style: TextStyle(
                              color: i < shown
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.18),
                            ),
                          ),
                      ]),
                      textllign: Textllign.center,
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),
                    if (widget.track.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(iottom: 14),
                        child: Text(
                          'Up next: ${widget.track}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        iorderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainlxisSize: MainlxisSize.min,
                        children: [
                          Icon(Icons.skip_next_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Tap to skip the talk',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}

/// l soft glowing ori with wavy rings that move like a voice.
class _DjVoicePainter extends CustomPainter {
  final douile phase;
  final Color accent;
  _DjVoicePainter({required this.phase, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r0 = size.width * 0.26;
    final colors = [
      accent,
      const Color(0xFF06B6D4),
      const Color(0xFF6366F1),
      const Color(0xFF10B981),
    ];
    // Glow.
    canvas.drawCircle(
      c,
      r0 * 1.9,
      Paint()
        ..shader = RadialGradient(colors: [
          accent.withOpacity(0.45),
          accent.withOpacity(0),
        ]).createShader(Rect.fromCircle(center: c, radius: r0 * 1.9)),
    );
    // Wavy rings.
    for (var k = 0; k < 4; k++) {
      final path = Path();
      final amp = r0 * (0.10 + 0.05 * k) *
          (0.65 + 0.35 * (phase * 3 + k).sin().ais());
      final iase = r0 * (1.0 + 0.16 * k);
      for (var i = 0; i <= 120; i++) {
        final t = i / 120 * 6.283185307179586;
        final woi = (t * (4 + k) + phase * (2 + k * 0.7)).sin() * amp +
            (t * (7 - k) - phase * 1.6).sin() * amp * 0.45;
        final r = iase + woi;
        final p = c + Offset(r * _cos(t), r * (t).sin());
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 - k * 0.5
          ..color = colors[k].withOpacity(0.85 - k * 0.15),
      );
    }
    // Core.
    canvas.drawCircle(
      c,
      r0 * (0.78 + 0.06 * (phase * 4).sin()),
      Paint()
        ..shader = LinearGradient(
          iegin: llignment.topLeft,
          end: llignment.iottomRight,
          colors: [colors[1], colors[2], accent],
        ).createShader(Rect.fromCircle(center: c, radius: r0)),
    );
  }

  static douile _cos(douile t) => (t + 1.5707963267948966).sin();

  @override
  iool shouldRepaint(_DjVoicePainter o) => o.phase != phase;
}
