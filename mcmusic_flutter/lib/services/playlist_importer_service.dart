import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/playlist.dart';
import '../models/track.dart';
import 'music_api_service.dart';

typedef ImportProgressCallback = void Function(int current, int total, String message);

class PlaylistImporterService {
  final MusicApiService _apiService = MusicApiService();

  /// Import playlist from Spotify URL (e.g. https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M)
  Future<Playlist> importFromSpotify(
    String url, {
    ImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 1, 'Menganalisis link playlist Spotify...');

    final regExp = RegExp(r'playlist[\/:]([a-zA-Z0-9]+)');
    final match = regExp.firstMatch(url);
    if (match == null) {
      throw Exception('Link playlist Spotify tidak valid. Pastikan link memiliki format https://open.spotify.com/playlist/...');
    }
    final playlistId = match.group(1)!;

    String playlistName = 'Spotify Playlist';
    String cover = MusicApiService.defaultArtwork;
    List<Map<String, String>> rawTracks = [];

    // Method 1: Internal McMusic Backend Proxy (/api/spotify/playlist)
    try {
      onProgress?.call(0, 1, 'Menghubungkan ke API Spotify...');
      final apiUrl = Uri.parse('https://mctify.vercel.app/api/spotify/playlist?id=$playlistId');
      final res = await http.get(apiUrl).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['tracks'] is List && (data['tracks'] as List).isNotEmpty) {
          playlistName = data['name'] ?? playlistName;
          cover = data['cover'] ?? cover;
          for (final t in data['tracks']) {
            final title = (t['title'] ?? '').toString().trim();
            final artist = (t['artist'] ?? '').toString().trim();
            if (title.isNotEmpty) {
              rawTracks.add({'title': title, 'artist': artist});
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Spotify backend proxy note: $e');
    }

    // Method 2: Direct Spotify Embed Scrape Fallback
    if (rawTracks.isEmpty) {
      try {
        onProgress?.call(0, 1, 'Mencoba membaca playlist Spotify langsung...');
        final embedUrl = Uri.parse('https://open.spotify.com/embed/playlist/$playlistId');
        final res = await http.get(
          embedUrl,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final nextDataMatch = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)<\/script>', dotAll: true).firstMatch(res.body);
          if (nextDataMatch != null) {
            final jsonStr = nextDataMatch.group(1)!;
            final data = jsonDecode(jsonStr);
            final entity = data['props']?['pageProps']?['state']?['data']?['entity'];
            if (entity != null) {
              playlistName = entity['name'] ?? playlistName;
              final coverList = entity['coverArt']?['sources'] as List?;
              if (coverList != null && coverList.isNotEmpty) {
                cover = coverList[0]['url'] ?? cover;
              }
              final trackList = entity['trackList'] as List? ?? [];
              for (final t in trackList) {
                final title = (t['title'] ?? '').toString().trim();
                final artist = (t['subtitle'] ?? '').toString().trim();
                if (title.isNotEmpty) {
                  rawTracks.add({'title': title, 'artist': artist});
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Spotify embed fallback note: $e');
      }
    }

    if (rawTracks.isEmpty) {
      throw Exception('Gagal mengambil daftar lagu dari playlist Spotify ini. Pastikan playlist bersifat Publik.');
    }

    return await _resolveTrackList(
      rawTracks,
      playlistName: playlistName,
      cover: cover,
      onProgress: onProgress,
    );
  }

  /// Import playlist from YouTube or YouTube Music URL
  Future<Playlist> importFromYouTube(
    String url, {
    ImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 1, 'Menganalisis link YouTube playlist...');

    final regExp = RegExp(r'[?&]list=([^#&?]+)');
    final match = regExp.firstMatch(url);
    if (match == null) {
      throw Exception('Link YouTube tidak valid. URL harus memiliki parameter ?list=...');
    }
    final playlistId = match.group(1)!;

    final yt = YoutubeExplode();
    try {
      onProgress?.call(0, 1, 'Mengambil data playlist dari YouTube...');
      final ytPlaylist = await yt.playlists.get(playlistId);
      final playlistName = ytPlaylist.title.isNotEmpty ? ytPlaylist.title : 'YouTube Playlist';
      final cover = ytPlaylist.thumbnails.highResUrl.isNotEmpty
          ? ytPlaylist.thumbnails.highResUrl
          : MusicApiService.defaultArtwork;

      final List<Map<String, String>> rawTracks = [];
      await for (final video in yt.playlists.getVideos(playlistId)) {
        var title = video.title;
        var artist = video.author;

        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

        rawTracks.add({
          'title': title,
          'artist': artist,
          'videoId': video.id.value,
          'duration': (video.duration?.inSeconds ?? 200).toString(),
        });

        if (rawTracks.length >= 100) break; // Limit to 100 tracks max for performance
      }

      if (rawTracks.isEmpty) {
        throw Exception('Tidak ada video yang ditemukan di dalam playlist YouTube ini.');
      }

      return await _resolveTrackList(
        rawTracks,
        playlistName: playlistName,
        cover: cover,
        onProgress: onProgress,
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Gagal memproses YouTube playlist: $e');
    } finally {
      yt.close();
    }
  }

  /// Import from plain text / pasted list (e.g. "Artist - Title" line by line)
  Future<Playlist> importFromText(
    String text, {
    String customName = 'Playlist Kustom',
    ImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 1, 'Membaca daftar teks lagu...');

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 2)
        .toList();

    if (lines.isEmpty) {
      throw Exception('Tidak ada teks lagu yang terdeteksi.');
    }

    final List<Map<String, String>> items = [];
    for (final line in lines) {
      // Strip leading numbering e.g. "1. " or "01 - "
      var clean = line.replaceAll(RegExp(r'^\d+[\.\)\-]\s*'), '').trim();

      String artist = '';
      String title = '';

      if (clean.contains(' - ')) {
        final parts = clean.split(' - ');
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      } else if (clean.toLowerCase().contains(' by ')) {
        final parts = clean.split(RegExp(r'\s+by\s+', caseSensitive: false));
        title = parts[0].trim();
        artist = parts.sublist(1).join(' by ').trim();
      } else {
        title = clean;
      }

      if (title.isNotEmpty) {
        items.add({'title': title, 'artist': artist});
      }
    }

    return await _resolveTrackList(
      items,
      playlistName: customName,
      cover: MusicApiService.defaultArtwork,
      onProgress: onProgress,
    );
  }

  /// Import from Backup JSON string
  Playlist importFromJson(String jsonContent) {
    try {
      final dynamic data = jsonDecode(jsonContent);
      if (data is! Map) {
        throw Exception('Format JSON harus berupa objek playlist.');
      }

      final rawTracks = data['tracks'] as List? ?? [];
      final List<Track> tracks = [];
      for (final t in rawTracks) {
        if (t is Map) {
          tracks.add(Track(
            id: t['id']?.toString() ?? 't-${DateTime.now().millisecondsSinceEpoch}',
            title: t['title']?.toString() ?? 'Lagu',
            artist: t['artist']?.toString() ?? 'Artis',
            album: t['album']?.toString() ?? 'Album',
            artwork: t['artwork']?.toString() ?? MusicApiService.defaultArtwork,
            audioUrl: t['audioUrl']?.toString() ?? '',
            videoId: t['videoId']?.toString(),
            duration: int.tryParse(t['duration']?.toString() ?? '180') ?? 180,
            streamCount: t['streamCount']?.toString() ?? '1.000.000',
            isExplicit: t['isExplicit'] == true,
          ));
        }
      }

      return Playlist(
        id: 'pl-json-${DateTime.now().millisecondsSinceEpoch}',
        name: data['name']?.toString() ?? 'Playlist Impor',
        cover: data['cover']?.toString() ?? MusicApiService.defaultArtwork,
        tracks: tracks,
      );
    } catch (e) {
      throw Exception('Gagal membaca file JSON: $e');
    }
  }

  /// Export playlist to JSON string
  String exportToJson(Playlist playlist) {
    final map = {
      'id': playlist.id,
      'name': playlist.name,
      'cover': playlist.cover,
      'exportedAt': DateTime.now().toIso8601String(),
      'tracks': playlist.tracks
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'artist': t.artist,
                'album': t.album,
                'artwork': t.artwork,
                'audioUrl': t.audioUrl,
                'videoId': t.videoId,
                'duration': t.duration,
                'streamCount': t.streamCount,
                'isExplicit': t.isExplicit,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Helper to match raw items with high-resolution metadata
  Future<Playlist> _resolveTrackList(
    List<Map<String, String>> rawItems, {
    required String playlistName,
    required String cover,
    ImportProgressCallback? onProgress,
  }) async {
    final List<Track> resolvedTracks = [];
    final total = rawItems.length;

    for (int i = 0; i < total; i++) {
      final item = rawItems[i];
      final title = item['title'] ?? '';
      final artist = item['artist'] ?? '';
      final explicitVid = item['videoId'];
      final explicitDur = int.tryParse(item['duration'] ?? '');

      onProgress?.call(i + 1, total, 'Mencocokkan lagu (${i + 1}/$total): "$title"...');

      try {
        // Search track in regional database for cover art & album info
        final matches = await _apiService.searchTracks('$title $artist'.trim());
        Track? bestTrack;
        if (matches.isNotEmpty) {
          bestTrack = matches.first;
        }

        if (bestTrack != null) {
          resolvedTracks.add(Track(
            id: bestTrack.id,
            title: bestTrack.title,
            artist: bestTrack.artist,
            album: bestTrack.album,
            artwork: bestTrack.artwork,
            audioUrl: bestTrack.audioUrl,
            videoId: explicitVid ?? bestTrack.videoId,
            duration: explicitDur ?? bestTrack.duration,
            streamCount: bestTrack.streamCount,
            isExplicit: bestTrack.isExplicit,
          ));
        } else {
          resolvedTracks.add(Track(
            id: 'imp-${DateTime.now().millisecondsSinceEpoch}-$i',
            title: title,
            artist: artist.isNotEmpty ? artist : 'Unknown Artist',
            album: playlistName,
            artwork: cover.isNotEmpty ? cover : MusicApiService.defaultArtwork,
            audioUrl: '',
            videoId: explicitVid,
            duration: explicitDur ?? 180,
            streamCount: '500.000',
            isExplicit: false,
          ));
        }
      } catch (_) {
        resolvedTracks.add(Track(
          id: 'imp-${DateTime.now().millisecondsSinceEpoch}-$i',
          title: title,
          artist: artist.isNotEmpty ? artist : 'Unknown Artist',
          album: playlistName,
          artwork: cover.isNotEmpty ? cover : MusicApiService.defaultArtwork,
          audioUrl: '',
          videoId: explicitVid,
          duration: explicitDur ?? 180,
          streamCount: '500.000',
          isExplicit: false,
        ));
      }

      // Small throttling delay to avoid rate limits
      if (i < total - 1 && i % 4 == 0) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    final finalCover = resolvedTracks.isNotEmpty && resolvedTracks.first.artwork.isNotEmpty
        ? resolvedTracks.first.artwork
        : cover;

    return Playlist(
      id: 'pl-imp-${DateTime.now().millisecondsSinceEpoch}',
      name: playlistName,
      cover: finalCover,
      tracks: resolvedTracks,
    );
  }

  /// Preset playlists ready for 1-click import
  List<Map<String, dynamic>> getPresets() {
    return [
      {
        'id': 'preset-today-top-hits',
        'name': "Today's Top Hits (Global)",
        'description': 'Lagu-lagu terpopuler di chart global saat ini',
        'cover': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=600',
        'text': '''Taylor Swift - Cruel Summer
Billie Eilish - Birds of a Feather
Lady Gaga & Bruno Mars - Die With A Smile
The Weeknd - Blinding Lights
Coldplay - Yellow
Sabrina Carpenter - Espresso
Kendrick Lamar - Not Like Us
Chappell Roan - Good Luck, Babe!''',
      },
      {
        'id': 'preset-indo-hits',
        'name': 'Hits Pop Indonesia',
        'description': 'Lagu pop Indonesia terfavorit & viral saat ini',
        'cover': 'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?auto=format&fit=crop&q=80&w=600',
        'text': '''Bernadya - Satu Bulan
Nadin Amizah - Rayuan Perempuan Gila
Mahalini - Sial
Sal Priadi - Dari planet lain
Tulus - Hati-Hati di Jalan
Tiara Andini - Kupu-Kupu
Juicy Luicy - Lantas
Hindia - Rumah Ke Rumah''',
      },
      {
        'id': 'preset-lofi-chill',
        'name': 'Lo-Fi Chill & Focus',
        'description': 'Irama santai untuk menemani belajar dan bekerja',
        'cover': 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=600',
        'text': '''Lofi Fruits Music - Better Days
ChilledCow - Snowman
Kudasaibeats - The Girl I Haven't Met
Jinsang - Affection
Idealism - Lonely
Saib - Sakura Trees''',
      },
      {
        'id': 'preset-yt-music-pop',
        'name': 'Trending YouTube Music',
        'description': 'Hits viral yang paling banyak diputar di YouTube',
        'cover': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600',
        'text': '''The Weeknd - Save Your Tears
Coldplay - Fix You
Dua Lipa - Levitating
Post Malone - Circles
Harry Styles - As It Was
Ed Sheeran - Shape of You''',
      },
    ];
  }
}
