import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/artist_card.dart';
import '../widgets/import_youtube_dialog.dart';
import '../widgets/optimized_image.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/track_action_sheet.dart';
import 'artist_view.dart';
import 'playlist_detail_view.dart';

class SearchView extends StatefulWidget {
  final AudioPlayerManager player;

  const SearchView({
    super.key,
    required this.player,
  });

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final MusicApiService _api = MusicApiService();
  final StorageService _storage = StorageService();

  Timer? _debounceTimer;
  Timer? _suggestTimer;
  int _searchToken = 0;

  String _selectedTab = 'Semua'; // Semua, Lagu, Artis, Album, Playlist, Lirik
  bool _isSearchFocused = false;
  List<Track> _searchResults = [];
  List<Artist> _artistResults = [];
  List<String> _suggestions = [];
  List<Playlist> _userPlaylists = [];
  List<Map<String, String>> _recentSearches = [];
  bool _isLoading = false;
  final Set<String> _likedIds = {};

  final List<Map<String, dynamic>> _genreCategories = [
    {
      'name': 'Pop Hits',
      'query': 'Pop Hits Terbaru 2025',
      'color': const Color(0xFFE13300),
      'image': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Indo Terbaik',
      'query': 'Lagu Indonesia Populer Tulus Bernadya',
      'color': const Color(0xFF006450),
      'image': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'K-Pop ON!',
      'query': 'K-Pop Hits NewJeans BTS',
      'color': const Color(0xFF8D67AB),
      'image': 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Hip-Hop & Rap',
      'query': 'Hip Hop Rap Kendrick Drake',
      'color': const Color(0xFFBA5D07),
      'image': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Dibuat Untukmu',
      'query': 'Rex Orange County Daniel Caesar Joji',
      'color': const Color(0xFF1E3264),
      'image': 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Chill & Lofi',
      'query': 'Chill Lofi Beats Acoustic',
      'color': const Color(0xFF27856A),
      'image': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'R&B & Soul',
      'query': 'R&B Soul Frank Ocean SZA NIKI',
      'color': const Color(0xFFDC148C),
      'image': 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Rock & Alt',
      'query': 'Rock Alternative Coldplay Arctic Monkeys',
      'color': const Color(0xFFE91429),
      'image': 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Galau & Senja',
      'query': 'Lagu Galau Akustik Indonesia',
      'color': const Color(0xFF477D95),
      'image': 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Dance & EDM',
      'query': 'Electronic Dance Calvin Harris Fred Again',
      'color': const Color(0xFF0077C2),
      'image': 'https://images.unsplash.com/photo-1571266028243-d220c6a22db2?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Rilis Terbaru',
      'query': 'New Music Release Hits 2025',
      'color': const Color(0xFF7D4B32),
      'image': 'https://images.unsplash.com/photo-1487180144351-b8472da7d491?auto=format&fit=crop&q=80&w=240',
    },
    {
      'name': 'Cari Lewat Lirik',
      'query': 'take a chance with me niki',
      'color': const Color(0xFF503750),
      'image': 'https://images.unsplash.com/photo-1511379938547-c1f69419868d?auto=format&fit=crop&q=80&w=240',
      'forceLyrics': true,
    },
  ];

  final List<String> _lyricChips = [
    'if you want me take a chance',
    'hati-hati di jalan',
    'ooh i am blinded by the lights',
    'ku selalu bahagia saat bersamamu',
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _searchFocus.addListener(_onFocusChanged);
    StorageService.playlistRevision.addListener(_loadInitialData);
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() => _isSearchFocused = _searchFocus.hasFocus);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _suggestTimer?.cancel();
    _searchFocus.removeListener(_onFocusChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    StorageService.playlistRevision.removeListener(_loadInitialData);
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final liked = await _storage.getLikedTracks();
    final playlists = await _storage.getPlaylists();
    final recent = await _storage.getRecentSearches();
    if (mounted) {
      setState(() {
        _likedIds.clear();
        _likedIds.addAll(liked.map((t) => t.id));
        _userPlaylists = playlists;
        _recentSearches = recent;
        _artistResults = MusicApiService.catalogArtists;
      });
    }
  }

