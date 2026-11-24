// Edge+: a small, curated recipe book.
//
// There is no free recipe API with German recipes and trustworthy nutrition,
// so these are typical home recipes written out by hand. Nutrition is never
// typed per recipe: it is summed from the ingredients' per-100 g values
// (rounded table values, BLS/USDA order of magnitude), so a recipe and its
// shopping list can never disagree. An estimate, like every typed number.

/// Shopping-list aisles, in the order a list is printed.
enum Aisle { produce, chilled, meat, pantry, spices }

String aisleLabel(Aisle a, {bool de = true}) => switch (a) {
  Aisle.produce => de ? 'Obst & Gemüse' : 'Produce',
  Aisle.chilled => de ? 'Kühlregal' : 'Chilled',
  Aisle.meat => de ? 'Fleisch & Fisch' : 'Meat & fish',
  Aisle.pantry => de ? 'Vorrat' : 'Pantry',
  Aisle.spices => de ? 'Gewürze & Basics' : 'Spices & basics',
};

class Ingredient {
  const Ingredient(
    this.name,
    this.aisle, [
    this.kcal = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fibre = 0,
    this.pieceG,
    this.piece = 'Stück',
    this.ml = false,
  ]);

  final String name;
  final Aisle aisle;

  /// Per 100 g (or 100 ml for [ml] items, density taken as 1).
  final double kcal, protein, carbs, fat, fibre;

  /// Weight of one piece, when the thing is bought and counted in pieces.
  final double? pieceG;
  final String piece;
  final bool ml;
}

/// A spice or basic: listed, never weighed.
const _s = Aisle.spices;

