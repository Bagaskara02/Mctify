import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'transition_engine.dart';

class StorageService {
  static const String _keyLiked = 'mcmusic_liked_tracks';
  static const String _keyPlaylists = 'mcmusic_playlists';
  static const String _keyHistory = 'mcmusic_history';
  static const String _keyPlayCounts = 'mcmusic_play_counts';

  /// Live notifier whenever playlists or liked tracks change
  static final ValueNotifier<int> playlistRevision = ValueNotifier<int>(0);

  Future<List<Track>> getLikedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLiked);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final rawList = list.map((e) => Track.fromJson(e)).toList();
      final seen = <String>{};
      final unique = <Track>[];
      for (final t in rawList) {
        final key = '${t.title.trim().toLowerCase()}_${t.artist.trim().toLowerCase()}';
        if (!seen.contains(key)) {
          seen.add(key);
          final hasPreview = t.audioUrl.contains('preview') ||
              t.audioUrl.contains('p.scdn.co') ||
              t.audioUrl.contains('mzstatic.com');
          if (hasPreview) {
            unique.add(Track(
              id: t.id,
              title: t.title,
              artist: t.artist,
              album: t.album,
              artwork: t.artwork,
              audioUrl: '', // Stripped 30s preview
              videoId: t.videoId,
              duration: t.duration,
              streamCount: t.streamCount,
              isExplicit: t.isExplicit,
            ));
          } else {
            unique.add(t);
          }
        }
      }
      return unique;
    } catch (_) {
      return [];
    }
  }

  Future<void> toggleLikeTrack(Track track) async {
    final prefs = await SharedPreferences.getInstance();
    final liked = await getLikedTracks();
    final index = liked.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      liked.removeAt(index);
    } else {
      liked.insert(0, track);
    }
    await prefs.setString(_keyLiked, jsonEncode(liked.map((t) => t.toJson()).toList()));
    playlistRevision.value++;
  }

  Future<bool> isTrackLiked(String trackId) async {
    final liked = await getLikedTracks();
    return liked.any((t) => t.id == trackId);
  }

  Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPlaylists);
    if (raw == null) {
      return [
        Playlist(
          id: 'pl-chill',
          name: 'Late Night Chill',
          description: 'Mellow melodies, ambient beats, and soothing vocals',
          cover: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
          tracks: [],
        )
      ];
    }
    try {
      final list = jsonDecode(raw) as List;
      final rawPlaylists = list.map((e) => Playlist.fromJson(e)).toList();

      final Map<String, Playlist> uniqueById = {};
      bool needsRewrite = false;

      for (final p in rawPlaylists) {
        final seenTracks = <String>{};
        final cleanedTracks = <Track>[];
        for (final t in p.tracks) {
          final hasVid = t.videoId != null && t.videoId!.trim().isNotEmpty;
          final trackKey = hasVid
              ? 'vid_${t.videoId!.trim()}'
              : '${t.title.trim().toLowerCase()}_${t.artist.trim().toLowerCase()}';
          if (!seenTracks.contains(trackKey)) {
            seenTracks.add(trackKey);
            final hasPreview = t.audioUrl.contains('preview') ||
                t.audioUrl.contains('p.scdn.co') ||
                t.audioUrl.contains('mzstatic.com');
            final sanitizedArt = Track.toHighResArtwork(t.artwork, fallbackVideoId: t.videoId);
            final artWasBroken = sanitizedArt != t.artwork;
            if (hasPreview || artWasBroken) {
              needsRewrite = true;
              cleanedTracks.add(Track(
                id: t.id,
                title: t.title,
                artist: t.artist,
                album: t.album,
                artwork: sanitizedArt,
                audioUrl: hasPreview ? '' : t.audioUrl,
                videoId: t.videoId,
                duration: t.duration,
                streamCount: t.streamCount,
                isExplicit: t.isExplicit,
              ));
            } else {
              cleanedTracks.add(t);
            }
          } else {
            needsRewrite = true;
          }
        }

        final healedCover = Playlist.sanitizeCover(p.cover, cleanedTracks);
        if (healedCover != p.cover) {
          needsRewrite = true;
        }

        final cleanedPlaylist = Playlist(
          id: p.id,
          name: p.name,
          description: p.description,
          cover: healedCover,
          tracks: cleanedTracks,
        );

        final idKey = p.id.trim().isNotEmpty ? p.id.trim() : p.name.trim().toLowerCase();
        if (!uniqueById.containsKey(idKey)) {
          uniqueById[idKey] = cleanedPlaylist;
        } else {
          needsRewrite = true;
          final existing = uniqueById[idKey]!;
          if (cleanedTracks.length > existing.tracks.length) {
            uniqueById[idKey] = cleanedPlaylist;
          }
        }
      }

      final result = uniqueById.values.toList();
      if (needsRewrite || result.length != rawPlaylists.length) {
        savePlaylists(result);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlaylists, jsonEncode(playlists.map((p) => p.toJson()).toList()));
    playlistRevision.value++;
  }

  Future<Playlist?> updatePlaylistDetails(String playlistId, {String? name, String? cover, String? description}) async {
    final all = await getPlaylists();
    final idx = all.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final old = all[idx];
      final sanitizedCover = (cover != null && cover.trim().isNotEmpty)
          ? Track.toHighResArtwork(cover.trim())
          : old.cover;
      final updated = Playlist(
        id: old.id,
        name: (name != null && name.trim().isNotEmpty) ? name.trim() : old.name,
        cover: sanitizedCover.isNotEmpty ? sanitizedCover : old.cover,
        description: description ?? old.description,
        tracks: old.tracks,
      );
      all[idx] = updated;
      await savePlaylists(all);
      return updated;
    }
    return null;
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final all = await getPlaylists();
    final idx = all.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final pl = all[idx];
      if (!pl.tracks.any((t) => t.id == track.id)) {
        final updatedTracks = [...pl.tracks, track];
        final updatedPlaylist = Playlist(
          id: pl.id,
          name: pl.name,
          description: pl.description,
          cover: pl.cover.contains('unsplash') && track.artwork.isNotEmpty
              ? track.artwork
              : pl.cover,
          tracks: updatedTracks,
        );
        all[idx] = updatedPlaylist;
        await savePlaylists(all);
      }
    }
  }

  Future<List<Track>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyHistory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final rawList = list.map((e) => Track.fromJson(e)).toList();
      final seen = <String>{};
      final unique = <Track>[];
      for (final t in rawList) {
        final key = '${t.title.trim().toLowerCase()}_${t.artist.trim().toLowerCase()}';
        if (!seen.contains(key)) {
          seen.add(key);
          unique.add(t);
        }
      }
      return unique;
    } catch (_) {
      return [];
    }
  }

  Future<void> recordPlay(Track track) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.removeWhere((t) => t.id == track.id);
    history.insert(0, track);
    if (history.length > 50) history.removeLast();
    await prefs.setString(_keyHistory, jsonEncode(history.map((t) => t.toJson()).toList()));

    // Increment play counts
    try {
      final rawCounts = prefs.getString(_keyPlayCounts);
      final Map<String, int> counts = rawCounts != null ? Map<String, int>.from(jsonDecode(rawCounts)) : {};
      counts[track.artist] = (counts[track.artist] ?? 0) + 1;
      await prefs.setString(_keyPlayCounts, jsonEncode(counts));
    } catch (_) {}
  }

  Future<String?> getTopArtist() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCounts = prefs.getString(_keyPlayCounts);
    if (rawCounts == null) return null;
    try {
      final Map<String, dynamic> counts = jsonDecode(rawCounts);
      if (counts.isEmpty) return null;
      var sorted = counts.entries.toList()..sort((a, b) => (b.value as int).compareTo(a.value as int));
      return sorted.first.key;
    } catch (_) {
      return null;
    }
  }

  static const String _keyAudioQuality = 'mcmusic_audio_quality';

  Future<String> getAudioQuality() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAudioQuality) ?? 'high';
  }

  Future<void> setAudioQuality(String quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAudioQuality, quality);
  }

  static const String _keyLyricsSyncPrefix = 'mcmusic_lyrics_sync_';

  Future<double> getLyricsSyncOffset(String trackKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('$_keyLyricsSyncPrefix$trackKey') ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> setLyricsSyncOffset(String trackKey, double offset) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rounded = (offset * 10).roundToDouble() / 10.0;
      await prefs.setDouble('$_keyLyricsSyncPrefix$trackKey', rounded);
    } catch (_) {}
  }

  static const String _keyRecentSearches = 'mctify_recent_searches';

  Future<List<Map<String, String>>> getRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRecentSearches);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addRecentSearch({
    required String query,
    String title = '',
    String subtitle = '',
    String artwork = '',
    String type = 'query',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getRecentSearches();
      current.removeWhere((item) =>
          (item['query'] ?? '').toLowerCase() == trimmed.toLowerCase() &&
          (item['type'] ?? 'query') == type);
      current.insert(0, {
        'query': trimmed,
        'title': title.isNotEmpty ? title : trimmed,
        'subtitle': subtitle,
        'artwork': artwork,
        'type': type,
      });
      if (current.length > 15) {
        current.removeRange(15, current.length);
      }
      await prefs.setString(_keyRecentSearches, jsonEncode(current));
    } catch (_) {}
  }

  Future<void> removeRecentSearch(String query, {String? type}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getRecentSearches();
      current.removeWhere((item) =>
          (item['query'] ?? '').toLowerCase() == query.toLowerCase() &&
          (type == null || item['type'] == type));
      await prefs.setString(_keyRecentSearches, jsonEncode(current));
    } catch (_) {}
  }

  Future<void> clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyRecentSearches);
    } catch (_) {}
  }

  static const String _keyLastSession = 'mcmusic_last_playback_session_v1';

  Future<void> savePlaybackSession({
    required Track currentTrack,
    required Duration position,
    required List<Track> queue,
    required int queueIndex,
    required bool isShuffle,
    required bool isRepeat,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Cap saved queue to at most 50 tracks centered around active track
      List<Track> trimmedQueue = queue;
      int adjustedIndex = queueIndex;
      if (queue.length > 50) {
        final safeIdx = queueIndex.clamp(0, queue.length - 1);
        final start = (safeIdx - 20).clamp(0, queue.length - 50);
        final end = (start + 50).clamp(start, queue.length);
        trimmedQueue = queue.sublist(start, end);
        adjustedIndex = (safeIdx - start).clamp(0, trimmedQueue.length - 1);
      }

      final payload = {
        'track': currentTrack.toJson(),
        'positionMs': position.inMilliseconds < 0 ? 0 : position.inMilliseconds,
        'queue': trimmedQueue.map((t) => t.toJson()).toList(),
        'queueIndex': adjustedIndex,
        'isShuffle': isShuffle,
        'isRepeat': isRepeat,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_keyLastSession, jsonEncode(payload));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadPlaybackSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyLastSession);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final trackRaw = decoded['track'];
      if (trackRaw is! Map) return null;
      final track = Track.fromJson(Map<String, dynamic>.from(trackRaw));
      if (track.title.isEmpty) return null;

      final queueRaw = decoded['queue'] as List? ?? [];
      final queue = queueRaw
          .whereType<Map>()
          .map((m) => Track.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final posMs = (decoded['positionMs'] as num?)?.toInt() ?? 0;
      final qIdx = (decoded['queueIndex'] as num?)?.toInt() ?? 0;

      return {
        'track': track,
        'positionMs': posMs < 0 ? 0 : posMs,
        'queue': queue.isNotEmpty ? queue : <Track>[track],
        'queueIndex': qIdx,
        'isShuffle': decoded['isShuffle'] == true,
        'isRepeat': decoded['isRepeat'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  static const String _keyTransitionSettings = 'mcmusic_transition_settings_v1';
  static const String _keyTransitionPairs = 'mcmusic_transition_pairs_v1';

  static String _pairKey(Track? outgoing, Track? incoming) {
    String norm(Track? t) {
      if (t == null) return 'none';
      if (t.id.isNotEmpty) return t.id.trim().toLowerCase();
      return '${t.title.trim().toLowerCase()}|${t.artist.trim().toLowerCase()}';
    }
    return '${norm(outgoing)}__to__${norm(incoming)}';
  }

  Future<TransitionConfig> getTransitionSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyTransitionSettings);
      if (raw == null || raw.isEmpty) return const TransitionConfig();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const TransitionConfig();
      return TransitionConfig.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const TransitionConfig();
    }
  }

  Future<TransitionConfig> saveTransitionSettings(TransitionConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTransitionSettings, jsonEncode(config.toJson()));
    } catch (_) {}
    return config;
  }

  Future<TransitionConfig> getTransitionForPair(Track? outgoing, Track? incoming) async {
    final base = await getTransitionSettings();
    final metaA = TransitionEngine.computeTrackBpmAndKey(outgoing);
    final metaB = TransitionEngine.computeTrackBpmAndKey(incoming);

    if (outgoing == null || incoming == null) {
      return base.copyWith(bpmA: metaA.bpm, bpmB: metaB.bpm);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyTransitionPairs);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final key = _pairKey(outgoing, incoming);
          final pairEntry = decoded[key];
          if (pairEntry is Map) {
            return TransitionConfig.fromJson({
              ...base.toJson(),
              ...Map<String, dynamic>.from(pairEntry),
              'bpmA': metaA.bpm,
              'bpmB': metaB.bpm,
              'pairKey': key,
            });
          }
        }
      }
    } catch (_) {}

    final barStats = TransitionEngine.computeBarDurationSec(metaA.bpm, metaB.bpm, base.bars);
    return base.copyWith(
      durationSec: barStats.durationSec,
      bpmA: metaA.bpm,
      bpmB: metaB.bpm,
    );
  }

  Future<TransitionConfig> saveTransitionForPair(
    Track? outgoing,
    Track? incoming,
    TransitionConfig config,
  ) async {
    final savedGlobal = await saveTransitionSettings(config);
    if (outgoing == null || incoming == null) return savedGlobal;

    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {};
      final raw = prefs.getString(_keyTransitionPairs);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }

      final key = _pairKey(outgoing, incoming);
      map[key] = {
        ...savedGlobal.toJson(),
        'pairKey': key,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      final keys = map.keys.toList();
      if (keys.length > 60) {
        map.remove(keys.first);
      }

      await prefs.setString(_keyTransitionPairs, jsonEncode(map));
      return savedGlobal.copyWith(pairKey: key);
    } catch (_) {
      return savedGlobal;
    }
  }
}