  Future<void> _saveSearchHistory({
    required String query,
    String title = '',
    String subtitle = '',
    String artwork = '',
    String type = 'query',
  }) async {
    await _storage.addRecentSearch(
      query: query,
      title: title,
      subtitle: subtitle,
      artwork: artwork,
      type: type,
    );
    final updated = await _storage.getRecentSearches();
    if (mounted) {
      setState(() => _recentSearches = updated);
    }
  }

  void _onSearch(String query, {bool forceLyrics = false}) {
    _debounceTimer?.cancel();
    _suggestTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchToken++;
      setState(() {
        _searchResults = [];
        _artistResults = MusicApiService.catalogArtists;
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    final currentToken = ++_searchToken;
    // Fast Spotify-style typeahead autocomplete suggestions
    _suggestTimer = Timer(const Duration(milliseconds: 120), () async {
      try {
        final sugs = await _api.getSearchSuggestions(trimmed);
        if (mounted && currentToken == _searchToken) {
          setState(() => _suggestions = sugs);
        }
      } catch (_) {}
    });

    _debounceTimer = Timer(const Duration(milliseconds: 220), () async {
      try {
        late Future<List<Track>> tracksFuture;
        if (forceLyrics || _selectedTab == 'Lirik') {
          tracksFuture = _api.searchTracksByLyrics(trimmed);
        } else {
          tracksFuture = _api.searchTracks(trimmed);
        }
        final artistsFuture = _api.searchArtists(trimmed);

        final results = await Future.wait([tracksFuture, artistsFuture]);
        final tracks = results[0] as List<Track>;
        final artists = results[1] as List<Artist>;

        if (mounted && currentToken == _searchToken) {
          setState(() {
            _searchResults = tracks;
            _artistResults = artists;
            _isLoading = false;
          });
          if (tracks.isNotEmpty) {
            widget.player.prewarmTracks(tracks.take(2).toList());
          }
        }
      } catch (_) {
        if (mounted && currentToken == _searchToken) {
          setState(() => _isLoading = false);
        }
      }
    });
  }

  void _triggerQuickQuery(String query, {bool forceLyrics = false}) {
    HapticFeedback.lightImpact();
    _searchController.text = query;
    if (forceLyrics) {
      _selectedTab = 'Lirik';
    }
    _onSearch(query, forceLyrics: forceLyrics);
    _saveSearchHistory(query: query, title: query, subtitle: 'Pencarian');
  }

  void _toggleLike(Track track) async {
    HapticFeedback.lightImpact();
    await _storage.toggleLikeTrack(track);
    setState(() {
      if (_likedIds.contains(track.id)) {
        _likedIds.remove(track.id);
      } else {
        _likedIds.add(track.id);
      }
    });
  }

  void _openArtist(Artist artist) {
    _saveSearchHistory(
      query: artist.name,
      title: artist.name,
      subtitle: 'Artis',
      artwork: artist.avatar,
      type: 'artist',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArtistView(
          artist: artist,
          player: widget.player,
        ),
      ),
    );
  }

  List<_AlbumGroup> _buildAlbumGroups() {
    final map = <String, _AlbumGroup>{};
    for (final t in _searchResults) {
      final albumName = t.album.trim().isNotEmpty && !t.album.startsWith('Lirik:')
          ? t.album.trim()
          : t.title;
      final key = '${albumName.toLowerCase()}_${t.artist.toLowerCase()}';
      if (!map.containsKey(key)) {
        map[key] = _AlbumGroup(
          title: albumName,
          artist: t.artist,
          artwork: t.artwork,
          tracks: [t],
        );
      } else {
        map[key]!.tracks.add(t);
      }
    }
    return map.values.toList();
  }

  bool _shouldShowArtistAsTopResult(String query) {
    if (_artistResults.isEmpty) return false;
    final cleanQ = query.trim().toLowerCase();
    final topArtist = _artistResults.first;
    final topArtistName = topArtist.name.toLowerCase();
    final topTrack = _searchResults.isNotEmpty ? _searchResults.first : null;

    final isExactArtist = topArtistName == cleanQ;
    final isStrongPrefix =
        topArtistName.startsWith(cleanQ) && cleanQ.length >= 3 && cleanQ.split(' ').length <= 2;
    if (!isExactArtist && !isStrongPrefix) return false;

    if (topTrack != null) {
      final trackTitleLower = topTrack.title.toLowerCase();
      final trackArtistLower = topTrack.artist.toLowerCase();
      final primaryArtist = trackArtistLower.split(',').first.trim();
      final trackMatchesArtist =
          trackArtistLower.contains(topArtistName) || topArtistName.contains(primaryArtist);

      // If the top track title is an exact match (e.g. "Yellow", "Hello", "Perfect")
      // for a different artist, promote the track as Top Result instead of the namesake artist.
      if ((trackTitleLower == cleanQ || trackTitleLower.startsWith('$cleanQ (')) &&
          !trackMatchesArtist) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Spotify Authentic Header: Title + Quick YouTube URL Import
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryAzure,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Colors.black, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Cari',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          showImportYouTubeDialog(context: context, player: widget.player);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF242428),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.play_circle_fill_rounded, color: Color(0xFFFF4E4E), size: 16),
                              SizedBox(width: 5),
                              Text(
                                'YouTube URL',
                                style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Signature White Spotify Search Input Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (val) => _onSearch(val),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      _saveSearchHistory(query: val.trim(), title: val.trim(), subtitle: 'Pencarian');
                    }
                  },
                  style: const TextStyle(color: Colors.black, fontSize: 14.5, fontWeight: FontWeight.w700),
                  cursorColor: Colors.black,
                  decoration: InputDecoration(
                    hintText: 'Apa yang ingin kamu dengarkan?',
                    hintStyle: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w600),
                    prefixIcon: (_isSearchFocused || isSearching)
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87, size: 22),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                              _searchFocus.unfocus();
                            },
                          )
                        : const Icon(Icons.search_rounded, color: Colors.black87, size: 24),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.black87, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.mic_none_rounded, color: Colors.black54, size: 22),
                            tooltip: 'Cari lewat penggalan lirik',
                            onPressed: () {
                              setState(() => _selectedTab = 'Lirik');
                              _searchFocus.requestFocus();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ketik penggalan lirik lagu apa saja untuk mencari!'),
                                  duration: Duration(milliseconds: 1400),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Filter Pills Bar when searching (Exact Spotify Search Filter Chips)
            if (isSearching)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ['Semua', 'Lagu', 'Artis', 'Album', 'Playlist', 'Lirik'].map((tab) {
                    final isSelected = _selectedTab == tab;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedTab = tab);
                          if (_searchController.text.trim().isNotEmpty && tab == 'Lirik') {
                            _onSearch(_searchController.text, forceLyrics: true);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryAzure : const Color(0xFF242426),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              tab == 'Lirik' ? '🎙️ Lirik' : tab,
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Live Spotify Autocomplete Suggestions Strip while typing
            if (isSearching && _suggestions.isNotEmpty)
              Container(
                height: 36,
                margin: const EdgeInsets.only(top: 6, bottom: 2),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _suggestions.take(6).length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final sug = _suggestions[idx];
                    return GestureDetector(
                      onTap: () => _triggerQuickQuery(sug),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1C20),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              sug,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(Icons.north_west_rounded, color: AppTheme.textMuted, size: 13),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Body Content
            Expanded(
              child: _isLoading
                  ? _buildSearchSkeleton()
                  : isSearching
                      ? _buildSearchResults()
                      : (_isSearchFocused ? _buildFocusedRecentView() : _buildBrowseCategories()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
      children: [
        const ShimmerBox(width: 120, height: 18),
        const SizedBox(height: 10),
        const ShimmerBox(width: double.infinity, height: 140, borderRadius: BorderRadius.all(Radius.circular(12))),
        const SizedBox(height: 20),
        const ShimmerBox(width: 90, height: 18),
        const SizedBox(height: 10),
        ...List.generate(
          6,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: const [
                ShimmerBox(width: 48, height: 48, borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 180, height: 14),
                      SizedBox(height: 6),
                      ShimmerBox(width: 110, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Focused Search Mode (Exact Spotify Mobile: tap Search -> shows Recent Searches cleanly)
  Widget _buildFocusedRecentView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pencarian Terkini',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await _storage.clearRecentSearches();
                  setState(() => _recentSearches = []);
                },
                child: const Text(
                  'Hapus semua',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._recentSearches.take(8).map((item) {
            final q = item['query'] ?? '';
            final title = item['title'] ?? q;
            final subtitle = item['subtitle'] ?? 'Pencarian';
            final artwork = item['artwork'] ?? '';
            final isArtist = item['type'] == 'artist';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 2),
              leading: artwork.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(isArtist ? 24 : 6),
                      child: OptimizedImage(
                        imageUrl: artwork,
                        width: 48,
                        height: 48,
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF242428),
                        borderRadius: BorderRadius.circular(isArtist ? 24 : 6),
                      ),
                      child: const Icon(Icons.history_rounded, color: AppTheme.textMuted, size: 22),
                    ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                onPressed: () async {
                  await _storage.removeRecentSearch(q, type: item['type']);
                  final updated = await _storage.getRecentSearches();
                  if (mounted) setState(() => _recentSearches = updated);
                },
              ),
              onTap: () => _triggerQuickQuery(q),
            );
          }),
        ] else ...[
          const SizedBox(height: 48),
          const Center(
            child: Column(
              children: [
                Icon(Icons.music_note_rounded, color: Colors.white24, size: 52),
                SizedBox(height: 14),
                Text(
                  'Putar apa yang kamu suka',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  'Cari artis, lagu, album, playlist, atau penggalan lirik.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Empty Search: Recent Searches + Lyric Prompts + Spotify Browse All Grid
  Widget _buildBrowseCategories() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
      children: [
        // 1. Recent Searches ("Pencarian Terkini")
        if (_recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pencarian Terkini',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              TextButton(
                onPressed: () async {
                  await _storage.clearRecentSearches();
                  setState(() => _recentSearches = []);
                },
                child: const Text(
                  'Hapus semua',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._recentSearches.take(5).map((item) {
            final q = item['query'] ?? '';
            final title = item['title'] ?? q;
            final subtitle = item['subtitle'] ?? 'Pencarian';
            final artwork = item['artwork'] ?? '';
            final isArtist = item['type'] == 'artist';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 2),
              leading: artwork.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(isArtist ? 24 : 6),
                      child: OptimizedImage(
                        imageUrl: artwork,
                        width: 46,
                        height: 46,
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                      ),
                    )
                  : Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF242428),
                        borderRadius: BorderRadius.circular(isArtist ? 24 : 6),
                      ),
                      child: const Icon(Icons.history_rounded, color: AppTheme.textMuted, size: 22),
                    ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                onPressed: () async {
                  await _storage.removeRecentSearch(q, type: item['type']);
                  final updated = await _storage.getRecentSearches();
                  if (mounted) setState(() => _recentSearches = updated);
                },
              ),
              onTap: () => _triggerQuickQuery(q),
            );
          }),
          const SizedBox(height: 18),
        ],

        // 2. Quick Lyric Discovery Chips
        const Text(
          'Coba Cari Penggalan Lirik',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _lyricChips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final chip = _lyricChips[idx];
              return GestureDetector(
                onTap: () => _triggerQuickQuery(chip, forceLyrics: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D2432),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.primaryAzure.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lyrics_outlined, color: AppTheme.primaryAzure, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        '"$chip"',
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 22),

        // 3. Spotify Browse All 12 Vibrant Category Cards with 25° Angled Art
        const Text(
          'Jelajahi Semua',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.75,
          ),
          itemCount: _genreCategories.length,
          itemBuilder: (context, index) {
            final cat = _genreCategories[index];
            final color = cat['color'] as Color;
            final name = cat['name'] as String;
            final query = cat['query'] as String;
            final img = cat['image'] as String;
            final forceLyrics = (cat['forceLyrics'] as bool?) ?? false;

            return GestureDetector(
              onTap: () => _triggerQuickQuery(query, forceLyrics: forceLyrics),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 52,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -10,
                      bottom: -8,
                      child: Transform.rotate(
                        angle: 0.44,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 8,
                                offset: Offset(-2, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: OptimizedImage(
                              imageUrl: img,
                              width: 68,
                              height: 68,
                              memCacheWidth: 140,
                              memCacheHeight: 140,
                            ),
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
      ],
    );
  }

  // Authentic Spotify Search Results View
  Widget _buildSearchResults() {
    final query = _searchController.text.trim();
    if (_searchResults.isEmpty && _artistResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 52, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                'Tidak menemukan hasil untuk "$query"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Coba ejaan lain, nama artis, penggalan lirik, atau tempel tautan YouTube.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => showImportYouTubeDialog(context: context, player: widget.player),
                icon: const Icon(Icons.link_rounded, size: 18, color: Colors.black),
                label: const Text('Putar dari Link YouTube', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAzure,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedTab == 'Artis') {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.88,
        ),
        itemCount: _artistResults.length,
        itemBuilder: (context, index) {
          final art = _artistResults[index];
          return ArtistCard(
            artist: art,
            onTap: () => _openArtist(art),
          );
        },
      );
    }

    if (_selectedTab == 'Album') {
      final albums = _buildAlbumGroups();
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 16,
          childAspectRatio: 0.78,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return GestureDetector(
            onTap: () {
              final pl = Playlist(
                id: 'album-${album.title.hashCode}',
                name: album.title,
                description: 'Album • ${album.artist}',
                cover: album.artwork,
                tracks: album.tracks,
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailView(playlist: pl, player: widget.player),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: OptimizedImage(
                      imageUrl: album.artwork,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 260,
                      memCacheHeight: 260,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_selectedTab == 'Playlist') {
      final matchingLocal = _userPlaylists
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
      final mixPlaylist = Playlist(
        id: 'mix-$query',
        name: 'McTify Mix: $query',
        description: '${_searchResults.length} lagu pilihan terbaik untuk "$query"',
        cover: _searchResults.isNotEmpty ? _searchResults.first.artwork : MusicApiService.defaultArtwork,
        tracks: _searchResults,
      );
      final combined = [...matchingLocal, if (_searchResults.isNotEmpty) mixPlaylist];

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
        itemCount: combined.length,
        itemBuilder: (context, index) {
          final pl = combined[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: OptimizedImage(
                imageUrl: pl.cover,
                width: 54,
                height: 54,
                memCacheWidth: 110,
                memCacheHeight: 110,
              ),
            ),
            title: Text(
              pl.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              'Playlist • ${pl.tracks.length} lagu',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailView(
                    playlist: pl,
                    player: widget.player,
                    isVirtualMix: index >= matchingLocal.length,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    if (_selectedTab == 'Lagu' || _selectedTab == 'Lirik') {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) => _buildTrackRow(_searchResults[index]),
      );
    }

    // Default TAB: "Semua" — Authentic Spotify Multi-Section Layout!
    final albums = _buildAlbumGroups();
    final isTopArtist = _shouldShowArtistAsTopResult(query);
    final topArtist = _artistResults.isNotEmpty ? _artistResults.first : null;
    final topTrack = _searchResults.isNotEmpty ? _searchResults.first : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 160),
      children: [
        // 1. "Hasil Teratas" Hero Card
        if (topTrack != null || topArtist != null) ...[
          const Text(
            'Hasil Teratas',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          const SizedBox(height: 10),
          isTopArtist && topArtist != null
              ? _buildTopArtistCard(topArtist)
              : (topTrack != null ? _buildTopTrackCard(topTrack) : const SizedBox.shrink()),
          const SizedBox(height: 22),
        ],

        // 2. "Lagu" List
        if (_searchResults.isNotEmpty) ...[
          const Text(
            'Lagu',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          const SizedBox(height: 8),
          ..._searchResults.take(6).map(_buildTrackRow),
          if (_searchResults.length > 6)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _selectedTab = 'Lagu'),
                child: const Text(
                  'Lihat semua lagu →',
                  style: TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          const SizedBox(height: 18),
        ],

        // 3. "Artis" Circular Horizontal Carousel
        if (_artistResults.isNotEmpty) ...[
          const Text(
            'Artis',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 162,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _artistResults.take(8).length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, idx) {
                final art = _artistResults[idx];
                return GestureDetector(
                  onTap: () => _openArtist(art),
                  child: SizedBox(
                    width: 112,
                    child: Column(
                      children: [
                        ClipOval(
                          child: OptimizedImage(
                            imageUrl: art.avatar,
                            width: 110,
                            height: 110,
                            memCacheWidth: 220,
                            memCacheHeight: 220,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          art.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'Artis',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 4. "Album" Horizontal Shelf
        if (albums.isNotEmpty) ...[
          const Text(
            'Album & Single',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 182,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: albums.take(8).length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, idx) {
                final album = albums[idx];
                return GestureDetector(
                  onTap: () {
                    final pl = Playlist(
                      id: 'album-${album.title.hashCode}',
                      name: album.title,
                      description: 'Album • ${album.artist}',
                      cover: album.artwork,
                      tracks: album.tracks,
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistDetailView(playlist: pl, player: widget.player),
                      ),
                    );
                  },
                  child: SizedBox(
                    width: 130,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: OptimizedImage(
                            imageUrl: album.artwork,
                            width: 130,
                            height: 130,
                            memCacheWidth: 260,
                            memCacheHeight: 260,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                        ),
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

  Widget _buildTopTrackCard(Track track) {
    final isCurrent = widget.player.currentTrack?.id == track.id;
    final isPlaying = isCurrent && widget.player.isPlaying;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _saveSearchHistory(
          query: track.title,
          title: track.title,
          subtitle: 'Lagu • ${track.artist}',
          artwork: track.artwork,
          type: 'track',
        );
        if (isCurrent) {
          widget.player.togglePlayPause();
        } else {
          widget.player.playTrackFromSearch(track);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: OptimizedImage(
                imageUrl: track.artwork,
                width: 78,
                height: 78,
                memCacheWidth: 160,
                memCacheHeight: 160,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          track.streamCount == 'Cocok Lirik' ? 'COCOK LIRIK' : 'LAGU',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: AppTheme.primaryAzure,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.black,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopArtistCard(Artist artist) {
    return GestureDetector(
      onTap: () => _openArtist(artist),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            ClipOval(
              child: OptimizedImage(
                imageUrl: artist.avatar,
                width: 78,
                height: 78,
                memCacheWidth: 160,
                memCacheHeight: 160,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Artis',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.primaryAzure,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow(Track track) {
    final isCurrent = widget.player.currentTrack?.id == track.id;
    final isLiked = _likedIds.contains(track.id);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _saveSearchHistory(
          query: track.title,
          title: track.title,
          subtitle: 'Lagu • ${track.artist}',
          artwork: track.artwork,
          type: 'track',
        );
        if (isCurrent) {
          widget.player.togglePlayPause();
        } else {
          widget.player.playTrackFromSearch(track);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: OptimizedImage(
                imageUrl: track.artwork,
                width: 48,
                height: 48,
                memCacheWidth: 100,
                memCacheHeight: 100,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCurrent) ...[
                        const Icon(Icons.graphic_eq_rounded, color: AppTheme.primaryAzure, size: 15),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (track.streamCount == 'Cocok Lirik' || track.album.startsWith('Lirik:')) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAzure.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: AppTheme.primaryAzure.withValues(alpha: 0.4), width: 0.8),
                          ),
                          child: const Text('Lirik', style: TextStyle(color: AppTheme.primaryAzure, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      if (track.isExplicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text('E', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isLiked ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                color: isLiked ? AppTheme.primaryAzure : Colors.white38,
                size: 22,
              ),
              onPressed: () => _toggleLike(track),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 21),
              onPressed: () => showTrackActionSheet(
                context: context,
                track: track,
                player: widget.player,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGroup {
  final String title;
  final String artist;
  final String artwork;
  final List<Track> tracks;

  _AlbumGroup({
    required this.title,
    required this.artist,
    required this.artwork,
    required this.tracks,
  });
}
