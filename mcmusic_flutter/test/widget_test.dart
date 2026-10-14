import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmusic_flutter/models/track.dart';
import 'package:mcmusic_flutter/widgets/track_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TrackTile renders track information and handles tap callbacks', (WidgetTester tester) async {
    final track = Track(
      id: 't1',
      title: 'Gala Bunga Matahari',
      artist: 'Sal Priadi',
      album: 'MARKERS AND SUCH',
      artwork: 'https://example.com/art.jpg',
      duration: 218,
    );

    bool playTapped = false;
    bool likeTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: track,
            index: 0,
            isCurrent: false,
            isPlaying: false,
            isLiked: false,
            onPlay: () {
              playTapped = true;
            },
            onToggleLike: () {
              likeTapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Gala Bunga Matahari'), findsOneWidget);
    expect(find.text('Sal Priadi'), findsOneWidget);
    expect(find.text('3:38'), findsOneWidget);

    await tester.tap(find.text('Gala Bunga Matahari'));
    await tester.pump();

    expect(playTapped, isTrue);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(likeTapped, isTrue);
  });
}
