class Artist {
  final String id;
  final String name;
  final String headerBanner;
  final String avatar;
  final String monthlyListeners;
  final bool isVerified;

  Artist({
    required this.id,
    required this.name,
    required this.headerBanner,
    required this.avatar,
    this.monthlyListeners = '4,9 jt pendengar bulanan',
    this.isVerified = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'headerBanner': headerBanner,
    'avatar': avatar,
    'monthlyListeners': monthlyListeners,
    'isVerified': isVerified,
  };

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    headerBanner: json['headerBanner'] ?? '',
    avatar: json['avatar'] ?? '',
    monthlyListeners: json['monthlyListeners'] ?? '4,9 jt pendengar bulanan',
    isVerified: json['isVerified'] ?? true,
  );
}
