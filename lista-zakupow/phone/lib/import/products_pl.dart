/// Typowe produkty - słownik do autokorekty rozpoznanego pisma, gdy w historii
/// jeszcze nic nie ma. Historia użytkownika ma pierwszeństwo przed tą listą.
const List<String> commonProducts = [
  // nabiał
  'Mleko', 'Masło', 'Margaryna', 'Jajka', 'Ser żółty', 'Ser biały', 'Twaróg', 'Serek wiejski',
  'Serek homogenizowany', 'Jogurt', 'Jogurt naturalny', 'Kefir', 'Maślanka', 'Śmietana',
  'Śmietanka', 'Mozzarella', 'Feta', 'Parmezan',
  // pieczywo
  'Chleb', 'Bułki', 'Bagietka', 'Rogaliki', 'Tortilla', 'Pieczywo chrupkie', 'Bułka tarta',
  // warzywa
  'Ziemniaki', 'Pomidory', 'Ogórki', 'Ogórek', 'Cebula', 'Czosnek', 'Marchew', 'Marchewka',
  'Pietruszka', 'Seler', 'Por', 'Kapusta', 'Kalafior', 'Brokuł', 'Sałata', 'Rukola', 'Szpinak',
  'Papryka', 'Cukinia', 'Bakłażan', 'Kukurydza', 'Groszek', 'Fasola', 'Fasolka', 'Pieczarki',
  'Rzodkiewka', 'Szczypiorek', 'Koperek', 'Natka pietruszki', 'Buraki', 'Dynia', 'Awokado',
  // owoce
  'Jabłka', 'Banany', 'Gruszki', 'Cytryny', 'Cytryna', 'Pomarańcze', 'Mandarynki', 'Winogrona',
  'Truskawki', 'Maliny', 'Borówki', 'Śliwki', 'Brzoskwinie', 'Kiwi', 'Ananas', 'Arbuz', 'Melon',
  'Grejpfrut', 'Limonka',
  // mięso i ryby
  'Kurczak', 'Filet z kurczaka', 'Udka', 'Indyk', 'Schab', 'Karkówka', 'Mięso mielone', 'Wołowina',
  'Wieprzowina', 'Szynka', 'Kiełbasa', 'Parówki', 'Boczek', 'Salami', 'Pasztet', 'Kabanosy',
  'Ryba', 'Łosoś', 'Dorsz', 'Tuńczyk', 'Śledzie', 'Paluszki rybne',
  // spiżarnia
  'Mąka', 'Cukier', 'Cukier puder', 'Sól', 'Pieprz', 'Ryż', 'Makaron', 'Kasza', 'Kasza gryczana',
  'Kasza jaglana', 'Płatki owsiane', 'Płatki kukurydziane', 'Musli', 'Olej', 'Oliwa', 'Ocet',
  'Ketchup', 'Musztarda', 'Majonez', 'Chrzan', 'Koncentrat pomidorowy', 'Passata', 'Przyprawy',
  'Papryka słodka', 'Oregano', 'Bazylia', 'Cynamon', 'Drożdże', 'Proszek do pieczenia',
  'Budyń', 'Galaretka', 'Dżem', 'Miód', 'Nutella', 'Masło orzechowe', 'Orzechy', 'Rodzynki',
  'Konserwa', 'Groszek konserwowy', 'Kukurydza konserwowa', 'Ciecierzyca', 'Soczewica',
  'Bulion', 'Kostki rosołowe', 'Sos', 'Pesto',
  // napoje
  'Woda', 'Woda gazowana', 'Sok', 'Sok pomarańczowy', 'Sok jabłkowy', 'Napój', 'Cola', 'Herbata',
  'Kawa', 'Kakao', 'Piwo', 'Wino', 'Mleko roślinne',
  // słodycze i przekąski
  'Czekolada', 'Ciastka', 'Wafelki', 'Cukierki', 'Żelki', 'Chipsy', 'Paluszki', 'Krakersy',
  'Lody', 'Batoniki', 'Popcorn',
  // mrożonki
  'Mrożonki', 'Frytki', 'Pizza', 'Pierogi', 'Warzywa mrożone',
  // chemia i higiena
  'Papier toaletowy', 'Ręczniki papierowe', 'Chusteczki', 'Chusteczki nawilżane',
  'Płyn do naczyń', 'Tabletki do zmywarki', 'Proszek do prania', 'Płyn do płukania',
  'Kapsułki do prania', 'Płyn do podłóg', 'Domestos', 'Gąbki', 'Worki na śmieci', 'Folia aluminiowa',
  'Folia spożywcza', 'Papier do pieczenia', 'Mydło', 'Żel pod prysznic', 'Szampon', 'Odżywka',
  'Pasta do zębów', 'Szczoteczka do zębów', 'Dezodorant', 'Krem', 'Płatki kosmetyczne',
  'Patyczki higieniczne', 'Podpaski', 'Pieluchy', 'Maszynki do golenia', 'Pianka do golenia',
  // inne
  'Baterie', 'Żarówka', 'Zapałki', 'Świeczki', 'Karma dla kota', 'Karma dla psa', 'Żwirek',
  'Lekarstwa', 'Witaminy', 'Kwiaty',
];