const kIngredients = <String, Ingredient>{
  // Obst & Gemüse
  'banane': Ingredient('Banane', Aisle.produce, 93, 1.2, 20, 0.2, 2, 100),
  'apfel': Ingredient('Apfel', Aisle.produce, 52, 0.3, 11.4, 0.2, 2.4, 180),
  'heidelbeeren': Ingredient('Heidelbeeren', Aisle.produce, 57, 0.7, 12, 0.3, 2.4),
  'avocado': Ingredient('Avocado', Aisle.produce, 160, 2, 3.5, 14.7, 6.7, 140),
  'zitrone': Ingredient('Zitrone', Aisle.produce, 29, 1.1, 3, 0.3, 2.8, 100),
  'tomaten': Ingredient('Tomaten', Aisle.produce, 18, 0.9, 2.6, 0.2, 1.2),
  'gurke': Ingredient('Gurke', Aisle.produce, 15, 0.6, 2.2, 0.1, 0.5, 300),
  'paprika': Ingredient('Paprika', Aisle.produce, 31, 1, 5, 0.3, 2.1, 150),
  'zwiebel': Ingredient('Zwiebel', Aisle.produce, 40, 1.1, 7.6, 0.1, 1.7, 80),
  'knoblauch': Ingredient('Knoblauch', Aisle.produce, 149, 6.4, 31, 0.5, 2.1, 4, 'Zehe'),
  'ingwer': Ingredient('Ingwer', Aisle.produce, 80, 1.8, 16, 0.8, 2),
  'karotte': Ingredient('Karotten', Aisle.produce, 41, 0.9, 6.8, 0.2, 2.8, 75),
  'brokkoli': Ingredient('Brokkoli', Aisle.produce, 34, 2.8, 4, 0.4, 2.6),
  'spinat': Ingredient('Babyspinat', Aisle.produce, 23, 2.9, 1.4, 0.4, 2.2),
  'zucchini': Ingredient('Zucchini', Aisle.produce, 17, 1.2, 2.2, 0.3, 1, 250),
  'champignons': Ingredient('Champignons', Aisle.produce, 22, 3.1, 0.6, 0.3, 2),
  'salat': Ingredient('Römersalat', Aisle.produce, 15, 1.2, 1.7, 0.2, 1.5),
  'kartoffeln': Ingredient('Kartoffeln', Aisle.produce, 77, 2, 15.6, 0.1, 2.1),
  'suesskartoffel': Ingredient('Süßkartoffeln', Aisle.produce, 86, 1.6, 17, 0.1, 3),
  'petersilie': Ingredient('Petersilie', _s),
  'basilikum': Ingredient('Basilikum', _s),
  // Kühlregal
  'milch': Ingredient('Milch 1,5 %', Aisle.chilled, 47, 3.4, 4.8, 1.5, 0, null, 'Stück', true),
  'skyr': Ingredient('Skyr', Aisle.chilled, 63, 11, 4, 0.2),
  'magerquark': Ingredient('Magerquark', Aisle.chilled, 67, 12, 4, 0.2),
  'joghurt': Ingredient('Naturjoghurt 1,5 %', Aisle.chilled, 47, 3.5, 4.5, 1.5),
  'ei': Ingredient('Eier', Aisle.chilled, 140, 12.6, 0.7, 9.5, 0, 60),
  'butter': Ingredient('Butter', Aisle.chilled, 741, 0.7, 0.6, 83),
  'kochsahne': Ingredient('Kochsahne 15 %', Aisle.chilled, 160, 3, 4, 15, 0, null, 'Stück', true),
  'feta': Ingredient('Feta', Aisle.chilled, 264, 14, 4, 21),
  'parmesan': Ingredient('Parmesan', Aisle.chilled, 392, 35.8, 3.2, 25.8),
  'mozzarella': Ingredient('Mozzarella', Aisle.chilled, 253, 18, 1, 19.5, 0, 125),
  'halloumi': Ingredient('Halloumi', Aisle.chilled, 320, 22, 2, 25),
  'tofu': Ingredient('Tofu natur', Aisle.chilled, 124, 13, 1.5, 7.5, 1),
  'hummus': Ingredient('Hummus', Aisle.chilled, 166, 7.9, 8.3, 9.6, 6),
  'pesto': Ingredient('Pesto Genovese', Aisle.chilled, 450, 5, 6, 45, 2),
  'wiener': Ingredient('Wiener Würstchen', Aisle.chilled, 260, 12, 1, 23, 0, 50),
  // Fleisch & Fisch
  'haehnchen': Ingredient('Hähnchenbrust', Aisle.meat, 112, 23.5, 0, 1.5),
  'pute': Ingredient('Putenbrust', Aisle.meat, 105, 24, 0, 1),
  'rinderhack': Ingredient('Rinderhack', Aisle.meat, 220, 20, 0, 15.5),
  'lachs': Ingredient('Lachsfilet', Aisle.meat, 208, 20, 0, 13.4, 0, 125),
  // Vorrat
  'haferflocken': Ingredient('Haferflocken', Aisle.pantry, 370, 13.5, 58.7, 7, 10),
  'granola': Ingredient('Knuspermüsli', Aisle.pantry, 450, 9, 62, 17, 7),
  'vollkornbrot': Ingredient('Vollkornbrot', Aisle.pantry, 220, 7, 39, 1.5, 7.5, 50, 'Scheibe'),
  'toast': Ingredient('Vollkorntoast', Aisle.pantry, 250, 9, 43, 4, 6, 30, 'Scheibe'),
  'wrap': Ingredient('Weizen-Wraps', Aisle.pantry, 310, 8.5, 50, 7.5, 3, 60),
  'spaghetti': Ingredient('Spaghetti', Aisle.pantry, 355, 12.5, 70, 1.5, 3),
  'penne': Ingredient('Penne', Aisle.pantry, 355, 12.5, 70, 1.5, 3),
  'reis': Ingredient('Basmatireis', Aisle.pantry, 350, 7.5, 78, 0.6, 1.3),
  'quinoa': Ingredient('Quinoa', Aisle.pantry, 368, 14, 57, 6, 7),
  'linsen': Ingredient('Rote Linsen', Aisle.pantry, 340, 24, 48, 1.5, 11),
  'passierte': Ingredient('Passierte Tomaten', Aisle.pantry, 33, 1.4, 5, 0.2, 1.2),
  'tomatendose': Ingredient('Gehackte Tomaten (Dose)', Aisle.pantry, 22, 1.2, 3.5, 0.2, 1),
  'kidney': Ingredient('Kidneybohnen (Dose)', Aisle.pantry, 110, 7.5, 13, 0.5, 7),
  'schwarzebohnen': Ingredient('Schwarze Bohnen (Dose)', Aisle.pantry, 100, 7, 12, 0.5, 7),
  'kichererbsen': Ingredient('Kichererbsen (Dose)', Aisle.pantry, 139, 7, 15, 2.8, 7.6),
  'mais': Ingredient('Mais (Dose)', Aisle.pantry, 80, 2.9, 15, 1.2, 2.5),
  'kokosmilch': Ingredient('Kokosmilch', Aisle.pantry, 197, 2, 3, 21, 0, null, 'Stück', true),
  'currypaste': Ingredient('Rote Currypaste', Aisle.pantry, 120, 2, 10, 8, 3),
  'oliven': Ingredient('Oliven', Aisle.pantry, 145, 1, 4, 15, 3.3),
  'edamame': Ingredient('Edamame (TK)', Aisle.pantry, 121, 11.9, 3.6, 5.2, 5.2),
  'erdnussbutter': Ingredient('Erdnussbutter', Aisle.pantry, 590, 25, 12, 49, 6),
  'datteln': Ingredient('Datteln', Aisle.pantry, 280, 2.5, 64, 0.4, 8),
  'kakao': Ingredient('Backkakao', Aisle.pantry, 360, 20, 11, 21, 30),
  'honig': Ingredient('Honig', Aisle.pantry, 304, 0.3, 80, 0),
  'whey': Ingredient('Proteinpulver', Aisle.pantry, 380, 78, 6, 5),
  'brühe': Ingredient('Gemüsebrühe', Aisle.pantry, 5, 0.3, 0.6, 0.1, 0, null, 'Stück', true),
  'sojasauce': Ingredient('Sojasauce', Aisle.pantry, 53, 8, 5, 0.1, 0.8, null, 'Stück', true),
  'olivenoel': Ingredient('Olivenöl', Aisle.pantry, 884, 0, 0, 100, 0, null, 'Stück', true),
  // Gewürze & Basics
  'salz': Ingredient('Salz', _s),
  'pfeffer': Ingredient('Pfeffer', _s),
  'paprikapulver': Ingredient('Paprikapulver', _s),
  'kreuzkuemmel': Ingredient('Kreuzkümmel', _s),
  'oregano': Ingredient('Oregano', _s),
  'chili': Ingredient('Chiliflocken', _s),
  'currypulver': Ingredient('Currypulver', _s),
  'zimt': Ingredient('Zimt', _s),
};

