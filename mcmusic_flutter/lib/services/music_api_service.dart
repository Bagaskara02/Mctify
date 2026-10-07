import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/artist.dart';

class MusicApiService {
  static const String defaultArtwork = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600';

  // Specific Tenxi Official Tracks matching Spotify screenshot media_1791353080300.png
  static final List<Track> tenxiTracks = [
    Track(
      id: 'tenxi-garam-madu',
      title: 'Garam & Madu (Sakit Dadaku)',
      artist: 'Tenxi',
      album: 'Garam & Madu (Sakit Dadaku)',
      artwork: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=600',
      audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/6b/ab/5c/6bab5c20-fbc1-9c2c-11b8-53f6f994a7bd/mzaf_9285225600682075380.plus.aac.p.m4a',
      duration: 184,
      streamCount: '310.756.981',
      isExplicit: false,
    ),
    Track(
      id: 'tenxi-mejikuhibiniu',
      title: 'mejikuhibiniu',
      artist: 'Tenxi',
      album: 'mejikuhibiniu',
      artwork: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=600',
      audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/53/3c/9e/533c9ed8-91e6-5178-d9b6-f4290e0bdb73/mzaf_13510159447515678936.plus.aac.p.m4a',
      duration: 196,
      streamCount: '207.620.762',
      isExplicit: true,
    ),
    Track(
      id: 'tenxi-kasih-aba-aba',
      title: 'Kasih Aba Aba',
      artist: 'Naykilla',
      album: 'Kasih Aba Aba',
      artwork: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=600',
      audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/ce/74/f3/ce74f32a-9a2c-fa0a-6f6b-63491cd5a8e3/mzaf_6060131703371369042.plus.aac.p.m4a',
      duration: 176,
      streamCount: '226.808.384',
      isExplicit: false,
    ),
    Track(
      id: 'tenxi-bintang-5',
      title: 'Bintang 5',
      artist: 'Tenxi',
      album: 'Puting Beliung',
      artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=600',
      audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/6b/ab/5c/6bab5c20-fbc1-9c2c-11b8-53f6f994a7bd/mzaf_9285225600682075380.plus.aac.p.m4a',
      duration: 246,
      streamCount: '114.835.312',
      isExplicit: false,
    ),
    Track(
      id: 'tenxi-berubah',
      title: 'Berubah',
      artist: 'Tenxi',
      album: 'Puting Beliung',
      artwork: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=600',
      audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/ce/74/f3/ce74f32a-9a2c-fa0a-6f6b-63491cd5a8e3/mzaf_6060131703371369042.plus.aac.p.m4a',
      duration: 185,
      streamCount: '89.412.050',
      isExplicit: false,
    ),
  ];

  // Specific Artists matching Spotify Screenshot media_1791353069505.png
  static final List<Artist> catalogArtists = [
    Artist(
      id: 'art-tenxi',
      name: 'Tenxi',
      headerBanner: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '4,9 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-naykilla',
      name: 'Naykilla',
      headerBanner: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '2,8 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-indahkus',
      name: 'INDAHKUS',
      headerBanner: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '1,5 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-dia',
      name: 'dia',
      headerBanner: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '1,2 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-jemsii',
      name: 'Jemsii',
      headerBanner: 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1501386761578-eac5c94b800a?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '980 rb pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-suisei',
      name: 'Suisei',
      headerBanner: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '850 rb pendengar bulanan',
      isVerified: true,
    ),
  ];

  // Search tracks across query
  Future<List<Track>> searchTracks(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return [];

    final List<Track> results = [];

    // 1. Check local catalog first (Tenxi, mejikuhibiniu, etc.)
    for (final t in tenxiTracks) {
      if (t.title.toLowerCase().contains(cleanQ) || t.artist.toLowerCase().contains(cleanQ)) {
        results.add(t);
      }
    }

    // 2. Query iTunes ID regional API
    try {
      final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&country=ID&entity=song&limit=25');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['results'] as List? ?? []);
        for (final item in list) {
          final title = item['trackName'] ?? '';
          final artist = item['artistName'] ?? '';
          if (title.isNotEmpty) {
            String art = item['artworkUrl100'] ?? defaultArtwork;
            art = art.replaceAll('100x100bb', '600x600bb');
            results.add(Track(
              id: (item['trackId'] ?? '').toString(),
              title: title,
              artist: artist,
              album: item['collectionName'] ?? 'Single',
              artwork: art,
              audioUrl: item['previewUrl'] ?? '',
              duration: item['trackTimeMillis'] != null ? (item['trackTimeMillis'] / 1000).round() : 180,
              streamCount: '${(100 + results.length * 15)}.000.000',
              isExplicit: item['trackExplicitness'] == 'explicit',
            ));
          }
        }
      }
    } catch (_) {}

    return results;
  }

  // Search Artists matching query
  Future<List<Artist>> searchArtists(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return catalogArtists;

    final matched = catalogArtists.where((a) => a.name.toLowerCase().contains(cleanQ)).toList();
    if (matched.isNotEmpty) return matched;

    // Fallback generate from query
    return [
      Artist(
        id: 'art-${Uri.encodeComponent(query)}',
        name: query,
        headerBanner: defaultArtwork,
        avatar: defaultArtwork,
        monthlyListeners: '3,2 jt pendengar bulanan',
        isVerified: true,
      ),
      ...catalogArtists.take(4),
    ];
  }

  // Get Artist Profile Details & Popular Songs
  Future<Map<String, dynamic>> getArtistDetails(String artistName) async {
    final clean = artistName.toLowerCase().trim();
    Artist artist = catalogArtists.firstWhere(
      (a) => a.name.toLowerCase() == clean,
      orElse: () => Artist(
        id: 'art-${Uri.encodeComponent(artistName)}',
        name: artistName,
        headerBanner: defaultArtwork,
        avatar: defaultArtwork,
        monthlyListeners: '4,9 jt pendengar bulanan',
        isVerified: true,
      ),
    );

    List<Track> topSongs = [];
    if (clean.contains('tenxi')) {
      topSongs = tenxiTracks;
    } else {
      topSongs = await searchTracks(artistName);
      if (topSongs.isEmpty) {
        topSongs = tenxiTracks;
      }
    }

    return {
      'artist': artist,
      'topSongs': topSongs,
    };
  }

  // Fetch Trending / Starter Tracks
  Future<List<Track>> getTrendingTracks() async {
    return [
      ...tenxiTracks,
      Track(
        id: 'coldplay-yellow',
        title: 'Yellow',
        artist: 'Coldplay',
        album: 'Parachutes',
        artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600',
        audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/6b/ab/5c/6bab5c20-fbc1-9c2c-11b8-53f6f994a7bd/mzaf_9285225600682075380.plus.aac.p.m4a',
        duration: 269,
        streamCount: '2.140.890.120',
      ),
      Track(
        id: 'the-weeknd-blinding-lights',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        artwork: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=600',
        audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/ce/74/f3/ce74f32a-9a2c-fa0a-6f6b-63491cd5a8e3/mzaf_6060131703371369042.plus.aac.p.m4a',
        duration: 200,
        streamCount: '3.890.100.540',
      ),
      Track(
        id: 'taylor-swift-cruel-summer',
        title: 'Cruel Summer',
        artist: 'Taylor Swift',
        album: 'Lover',
        artwork: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=600',
        audioUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/53/3c/9e/533c9ed8-91e6-5178-d9b6-f4290e0bdb73/mzaf_13510159447515678936.plus.aac.p.m4a',
        duration: 178,
        streamCount: '1.980.200.410',
      ),
    ];
  }
}
