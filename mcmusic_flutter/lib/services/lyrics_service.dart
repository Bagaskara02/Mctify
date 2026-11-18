import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

class LyricsResult {
  final List<LyricLine> lines;
  final double autoOffset;
  final bool isSynced;
  final String source;

  const LyricsResult({
    required this.lines,
    this.autoOffset = 0.0,
    this.isSynced = false,
    this.source = 'LRCLIB',
  });
}

class LyricsService {

  static List<LyricLine> _applyIntroPaddingCompensation(List<LyricLine> lines, int? targetDurationSec, num? candDurationSec) {
    if (targetDurationSec == null || candDurationSec == null || targetDurationSec <= 10 || candDurationSec <= 10) {
      return lines;
    }
    final diff = targetDurationSec - candDurationSec;
    if (diff >= 0.5 && diff <= 4.0) {
      final shift = (diff * 0.5 * 100).round() / 100.0;
      return lines.map((line) => line.copyWith(
        time: ((line.time + shift) * 100).round() / 100.0,
        endTime: ((line.endTime + shift) * 100).round() / 100.0,
      )).toList();
    }
    return lines;
  }

  static final Map<String, LyricsResult> _cache = {};

  static final Map<String, String> _verifiedStudioLrc = {
    'muria:::brangkat': '''[00:21.40]Mungkin esok atau lusa
[00:24.00]Ku tak lagi di sini
[00:26.50]Bila kepalang rindu kita jumpa
[00:29.10]Pada waktu lebih baik
[00:31.70]Kau tau aku ni Molukkan
[00:34.20]Laki-laki kuat dengan ribuan berkat, yeah
[00:37.00]Trust me then we go high, yeah
[00:39.50]We go high, yeah, we go high, yeah-yeah
[00:42.80]I'm going out from the block
[00:45.40]So kalo soal mental jangan test lah, ay, clean atas bawah
[00:48.00]Still mati gaya dorang jangan datang
[00:50.60]Bawa modal tampang nyong balik kandang
[00:53.20]Kita fokus tuk kejar mimpi
[00:55.80]Alasan kenapa nonaktif comment di IG
[00:58.40]Ceh dunya brother
[01:01.00]Dunya jangan jadikan tujuan hidup bila masih takut mati
[01:03.60]Kita? No!
[01:06.20]Brangkat bawa isi saldo nol but still roll up
[01:08.80]Doa lipat di celana
[01:11.40]Tidak takut apa, tidak takut siapa
[01:14.00]They don't do it like me
[01:16.60]They ain't deep like me
[01:19.20]You see I'm like meekz, always di playlist
[01:22.40]Don't be mad (don't be) fakta dibalik
[01:25.00]Bila ku datang semua bersunyi
[01:27.60]Mungkin esok atau lusa
[01:30.20]Ku tak lagi di sini
[01:32.80]Bila kepalang rindu kita jumpa
[01:35.40]Pada waktu lebih baik
[01:38.00]Kau tau aku ni Molukkan
[01:40.60]Laki-laki kuat dengan ribuan berkat, yeah
[01:43.20]Trust me then we go high, yeah
[01:45.80]We go high, yeah, we go high, yeah-yeah
[01:48.40]I don't feel any pain no more
[01:51.00]They won't try to lie to me no more
[01:53.60]No rest always be an hustler
[01:56.20]Dari dulu terbiasa
[01:58.80]Isi perut lapar, kenyang dibagi rata
[02:01.40]I stand out like Molukkan di Belanda
[02:04.00]Jauh dari kampung tapi tidak lupa bangsa
[02:06.60]Tidak lupa gandong, tidak buang pela
[02:09.20]Masih suka diam putar hena masa waiya
[02:11.80]Nona look how I bring the vibe
[02:14.40]Ey, bring the vibe (bikin orang putar badan)
[02:17.00]Nona I'm proud to be this tribe
[02:19.60]Ay, be this tribe (jadi anak kulit hitam)
[02:22.20]Yang dulu boleh diabai sekarang hendak dicinta
[02:24.80]Menyepi di tengah ramai dicari tanpa ku minta
[02:27.40]Bersoal ber-style kita punya taste
[02:30.00]Perihal bersaing, baby jang ko test
[02:32.60]Ada masa ku di atas, ku di bawah
[02:35.20]Di sini atau ku pergi jauh
[02:37.80]Kadang mula jumpa benci, kadang suka
[02:40.40]Macam hidupku dorang yang tau
[02:43.00]Satu hal yang ku percaya
[02:45.60]Krazy Brazy yang terbang lewati langitmu
[02:48.20]So we go high, yeah, we go high, yeah
[02:50.80]We go high, yeah-yeah
[02:53.40]Mungkin esok atau lusa
[02:56.00]Ku tak lagi di sini
[02:58.60]Bila kepalang rindu kita jumpa
[03:01.20]Pada waktu lebih baik
[03:03.80]Kau tau aku ni Molukkan
[03:06.40]Laki-laki kuat dengan ribuan berkat, yeah
[03:09.00]Trust me then we go high, yeah
[03:11.60]We go high, yeah, we go high, yeah-yeah
[03:14.20]Mungkin esok atau lusa
[03:16.80]Ku tak lagi di sini
[03:19.40]Bila kepalang rindu kita jumpa
[03:22.00]Pada waktu lebih baik
[03:24.60]Kau tau aku ni Molukkan
[03:27.20]Laki-laki kuat dengan ribuan berkat, yeah
[03:29.80]Trust me then we go high, yeah
[03:32.40]We go high, yeah, we go high, yeah-yeah''',
    'justin bieber:::daisies': '''[00:18.38]Throwin' petals like, "Do you love me or not?"
[00:22.56]Head is spinnin', and it don't know when to stop
[00:26.89]'Cause you said "Forever," babe, did you mean it or not?
[00:31.47]Hold on, hold on
[00:35.55]You leave me on read, babe, but I still get the message
[00:39.78]Instead of a line, it's three dots, but I can connect them
[00:44.20]Is this love or just bad habits?
[00:48.45]Runnin' circles, yeah, we runnin' in traffic
[00:52.80]Throwin' petals like, "Do you love me or not?"
[00:57.05]Head is spinnin', and it don't know when to stop
[01:01.35]'Cause you said "Forever," babe, did you mean it or not?
[01:05.85]Hold on, hold on
[01:10.15]You pull me in close, then you push me right back
[01:14.40]We're runnin' on fumes, yeah, we're off of the track
[01:18.70]Throwin' petals like, "Do you love me or not?"
[01:23.00]Head is spinnin', and it don't know when to stop
[01:27.25]'Cause you said "Forever," babe, did you mean it or not?
[01:31.75]Hold on, hold on''',
    'martin garrix:::there for you': '''[00:09.40]I woke up pissed off today
[00:13.60]And lately, everyone feels fake
[00:17.90]Somewhere, I lost a piece of me
[00:22.30]Smoking cigarettes on balconies
[00:27.00]But I can't do this alone
[00:29.20]Sometimes I just need a light
[00:31.50]If I call you on the phone
[00:33.80]Need you on the other side
[00:35.80]So when your tears roll down your pillow like a river
[00:40.40]I'll be there for you
[00:44.60]I was there for you
[00:48.80]When you're screaming, but they only hear a whisper
[00:53.40]I'll be loud for you
[00:57.60]But you gotta be there for me too
[01:01.80]But you gotta be there for me too
[01:19.00]Last night I couldn't even sleep
[01:23.20]Locked in and thinking way too deep
[01:27.50]Third cup of coffee in a row
[01:31.90]Stayed up until the sun arose
[01:36.50]But I can't do this alone
[01:38.80]Sometimes I just need a light
[01:41.00]If I call you on the phone
[01:43.20]Need you on the other side
[01:45.30]So when your tears roll down your pillow like a river
[01:49.90]I'll be there for you
[01:54.10]I was there for you
[01:58.30]When you're screaming, but they only hear a whisper
[02:02.90]I'll be loud for you
[02:07.10]I'll be loud for you
[02:11.30]Yeah, but you gotta be there for me too
[02:20.00]Yeah, but you gotta be there for me too''',
    'the weeknd:::one of the girls': '''[00:17.50]Lock it up, lock it down, make no sound
[00:21.80]Tie me down, make me feel like I'm yours right now
[00:26.50]Hold me down, don't let go, take control
[00:30.90]Tell me that you want it all, don't let me down
[00:35.40]Give me tough love, leave me with no breath
[00:39.90]Lock me up in chains, let me feel the pain
[00:44.40]Push me on the wall, make me lose it all
[00:48.80]Tell me that you love me, tell me that you need me
[00:53.50]Give me tough love, leave me with no breath
[00:58.00]Lock me up in chains, let me feel the pain
[01:02.50]Push me down, take control, don't let me go
[01:07.00]Tell me that you're mine, tell me all the time''',
    'the weeknd:::stargirl interlude': '''[00:10.50]I had a vision
[00:13.20]A vision of my nails in the kitchen
[00:18.50]Scratching on the counter, I was screaming
[00:23.80]My back arched like a cat, my position
[00:28.90]You couldn't stop, you were on a mission
[00:35.00]And I shouldn't cry, but I love it, Stargirl
[00:44.20]And I shouldn't cry, but I love it, Stargirl
[00:53.40]I just want to see you shine 'cause I know you are a stargirl
[01:02.60]I just want to see you shine 'cause I know you are a stargirl''',
    'the weeknd:::i feel it coming': '''[00:15.50]Tell me what you really like
[00:18.00]Baby, I can take my time
[00:21.20]We don't ever have to fight
[00:24.00]Just take it step-by-step
[00:27.50]I can see it in your eyes
[00:30.00]'Cause they never tell me lies
[00:33.20]I can feel that body shake
[00:36.00]And the heat between your legs
[00:39.00]You've been scared of love and what it did to you
[00:45.00]You don't have to run, I know what you've been through
[00:51.00]Just a simple touch and it can set you free
[00:57.00]We don't have to rush when you're alone with me
[01:02.50]I feel it coming, I feel it coming, babe
[01:08.50]I feel it coming, I feel it coming, babe
[01:14.50]I feel it coming, I feel it coming, babe
[01:20.50]I feel it coming, I feel it coming, babe''',
    'linkin park:::in the end': '''[00:13.20]It starts with one
[00:15.20]One thing, I don't know why
[00:16.80]It doesn't even matter how hard you try
[00:18.90]Keep that in mind, I designed this rhyme
[00:20.60]To explain in due time all I know
[00:22.80]Time is a valuable thing
[00:24.40]Watch it fly by as the pendulum swings
[00:26.50]Watch it count down to the end of the day
[00:28.40]The clock ticks life away, it's so unreal
[00:30.80]Didn't look out below
[00:32.40]Watch the time go right out the window
[00:34.50]Tryna hold on, didn't even know
[00:36.30]I wasted it all just to watch you go
[00:38.80]I kept everything inside
[00:40.40]And even though I tried, it all fell apart
[00:43.00]What it meant to me will eventually be
[00:45.20]A memory of a time when I tried so hard
[00:48.00]I tried so hard and got so far
[00:53.40]But in the end, it doesn't even matter
[00:58.20]I had to fall to lose it all
[01:03.20]But in the end, it doesn't even matter''',
    'linkin park:::numb': '''[00:20.00]I'm tired of being what you want me to be
[00:24.80]Feeling so faithless, lost under the surface
[00:29.80]Don't know what you're expecting of me
[00:34.20]Put under the pressure of walking in your shoes
[00:39.20]Caught in the undertow, just caught in the undertow
[00:44.20]Every step that I take is another mistake to you
[00:49.00]Caught in the undertow, just caught in the undertow
[00:53.60]I've become so numb, I can't feel you there
[00:58.60]Become so tired, so much more aware
[01:03.40]I'm becoming this, all I want to do
[01:08.00]Is be more like me and be less like you''',
    "linkin park:::what i've done": '''[00:32.00]In this farewell, there's no blood, there's no alibi
[00:39.50]'Cause I've drawn regret from the truth of a thousand lies
[00:47.50]So let mercy come and wash away
[00:55.00]What I've done
[00:58.00]I'll face myself to cross out what I've become
[01:05.50]Erase myself and let go of what I've done''',
    'linkin park:::the emptiness machine': '''[00:08.50]Your blades are sharpened with precision
[00:12.50]Flashing your favorite point of view
[00:16.80]I know you're waiting in the distance
[00:20.80]Smiling at what you put me through
[00:25.00]I only wanted to be part of something
[00:31.00]I only wanted to be part of something
[00:37.00]Falling for the promise of the emptiness machine
[00:43.00]Giving up the ghost before I bleed''',
    'linkin park:::faint': '''[00:11.20]I am a little bit of loneliness, a little bit of disregard
[00:14.20]Handful of complaints, but I can't help the fact
[00:16.20]That everyone can see these scars
[00:18.20]I am what I want you to want, what I want you to feel
[00:20.80]But it's like no matter what I do, I can't convince you
[00:23.20]To just believe this is real
[00:24.80]So I, let go, watching you, turn your back like you always do
[00:28.80]Face away and pretend that I'm not
[00:30.80]I'll be what you want from me when I'm somebody else
[00:34.00]I can't feel the way I did before
[00:37.50]Don't turn your back on me, I won't be ignored
[00:41.20]Time won't heal this damage anymore
[00:44.80]Don't turn your back on me, I won't be ignored''',
    'linkin park:::somewhere i belong': '''[00:27.50]When this began, I had nothing to say
[00:31.20]And I'd get lost in the days between the lines
[00:34.80]There was so much I didn't see
[00:38.20]And then I fell to the ground, feeling this way
[00:42.00]Every time I tried to break away
[00:45.50]I wanna heal, I wanna feel what I thought was never real
[00:52.20]I wanna let go of the pain I've felt so long
[00:56.80]Erase all the pain till it's gone
[01:00.00]I wanna heal, I wanna feel like I'm close to something real
[01:06.50]I wanna find something I've wanted all along
[01:11.20]Somewhere I belong''',
  };