/// One line of a recipe: an ingredient and how much, for the whole recipe.
/// Grams 0 is "to taste" — listed, never weighed.
class RecipeItem {
  const RecipeItem(this.key, [this.g = 0]);
  final String key;
  final double g;
  Ingredient get ingredient => kIngredients[key]!;
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.meals,
    required this.servings,
    required this.minutes,
    required this.items,
    required this.steps,
  });

  final String id;
  final String name;

  /// Which of `kMeals` it suits, first is the main one.
  final List<String> meals;
  final int servings;
  final int minutes;
  final List<RecipeItem> items;
  final List<String> steps;
}

class Nutrients {
  const Nutrients(this.kcal, this.protein, this.carbs, this.fat, this.fibre);
  final double kcal, protein, carbs, fat, fibre;
  Nutrients operator *(double k) =>
      Nutrients(kcal * k, protein * k, carbs * k, fat * k, fibre * k);
}

/// Nutrition for ONE serving, summed from the ingredients.
Nutrients perServing(Recipe r) {
  double k = 0, p = 0, c = 0, f = 0, fi = 0;
  for (final it in r.items) {
    final i = it.ingredient;
    final x = it.g / 100;
    k += i.kcal * x;
    p += i.protein * x;
    c += i.carbs * x;
    f += i.fat * x;
    fi += i.fibre * x;
  }
  final n = r.servings;
  return Nutrients(k / n, p / n, c / n, f / n, fi / n);
}

Recipe? recipeById(String? id) {
  for (final r in kRecipes) {
    if (r.id == id) return r;
  }
  return null;
}

/// "120 g", "250 ml", "2 Stück (120 g)", or "" for a to-taste item.
String amountLabel(RecipeItem it, double factor) {
  final g = it.g * factor;
  if (g <= 0) return '';
  final i = it.ingredient;
  final unit = i.ml ? 'ml' : 'g';
  final base = '${_round(g)} $unit';
  final pg = i.pieceG;
  if (pg == null) return base;
  final n = (g / pg * 2).round() / 2;
  if (n < 0.5) return base;
  final count = n == n.roundToDouble()
      ? n.round().toString()
      : n.toString().replaceAll('.', ',');
  return '$count ${i.piece}${n > 1 && i.piece != 'Stück' ? 'n' : ''} ($base)';
}

int _round(double g) => g >= 50 ? (g / 5).round() * 5 : g.round();

/// One shopping-list line: an ingredient and the total needed.
class ShoppingLine {
  ShoppingLine(this.key, this.g);
  final String key;
  double g;
  Ingredient get ingredient => kIngredients[key]!;
}

/// The shopping list for these recipes at these servings, by aisle.
Map<Aisle, List<ShoppingLine>> shoppingList(
    Iterable<(Recipe, double)> planned) {
  final byKey = <String, ShoppingLine>{};
  for (final (r, servings) in planned) {
    final factor = servings / r.servings;
    for (final it in r.items) {
      (byKey[it.key] ??= ShoppingLine(it.key, 0)).g += it.g * factor;
    }
  }
  final out = <Aisle, List<ShoppingLine>>{};
  for (final a in Aisle.values) {
    final lines = byKey.values.where((l) => l.ingredient.aisle == a).toList()
      ..sort((x, y) => x.ingredient.name.compareTo(y.ingredient.name));
    if (lines.isNotEmpty) out[a] = lines;
  }
  return out;
}

