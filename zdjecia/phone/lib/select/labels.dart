// Etykiety ML Kit (model podstawowy, ~450 nazw: developers.google.com/ml-kit/vision/image-labeling/label-map)
// pogrupowane w to, co czyni zdjęcie ciekawym na zegarku, i w to, co je wyklucza.

class LabelGroup {
  const LabelGroup(this.tag, this.weight, this.labels);

  /// Krótki powód wyboru pokazywany w aplikacji
  final String tag;
  final double weight;
  final Set<String> labels;
}

const labelGroups = <LabelGroup>[
  LabelGroup('emocje', 0.5, {'Smile', 'Laugh', 'Fun', 'Love', 'Selfie'}),
  LabelGroup('dziecko', 0.5, {'Baby', 'Playground', 'Swing', 'Toy', 'Stuffed toy', 'Plush'}),
  LabelGroup('zwierzę', 0.5, {
    'Pet', 'Dog', 'Cat', 'Horse', 'Bird', 'Duck', 'Cattle', 'Herd', 'Turtle', 'Butterfly', 'Insect',
    'Shetland sheepdog', 'Dalmatian', 'Basset hound', 'Cairn terrier', 'Cavalier', 'Ragdoll', 'Sphynx',
    'Himalayan', 'Pixie-bob', 'Shikoku', 'Gerbil', 'Penguin', 'Waterfowl', 'Bear', 'Seal',
  }),
  LabelGroup('święto', 0.45, {
    'Party', 'Marriage', 'Bride', 'Groom', 'Veil', 'Graduation', 'Mortarboard', 'Christmas', 'Santa claus',
    'Fireworks', 'Sparkler', 'Balloon', 'Cake', 'Carnival', 'Concert', 'Dance', 'Prom', 'Event', 'Thanksgiving',
    'Hanukkah', 'Grandparent', 'Picnic', 'Bonfire',
  }),
  LabelGroup('zachód słońca', 0.45, {'Sunset', 'Rainbow', 'Aurora', 'Moon', 'Star', 'Lightning', 'Fog'}),
  LabelGroup('krajobraz', 0.35, {
    'Mountain', 'Lake', 'Beach', 'River', 'Waterfall', 'Forest', 'Glacier', 'Canyon', 'Cliff', 'Field',
    'Prairie', 'Dune', 'Desert', 'Iceberg', 'Icicle', 'Volcano', 'Jungle', 'Swamp', 'Cave', 'Sky', 'Skyline',
    'Park', 'Garden', 'Farm', 'Ranch', 'Sand', 'Reef', 'Underwater',
  }),
  LabelGroup('kwiaty', 0.3, {'Flower', 'Petal', 'Flora', 'Flowerpot'}),
  LabelGroup('wycieczka', 0.3, {
    'Vacation', 'Camping', 'Backpacking', 'Castle', 'Monument', 'Ruins', 'Lighthouse', 'Palace', 'Cathedral',
    'Temple', 'Church', 'Statue', 'Museum', 'Ferris wheel', 'Pier', 'Bridge', 'Tower', 'Safari',
  }),
  LabelGroup('sport', 0.3, {
    'Sports', 'Cycling', 'Running', 'Marathon', 'Skiing', 'Sledding', 'Snowboarding', 'Swimming', 'Surfing',
    'Kayak', 'Canoe', 'Rowing', 'Boat', 'Sailboat', 'Fishing', 'Soccer', 'Competition', 'Race', 'Scuba diving',
    'Snorkeling', 'Gymnastics', 'Archery',
  }),
  LabelGroup('jedzenie', 0.15, {
    'Food', 'Meal', 'Lunch', 'Supper', 'Cuisine', 'Pizza', 'Sushi', 'Bread', 'Fruit', 'Vegetable', 'Pie',
    'Cookie', 'Gelato', 'Coffee', 'Cappuccino', 'Wine',
  }),
  // Nudne tło - lekko w dół
  LabelGroup('', -0.3, {
    'Computer', 'Television', 'Mobile phone', 'Odometer', 'Tire', 'Product', 'Countertop', 'Shelf', 'Drawer',
    'Desk', 'Bathroom', 'Sink', 'Junk', 'Asphalt', 'Pattern', 'Tile', 'Cabinetry', 'Windshield', 'Bumper',
    'Wheel', 'Subwoofer', 'Lampshade', 'Curtain', 'Textile', 'Metal', 'Brick', 'Wall', 'Soil',
  }),
];

/// Zdjęcia dokumentów, ekranów i kartek - nie na zegarek
const documentLabels = <String>{
  'Screenshot', 'Receipt', 'Paper', 'Menu', 'Newspaper', 'News', 'Poster', 'Web page', 'Whiteboard',
  'Blackboard', 'Presentation', 'Passport', 'Money', 'Icon', 'Comics',
};

/// Pewność, od której etykieta dokumentu wyklucza zdjęcie
const double documentConfidence = 0.6;

/// Tyle liter/cyfr na zdjęciu bez twarzy = raczej dokument albo kartka
const int documentTextChars = 60;
