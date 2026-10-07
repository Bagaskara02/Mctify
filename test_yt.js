import { Innertube } from 'youtubei.js';

async function test() {
  try {
    console.log('Initializing Innertube...');
    const yt = await Innertube.create();
    console.log('Searching YouTube Music for Coldplay Yellow...');
    const search = await yt.music.search('Coldplay Yellow', { type: 'song' });
    const songs = search.songs?.contents || search.results || [];
    console.log('Songs found:', songs.length);
    if (songs[0]) {
      console.log('Top match title:', songs[0].title);
      console.log('Top match ID:', songs[0].id);
      console.log('Top match artist:', songs[0].artists?.[0]?.name);
      
      const info = await yt.getBasicInfo(songs[0].id);
      const audioStreams = info.streaming_data?.adaptive_formats?.filter(f => f.has_audio && !f.has_video) || [];
      console.log('Audio streams available:', audioStreams.length);
      if (audioStreams[0]) {
        console.log('Bitrate:', audioStreams[0].bitrate);
        console.log('MimeType:', audioStreams[0].mime_type);
        console.log('Sample URL prefix:', audioStreams[0].url?.slice(0, 60));
      }
    }
  } catch (err) {
    console.error('Error in test:', err);
  }
}

test();