const _sp = [RecipeItem('salz'), RecipeItem('pfeffer')];

const kRecipes = <Recipe>[
  // ── Frühstück ──
  Recipe(
    id: 'porridge',
    name: 'Porridge mit Banane und Beeren',
    meals: ['breakfast'],
    servings: 1,
    minutes: 10,
    items: [
      RecipeItem('haferflocken', 60),
      RecipeItem('milch', 250),
      RecipeItem('banane', 100),
      RecipeItem('heidelbeeren', 50),
      RecipeItem('zimt'),
    ],
    steps: [
      'Haferflocken mit Milch aufkochen und 3–4 Minuten unter Rühren köcheln.',
      'Banane in Scheiben schneiden.',
      'Porridge mit Banane, Beeren und etwas Zimt servieren.',
    ],
  ),
  Recipe(
    id: 'overnight_oats',
    name: 'Overnight Oats mit Skyr',
    meals: ['breakfast'],
    servings: 1,
    minutes: 5,
    items: [
      RecipeItem('haferflocken', 50),
      RecipeItem('skyr', 150),
      RecipeItem('milch', 100),
      RecipeItem('heidelbeeren', 80),
      RecipeItem('honig', 10),
    ],
    steps: [
      'Haferflocken, Skyr und Milch in einem Glas verrühren.',
      'Über Nacht abgedeckt in den Kühlschrank stellen.',
      'Morgens Beeren und Honig darauf geben.',
    ],
  ),
  Recipe(
    id: 'ruehrei',
    name: 'Rührei mit Vollkornbrot',
    meals: ['breakfast'],
    servings: 1,
    minutes: 10,
    items: [
      RecipeItem('ei', 180),
      RecipeItem('butter', 5),
      RecipeItem('vollkornbrot', 100),
      RecipeItem('tomaten', 80),
      ..._sp,
    ],
    steps: [
      'Eier mit Salz und Pfeffer verquirlen.',
      'Butter in einer Pfanne schmelzen, Eier bei mittlerer Hitze langsam stocken lassen.',
      'Mit Brot und Tomatenscheiben servieren.',
    ],
  ),
  Recipe(
    id: 'avocado_toast',
    name: 'Avocado-Toast mit Ei',
    meals: ['breakfast', 'snack'],
    servings: 1,
    minutes: 10,
    items: [
      RecipeItem('toast', 60),
      RecipeItem('avocado', 70),
      RecipeItem('ei', 120),
      RecipeItem('zitrone', 5),
      RecipeItem('chili'),
      ..._sp,
    ],
    steps: [
      'Eier 7 Minuten kochen, abschrecken und pellen.',
      'Toast rösten. Avocado mit Zitronensaft, Salz und Pfeffer zerdrücken.',
      'Avocado auf den Toast streichen, Ei in Scheiben darauf legen, mit Chili bestreuen.',
    ],
  ),
  Recipe(
    id: 'skyr_bowl',
    name: 'Skyr-Bowl mit Knuspermüsli',
    meals: ['breakfast', 'snack'],
    servings: 1,
    minutes: 5,
    items: [
      RecipeItem('skyr', 250),
      RecipeItem('granola', 40),
      RecipeItem('heidelbeeren', 100),
    ],
    steps: ['Skyr in eine Schüssel geben, Müsli und Beeren darauf verteilen.'],
  ),
  Recipe(
    id: 'protein_pancakes',
    name: 'Protein-Pancakes',
    meals: ['breakfast'],
    servings: 1,
    minutes: 15,
    items: [
      RecipeItem('haferflocken', 50),
      RecipeItem('banane', 100),
      RecipeItem('ei', 120),
      RecipeItem('magerquark', 125),
      RecipeItem('olivenoel', 5),
      RecipeItem('heidelbeeren', 50),
    ],
    steps: [
      'Haferflocken, Banane, Eier und Quark zu einem glatten Teig pürieren.',
      'Wenig Öl in einer Pfanne erhitzen, kleine Pancakes je Seite 2 Minuten backen.',
      'Mit Beeren servieren.',
    ],
  ),
  Recipe(
    id: 'shakshuka',
    name: 'Shakshuka',
    meals: ['breakfast', 'dinner'],
    servings: 2,
    minutes: 25,
    items: [
      RecipeItem('olivenoel', 10),
      RecipeItem('zwiebel', 80),
      RecipeItem('paprika', 150),
      RecipeItem('knoblauch', 8),
      RecipeItem('tomatendose', 400),
      RecipeItem('ei', 240),
      RecipeItem('feta', 50),
      RecipeItem('vollkornbrot', 100),
      RecipeItem('kreuzkuemmel'),
      RecipeItem('paprikapulver'),
      ..._sp,
    ],
    steps: [
      'Zwiebel, Paprika und Knoblauch würfeln und in Öl 5 Minuten anbraten.',
      'Gewürze kurz mitrösten, Tomaten dazu und 10 Minuten einkochen.',
      'Vier Mulden formen, Eier hineinschlagen, zugedeckt 6–8 Minuten stocken lassen.',
      'Feta darüber bröseln, mit Brot servieren.',
    ],
  ),
  // ── Mittag & Abend ──
  Recipe(
    id: 'bolognese',
    name: 'Spaghetti Bolognese',
    meals: ['lunch', 'dinner'],
    servings: 4,
    minutes: 40,
    items: [
      RecipeItem('spaghetti', 400),
      RecipeItem('rinderhack', 500),
      RecipeItem('zwiebel', 80),
      RecipeItem('karotte', 150),
      RecipeItem('knoblauch', 8),
      RecipeItem('passierte', 700),
      RecipeItem('olivenoel', 10),
      RecipeItem('parmesan', 40),
      RecipeItem('oregano'),
      ..._sp,
    ],
    steps: [
      'Zwiebel, Karotten und Knoblauch fein würfeln.',
      'Hackfleisch in Öl krümelig anbraten, Gemüse 3 Minuten mitbraten.',
      'Passierte Tomaten und Oregano dazu, 20 Minuten köcheln, abschmecken.',
      'Spaghetti nach Packung kochen und mit Sauce und Parmesan servieren.',
    ],
  ),
  Recipe(
    id: 'chili',
    name: 'Chili con Carne mit Reis',
    meals: ['lunch', 'dinner'],
    servings: 4,
    minutes: 45,
    items: [
      RecipeItem('rinderhack', 500),
      RecipeItem('zwiebel', 100),
      RecipeItem('paprika', 300),
      RecipeItem('knoblauch', 8),
      RecipeItem('tomatendose', 800),
      RecipeItem('kidney', 250),
      RecipeItem('mais', 140),
      RecipeItem('olivenoel', 10),
      RecipeItem('reis', 250),
      RecipeItem('kreuzkuemmel'),
      RecipeItem('paprikapulver'),
      RecipeItem('chili'),
      ..._sp,
    ],
    steps: [
      'Zwiebel, Knoblauch und Paprika würfeln.',
      'Hack in Öl anbraten, Gemüse und Gewürze dazu.',
      'Tomaten zugeben und 25 Minuten köcheln.',
      'Bohnen und Mais abspülen, unterrühren, 5 Minuten mitkochen.',
      'Reis nach Packung garen und dazu servieren.',
    ],
  ),
  Recipe(
    id: 'curry',
    name: 'Hähnchen-Curry mit Reis',
    meals: ['lunch', 'dinner'],
    servings: 4,
    minutes: 35,
    items: [
      RecipeItem('haehnchen', 600),
      RecipeItem('kokosmilch', 400),
      RecipeItem('currypaste', 40),
      RecipeItem('zwiebel', 100),
      RecipeItem('paprika', 300),
      RecipeItem('brokkoli', 250),
      RecipeItem('olivenoel', 15),
      RecipeItem('reis', 300),
      RecipeItem('salz'),
    ],
    steps: [
      'Reis nach Packung garen.',
      'Hähnchen würfeln und in Öl rundum anbraten, herausnehmen.',
      'Zwiebel und Paprika anbraten, Currypaste 1 Minute mitrösten.',
      'Kokosmilch und Brokkoli dazu, 8 Minuten köcheln.',
      'Hähnchen zurück in die Sauce geben, 3 Minuten ziehen lassen.',
    ],
  ),
  Recipe(
    id: 'dal',
    name: 'Rote-Linsen-Dal',
    meals: ['lunch', 'dinner'],
    servings: 4,
    minutes: 30,
    items: [
      RecipeItem('linsen', 250),
      RecipeItem('kokosmilch', 400),
      RecipeItem('tomatendose', 400),
      RecipeItem('zwiebel', 100),
      RecipeItem('knoblauch', 8),
      RecipeItem('ingwer', 15),
      RecipeItem('spinat', 150),
      RecipeItem('olivenoel', 10),
      RecipeItem('reis', 200),
      RecipeItem('currypulver'),
      RecipeItem('kreuzkuemmel'),
      RecipeItem('salz'),
    ],
    steps: [
      'Zwiebel, Knoblauch und Ingwer fein hacken und in Öl andünsten.',
      'Gewürze kurz mitrösten.',
      'Linsen, Tomaten, Kokosmilch und 300 ml Wasser dazu, 15 Minuten köcheln.',
      'Spinat unterheben, salzen. Mit Reis servieren.',
    ],
  ),
  Recipe(
    id: 'griechischer_salat',
    name: 'Griechischer Salat',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 15,
    items: [
      RecipeItem('tomaten', 300),
      RecipeItem('gurke', 300),
      RecipeItem('paprika', 150),
      RecipeItem('zwiebel', 40),
      RecipeItem('feta', 150),
      RecipeItem('oliven', 60),
      RecipeItem('olivenoel', 20),
      RecipeItem('vollkornbrot', 100),
      RecipeItem('oregano'),
      ..._sp,
    ],
    steps: [
      'Tomaten, Gurke und Paprika grob würfeln, Zwiebel in Ringe schneiden.',
      'Mit Oliven, Öl, Oregano, Salz und Pfeffer mischen.',
      'Feta darauf legen, mit Brot servieren.',
    ],
  ),
  Recipe(
    id: 'wraps',
    name: 'Hähnchen-Wraps',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 20,
    items: [
      RecipeItem('wrap', 240),
      RecipeItem('haehnchen', 300),
      RecipeItem('salat', 100),
      RecipeItem('tomaten', 150),
      RecipeItem('gurke', 100),
      RecipeItem('joghurt', 150),
      RecipeItem('olivenoel', 10),
      RecipeItem('paprikapulver'),
      ..._sp,
    ],
    steps: [
      'Hähnchen in Streifen schneiden, würzen und in Öl 6 Minuten braten.',
      'Joghurt mit Salz und Pfeffer verrühren.',
      'Wraps kurz erwärmen, mit Joghurt bestreichen.',
      'Salat, Gemüse und Hähnchen darauf, einrollen.',
    ],
  ),
  Recipe(
    id: 'lachs',
    name: 'Lachs mit Ofenkartoffeln und Brokkoli',
    meals: ['dinner', 'lunch'],
    servings: 2,
    minutes: 35,
    items: [
      RecipeItem('lachs', 250),
      RecipeItem('kartoffeln', 600),
      RecipeItem('brokkoli', 400),
      RecipeItem('olivenoel', 15),
      RecipeItem('zitrone', 20),
      ..._sp,
    ],
    steps: [
      'Ofen auf 200 °C vorheizen. Kartoffeln vierteln, mit Öl und Salz 20 Minuten backen.',
      'Brokkoli und Lachs aufs Blech legen, würzen, weitere 12–15 Minuten backen.',
      'Mit Zitronensaft beträufeln.',
    ],
  ),
  Recipe(
    id: 'tofu_pfanne',
    name: 'Gemüsepfanne mit Tofu und Reis',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 25,
    items: [
      RecipeItem('tofu', 200),
      RecipeItem('zucchini', 250),
      RecipeItem('paprika', 150),
      RecipeItem('champignons', 150),
      RecipeItem('knoblauch', 4),
      RecipeItem('ingwer', 10),
      RecipeItem('sojasauce', 30),
      RecipeItem('olivenoel', 10),
      RecipeItem('reis', 150),
    ],
    steps: [
      'Reis nach Packung garen.',
      'Tofu würfeln und in Öl knusprig braten, herausnehmen.',
      'Gemüse in Streifen schneiden und 5 Minuten scharf anbraten.',
      'Knoblauch, Ingwer, Sojasauce und Tofu dazu, kurz schwenken.',
    ],
  ),
  Recipe(
    id: 'kartoffelsuppe',
    name: 'Kartoffelsuppe mit Würstchen',
    meals: ['lunch', 'dinner'],
    servings: 4,
    minutes: 40,
    items: [
      RecipeItem('kartoffeln', 1000),
      RecipeItem('karotte', 200),
      RecipeItem('zwiebel', 100),
      RecipeItem('brühe', 1000),
      RecipeItem('kochsahne', 100),
      RecipeItem('butter', 10),
      RecipeItem('wiener', 200),
      RecipeItem('petersilie'),
      ..._sp,
    ],
    steps: [
      'Kartoffeln, Karotten und Zwiebel würfeln.',
      'Zwiebel in Butter andünsten, Gemüse und Brühe dazu, 20 Minuten köcheln.',
      'Etwa die Hälfte pürieren, Sahne einrühren, abschmecken.',
      'Würstchen in Scheiben darin erwärmen, mit Petersilie servieren.',
    ],
  ),
  Recipe(
    id: 'pesto_penne',
    name: 'Penne mit Pesto und Hähnchen',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 20,
    items: [
      RecipeItem('penne', 200),
      RecipeItem('haehnchen', 250),
      RecipeItem('pesto', 60),
      RecipeItem('tomaten', 200),
      RecipeItem('parmesan', 20),
      RecipeItem('olivenoel', 5),
      ..._sp,
    ],
    steps: [
      'Penne nach Packung kochen.',
      'Hähnchen würfeln und in Öl goldbraun braten.',
      'Tomaten halbieren. Alles mit Pesto mischen, Parmesan darüber.',
    ],
  ),
  Recipe(
    id: 'teriyaki_bowl',
    name: 'Teriyaki-Hähnchen-Bowl',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 25,
    items: [
      RecipeItem('reis', 150),
      RecipeItem('haehnchen', 300),
      RecipeItem('sojasauce', 40),
      RecipeItem('honig', 20),
      RecipeItem('knoblauch', 4),
      RecipeItem('ingwer', 10),
      RecipeItem('edamame', 150),
      RecipeItem('karotte', 100),
      RecipeItem('gurke', 100),
      RecipeItem('olivenoel', 5),
    ],
    steps: [
      'Reis nach Packung garen, Edamame 4 Minuten kochen.',
      'Sojasauce, Honig, Knoblauch und Ingwer verrühren.',
      'Hähnchen in Öl braten, Sauce dazu und einkochen lassen, bis sie glänzt.',
      'Reis in Schalen, Hähnchen, Edamame, Karotte und Gurke darauf.',
    ],
  ),
  Recipe(
    id: 'burrito_bowl',
    name: 'Burrito-Bowl',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 25,
    items: [
      RecipeItem('reis', 150),
      RecipeItem('haehnchen', 250),
      RecipeItem('schwarzebohnen', 240),
      RecipeItem('mais', 140),
      RecipeItem('avocado', 140),
      RecipeItem('tomaten', 150),
      RecipeItem('zitrone', 10),
      RecipeItem('olivenoel', 5),
      RecipeItem('kreuzkuemmel'),
      RecipeItem('paprikapulver'),
      RecipeItem('salz'),
    ],
    steps: [
      'Reis nach Packung garen.',
      'Hähnchen mit Kreuzkümmel, Paprika und Salz würzen und in Öl braten.',
      'Bohnen und Mais abspülen und kurz erwärmen.',
      'Alles mit Avocado und Tomaten in Schalen anrichten, mit Zitrone beträufeln.',
    ],
  ),
  Recipe(
    id: 'halloumi_ofen',
    name: 'Ofengemüse mit Halloumi',
    meals: ['dinner', 'lunch'],
    servings: 2,
    minutes: 35,
    items: [
      RecipeItem('suesskartoffel', 400),
      RecipeItem('zucchini', 250),
      RecipeItem('paprika', 150),
      RecipeItem('zwiebel', 80),
      RecipeItem('kichererbsen', 240),
      RecipeItem('halloumi', 200),
      RecipeItem('olivenoel', 15),
      RecipeItem('paprikapulver'),
      ..._sp,
    ],
    steps: [
      'Ofen auf 200 °C vorheizen. Gemüse würfeln, mit Kichererbsen, Öl und Gewürzen mischen.',
      '20 Minuten backen.',
      'Halloumi in Scheiben darauf legen, weitere 10 Minuten backen.',
    ],
  ),
  Recipe(
    id: 'omelett',
    name: 'Gemüse-Omelett',
    meals: ['dinner', 'breakfast'],
    servings: 1,
    minutes: 10,
    items: [
      RecipeItem('ei', 180),
      RecipeItem('spinat', 50),
      RecipeItem('champignons', 50),
      RecipeItem('tomaten', 50),
      RecipeItem('feta', 30),
      RecipeItem('butter', 5),
      ..._sp,
    ],
    steps: [
      'Champignons in Butter anbraten, Spinat zusammenfallen lassen.',
      'Verquirlte Eier darüber gießen, bei kleiner Hitze stocken lassen.',
      'Tomaten und Feta darauf, zusammenklappen.',
    ],
  ),
  Recipe(
    id: 'pute_suesskartoffel',
    name: 'Putenbrust mit Süßkartoffelpüree',
    meals: ['dinner', 'lunch'],
    servings: 2,
    minutes: 30,
    items: [
      RecipeItem('pute', 300),
      RecipeItem('suesskartoffel', 500),
      RecipeItem('brokkoli', 300),
      RecipeItem('butter', 10),
      RecipeItem('milch', 50),
      RecipeItem('olivenoel', 10),
      ..._sp,
    ],
    steps: [
      'Süßkartoffeln schälen, würfeln und 15 Minuten weich kochen.',
      'Mit Butter und Milch zerstampfen, salzen.',
      'Brokkoli 5 Minuten dämpfen. Pute würzen und in Öl je Seite 4–5 Minuten braten.',
    ],
  ),
  Recipe(
    id: 'quinoa_salat',
    name: 'Quinoa-Salat mit Kichererbsen',
    meals: ['lunch', 'dinner'],
    servings: 2,
    minutes: 25,
    items: [
      RecipeItem('quinoa', 120),
      RecipeItem('kichererbsen', 240),
      RecipeItem('gurke', 150),
      RecipeItem('tomaten', 200),
      RecipeItem('feta', 100),
      RecipeItem('olivenoel', 15),
      RecipeItem('zitrone', 20),
      RecipeItem('petersilie'),
      ..._sp,
    ],
    steps: [
      'Quinoa gründlich spülen und 15 Minuten in Salzwasser garen, abkühlen lassen.',
      'Gemüse würfeln, Kichererbsen abspülen.',
      'Alles mit Öl, Zitrone, Petersilie, Salz und Pfeffer mischen, Feta darüber.',
    ],
  ),
  Recipe(
    id: 'aglio_olio',
    name: 'Spaghetti Aglio e Olio',
    meals: ['dinner', 'lunch'],
    servings: 2,
    minutes: 15,
    items: [
      RecipeItem('spaghetti', 200),
      RecipeItem('knoblauch', 16),
      RecipeItem('olivenoel', 30),
      RecipeItem('parmesan', 20),
      RecipeItem('chili'),
      RecipeItem('petersilie'),
      RecipeItem('salz'),
    ],
    steps: [
      'Spaghetti in Salzwasser kochen.',
      'Knoblauch in Scheiben schneiden und mit Chili im Öl sanft goldgelb braten.',
      'Spaghetti mit etwas Nudelwasser dazu, schwenken, mit Petersilie und Parmesan servieren.',
    ],
  ),
  Recipe(
    id: 'caprese_brot',
    name: 'Tomate-Mozzarella mit Brot',
    meals: ['dinner', 'snack'],
    servings: 2,
    minutes: 10,
    items: [
      RecipeItem('tomaten', 300),
      RecipeItem('mozzarella', 250),
      RecipeItem('olivenoel', 10),
      RecipeItem('vollkornbrot', 100),
      RecipeItem('basilikum'),
      ..._sp,
    ],
    steps: [
      'Tomaten und Mozzarella in Scheiben schneiden und abwechselnd anrichten.',
      'Mit Öl, Basilikum, Salz und Pfeffer würzen. Brot dazu.',
    ],
  ),
  // ── Snacks ──
  Recipe(
    id: 'quark_beeren',
    name: 'Magerquark mit Beeren',
    meals: ['snack', 'breakfast'],
    servings: 1,
    minutes: 3,
    items: [
      RecipeItem('magerquark', 250),
      RecipeItem('heidelbeeren', 100),
      RecipeItem('honig', 10),
    ],
    steps: ['Quark glatt rühren, Beeren und Honig darauf geben.'],
  ),
  Recipe(
    id: 'hummus_sticks',
    name: 'Hummus mit Gemüsesticks',
    meals: ['snack'],
    servings: 1,
    minutes: 5,
    items: [
      RecipeItem('hummus', 80),
      RecipeItem('karotte', 100),
      RecipeItem('paprika', 100),
      RecipeItem('gurke', 100),
    ],
    steps: ['Gemüse in Sticks schneiden und mit Hummus servieren.'],
  ),
  Recipe(
    id: 'apfel_erdnuss',
    name: 'Apfel mit Erdnussbutter',
    meals: ['snack'],
    servings: 1,
    minutes: 2,
    items: [RecipeItem('apfel', 180), RecipeItem('erdnussbutter', 20)],
    steps: ['Apfel in Spalten schneiden und mit Erdnussbutter essen.'],
  ),
  Recipe(
    id: 'protein_shake',
    name: 'Protein-Shake mit Banane',
    meals: ['snack', 'breakfast'],
    servings: 1,
    minutes: 2,
    items: [
      RecipeItem('whey', 30),
      RecipeItem('milch', 300),
      RecipeItem('banane', 100),
    ],
    steps: ['Alles im Mixer 20 Sekunden mixen.'],
  ),
  Recipe(
    id: 'energy_balls',
    name: 'Energy Balls (2 Stück)',
    meals: ['snack'],
    servings: 6,
    minutes: 15,
    items: [
      RecipeItem('haferflocken', 100),
      RecipeItem('datteln', 150),
      RecipeItem('erdnussbutter', 60),
      RecipeItem('kakao', 15),
    ],
    steps: [
      'Datteln 10 Minuten in warmem Wasser einweichen, abtropfen lassen.',
      'Alles im Mixer zu einer klebrigen Masse verarbeiten.',
      '12 Kugeln formen und kalt stellen.',
    ],
  ),
];
