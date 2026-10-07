async function test() {
  try {
    const url = 'https://open.spotify.com/embed/playlist/4EK6n0S5FqMXdIsdbSpKaC';
    console.log('Fetching', url);
    const res = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      }
    });
    console.log('Status:', res.status);
    const html = await res.text();
    console.log('HTML length:', html.length);

    // Check __NEXT_DATA__
    const match = html.match(/<script id="__NEXT_DATA__"[^>]*>(.*?)<\/script>/s);
    if (match) {
      const data = JSON.parse(match[1]);
      const entity = data.props?.pageProps?.state?.data?.entity;
      console.log('Playlist Name:', entity?.name);
      console.log('Cover:', entity?.coverArt?.sources?.[0]?.url);
      console.log('Track count:', entity?.trackList?.length);
      console.log('Tracks sample:', entity?.trackList?.slice(0, 5).map(t => `${t.title} by ${t.subtitle}`));
      return;
    }

    // Check initial-state
    const m2 = html.match(/<script id="initial-state"[^>]*>(.*?)<\/script>/s);
    if (m2) {
      console.log('Found initial-state!');
      // base64 decode if encoded
    }

    // Check open.spotify.com/playlist API or scraping
    console.log('Snippet of HTML:', html.slice(0, 500));
  } catch (e) {
    console.error('Error:', e);
  }
}

test();
