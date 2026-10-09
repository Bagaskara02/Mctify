import 'package:flutter/material.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/artist_card.dart';
import '../widgets/track_tile.dart';
import 'artist_view.dart';

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
  final MusicApiService _api = MusicApiService();
  final StorageService _storage = StorageService();

  String _selectedTab = 'Semua';
  List<Track> _searchResults = [];
  List<Artist> _artistResults = [];
  bool _isLoading = false;
  final Set<String> _likedIds = {};

  final List<String> _quickChips = [
    'HONNE',
    'Justin Bieber',
    'Coldplay',
    'Shawn Mendes',
    'Taylor Swift',
    'The Weeknd',
    'Billie Eilish',
    'Bernadya',
  ];

  final List<Map<String, dynamic>> _genreCategories = [
    {'name': 'Pop', 'color': Color(0xFF2563EB)},
    {'name': 'Hip-Hop', 'color': Color(0xFF3B82F6)},
    {'name': 'Indie & Folk', 'color': Color(0xFF0284C7)},
    {'name': 'Rock & Metal', 'color': Color(0xFF6366F1)},
    {'name': 'R&B & Soul', 'color': Color(0xFF4F46E5)},
    {'name': 'Akustik & Chill', 'color': Color(0xFF0EA5E9)},
    {'name': 'K-Pop', 'color': Color(0xFF0072CE)},
    {'name': 'Dance & EDM', 'color': Color(0xFF00A3FF)},
  ];

  @override
  void initState() {
    super.initState();
    _loadLikes();
    _artistResults = MusicApiService.catalogArtists;
  }

  Future<void> _loadLikes() async {
    final liked = await _storage.getLikedTracks();
    if (mounted) {
      setState(() {
        _likedIds.addAll(liked.map((t) => t.id));
      });
    }
  }

  void _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _artistResults = MusicApiService.catalogArtists;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    final tracks = await _api.searchTracks(query);
    final artists = await _api.searchArtists(query);

    if (mounted) {
      setState(() {
        _searchResults = tracks;
        _artistResults = artists;
        _isLoading = false;
      });
    }
  }

  void _toggleLike(Track track) async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Container(
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearch,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Apa yang ingin kamu putar?',
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.textMuted, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearch('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter Tabs matching media_1791353069505.png
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ['Semua', 'Lagu', 'Artis', 'Playlist'].map((tab) {
                final isSelected = _selectedTab == tab;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tab),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedTab = tab),
                    selectedColor: Colors.white,
                    backgroundColor: const Color(0xFF242424),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Quick Suggestion Chips
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickChips.length,
              itemBuilder: (context, index) {
                final chip = _quickChips[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(chip),
                    backgroundColor: const Color(0xFF1E1E1E),
                    labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    onPressed: () {
                      _searchController.text = chip;
                      _onSearch(chip);
                    },
                  ),
                );
              },
            ),
          ),

          // Main Search Body
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryAzure),
                  )
                : _searchController.text.trim().isEmpty
                    ? _buildBrowseGenres()
                    : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  // Genre categories grid (when query is empty) matching media_1791353002996.png
  Widget _buildBrowseGenres() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Jelajahi Semua Genre',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
            childAspectRatio: 1.6,
          ),
          itemCount: _genreCategories.length,
          itemBuilder: (context, index) {
            final cat = _genreCategories[index];
            return InkWell(
              onTap: () {
                _searchController.text = cat['name'];
                _onSearch(cat['name']);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: cat['color'],
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: Text(
                  cat['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    // TAB: ARTIS (matching media_1791353069505.png)
    if (_selectedTab == 'Artis') {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.9,
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

    // TAB: LAGU
    if (_selectedTab == 'Lagu') {
      return ListView.builder(
        cacheExtent: 300,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final track = _searchResults[index];
          final isCurrent = widget.player.currentTrack?.id == track.id;

          return TrackTile(
            track: track,
            index: index,
            isCurrent: isCurrent,
            isPlaying: widget.player.isPlaying,
            isLiked: _likedIds.contains(track.id),
            onPlay: () {
              if (isCurrent) {
                widget.player.togglePlayPause();
              } else {
                widget.player.playTrackFromSearch(track);
              }
            },
            onToggleLike: () => _toggleLike(track),
          );
        },
      );
    }

    // TAB: SEMUA
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Top Artists Horizontal Scroll Row
        if (_artistResults.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Artis',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _artistResults.length,
              itemBuilder: (context, index) {
                final art = _artistResults[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ArtistCard(
                    artist: art,
                    onTap: () => _openArtist(art),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Songs section
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Lagu',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        ..._searchResults.map((track) {
          final isCurrent = widget.player.currentTrack?.id == track.id;
          return TrackTile(
            track: track,
            index: _searchResults.indexOf(track),
            isCurrent: isCurrent,
            isPlaying: widget.player.isPlaying,
            isLiked: _likedIds.contains(track.id),
            onPlay: () {
              if (isCurrent) {
                widget.player.togglePlayPause();
              } else {
                widget.player.playTrackFromSearch(track);
              }
            },
            onToggleLike: () => _toggleLike(track),
          );
        }),
      ],
    );
  }
}
