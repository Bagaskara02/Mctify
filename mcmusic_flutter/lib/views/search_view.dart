import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/artist_card.dart';
import '../widgets/optimized_image.dart';
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

  final List<Map<String, dynamic>> _genreCategories = [
    {
      'name': 'Music',
      'color': const Color(0xFFE91E63),
      'image': 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Podcasts',
      'color': const Color(0xFF00897B),
      'image': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Live Events',
      'color': const Color(0xFF8E24AA),
      'image': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'K-Pop ON!',
      'color': const Color(0xFF1E88E5),
      'image': 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Made For You',
      'color': const Color(0xFF5E35B1),
      'image': 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Indo Hits',
      'color': const Color(0xFF0288D1),
      'image': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Rock',
      'color': const Color(0xFF3949AB),
      'image': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=200',
    },
    {
      'name': 'Chill & Folk',
      'color': const Color(0xFF00ACC1),
      'image': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=200',
    },
  ];

  final List<Map<String, String>> _discoverStories = [
    {
      'tag': '#admiration',
      'image': 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=300',
      'query': 'admiration chill',
    },
    {
      'tag': '#downtown vibes',
      'image': 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=300',
      'query': 'downtown night drive',
    },
    {
      'tag': '#make out',
      'image': 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=300',
      'query': 'romantic slow',
    },
    {
      'tag': '#chill beats',
      'image': 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=300',
      'query': 'lofi chill',
    },
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
    final isSearching = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header: "Search" title + Camera icon - NO PROFILE ICON!
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Search',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 26),
                    tooltip: 'Pindai Musik',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pencarian audio aktif. Mulai dengarkan di sekitarmu!'),
                          duration: Duration(milliseconds: 1200),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // White Spotify Search Box ("What do you want to listen to?")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600),
                  cursorColor: Colors.black,
                  decoration: InputDecoration(
                    hintText: 'What do you want to listen to?',
                    hintStyle: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w500),
                    prefixIcon: const Icon(Icons.search, color: Colors.black87, size: 24),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.black54, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Tabs row when searching (Semua, Lagu, Artis, Playlist)
            if (isSearching)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: ['Semua', 'Lagu', 'Artis', 'Playlist'].map((tab) {
                    final isSelected = _selectedTab == tab;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = tab),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryAzure : const Color(0xFF242426),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tab,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Main Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAzure))
                  : isSearching
                      ? _buildSearchResults()
                      : _buildBrowseCategories(),
            ),
          ],
        ),
      ),
    );
  }

  // Spotify Browse Categories + Discover Something New (matching screenshot 5)
  Widget _buildBrowseCategories() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        // 2-column Category Cards with signature angled art in bottom-right corner!
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.8,
          ),
          itemCount: _genreCategories.length,
          itemBuilder: (context, index) {
            final cat = _genreCategories[index];
            final color = cat['color'] as Color;
            final name = cat['name'] as String;
            final img = cat['image'] as String;

            return GestureDetector(
              onTap: () {
                _searchController.text = name;
                _onSearch(name);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Category Title at top-left
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 48,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    // Angled cover art at bottom-right (Spotify signature design!)
                    Positioned(
                      right: -12,
                      bottom: -8,
                      child: Transform.rotate(
                        angle: 0.45,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: OptimizedImage(
                            imageUrl: img,
                            width: 64,
                            height: 64,
                            memCacheWidth: 120,
                            memCacheHeight: 120,
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

        const SizedBox(height: 24),

        // Section: "Discover something new" (Exact match to screenshot 5)
        const Text(
          'Discover something new',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _discoverStories.length,
            itemBuilder: (context, idx) {
              final story = _discoverStories[idx];
              return GestureDetector(
                onTap: () {
                  _searchController.text = story['query'] ?? '';
                  _onSearch(story['query'] ?? '');
                },
                child: Container(
                  width: 125,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      OptimizedImage(
                        imageUrl: story['image']!,
                        memCacheWidth: 250,
                        memCacheHeight: 380,
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 8,
                        right: 8,
                        child: Text(
                          story['tag']!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Search Results List
  Widget _buildSearchResults() {
    if (_searchResults.isEmpty && _artistResults.isEmpty) {
      return Center(
        child: Text(
          'Tidak menemukan hasil untuk "${_searchController.text}"',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    if (_selectedTab == 'Artis') {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final track = _searchResults[index];
        final isCurrent = widget.player.currentTrack?.id == track.id;
        final isLiked = _likedIds.contains(track.id);

        return InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
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
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (track.isExplicit) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              margin: const EdgeInsets.only(right: 4),
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
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.check_circle : Icons.check_circle_outline,
                    color: isLiked ? AppTheme.primaryAzure : Colors.white24,
                    size: 22,
                  ),
                  onPressed: () => _toggleLike(track),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
