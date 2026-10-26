import { storageService } from './storageService';

export const DEFAULT_ARTWORK = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600';

/**
 * Universal High-Resolution Artwork Transformer
 * Converts 60x60, 100x100, or low-res thumbnails from Google User Content, YouTube, iTunes, and Spotify into 800x800+ Ultra-HD
 */
export function getHighResArtworkUrl(url) {
  if (!url || typeof url !== 'string') return url || DEFAULT_ARTWORK;
  let clean = url.trim();

  // 1. Google User Content (YouTube Music album art: yt3.googleusercontent.com, lh3.googleusercontent.com)
  if (clean.includes('googleusercontent.com')) {
    if (/=w\d+-h\d+/i.test(clean)) {
      return clean.replace(/=w\d+-h\d+[^?#]*/i, '=w800-h800-l90-rj');
    }
    if (/=s\d+/i.test(clean)) {
      return clean.replace(/=s\d+[^?#]*/i, '=w800-h800-l90-rj');
    }
    if (!clean.includes('=')) {
      return `${clean}=w800-h800-l90-rj`;
    }
  }

  // 2. YouTube Video Thumbnails (i.ytimg.com)
  if (clean.includes('ytimg.com')) {
    if (/default\.jpg/i.test(clean)) {
      return clean.replace(/(default|mqdefault|sddefault)\.jpg/i, 'hq720.jpg').split('?')[0];
    }
  }

  // 3. Apple Music / iTunes (mzstatic.com)
  if (clean.includes('mzstatic.com')) {
    return clean.replace(/\/\d+x\d+bb\./i, '/1000x1000bb.');
  }

  // 4. Spotify CDN
  if (clean.includes('i.scdn.co/image/ab67616d00004851')) {
    return clean.replace('ab67616d00004851', 'ab67616d0000b273');
  }

  return clean;
}

/**
 * Quality & Popularity Filter:
 * Rejects obscure amateur covers, karaoke versions, instrumentals, parodies,
 * tutorials, and junk uploads to ensure ONLY verified, well-known popular hits.
 */
export function isCleanPopularTrack(t) {
  if (!t || !t.title || !t.artist) return false;
  const title = t.title.toLowerCase();
  const artist = t.artist.toLowerCase();

  const bannedKeywords = [
    'karaoke', 'instrumental', 'backing track', 'cover by', 'tribute to',
    'parodi', 'parody', 'ringtone', 'sped up', 'slowed', 'reverb',
    '8d audio', 'tutorial', 'chord', 'guitar lesson', 'bass tab',
    'drum cover', 'reaction', 'teaser', 'trailer', 'podcast',
    'audio visualizer', 'cara ', 'belajar ', 'remake', 'audio only',
    'lirik video', 'lyrics video', 'acapella'
  ];

  if (bannedKeywords.some(w => title.includes(w) || artist.includes(w))) {
    return false;
  }

  // Reasonably standard radio track duration (between 1:15 and 7:30)
  const dur = t.duration || 180;
  if (dur < 75 || dur > 450) return false;

  return true;
}

/**
 * Curated Top Hitmaker Clusters:
 * Groups the biggest, most beloved, and recognizable artists so that
 * recommendations always feature household-name hits.
 */
export const ARTIST_GENRE_CLUSTERS = [
  {
    name: 'Western R&B, Chill Hop & Urban',
    region: 'western',
    genreKeywords: ['r&b', 'r&b/soul', 'soul', 'neo-soul', 'contemporary r&b', 'chill', 'lo-fi'],
    keywords: [
      '88rising', 'joji', 'rich brian', 'niki', 'warren hue', 'stephanie poetri',
      'daniel caesar', 'frank ocean', 'sza', 'steve lacy', 'giveon',
      'brent faiyaz', 'keshi', 'umi', 'mac ayres', 'jeremy zucker',
      'lauv', 'lany', 'honne', 'alec benjamin', 'rex orange county',
      'boy pablo', 'clairo', 'cuco', 'faye webster', 'bruno major',
      'dominic fike', 'childish gambino', 'khalid', 'post malone', 'bazzi', 'pink sweat$'
    ],
    peers: [
      'Joji', 'Keshi', 'NIKI', 'Rich Brian', 'Daniel Caesar', 'Frank Ocean',
      'SZA', 'Steve Lacy', 'Dominic Fike', 'Khalid', 'Lauv', 'LANY',
      'Jeremy Zucker', 'Brent Faiyaz', 'Giveon', 'Bazzi', 'Pink Sweat$',
      'Boy Pablo', 'Rex Orange County', 'Childish Gambino'
    ]
  },
  {
    name: 'Global & Western Pop Hits',
    region: 'western',
    genreKeywords: ['pop', 'dance pop', 'electropop', 'teen pop'],
    keywords: [
      'the weeknd', 'bruno mars', 'taylor swift', 'billie eilish', 'olivia rodrigo',
      'ed sheeran', 'coldplay', 'dua lipa', 'maroon 5', 'sabrina carpenter',
      'ariana grande', 'justin bieber', 'harry styles', 'lady gaga', 'shawn mendes',
      'adele', 'sam smith', 'charlie puth', 'katy perry', 'rihanna', 'beyonce',
      'selena gomez', 'miley cyrus', 'sia', 'camila cabello', 'chappell roan',
      'tate mcrae', 'one direction', 'halsey', 'benson boone', 'teddy swims'
    ],
    peers: [
      'The Weeknd', 'Bruno Mars', 'Taylor Swift', 'Billie Eilish',
      'Olivia Rodrigo', 'Coldplay', 'Sabrina Carpenter', 'Ed Sheeran',
      'Dua Lipa', 'Ariana Grande', 'Maroon 5', 'Justin Bieber', 'Harry Styles',
      'Lady Gaga', 'Shawn Mendes', 'Adele', 'Charlie Puth'
    ]
  },
  {
    name: 'Western Rock, Alternative, Metal & Punk Hits',
    region: 'western',
    genreKeywords: ['rock', 'hard rock', 'metal', 'heavy metal', 'punk', 'alternative rock', 'grunge', 'emo'],
    keywords: [
      'linkin park', 'avenged sevenfold', 'bring me the horizon', 'green day',
      'slipknot', 'queen', 'bon jovi', "guns n' roses", 'nirvana', 'foo fighters',
      'my chemical romance', 'arctic monkeys', 'red hot chili peppers', 'radiohead',
      'muse', 'fall out boy', 'paramore', 'evanescence', 'metallica', 'system of a down',
      'oasis', 'the beatles', 'ac/dc', 'aerosmith', 'led zeppelin', 'blink-182',
      'sum 41', 'simple plan', 'the killers', 'imagine dragons', 'twenty one pilots',
      'three days grace', 'papa roach', 'disturbed', 'korn', 'deftones'
    ],
    peers: [
      'Linkin Park', 'Avenged Sevenfold', 'Bring Me The Horizon', 'Green Day',
      'Arctic Monkeys', 'My Chemical Romance', 'Queen', 'Red Hot Chili Peppers',
      'Imagine Dragons', 'Radiohead', 'Nirvana', 'Foo Fighters', 'Blink-182',
      'Fall Out Boy', 'Paramore', 'Metallica', 'System Of A Down'
    ]
  },
  {
    name: 'Western Hip-Hop, Rap & Trap Hits',
    region: 'western',
    genreKeywords: ['hip-hop', 'hip hop', 'rap', 'trap', 'urban'],
    keywords: [
      'eminem', 'drake', 'kendrick lamar', 'travis scott', 'kanye west',
      'juice wrld', 'j. cole', '21 savage', 'metro boomin', 'future',
      'lil nas x', 'jack harlow', 'xxxtentacion', 'cardi b', 'nicki minaj',
      'snoop dogg', '50 cent', 'dr. dre', 'jay-z', 'tyler, the creator',
      'asap rocky', 'playboi carti', 'central cee', 'gunna', 'lil baby', 'lil uzi vert'
    ],
    peers: [
      'Eminem', 'Drake', 'Kendrick Lamar', 'Travis Scott', 'Kanye West',
      'Juice WRLD', 'Metro Boomin', 'J. Cole', 'Central Cee', 'XXXTENTACION',
      'Tyler, The Creator', 'Future', '21 Savage', '50 Cent'
    ]
  },
  {
    name: 'EDM, Dance & Electronic Hits',
    region: 'western',
    genreKeywords: ['electronic', 'dance', 'edm', 'house', 'techno', 'dubstep'],
    keywords: [
      'alan walker', 'marshmello', 'avicii', 'the chainsmokers', 'calvin harris',
      'martin garrix', 'dj snake', 'david guetta', 'zedd', 'kygo', 'skrillex',
      'tiesto', 'alesso', 'major lazer', 'illenium', 'clean bandit', 'galantis'
    ],
    peers: [
      'Alan Walker', 'Marshmello', 'Avicii', 'The Chainsmokers',
      'Calvin Harris', 'Martin Garrix', 'Zedd', 'Kygo', 'DJ Snake', 'David Guetta'
    ]
  },
  {
    name: 'Indonesian Pop & Ballad Hits',
    region: 'indonesia',
    genreKeywords: ['pop', 'indo pop', 'indonesian pop', 'ballad'],
    keywords: [
      'mahalini', 'tulus', 'juicy luicy', 'tiara andini', 'lyodra', 'ziva magnolya',
      'yura yunita', 'rizky febian', 'raisa', 'afgan', 'judika', 'fabio asher',
      'budi doremi', 'keisya levronka', 'jaz', 'andmesh', 'cakra khan', 'arash buana',
      'idgitaf', 'glenn fredly', 'marcell', 'rio febrian', 'sammy simorangkir', 'feby putri'
    ],
    peers: [
      'Mahalini', 'Tulus', 'Juicy Luicy', 'Tiara Andini', 'Lyodra',
      'Yura Yunita', 'Rizky Febian', 'Raisa', 'Afgan', 'Judika',
      'Fabio Asher', 'Budi Doremi', 'Andmesh', 'Cakra Khan'
    ]
  },
  {
    name: 'Indonesian Indie, Folk & Alternative Hits',
    region: 'indonesia',
    genreKeywords: ['indie', 'alternative', 'folk', 'indie pop', 'acoustic'],
    keywords: [
      'hindia', 'feast', '.feast', 'nadin amizah', 'sal priadi', 'kunto aji',
      'pamungkas', 'danilla', 'fourtwnty', 'barasuara', 'reality club',
      'efek rumah kaca', 'sore', 'the adams', 'morad', 'fiersa besari',
      'bilal indrajaya', 'bernadya', 'perunggu', 'jason ranti', 'soegi bornean'
    ],
    peers: [
      'Hindia', '.Feast', 'Nadin Amizah', 'Sal Priadi', 'Kunto Aji',
      'Pamungkas', 'Fourtwnty', 'Reality Club', 'Barasuara', 'The Adams',
      'Fiersa Besari', 'Danilla', 'Bilal Indrajaya', 'Perunggu'
    ]
  },
  {
    name: 'Indonesian Pop Rock & Legend Band Hits',
    region: 'indonesia',
    genreKeywords: ['rock', 'pop rock', 'legend', 'band indonesia', 'classic rock'],
    keywords: [
      'sheila on 7', 'dewa 19', 'peterpan', 'noah', 'padi', 'ungu', "d'masiv",
      'ada band', 'kotak', 'gigi', 'slank', 'chrisye', 'ari lasso', 'kerispatih',
      'samsons', 'letto', 'naif', 'j-rocks', 'radja', 'wali', 'armada', 'repvblik',
      'seventeen', 'kangen band', 'jamrud', 'boomerang'
    ],
    peers: [
      'Sheila On 7', 'Dewa 19', 'NOAH', 'Peterpan', 'Padi', 'Ungu',
      "D'Masiv", 'Ada Band', 'Ari Lasso', 'Glenn Fredly', 'Kerispatih', 'Samsons', 'Naif'
    ]
  },
  {
    name: 'Indonesian Dangdut, Koplo & Jawa Pop Hits',
    region: 'indonesia',
    genreKeywords: ['dangdut', 'koplo', 'jawa', 'campursari'],
    keywords: [
      'denny caknan', 'guyon waton', 'ndarboy genk', 'happy asmara', 'gilga sahid',
      'didi kempot', 'nella kharisma', 'via vallen', 'gildcoustic', 'aftershine',
      'hendra kumbara', 'woro widowati', 'difarina indra', 'tasya rosmala',
      'shinta arsinta', 'masdddho', 'niken salindry'
    ],
    peers: [
      'Denny Caknan', 'Guyon Waton', 'Happy Asmara', 'Gilga Sahid',
      'Ndarboy Genk', 'Didi Kempot', 'Aftershine', 'Gildcoustic', 'Nella Kharisma'
    ]
  },
  {
    name: 'K-Pop Hits',
    region: 'kpop',
    genreKeywords: ['k-pop', 'kpop', 'korean', 'k-rock'],
    keywords: [
      'newjeans', 'bts', 'blackpink', 'aespa', 'le sserafim', 'twice', 'iu',
      'seventeen', 'stray kids', 'rosé', 'jennie', 'jungkook', 'ive', 'txt',
      'enhypen', '(g)i-dle', 'itzy', 'exo', 'red velvet', 'nct', 'babymonster',
      'illit', 'riize', 'ateez', 'taeyeon', 'lisa'
    ],
    peers: [
      'NewJeans', 'BTS', 'BLACKPINK', 'aespa', 'LE SSERAFIM',
      'TWICE', 'IU', 'SEVENTEEN', 'ROSÉ', 'IVE', '(G)I-DLE', 'ITZY', 'EXO'
    ]
  },
  {
    name: 'J-Pop, J-Rock & Anime Hits',
    region: 'jpop',
    genreKeywords: ['j-pop', 'jpop', 'j-rock', 'anime', 'japanese'],
    keywords: [
      'yoasobi', 'lisa', 'eve', 'radwimps', 'kenshi yonezu', 'ado', 'aimer',
      'official hige dandism', 'fujii kaze', 'king gnu', 'vaundy', 'one ok rock',
      'mrs. green apple', 'yuuri', 'back number', 'kana-boon', 'spyair', 'flow'
    ],
    peers: [
      'YOASOBI', 'Kenshi Yonezu', 'Ado', 'Aimer', 'Official HIGE DANdism',
      'Fujii Kaze', 'RADWIMPS', 'ONE OK ROCK', 'Eve', 'King Gnu', 'Vaundy'
    ]
  }
];

export const POPULAR_ARTIST_CLUSTERS = ARTIST_GENRE_CLUSTERS;

/**
 * Detects the musical region of a track (western vs indonesia vs kpop vs jpop)
 * to strictly prevent regional mixing (e.g. Indonesian songs in English tracks).
 */
export function detectTrackRegion(artistName = '', title = '', genre = '') {
  const normArtist = (artistName || '').toLowerCase().trim();
  const normTitle = (title || '').toLowerCase().trim();
  const normGenre = (genre || '').toLowerCase().trim();

  // 1. Direct cluster keyword lookup
  for (const cluster of ARTIST_GENRE_CLUSTERS) {
    if (cluster.keywords.some(k => normArtist.includes(k) || k.includes(normArtist))) {
      return cluster.region;
    }
  }

  // 2. Specific genre keyword hints
  if (normGenre.includes('dangdut') || normGenre.includes('koplo') || normGenre.includes('campursari') || normGenre.includes('indo')) {
    return 'indonesia';
  }
  if (normGenre.includes('k-pop') || normGenre.includes('kpop') || normGenre.includes('korean')) {
    return 'kpop';
  }
  if (normGenre.includes('j-pop') || normGenre.includes('jpop') || normGenre.includes('anime') || normGenre.includes('japanese')) {
    return 'jpop';
  }

  // 3. Common English words in Western song titles / artist names
  const englishWords = [
    'the', 'you', 'me', 'love', 'night', 'madness', 'midsummer', 'die', 'smile',
    'summer', 'winter', 'fall', 'spring', 'heart', 'baby', 'boy', 'girl', 'good',
    'bad', 'time', 'life', 'world', 'star', 'sun', 'moon', 'sky', 'blue', 'red',
    'black', 'white', 'feel', 'kiss', 'dance', 'stay', 'go', 'run', 'walk', 'eyes',
    'dream', 'happy', 'sad', 'cry', 'tears', 'rain', 'fire', 'light', 'dark', 'sweet',
    'young', 'forever', 'together', 'without', 'about', 'never', 'again', 'always',
    'some', 'where', 'what', 'when', 'how', 'why', 'who', 'little', 'big', 'high',
    'low', 'cold', 'hot', 'wild', 'free', 'crazy', 'lost', 'found', 'broken', 'home'
  ];
  const titleTokens = normTitle.split(/[^a-zA-Z0-9]+/).filter(Boolean);
  if (titleTokens.some(token => englishWords.includes(token))) {
    return 'western';
  }

  return 'western';
}

/**
 * Intelligently resolves peer hitmaker artists matching the artist, genre, or playlist context.
 * Strictly locks to the target track's region to prevent mixing languages.
 */
export function getSimilarArtists(artistName = '', genreName = '', playlistTracks = [], title = '') {
  const normArtist = (artistName || '').toLowerCase().trim();
  const normGenre = (genreName || '').toLowerCase().trim();

  // Determine target region
  const targetRegion = detectTrackRegion(artistName, title, genreName);

  // 1. Direct artist match in cluster
  if (normArtist) {
    for (const cluster of ARTIST_GENRE_CLUSTERS) {
      if (cluster.keywords.some(k => normArtist.includes(k) || k.includes(normArtist))) {
        const peers = cluster.peers.filter(p => !p.toLowerCase().includes(normArtist) && !normArtist.includes(p.toLowerCase()));
        return [...peers].sort(() => Math.random() - 0.5);
      }
    }
  }

  // 2. Dominant playlist artist cluster matching the target region
  if (playlistTracks && playlistTracks.length > 0) {
    const clusterScores = new Map();
    for (const t of playlistTracks) {
      const art = (t.artist || '').toLowerCase().trim();
      const g = (t.genre || '').toLowerCase().trim();
      for (const cluster of ARTIST_GENRE_CLUSTERS) {
        if (cluster.region === targetRegion) {
          if (cluster.keywords.some(k => art.includes(k) || k.includes(art)) ||
              (g && cluster.genreKeywords.some(gk => g.includes(gk)))) {
            clusterScores.set(cluster, (clusterScores.get(cluster) || 0) + 1);
          }
        }
      }
    }
    if (clusterScores.size > 0) {
      let topCluster = null;
      let maxVotes = 0;
      for (const [cluster, votes] of clusterScores.entries()) {
        if (votes > maxVotes) {
          maxVotes = votes;
          topCluster = cluster;
        }
      }
      if (topCluster) {
        const peers = topCluster.peers.filter(p => !p.toLowerCase().includes(normArtist) && !normArtist.includes(p.toLowerCase()));
        return [...peers].sort(() => Math.random() - 0.5);
      }
    }
  }

  // 3. Match genre keyword restricted to target region
  if (normGenre) {
    for (const cluster of ARTIST_GENRE_CLUSTERS) {
      if (cluster.region === targetRegion && cluster.genreKeywords.some(gk => normGenre.includes(gk))) {
        const peers = cluster.peers.filter(p => !p.toLowerCase().includes(normArtist) && !normArtist.includes(p.toLowerCase()));
        return [...peers].sort(() => Math.random() - 0.5);
      }
    }
  }

  // 4. Region-locked fallbacks (strictly respect target region!)
  if (targetRegion === 'western') {
    const westernPools = [
      ['The Weeknd', 'Bruno Mars', 'Coldplay', 'Taylor Swift', 'Billie Eilish', 'Olivia Rodrigo'],
      ['Joji', 'Keshi', 'NIKI', 'Daniel Caesar', 'Frank Ocean', 'SZA', 'Dominic Fike'],
      ['Linkin Park', 'Avenged Sevenfold', 'Green Day', 'Queen', 'Arctic Monkeys'],
      ['Eminem', 'Drake', 'Kendrick Lamar', 'Travis Scott', 'Post Malone', 'Juice WRLD']
    ];
    const selected = westernPools[Math.floor(Math.random() * westernPools.length)];
    return [...selected].sort(() => Math.random() - 0.5);
  }

  if (targetRegion === 'kpop') {
    return ['NewJeans', 'BTS', 'BLACKPINK', 'aespa', 'LE SSERAFIM', 'TWICE', 'IU'].sort(() => Math.random() - 0.5);
  }

  if (targetRegion === 'jpop') {
    return ['YOASOBI', 'Kenshi Yonezu', 'Ado', 'Aimer', 'RADWIMPS', 'Official HIGE DANdism'].sort(() => Math.random() - 0.5);
  }

  const indoPools = [
    ['Sheila On 7', 'Dewa 19', 'NOAH', 'Peterpan', 'Padi', 'Ungu', 'D\'Masiv'],
    ['Mahalini', 'Tulus', 'Juicy Luicy', 'Tiara Andini', 'Lyodra', 'Yura Yunita', 'Rizky Febian'],
    ['Denny Caknan', 'Guyon Waton', 'Happy Asmara', 'Gilga Sahid', 'Ndarboy Genk']
  ];
  const selected = indoPools[Math.floor(Math.random() * indoPools.length)];
  return [...selected].sort(() => Math.random() - 0.5);
}

function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  const matrix = [];
  for (let i = 0; i <= b.length; i++) matrix[i] = [i];
  for (let j = 0; j <= a.length; j++) matrix[0][j] = j;
  for (let i = 1; i <= b.length; i++) {
    for (let j = 1; j <= a.length; j++) {
      if (b.charAt(i - 1) === a.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }
  return matrix[b.length][a.length];
}

function normalizeSearchText(s) {
  return (s || '')
    .toLowerCase()
    .replace(/[ü]/g, 'u')
    .replace(/['’´`]/g, '')
    .replace(/[\(\)\[\]\-–—.,\/#!$%\^&\*;:{}=\_`~?]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  // Expand common informal abbreviations
  return base.split(' ').map(t => {
    if (t === 'u') return 'you';
    if (t === 'ur') return 'your';
    if (t === 'r') return 'are';
    if (t === 'im') return 'i am';
    if (t === 'ft' || t === 'feat') return 'featuring';
    return t;
  }).join(' ');
}

const SUPERSTAR_ARTISTS = [
  'justin bieber', 'dj khaled', 'the weeknd', 'taylor swift', 'bruno mars',
  'billie eilish', 'coldplay', 'ed sheeran', 'ariana grande', 'drake',
  'post malone', 'dua lipa', 'eminem', 'rihanna', 'maroon 5', 'shawn mendes',
  'charlie puth', 'sam smith', 'adele', 'katy perry', 'harry styles',
  'olivia rodrigo', 'kendrick lamar', 'travis scott', 'sza', 'bts', 'blackpink',
  'niki', 'rich brian', 'bernadya', 'sal priadi', 'hindia', 'mahalini',
  'tulus', 'juicy luicy', 'sheila on 7', 'dewa 19', 'noah', 'tiara andini',
  'lyodra', 'yura yunita', 'pamungkas', 'feby putri', 'fiersa besari', 'glenn fredly'
];

function calculateSearchRelevance(track, rawQuery) {
  const qNorm = normalizeSearchText(rawQuery);
  const qTokens = qNorm.split(' ').filter(t => t.length > 0);
  if (qTokens.length === 0) return 0;

  const tTitle = normalizeSearchText(track.title);
  const tArtist = normalizeSearchText(track.artist);
  const tAlbum = normalizeSearchText(track.album || '');
  const combined = `${tTitle} ${tArtist}`;
  const trackWords = combined.split(' ').filter(w => w.length > 0);

  let score = 1000;

  let matchedTokens = 0;
  for (const qTok of qTokens) {
    let bestDist = 999;
    let exactFound = false;

    for (const w of trackWords) {
      if (w === qTok) {
        exactFound = true;
        break;
      }
      if (w.includes(qTok) || qTok.includes(w)) {
        if (qTok.length >= 3 && w.length >= 3) {
          exactFound = true;
          break;
        }
      }
      if (qTok.length >= 4 && w.length >= 4) {
        const d = levenshtein(qTok, w);
        if (d < bestDist) bestDist = d;
      }
    }

    if (exactFound) {
      matchedTokens += 1.0;
      score += 260;
    } else if (bestDist <= 1) {
      matchedTokens += 0.9;
      score += 190;
    } else if (bestDist <= 2 && qTok.length >= 6) {
      matchedTokens += 0.6;
      score += 110;
    }
  }

  const matchRatio = matchedTokens / qTokens.length;
  score += Math.round(matchRatio * 700);

  // YouTube Music search engine rank bonus (preserves deep neural / lyrics ranking)
  if (typeof track.ytRank === 'number') {
    if (track.ytRank === 0) score += 950;
    else if (track.ytRank === 1) score += 700;
    else if (track.ytRank === 2) score += 500;
    else if (track.ytRank < 5) score += 300;
    else if (track.ytRank < 10) score += 150;
  }

  // Lyrics Search Detection:
  // When a user types 3+ words (e.g. "hidup berjalan seperti bajingan" or "cause you're a sky full of stars"),
  // and direct title match is low (<0.4), but YouTube Music returned it in top results:
  if (qTokens.length >= 3 && matchRatio < 0.4 && typeof track.ytRank === 'number' && track.ytRank < 3) {
    track.isLyricMatch = true;
    score += 1200; // Strong boost to put lyric match on top!
  }

  // 1. Prefix match bonus (Spotify-like instant hit suggestion on short prefixes like "im the ")
  if (tTitle.startsWith(qNorm)) {
    score += 550;
  } else if (combined.startsWith(qNorm)) {
    score += 400;
  }

  if (tTitle.includes(qNorm) || combined.includes(qNorm)) {
    score += 450;
  }
  if (tTitle === qNorm) {
    score += 650;
  }

  // 2. Popularity / Rank weighting
  const rank = track.popularity || track.rank || 0;
  if (rank > 0) {
    score += Math.round((rank / 1000) * 0.85);
  }

  // 3. Superstar / Global Hitmaker artist bonus
  if (SUPERSTAR_ARTISTS.some(art => tArtist.includes(art))) {
    score += 450;
  }

  // 4. Two-way version scoring for search (acoustic, remix, live)
  const isAcousticRequested = qNorm.includes('acoustic');
  const isRemixRequested = qNorm.includes('remix');
  const isLiveRequested = qNorm.includes('live') || qNorm.includes('concert') || qNorm.includes('konser');

  if (isAcousticRequested) {
    if (tTitle.includes('acoustic')) score += 750;
    else score -= 900;
  }
  if (isRemixRequested) {
    if (tTitle.includes('remix')) score += 750;
    else score -= 900;
  }
  if (isLiveRequested) {
    if (tTitle.includes('live') || tTitle.includes('concert')) score += 750;
    else score -= 900;
  }

  // HEAVY PENALTIES FOR NON-ORIGINAL VERSIONS (Remix, Live, Concert, Cover, Karaoke, Tribute, Slowed)
  const junkTerms = [
    'cover', 'karaoke', 'instrumental', 'tribute', 'parodi', 'parody',
    'sped up', 'speed up', 'slowed', 'reverb', 'nightcore', 'reaction',
    'tutorial', 'originally performed', 'in the style of', 'backing track',
    'guitar cover', 'piano cover', 'acoustic cover'
  ];

  for (const term of junkTerms) {
    if (!qNorm.includes(term)) {
      if (tTitle.includes(term)) score -= 850;
      if (tAlbum.includes(term)) score -= 450;
      if (tArtist.includes(term)) score -= 950;
    } else {
      score += 300;
    }
  }

  if (!isRemixRequested && !qNorm.includes('remix') && tTitle.includes('remix')) {
    score -= 850;
  }
  if (!isLiveRequested && !isAcousticRequested && !qNorm.includes('live') &&
      (tTitle.includes('live') || tTitle.includes('concert') || tTitle.includes('konser'))) {
    score -= 850;
  }

  // STUDIO ORIGINAL BONUS
  if (!tTitle.includes('remix') && !tTitle.includes('live') && !tTitle.includes('cover') && !tTitle.includes('karaoke')) {
    score += 250;
  }
  if (tTitle.includes('official') || tTitle.includes('original')) {
    score += 200;
  }

  return score;
}

export const musicApi = {
  /**
   * Resolve Full Song YouTube Video ID & Duration
   */
  async resolveYouTubeMatch(title, artist, duration) {
    if (!title) return null;
    try {
      const q = `${title} ${artist || ''}`.trim();
      const durParam = duration ? `&duration=${encodeURIComponent(duration)}` : '';
      const res = await fetch(`/api/yt/search?q=${encodeURIComponent(q)}${durParam}`);
      if (res.ok) {
        const data = await res.json();
        if (data && data.videoId) {
          if (data.thumbnail) {
            data.thumbnail = getHighResArtworkUrl(data.thumbnail);
          }
          return data; // { videoId, title, artist, duration, thumbnail }
        }
      }
    } catch (e) {
      console.warn('YouTube backend resolver lookup failed:', e);
    }

    // Retry with title only if artist was included and returned 404
    if (artist) {
      try {
        const res = await fetch(`/api/yt/search?q=${encodeURIComponent(title)}`);
        if (res.ok) {
          const data = await res.json();
          if (data && data.videoId) {
            if (data.thumbnail) {
              data.thumbnail = getHighResArtworkUrl(data.thumbnail);
            }
            return data;
          }
        }
      } catch (_) {}
    }

    return null;
  },

  /**
   * Search both Songs and Artists across YouTube Music, iTunes, and Deezer
   */
  async searchAll(query) {
    if (!query || !query.trim()) return { songs: [], artists: [] };

    try {
      const q = query.trim();
      // 1. YouTube Music backend multi-search
      const ytPromise = fetch(`/api/yt/search-multi?q=${encodeURIComponent(q)}`)
        .then(r => r.ok ? r.json() : { songs: [], artists: [] })
        .catch(() => ({ songs: [], artists: [] }));

      // 2. iTunes Global Search (Worldwide hits indexing)
      const itunesPromise = fetch(`https://itunes.apple.com/search?term=${encodeURIComponent(q)}&entity=song&limit=25`)
        .then(r => r.ok ? r.json() : { results: [] })
        .catch(() => ({ results: [] }));

      // 3. Deezer Global Music Catalog (90M+ tracks)
      const deezerPromise = fetch(`https://api.deezer.com/search?q=${encodeURIComponent(q)}&limit=20`)
        .then(r => r.ok ? r.json() : { data: [] })
        .catch(() => ({ data: [] }));

      const [ytData, itunesData, deezerData] = await Promise.all([ytPromise, itunesPromise, deezerPromise]);

      const itunesTracks = (itunesData.results || []).map(item => this.formatTrack(item));

      const deezerTracks = (deezerData.data || []).map(item => ({
        id: `dz_${item.id}`,
        title: item.title || '',
        artist: item.artist?.name || '',
        album: item.album?.title || 'Single',
        artwork: getHighResArtworkUrl(item.album?.cover_big || item.album?.cover_medium || DEFAULT_ARTWORK),
        originalArtwork: item.album?.cover_medium || DEFAULT_ARTWORK,
        duration: item.duration || 180,
        genre: 'Pop',
        audioUrl: '',
      }));

      const ytSongs = (ytData.songs || []).map((s, idx) => ({
        id: s.videoId || s.id,
        videoId: s.videoId || s.id,
        title: s.title,
        artist: s.artist,
        album: s.album || 'Single',
        artwork: getHighResArtworkUrl(s.artwork) || DEFAULT_ARTWORK,
        duration: s.duration || 180,
        genre: 'Pop',
        audioUrl: '',
        ytRank: idx,
      }));

      // Deduplicate and rank all candidates prioritizing verified studio original tracks
      const map = new Map();

      // Prioritize ytSongs first to retain clean videoId & YouTube Music rank
      for (const s of ytSongs) {
        if (!s || !s.title) continue;
        const key = `${normalizeSearchText(s.title)}___${normalizeSearchText(s.artist)}`;
        map.set(key, s);
      }

      for (const s of [...itunesTracks, ...deezerTracks]) {
        if (!s || !s.title) continue;
        const key = `${normalizeSearchText(s.title)}___${normalizeSearchText(s.artist)}`;
        if (map.has(key)) {
          const existing = map.get(key);
          if (!existing.album || existing.album === 'Single') {
            existing.album = s.album;
          }
          if (s.artwork && !existing.artwork) {
            existing.artwork = s.artwork;
          }
        } else {
          map.set(key, s);
        }
      }

      const uniqueSongs = Array.from(map.values());

      // Sort by Studio Original Relevance: Famous original songs and lyric matches on top!
      uniqueSongs.sort((a, b) => calculateSearchRelevance(b, q) - calculateSearchRelevance(a, q));

      return {
        songs: uniqueSongs,
        artists: ytData.artists || [],
      };
    } catch (e) {
      console.error('searchAll error:', e);
      return { songs: [], artists: [] };
    }
  },

  /**
   * Get artist details and their popular singles/songs
   */
  async getArtistDetails(artistId, artistName) {
    try {
      const res = await fetch(`/api/yt/artist?id=${encodeURIComponent(artistId || '')}&name=${encodeURIComponent(artistName || '')}`);
      if (res.ok) {
        const data = await res.json();
        return data; // { artist, topSongs, allSongs }
      }
    } catch (e) {
      console.error('getArtistDetails error:', e);
    }

    // Fallback if needed
    const songs = await this.searchTracks(artistName, 12);
    return {
      artist: {
        id: artistId || 'art-' + encodeURIComponent(artistName),
        name: artistName,
        headerBanner: songs[0]?.artwork || DEFAULT_ARTWORK,
        avatar: songs[0]?.artwork || DEFAULT_ARTWORK,
        monthlyListeners: '4,9 jt pendengar bulanan',
        verified: true,
      },
      topSongs: songs.slice(0, 5),
      allSongs: songs,
    };
  },

  /**
   * Search tracks by keyword (uses combined searchAll with studio original ranking)
   */
  async searchTracks(query, limit = 25) {
    if (!query || !query.trim()) return [];

    try {
      const data = await this.searchAll(query);
      if (data.songs && data.songs.length > 0) {
        return data.songs.slice(0, limit);
      }
    } catch (e) {
      console.warn('searchTracks combined failed, trying fallback:', e);
    }

    try {
      const url = `https://itunes.apple.com/search?term=${encodeURIComponent(query.trim())}&entity=song&limit=${limit}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error('Search request failed');

      const data = await res.json();
      const list = (data.results || []).map(item => this.formatTrack(item));
      list.sort((a, b) => calculateSearchRelevance(b, query) - calculateSearchRelevance(a, query));
      return list;
    } catch (e) {
      console.error('Music search error:', e);
      return [];
    }
  },

  /**
   * Search for single track to match an imported title/artist
   */
  async findTrackMatch(title, artist) {
    const q = `${title} ${artist || ''}`.trim();
    const results = await this.searchTracks(q, 5);
    if (results.length > 0) return results[0];

    // Fallback search with title only
    const titleOnlyResults = await this.searchTracks(title, 3);
    return titleOnlyResults[0] || null;
  },

  /**
   * Extract YouTube Video ID from any URL, share link, or raw ID.
   * Handles: youtu.be, music.youtube.com, m.youtube.com, shorts, embed, and share text with embedded links.
   */
  extractYouTubeId(input) {
    if (!input || typeof input !== 'string') return null;
    const clean = input.trim();

    // 1. Support share message text with embedded URL (e.g. "Check out this song: https://youtu.be/...")
    const urlMatch = clean.match(/https?:\/\/[^\s]+/i);
    let target = urlMatch ? urlMatch[0] : clean;
    target = target.replace(/[\.,!?;:)\>\]"']+$/, '');

    try {
      const url = new URL(target.startsWith('http') ? target : `https://${target}`);
      let videoId = url.searchParams.get('v');
      if (!videoId) {
        if (url.hostname.includes('youtu.be')) {
          const parts = url.pathname.split('/').filter(Boolean);
          videoId = parts[0];
        } else if (url.pathname.includes('/shorts/') || url.pathname.includes('/embed/') || url.pathname.includes('/live/') || url.pathname.includes('/v/')) {
          const parts = url.pathname.split('/').filter(Boolean);
          videoId = parts[parts.length - 1];
        }
      }
      if (videoId) {
        if (videoId.includes('?')) videoId = videoId.split('?')[0];
        if (videoId.includes('&')) videoId = videoId.split('&')[0];
        if (/^[a-zA-Z0-9_-]{11}$/.test(videoId)) return videoId;
      }
    } catch (_) {}

    // 2. Regex fallback for non-standard formats
    const match = target.match(/(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:embed\/|v\/|watch\?.*v=|shorts\/|live\/))([a-zA-Z0-9_-]{11})/i);
    if (match) return match[1];
    if (/^[a-zA-Z0-9_-]{11}$/.test(clean)) return clean;
    return null;
  },

  /**
   * Resolve YouTube URL or Query into a playable Track
   */
  async resolveYouTubeImport(urlOrQuery) {
    if (!urlOrQuery || typeof urlOrQuery !== 'string') return null;
    const clean = urlOrQuery.trim();
    const videoId = this.extractYouTubeId(clean);

    if (videoId) {
      try {
        const oembedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`;
        const res = await fetch(oembedUrl);
        if (res.ok) {
          const data = await res.json();
          let rawTitle = data.title || 'YouTube Music';
          let artist = data.author_name || 'YouTube';
          let title = rawTitle;

          // If title is "Artist - Title" format
          if (rawTitle.includes(' - ')) {
            const parts = rawTitle.split(' - ');
            artist = parts[0].trim();
            title = parts.slice(1).join(' - ').trim();
          }

          // Clean common video tag strings
          title = title.replace(/\(Official (Music )?Video\)/gi, '')
                       .replace(/\[Official (Music )?Video\]/gi, '')
                       .replace(/\(Official Audio\)/gi, '')
                       .replace(/\[Official Audio\]/gi, '')
                       .replace(/\(Lyric(s)? Video\)/gi, '')
                       .replace(/\[Lyric(s)? Video\]/gi, '')
                       .trim();

          return {
            id: `yt_${videoId}`,
            title,
            artist,
            album: 'YouTube Import',
            artwork: getHighResArtworkUrl(`https://i.ytimg.com/vi/${videoId}/hq720.jpg`),
            originalArtwork: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
            audioUrl: '',
            videoId: videoId,
            duration: 210,
            genre: 'YouTube Import',
            releaseYear: new Date().getFullYear().toString(),
            isYouTubeImport: true,
          };
        }
      } catch (e) {
        console.warn('YouTube oEmbed resolve error:', e);
      }

      // Direct fallback - We have videoId, so NEVER fail
      return {
        id: `yt_${videoId}`,
        title: `YouTube Video (${videoId})`,
        artist: 'YouTube',
        album: 'YouTube Import',
        artwork: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
        audioUrl: '',
        videoId: videoId,
        duration: 210,
        genre: 'YouTube Import',
        releaseYear: new Date().getFullYear().toString(),
        isYouTubeImport: true,
      };
    }

    // If query string instead of direct link, resolve via backend search
    try {
      const match = await this.resolveYouTubeMatch(clean, '');
      if (match && match.videoId) {
        return {
          id: `yt_${match.videoId}`,
          title: match.title || clean,
          artist: match.artist || 'YouTube',
          album: 'YouTube Search',
          artwork: match.thumbnail || `https://i.ytimg.com/vi/${match.videoId}/hqdefault.jpg`,
          audioUrl: '',
          videoId: match.videoId,
          duration: match.duration || 210,
          genre: 'YouTube Import',
          releaseYear: new Date().getFullYear().toString(),
          isYouTubeImport: true,
        };
      }

      // Catalog fallback (iTunes/Deezer -> YouTube match)
      const tracks = await this.searchTracks(clean, 2);
      if (tracks && tracks.length > 0) {
        const top = tracks[0];
        const topMatch = await this.resolveYouTubeMatch(top.title, top.artist, top.duration);
        if (topMatch && topMatch.videoId) {
          return {
            ...top,
            videoId: topMatch.videoId,
            duration: topMatch.duration || top.duration,
            artwork: topMatch.thumbnail || top.artwork,
            isYouTubeImport: true,
          };
        }
        return {
          ...top,
          isYouTubeImport: true,
        };
      }
    } catch (_) {}

    return null;
  },

  /**
   * Search Tracks by Lyrics snippet (using YouTube Music full lyrics indexing + LRCLIB)
   */
  async searchTracksByLyrics(lyricsQuery) {
    if (!lyricsQuery || !lyricsQuery.trim()) return [];
    const q = lyricsQuery.trim();

    try {
      const ytPromise = fetch(`/api/yt/search-multi?q=${encodeURIComponent(q)}`)
        .then(r => r.ok ? r.json() : null)
        .catch(() => null);

      const lrclibPromise = fetch(`https://lrclib.net/api/search?q=${encodeURIComponent(q)}`)
        .then(r => r.ok ? r.json() : [])
        .catch(() => []);

      const [ytData, lrcData] = await Promise.all([ytPromise, lrclibPromise]);

      const results = [];
      const seen = new Set();

      if (ytData?.songs && Array.isArray(ytData.songs)) {
        for (const s of ytData.songs) {
          if (!s || !s.title) continue;
          const key = `${s.title.toLowerCase().trim()}_${(s.artist || '').toLowerCase().trim()}`;
          if (!seen.has(key)) {
            seen.add(key);
            results.push({
              ...s,
              isLyricMatch: true,
              lyricSnippet: q,
            });
          }
        }
      }

      if (Array.isArray(lrcData)) {
        for (const item of lrcData) {
          if (!item.trackName || !item.artistName) continue;
          const key = `${item.trackName.toLowerCase().trim()}_${item.artistName.toLowerCase().trim()}`;
          if (!seen.has(key)) {
            seen.add(key);
            results.push({
              id: `lrc_${item.id}`,
              title: item.trackName,
              artist: item.artistName,
              album: item.albumName || 'Single',
              artwork: DEFAULT_ARTWORK,
              audioUrl: '',
              videoId: null,
              duration: item.duration ? Math.round(item.duration) : 180,
              isLyricMatch: true,
              lyricSnippet: q,
            });
          }
        }
      }

      if (results.length > 0) return results.slice(0, 20);
      return await this.searchTracks(`${q} lagu`, 10);
    } catch (e) {
      console.warn('searchTracksByLyrics error:', e);
      return [];
    }
  },

  /**
   * Format raw iTunes API track into clean app format
   */
  formatTrack(item) {
    let artwork = DEFAULT_ARTWORK;
    if (item.artworkUrl100) {
      artwork = getHighResArtworkUrl(item.artworkUrl100);
    }

    return {
      id: item.trackId ? item.trackId.toString() : 't-' + Math.random().toString(36).substr(2, 9),
      title: item.trackName || 'Unknown Title',
      artist: item.artistName || 'Unknown Artist',
      album: item.collectionName || 'Single',
      artwork: artwork,
      originalArtwork: item.artworkUrl100 || DEFAULT_ARTWORK,
      audioUrl: item.previewUrl || '',
      videoId: null, // Will be filled dynamically by YouTube Matcher
      duration: item.trackTimeMillis ? Math.round(item.trackTimeMillis / 1000) : 180,
      genre: item.primaryGenreName || 'Pop',
      releaseYear: item.releaseDate ? item.releaseDate.slice(0, 4) : '2024',
    };
  },

  /**
   * Fetch Live Trending Tracks directly from iTunes API using varied, multi-genre hitmaker artists
   */
  async fetchTrendingTracks() {
    try {
      const topArtists = [
        'The Weeknd', 'Bruno Mars', 'Coldplay', 'Taylor Swift', 'Billie Eilish',
        'Sheila On 7', 'Dewa 19', 'NOAH', 'Mahalini', 'Tulus',
        'Linkin Park', 'Avenged Sevenfold', 'NewJeans', 'Denny Caknan'
      ];
      // Shuffle slightly so home is fresh and well-diversified
      const shuffledQueries = [...topArtists].sort(() => Math.random() - 0.5).slice(0, 4);
      const promises = shuffledQueries.map(q => this.searchTracks(q, 4));
      const resultsArrays = await Promise.all(promises);
      const combined = resultsArrays.flat().filter(isCleanPopularTrack);

      if (combined.length > 0) {
        const unique = [];
        const seen = new Set();
        for (const t of combined) {
          if (!seen.has(t.id)) {
            seen.add(t.id);
            unique.push(t);
          }
        }
        return unique.slice(0, 18);
      }
    } catch (e) {
      console.warn('Failed to fetch live trending tracks', e);
    }

    const fallbackResults = (await this.searchTracks('Coldplay', 10)).filter(isCleanPopularTrack);
    return fallbackResults.length > 0 ? fallbackResults : [];
  },

  /**
   * Smart Next / Autoplay: Intelligently finds famous, popular tracks related to current track and playlist
   */
  async getSmartRecommendations(currentTrack, existingQueue = []) {
    if (!currentTrack) return [];
    const radioTracks = await this.getArtistGenreRadio(currentTrack, 15, existingQueue);
    const existingIds = new Set(existingQueue.map(t => t.id));
    const existingTitles = new Set(existingQueue.map(t => (t.title || '').toLowerCase().trim()));
    return radioTracks.filter(t => !existingIds.has(t.id) && !existingTitles.has((t.title || '').toLowerCase().trim()));
  },

  /**
   * Search Radio Mode:
   * Generates a context-aware randomized queue of TOP POPULAR, FAMOUS songs matching the artist or peer hitmakers.
   * Dynamically adapts to the artist, genre, and playlist without static bias.
   */
  async getArtistGenreRadio(track, limit = 18, playlistContext = []) {
    if (!track) return [];
    const targetId = track.id;
    const targetTitle = (track.title || '').toLowerCase().trim();
    const targetArtist = (track.artist || '').toLowerCase().trim();

    try {
      const seen = new Set();
      if (targetId) seen.add(targetId);
      seen.add(targetTitle);

      const targetRegion = detectTrackRegion(track.artist, track.title, track.genre);

      // 1. Identify peer hitmaker cluster dynamically using artist, genre, playlist context, and title
      const peerArtists = getSimilarArtists(track.artist, track.genre, playlistContext, track.title);

      // 2. Fetch user's frequently played & liked songs (strictly matching target region!)
      const userFavoriteHits = [];
      try {
        const liked = storageService.getLikedTracks() || [];
        const taste = storageService.getTasteProfile();
        const mostPlayed = taste?.mostPlayedTracks || [];
        const userPool = [...liked, ...mostPlayed];

        for (const t of userPool) {
          if (!t || !t.id || !t.title) continue;
          const artLower = (t.artist || '').toLowerCase();
          const cleanT = (t.title || '').toLowerCase().trim();
          if (seen.has(t.id) || seen.has(cleanT)) continue;

          // STRICT REGION CHECK: If current track is Western, do NOT include Indonesian songs!
          const itemRegion = detectTrackRegion(t.artist, t.title, t.genre);
          if (itemRegion !== targetRegion) continue;

          // If track belongs to the target artist or matching genre peers
          const isArtistMatch = artLower.includes(targetArtist) || targetArtist.includes(artLower);
          const isPeerMatch = peerArtists.some(p => artLower.includes(p.toLowerCase()));

          if ((isArtistMatch || isPeerMatch) && isCleanPopularTrack(t)) {
            seen.add(t.id);
            seen.add(cleanT);
            userFavoriteHits.push(t);
          }
        }
      } catch (err) {
        console.warn('Taste profile lookup in radio:', err);
      }

      // 3. Pick 5-6 random peers each time from the cluster pool for infinite non-template variety
      const selectedPeers = [...peerArtists].sort(() => Math.random() - 0.5).slice(0, 6);

      // 4. Fetch artist's verified top hits & peer hitmakers in parallel
      const artistSearchPromise = this.searchTracks(track.artist, 15).catch(() => []);
      const peerPromises = selectedPeers.map(peer => this.searchTracks(peer, 8).catch(() => []));

      const [artistSearch, ...peerResults] = await Promise.all([
        artistSearchPromise,
        ...peerPromises,
      ]);

      // Collect artist's popular tracks and randomly sample 2-3 hits from the top hits
      const cleanArtistHits = [];
      for (const t of artistSearch) {
        const cleanT = (t.title || '').toLowerCase().trim();
        if (isCleanPopularTrack(t) && !seen.has(t.id) && !seen.has(cleanT)) {
          seen.add(t.id);
          seen.add(cleanT);
          cleanArtistHits.push(t);
        }
      }
      // Sample 2-3 different artist hits each time
      const sampledArtistHits = [...cleanArtistHits].sort(() => Math.random() - 0.5).slice(0, 3);

      // Collect peer hitmakers' popular tracks and randomly sample 1-2 hits from each peer
      const sampledPeerHits = [];
      peerResults.forEach(peerSongs => {
        const cleanPeers = [];
        for (const t of peerSongs) {
          const cleanT = (t.title || '').toLowerCase().trim();
          const songRegion = detectTrackRegion(t.artist, t.title, t.genre);
          if (songRegion === targetRegion && isCleanPopularTrack(t) && !seen.has(t.id) && !seen.has(cleanT)) {
            seen.add(t.id);
            seen.add(cleanT);
            cleanPeers.push(t);
          }
        }
        // Randomly sample 1-2 tracks from this peer
        const sampled = cleanPeers.sort(() => Math.random() - 0.5).slice(0, 2);
        sampledPeerHits.push(...sampled);
      });

      // Shuffle the peer hits so the artist ordering is dynamic and exciting
      sampledPeerHits.sort(() => Math.random() - 0.5);

      // Fallback: If not enough hits found, query remaining peer hitmakers from same genre
      if (sampledArtistHits.length + sampledPeerHits.length < 8) {
        const extraPeers = peerArtists.filter(p => !selectedPeers.includes(p)).slice(0, 4);
        for (const peer of extraPeers) {
          const peerSongs = await this.searchTracks(peer, 5).catch(() => []);
          for (const t of peerSongs) {
            const cleanT = (t.title || '').toLowerCase().trim();
            const songRegion = detectTrackRegion(t.artist, t.title, t.genre);
            if (songRegion === targetRegion && isCleanPopularTrack(t) && !seen.has(t.id) && !seen.has(cleanT)) {
              seen.add(t.id);
              seen.add(cleanT);
              sampledPeerHits.push(t);
            }
          }
        }
      }

      // Build structured popular queue:
      const finalRadioQueue = [];
      let userIdx = 0;
      let artistIdx = 0;
      let peerIdx = 0;

      while (
        finalRadioQueue.length < limit &&
        (userIdx < userFavoriteHits.length || artistIdx < sampledArtistHits.length || peerIdx < sampledPeerHits.length)
      ) {
        // Interleave user's frequently played / liked song if available
        if (userIdx < userFavoriteHits.length && (finalRadioQueue.length === 0 || finalRadioQueue.length % 3 === 0)) {
          finalRadioQueue.push(userFavoriteHits[userIdx++]);
        }
        // Interleave artist's top hit
        if (artistIdx < sampledArtistHits.length && finalRadioQueue.length < limit) {
          finalRadioQueue.push(sampledArtistHits[artistIdx++]);
        }
        // Interleave peer's top hit
        if (peerIdx < sampledPeerHits.length && finalRadioQueue.length < limit) {
          finalRadioQueue.push(sampledPeerHits[peerIdx++]);
        }
        // If artist and peer pools are exhausted, add remaining user favorites
        if (artistIdx >= sampledArtistHits.length && peerIdx >= sampledPeerHits.length && userIdx < userFavoriteHits.length && finalRadioQueue.length < limit) {
          finalRadioQueue.push(userFavoriteHits[userIdx++]);
        }
      }

      return finalRadioQueue.slice(0, limit);
    } catch (e) {
      console.warn('getArtistGenreRadio error:', e);
      return [];
    }
  },

  /**
   * Fetch Dynamic Personalized Home Sections based on User Taste Profile
   */
  async fetchPersonalizedHome(tasteProfile) {
    try {
      if (tasteProfile && tasteProfile.hasHistory) {
        const topArtistsList = (tasteProfile.topArtists || []).slice(0, 5);
        const topArtist = topArtistsList[0];
        const secondaryArtist = topArtistsList[1];
        const thirdArtist = topArtistsList[2];
        const lastTrack = tasteProfile.lastPlayedTrack;

        // Fetch tracks for top artists, smart recommendations & trending in parallel
        const [artistTracks, secondaryArtistTracks, thirdArtistTracks, similarTracks, trending] = await Promise.all([
          topArtist ? this.searchTracks(topArtist, 8) : Promise.resolve([]),
          secondaryArtist ? this.searchTracks(secondaryArtist, 8) : Promise.resolve([]),
          thirdArtist ? this.searchTracks(thirdArtist, 8) : Promise.resolve([]),
          lastTrack ? this.getSmartRecommendations(lastTrack) : Promise.resolve([]),
          this.fetchTrendingTracks(),
        ]);

        // Construct dynamic, randomized and artist-diverse quick cards
        const rawPool = [
          ...(tasteProfile.likedTracks || []),
          ...(tasteProfile.recentTracks || []),
          ...(tasteProfile.mostPlayedTracks || []),
          ...(similarTracks || []),
          ...(artistTracks || []),
          ...(secondaryArtistTracks || []),
          ...(thirdArtistTracks || []),
          ...(trending || []),
        ];

        // Shuffle candidates for fresh, randomized discovery on every refresh
        const shuffledPool = [...rawPool].sort(() => Math.random() - 0.5);

        const seenIds = new Set();
        const seenTitles = new Set();
        const artistCounts = {};
        const quickCards = [];

        // Pass 1: Maximum 1 song per artist for diverse Spotify-style cards
        for (const t of shuffledPool) {
          if (!t || !t.id || !t.title) continue;
          const artKey = (t.artist || '').trim().toLowerCase();
          const titleKey = (t.title || '').trim().toLowerCase();
          if (seenIds.has(t.id) || seenTitles.has(titleKey)) continue;
          if (artistCounts[artKey] && artistCounts[artKey] >= 1) continue;

          seenIds.add(t.id);
          seenTitles.add(titleKey);
          artistCounts[artKey] = (artistCounts[artKey] || 0) + 1;
          quickCards.push(t);
          if (quickCards.length >= 6) break;
        }

        // Pass 2: If fewer than 6, allow max 2 per artist
        if (quickCards.length < 6) {
          for (const t of shuffledPool) {
            if (!t || !t.id || !t.title) continue;
            const artKey = (t.artist || '').trim().toLowerCase();
            const titleKey = (t.title || '').trim().toLowerCase();
            if (seenIds.has(t.id) || seenTitles.has(titleKey)) continue;
            if (artistCounts[artKey] && artistCounts[artKey] >= 2) continue;

            seenIds.add(t.id);
            seenTitles.add(titleKey);
            artistCounts[artKey] = (artistCounts[artKey] || 0) + 1;
            quickCards.push(t);
            if (quickCards.length >= 6) break;
          }
        }

        // Pass 3: Fill remaining with unique trending tracks
        if (quickCards.length < 6) {
          for (const t of trending) {
            if (!t || !t.id || !t.title) continue;
            const titleKey = (t.title || '').trim().toLowerCase();
            if (!seenIds.has(t.id) && !seenTitles.has(titleKey)) {
              seenIds.add(t.id);
              seenTitles.add(titleKey);
              quickCards.push(t);
              if (quickCards.length >= 6) break;
            }
          }
        }

        const sections = [
          ...(topArtist ? [{
            id: 'top-artist',
            title: `Karena kamu sering memutar ${topArtist}`,
            subtitle: `Rekomendasi terbaik dan lagu serupa dengan artis favoritmu`,
            badge: 'Berdasarkan Selera Musik',
            tracks: artistTracks.length > 0 ? artistTracks : trending.slice(0, 8),
          }] : []),
          ...(lastTrack ? [{
            id: 'similar-vibe',
            title: `Lagu serupa dengan "${lastTrack.title}"`,
            subtitle: `Dipersonalisasi berdasarkan musik yang baru saja kamu dengar`,
            badge: 'Radio Pintar',
            tracks: similarTracks.length > 0 ? similarTracks : trending.slice(6, 14),
          }] : []),
          ...(secondaryArtist && secondaryArtistTracks.length > 0 ? [{
            id: 'secondary-artist',
            title: `Eksplorasi ${secondaryArtist}`,
            subtitle: `Koleksi musik pilihan dari artis favoritmu yang lain`,
            badge: 'Artis Pilihan',
            tracks: secondaryArtistTracks,
          }] : []),
          ...(thirdArtist && thirdArtistTracks.length > 0 ? [{
            id: 'third-artist',
            title: `Hits dari ${thirdArtist}`,
            subtitle: `Pilihan lagu terbaik dari ${thirdArtist}`,
            badge: 'Artis Favorit',
            tracks: thirdArtistTracks,
          }] : []),
          {
            id: 'trending-section',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Tangga lagu terhangat dan musik paling banyak didengar',
            badge: 'Trending',
            tracks: trending,
          },
        ];

        return {
          isPersonalized: true,
          topArtist,
          quickCards: quickCards.slice(0, 6),
          sections,
          trending,
        };
      }

      // Default state for brand new user with no history yet
      const trending = await this.fetchTrendingTracks();
      return {
        isPersonalized: false,
        quickCards: trending.slice(0, 6),
        sections: [
          {
            id: 'trending-today',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Musik yang sedang viral dan menduduki puncak tangga lagu',
            badge: 'Trending',
            tracks: trending.slice(0, 10),
          },
          {
            id: 'fresh-finds',
            title: 'Pilihan Musik Segar & Terkini',
            subtitle: 'Eksplorasi ragam genre mulai dari pop, r&b, hingga akustik',
            badge: 'Pilihan Untukmu',
            tracks: trending.slice(6, 16),
          },
        ],
        trending,
      };
    } catch (e) {
      console.warn('Personalized home fetch failed, using fallback:', e);
      const trending = await this.fetchTrendingTracks();
      return {
        isPersonalized: false,
        quickCards: trending.slice(0, 6),
        sections: [
          {
            id: 'fallback-trending',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Musik terhangat',
            badge: 'Trending',
            tracks: trending,
          },
        ],
        trending,
      };
    }
  },
};