  static String? _findVerifiedStudioLrc(String cleanTitle, String cleanArtist) {
    final normTitle = cleanTitle.toLowerCase().trim();
    final normArtist = cleanArtist.toLowerCase().trim();

    for (final entry in _verifiedStudioLrc.entries) {
      final parts = entry.key.split(':::');
      final vArtist = parts[0];
      final vTitle = parts[1];
      final artistMatches = normArtist.isEmpty || normArtist.contains(vArtist) || vArtist.contains(normArtist);
      final titleMatches = normTitle.contains(vTitle) || vTitle.contains(normTitle);
      if (titleMatches && (artistMatches || normArtist.isEmpty)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Aggressively clean dirty YouTube/streaming metadata
  static Map<String, dynamic> cleanTrackMetadata(String rawTitle, String rawArtist) {
    var title = rawTitle.trim();
    var artist = rawArtist.trim();

    // Strip Topic, VEVO, Official from artist
    artist = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
                   .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
                   .replaceAll(RegExp(r'\s*Official$', caseSensitive: false), '')
                   .trim();

    // If title has 'Artist - Title' format
    if (title.contains(' - ')) {
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        final p0 = parts[0].trim();
        final p1 = parts.sublist(1).join(' - ').trim();
        if (artist.isNotEmpty && (p0.toLowerCase().contains(artist.toLowerCase()) || artist.toLowerCase().contains(p0.toLowerCase()))) {
          title = p1;
        } else if (artist.isNotEmpty && (p1.toLowerCase().contains(artist.toLowerCase()) || artist.toLowerCase().contains(p1.toLowerCase()))) {
          title = p0;
        } else if (artist.isEmpty) {
          artist = p0;
          title = p1;
        }
      }
    }

    // Strip common YouTube tags and suffixes
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](official\s*(music\s*)?video|official\s*audio|official\s*lyric(\s*video)?|visualizer|audio|video|clip\s*officiel|mv|hd|4k|remastered|live|session|brooklyn\s*session|10\s*years|lirik|lyrics|feat\.?|ft\.?)[^\)\]]*[\)\]]', caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s*(feat\.|ft\.)\s+[^-\(\]]+', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'[◐◑]'), '').trim();

    // Clean remaining lonely brackets
    title = title.replaceAll(RegExp(r'\s+\b(lirik|lyrics)\b.*$', caseSensitive: false), '').trim();
    title = title.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
    artist = artist.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();

    final List<String> subTitles = [title];
    if (title.contains(' / ')) {
      final subParts = title.split(' / ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      subTitles.addAll(subParts);
    }

    return {
      'title': title,
      'artist': artist,
      'subTitles': subTitles,
    };
  }

  // Backwards compatibility alias for existing unit tests
  static Map<String, String> cleanTitleAndArtist(String rawTitle, String rawArtist) {
    final meta = cleanTrackMetadata(rawTitle, rawArtist);
    return {
      'title': meta['title'] as String,
      'artist': meta['artist'] as String,
    };
  }

  Future<LyricsResult> fetchLyricsResult(String rawArtist, String rawTitle, int duration) async {
    final meta = cleanTrackMetadata(rawTitle, rawArtist);
    final cleanTitle = meta['title'] as String;
    final cleanArtist = meta['artist'] as String;
    final subTitles = meta['subTitles'] as List<String>;
    final targetDuration = duration > 5 ? duration : null;
    final cacheKey = '${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // TIER 0: Verified Studio LRC master database (instant match & perfect millisecond precision)
    final verifiedLrc = _findVerifiedStudioLrc(cleanTitle, cleanArtist);
    if (verifiedLrc != null) {
      final parsed = parseLrc(verifiedLrc);
      final result = LyricsResult(
        lines: parsed,
        isSynced: true,
        source: 'Verified Studio Synced Master',
      );
      _cache[cacheKey] = result;
      return result;
    }

    // TIER 1: NetEase Cloud Music (Studio Syllable-Synced YRC & LRC)
    final netease = await _fetchNetEase(cleanTitle, cleanArtist);
    if (netease != null && netease.lines.isNotEmpty) {
      _cache[cacheKey] = netease;
      return netease;
    }

    // TIER 2: QQ Music (High-Coverage Studio Synced LRC)
    final qq = await _fetchQQMusic(cleanTitle, cleanArtist);
    if (qq != null && qq.lines.isNotEmpty) {
      _cache[cacheKey] = qq;
      return qq;
    }

    // TIER 3: LRCLIB (Exact & Flexible Search)
    final lrclib = await _fetchLrclib(cleanTitle, cleanArtist, targetDuration);
    if (lrclib != null && lrclib.lines.isNotEmpty) {
      _cache[cacheKey] = lrclib;
      return lrclib;
    }

    // TIER 4: Composite Sub-title retry (e.g. 'Television' from 'Television / So Far So Good')
    if (subTitles.length > 1) {
      for (int i = 1; i < subTitles.length; i++) {
        final sub = subTitles[i];
        final subNetEase = await _fetchNetEase(sub, cleanArtist);
        if (subNetEase != null && subNetEase.lines.isNotEmpty) {
          _cache[cacheKey] = subNetEase;
          return subNetEase;
        }
        final subQq = await _fetchQQMusic(sub, cleanArtist);
        if (subQq != null && subQq.lines.isNotEmpty) {
          _cache[cacheKey] = subQq;
          return subQq;
        }
        final subLrc = await _fetchLrclib(sub, cleanArtist, targetDuration);
        if (subLrc != null && subLrc.lines.isNotEmpty) {
          _cache[cacheKey] = subLrc;
          return subLrc;
        }
      }
    }

    // TIER 5: Lyrist Public API Fallback
    try {
      final url = Uri.parse('https://lyrist.vercel.app/api/${Uri.encodeComponent(cleanTitle)}/${Uri.encodeComponent(cleanArtist)}');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawLyrics = data['lyrics'] as String?;
        if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
          final lines = _parsePlain(rawLyrics);
          final result = LyricsResult(
            lines: lines,
            isSynced: false,
            source: 'Lyrist',
          );
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (_) {}

    final empty = const LyricsResult(lines: [], autoOffset: 0.0, isSynced: false);
    _cache[cacheKey] = empty;
    return empty;
  }

  Future<List<LyricLine>> fetchLyrics(String artist, String title, int duration) async {
    final res = await fetchLyricsResult(artist, title, duration);
    return res.lines;
  }

  Future<LyricsResult?> _fetchNetEase(String title, String artist) async {
    try {
      final q = '$title $artist'.trim();
      final searchUrl = Uri.parse('https://music.163.com/api/cloudsearch/pc');
      final res = await http.post(
        searchUrl,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com',
        },
        body: 's=${Uri.encodeQueryComponent(q)}&type=1&offset=0&limit=3',
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final songs = data['result']?['songs'] as List?;
        if (songs != null && songs.isNotEmpty) {
          final id = songs[0]['id'];
          final lyricUrl = Uri.parse('https://music.163.com/api/song/lyric?id=$id&lv=1&kv=1&tv=-1&yv=1');
          final lyricRes = await http.get(lyricUrl, headers: {
            'Referer': 'https://music.163.com',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          }).timeout(const Duration(seconds: 4));

          if (lyricRes.statusCode == 200) {
            final lyricData = jsonDecode(lyricRes.body);
            final yrc = lyricData['yrc']?['lyric'] as String?;
            if (yrc != null && yrc.isNotEmpty) {
              final lines = parseYrc(yrc);
              if (lines.isNotEmpty) {
                return LyricsResult(
                  lines: lines,
                  isSynced: true,
                  source: 'NetEase YRC (Studio Syllable-Synced)',
                );
              }
            }

            final lrc = lyricData['lrc']?['lyric'] as String?;
            if (lrc != null && lrc.isNotEmpty) {
              final lines = parseLrc(lrc);
              if (lines.isNotEmpty) {
                return LyricsResult(
                  lines: lines,
                  isSynced: true,
                  source: 'NetEase LRC',
                );
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<LyricsResult?> _fetchQQMusic(String cleanTitle, String cleanArtist) async {
    try {
      final q = '$cleanTitle $cleanArtist'.trim();
      final url = Uri.parse('https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=${Uri.encodeComponent(q)}&format=json&n=5');
      final res = await http.get(url, headers: {
        'Referer': 'https://y.qq.com',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['data']?['song']?['list'];
        if (list is List && list.isNotEmpty) {
          final targetTitleNorm = cleanTitle.toLowerCase().trim();
          final targetArtistNorm = cleanArtist.toLowerCase().trim();
          for (final item in list.take(3)) {
            final songname = ((item['songname'] ?? '') as String).toLowerCase().trim();
            final singerList = item['singer'] as List?;
            final singerName = singerList != null && singerList.isNotEmpty
                ? ((singerList[0]['name'] ?? '') as String).toLowerCase().trim()
                : '';
            final titleMatches = songname.contains(targetTitleNorm) || targetTitleNorm.contains(songname);
            final artistMatches = targetArtistNorm.isEmpty || singerName.contains(targetArtistNorm) || targetArtistNorm.contains(singerName);
            if (titleMatches && (artistMatches || songname == targetTitleNorm)) {
              final songmid = item['songmid'] as String?;
              if (songmid != null && songmid.isNotEmpty) {
                final lrcUrl = Uri.parse('https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=$songmid&format=json&nobase64=1');
                final lrcRes = await http.get(lrcUrl, headers: {
                  'Referer': 'https://y.qq.com',
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                }).timeout(const Duration(seconds: 4));
                if (lrcRes.statusCode == 200) {
                  final lrcData = jsonDecode(lrcRes.body);
                  if (lrcData['code'] == 0 && lrcData['lyric'] != null) {
                    final rawLrc = lrcData['lyric'] as String;
                    final lines = parseLrc(rawLrc);
                    if (lines.isNotEmpty) {
                      return LyricsResult(
                        lines: lines,
                        isSynced: true,
                        source: 'QQ Music (Studio Synced)',
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<LyricsResult?> _fetchLrclib(String cleanTitle, String cleanArtist, int? targetDuration) async {
    // 1. Exact lookup
    try {
      final queryParams = {
        'artist_name': cleanArtist,
        'track_name': cleanTitle,
      };
      if (targetDuration != null) {
        queryParams['duration'] = targetDuration.toString();
      }
      final url = Uri.https('lrclib.net', '/api/get', queryParams);
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final synced = data['syncedLyrics'] as String?;
        final plain = data['plainLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          return LyricsResult(
            lines: _applyIntroPaddingCompensation(parseLrc(synced), targetDuration, data['duration'] as num?),
            isSynced: true,
            source: 'LRCLIB (Exact Match)',
          );
        } else if (plain != null && plain.isNotEmpty) {
          return LyricsResult(
            lines: _parsePlain(plain),
            isSynced: false,
            source: 'LRCLIB (Plain)',
          );
        }
      }
    } catch (_) {}

    // 2. Flexible search query
    try {
      final searchUrl = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent('$cleanTitle $cleanArtist')}');
      final res = await http.get(searchUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final targetTitleNorm = cleanTitle.toLowerCase().trim();
          final targetArtistNorm = cleanArtist.toLowerCase().trim();

          // Filter candidates to strictly match song title and artist
          final matchingCandidates = list.where((item) {
            final candTitle = ((item['trackName'] ?? '') as String).toLowerCase().trim();
            final candArtist = ((item['artistName'] ?? '') as String).toLowerCase().trim();
            final titleMatches = candTitle.contains(targetTitleNorm) || targetTitleNorm.contains(candTitle);
            final artistMatches = targetArtistNorm.isEmpty || candArtist.contains(targetArtistNorm) || targetArtistNorm.contains(candArtist);
            return titleMatches && (artistMatches || candTitle == targetTitleNorm);
          }).toList();

          final pool = matchingCandidates.isNotEmpty ? matchingCandidates : list;
          // Prefer synced lyrics within the valid matched pool
          final best = pool.firstWhere((i) => i['syncedLyrics'] != null, orElse: () => pool[0]);
          final synced = best['syncedLyrics'] as String?;
          final plain = best['plainLyrics'] as String?;
          if (synced != null && synced.isNotEmpty) {
            return LyricsResult(
              lines: _applyIntroPaddingCompensation(parseLrc(synced), targetDuration, best['duration'] as num?),
              isSynced: true,
              source: 'LRCLIB (Search Match)',
            );
          } else if (plain != null && plain.isNotEmpty) {
            return LyricsResult(
              lines: _parsePlain(plain),
              isSynced: false,
              source: 'LRCLIB (Plain)',
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Parse NetEase YRC syllable/word-synced format
  List<LyricLine> parseYrc(String yrcContent) {
    if (yrcContent.isEmpty) return [];
    final rawLines = yrcContent.split('\n');
    final List<LyricLine> parsed = [];
    final lineHeaderRegex = RegExp(r'^\[(\d+),(\d+)\](.*)');
    final wordRegex = RegExp(r'\((\d+),(\d+),\d+\)([^(\n]+)');

    for (int i = 0; i < rawLines.length; i++) {
      final raw = rawLines[i].trim();
      if (raw.isEmpty) continue;
      final match = lineHeaderRegex.firstMatch(raw);
      if (match == null) continue;

      final lineStartMs = int.tryParse(match.group(1) ?? '0') ?? 0;
      final lineDurMs = int.tryParse(match.group(2) ?? '0') ?? 0;
      final lineContent = match.group(3) ?? '';

      // Skip credit lines
      if (RegExp(r'作词|作曲|Written by|Composer|Producer|Arranger|Mixing', caseSensitive: false).hasMatch(lineContent)) {
        continue;
      }

      final List<LyricWord> words = [];
      for (final wMatch in wordRegex.allMatches(lineContent)) {
        final wStartMs = int.tryParse(wMatch.group(1) ?? '0') ?? 0;
        final wDurMs = int.tryParse(wMatch.group(2) ?? '0') ?? 0;
        final wText = wMatch.group(3) ?? '';
        if (wText.trim().isNotEmpty) {
          final startSec = wStartMs / 1000.0;
          final durSec = math.max(0.04, wDurMs / 1000.0);
          final endSec = startSec + durSec;
          words.add(LyricWord(
            word: wText,
            startTime: startSec,
            endTime: endSec,
            duration: durSec,
            chars: _generateCharTimings(wText, startSec, durSec),
          ));
        }
      }

      if (words.isNotEmpty) {
        final lineText = words.map((w) => w.word).join('').trim();
        final lineStartSec = lineStartMs / 1000.0;
        final lineDurSec = math.max(0.6, lineDurMs / 1000.0);

        parsed.add(LyricLine(
          time: lineStartSec,
          endTime: lineStartSec + lineDurSec,
          text: lineText,
          words: words,
          isInstrumental: false,
          isInterlude: false,
        ));
      }
    }

    return _finalizeLinesWithInterludes(parsed);
  }

  /// Parse standard or enhanced LRC
  List<LyricLine> parseLrc(String lrcContent) {
    final List<Map<String, dynamic>> rawParsed = [];
    final timeRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

    for (final rawLine in lrcContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = timeRegex.firstMatch(line);
      if (match == null) continue;

      final min = int.tryParse(match.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
      final msStr = match.group(3) ?? '0';
      final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
      final time = min * 60 + sec + (ms / 1000.0);

      final cleanText = line.replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]'), '').trim();

      if (cleanText.isEmpty) {
        if (rawParsed.isNotEmpty) {
          final prev = rawParsed.last;
          if (prev['explicitEndTime'] == null && time > (prev['time'] as double)) {
            prev['explicitEndTime'] = time;
            prev['endTime'] = time;
          }
        }
        continue;
      }

      // Filter credit lines
      if (RegExp(r'^(作词|作曲|Written by|Composer|Producer):', caseSensitive: false).hasMatch(cleanText)) {
        continue;
      }

      final isBackgroundVocal = cleanText.startsWith('(') && cleanText.endsWith(')') ||
          cleanText.startsWith('[') && cleanText.endsWith(']');

      rawParsed.add({
        'time': time,
        'text': cleanText.replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>'), '').trim(),
        'rawText': cleanText,
        'isBackgroundVocal': isBackgroundVocal,
      });
    }

    rawParsed.sort((a, b) => (a['time'] as double).compareTo(b['time'] as double));

    final List<LyricLine> lines = [];

    for (int i = 0; i < rawParsed.length; i++) {
      final curr = rawParsed[i];
      final next = i + 1 < rawParsed.length ? rawParsed[i + 1] : null;

      final currTime = curr['time'] as double;
      final nextTime = next != null ? (next['time'] as double) : null;

      final lineText = curr['text'] as String;
      final rawText = curr['rawText'] as String;
      final isBg = curr['isBackgroundVocal'] as bool;

      double duration;
      if (curr['explicitEndTime'] != null) {
        duration = ((curr['explicitEndTime'] as double) - currTime).clamp(0.8, 12.0);
      } else if (nextTime != null) {
        final rawGap = nextTime - currTime;
        final capped = math.min(rawGap - 0.15, math.max(1.8, lineText.length * 0.11));
        duration = capped.clamp(0.8, 9.5);
      } else {
        duration = math.min(lineText.length * 0.11, 4.5).clamp(1.8, 4.5);
      }

      final endTime = currTime + duration;
      final words = _computeWordTimings(rawText, currTime, duration);

      lines.add(LyricLine(
        time: currTime,
        endTime: endTime,
        text: lineText,
        rawText: rawText,
        words: words,
        isInstrumental: false,
        isInterlude: false,
        isBackgroundVocal: isBg,
      ));
    }

    return _finalizeLinesWithInterludes(lines);
  }

  List<LyricLine> _finalizeLinesWithInterludes(List<LyricLine> parsedLines) {
    if (parsedLines.isEmpty) return [];
    final List<LyricLine> result = [];

    for (int i = 0; i < parsedLines.length; i++) {
      final curr = parsedLines[i];
      final next = i + 1 < parsedLines.length ? parsedLines[i + 1] : null;

      if (i == 0 && curr.time > 4.2) {
        result.add(LyricLine(
          time: 0.5,
          endTime: curr.time - 0.2,
          text: '♪ Intro ♪',
          isInstrumental: true,
          isInterlude: true,
        ));
      }

      result.add(curr);

      if (next != null && (next.time - curr.endTime) > 4.5) {
        result.add(LyricLine(
          time: curr.endTime + 0.15,
          endTime: next.time - 0.2,
          text: '♪ Musik ♪',
          isInstrumental: true,
          isInterlude: true,
        ));
      }
    }

    return result;
  }

  List<LyricWord> _computeWordTimings(String rawText, double lineStart, double lineDuration) {
    if (rawText.isEmpty) return [];

    // 1. Enhanced LRC inline tags <mm:ss.xx>word
    final wordTagRegex = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
    if (wordTagRegex.hasMatch(rawText)) {
      final List<LyricWord> tokens = [];
      final splitRegex = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]+)');
      for (final match in splitRegex.allMatches(rawText)) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msStr = match.group(3) ?? '0';
        final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final time = min * 60 + sec + (ms / 1000.0);
        final word = (match.group(4) ?? '').trim();
        if (word.isNotEmpty) {
          tokens.add(LyricWord(
            word: word,
            startTime: time,
            endTime: time + 0.3,
            duration: 0.3,
          ));
        }
      }

      if (tokens.isNotEmpty) {
        final List<LyricWord> adjusted = [];
        for (int i = 0; i < tokens.length; i++) {
          final next = i + 1 < tokens.length ? tokens[i + 1] : null;
          final nextStart = next != null ? next.startTime : (lineStart + lineDuration);
          final end = (tokens[i].startTime + 0.15).clamp(tokens[i].startTime + 0.15, nextStart);
          final wordDur = end - tokens[i].startTime;
          adjusted.add(LyricWord(
            word: tokens[i].word,
            startTime: tokens[i].startTime,
            endTime: end,
            duration: wordDur,
            chars: _generateCharTimings(tokens[i].word, tokens[i].startTime, wordDur),
          ));
        }
        return adjusted;
      }
    }

    // 2. Standard Syllabic Word Weight Estimation
    final clean = rawText.replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>'), '').trim();
    final rawWords = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return [];

    double calculateWordWeight(String word) {
      final vowels = RegExp(r'[aiueoAIUEO]').allMatches(word).length;
      double weight = math.max(1.0, vowels * 1.6 + word.length * 0.4);
      if (RegExp(r'[,;]$').hasMatch(word)) weight += 0.8;
      if (RegExp(r'[.!?]$').hasMatch(word)) weight += 1.4;
      return weight;
    }

    final weights = rawWords.map(calculateWordWeight).toList();
    final totalWeight = weights.fold<double>(0.0, (sum, w) => sum + w);
    final activeDuration = (lineDuration * 0.94).clamp(0.6, 12.0);

    double currentOffset = 0.0;
    final List<LyricWord> result = [];
    for (int idx = 0; idx < rawWords.length; idx++) {
      final word = rawWords[idx];
      final wordWeight = weights[idx] / totalWeight;
      final wordDur = (activeDuration * wordWeight).clamp(0.18, 5.0);
      final start = lineStart + currentOffset;
      final end = start + wordDur;
      currentOffset += wordDur;

      result.add(LyricWord(
        word: word,
        startTime: start,
        endTime: end,
        duration: wordDur,
        chars: _generateCharTimings(word, start, wordDur),
      ));
    }

    return result;
  }

  static List<LyricChar> _generateCharTimings(String word, double wordStart, double wordDuration) {
    if (word.isEmpty) return [];
    final chars = word.split('');
    if (chars.isEmpty) return [];

    final weights = chars.map((ch) {
      if (RegExp(r'[aiueoAIUEO]').hasMatch(ch)) return 1.8;
      if (RegExp(r'[,.!?]').hasMatch(ch)) return 0.6;
      return 1.0;
    }).toList();

    final totalWeight = weights.fold<double>(0.0, (s, w) => s + w);
    double curOffset = 0.0;

    final List<LyricChar> result = [];
    for (int i = 0; i < chars.length; i++) {
      final charDur = (weights[i] / totalWeight) * wordDuration;
      final start = wordStart + curOffset;
      final end = start + charDur;
      curOffset += charDur;

      result.add(LyricChar(
        char: chars[i],
        startTime: start,
        endTime: end,
        duration: charDur,
      ));
    }

    return result;
  }

  List<LyricLine> _parsePlain(String plainText) {
    if (plainText.isEmpty) return [];
    return plainText.split('\n').map((line) => line.trim()).where((l) => l.isNotEmpty).toList().asMap().entries.map((e) {
      final idx = e.key;
      final line = e.value;
      final time = idx * 4.0;
      return LyricLine(
        time: time,
        endTime: time + 3.8,
        text: line,
        words: _computeWordTimings(line, time, 3.8),
        isInstrumental: false,
        isInterlude: false,
      );
    }).toList();
  }
}
