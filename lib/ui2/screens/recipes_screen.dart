// Edge+: recipe picker, recipe page and the week's shopping list.
//
// Fork-only, kept in its own file so the upstream nutrition screens carry
// only a few hook lines. Recipes come from `lib/data/recipes.dart`, the week
// plan from `lib/data/meal_plan_store.dart`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/meal_plan_store.dart';
import '../../data/nutrition_store.dart';
import '../../data/recipes.dart';
import '../../state/prefs.dart';
import '../ui2.dart';

/// What the picker or the recipe page hands back.
class RecipePick {
  const RecipePick({
    this.recipe,
    required this.name,
    this.servings = 1,
    this.eat = false,
    this.remove = false,
  });

  /// Null for a meal planned by name only.
  final Recipe? recipe;
  final String name;
  final double servings;

  /// Log it as eaten (true) or put it in the plan (false).
  final bool eat;

  /// From a planned meal's page: take it out of the plan.
  final bool remove;

  Nutrients? get nutrients {
    final r = recipe;
    return r == null ? null : perServing(r) * servings;
  }

  PlannedMeal toPlanned(String meal) {
    final n = nutrients;
    return PlannedMeal(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      meal: meal,
      name: name,
      recipeId: recipe?.id,
      servings: servings,
      kcal: n?.kcal,
      proteinG: n?.protein,
      carbsG: n?.carbs,
      fatG: n?.fat,
      fibreG: n?.fibre,
    );
  }
}

/// A typical clock time for a meal on a day that is not today, so a meal
/// logged after the fact still has a time.
const _mealHour = {'breakfast': 8, 'lunch': 12, 'snack': 16, 'dinner': 19};

/// Write a pick (or a planned meal) to the food log as eaten.
Future<void> logEaten({
  required String date,
  required String meal,
  required String name,
  required double servings,
  Nutrients? n,
}) async {
  final now = DateTime.now();
  final d = DateTime.tryParse(date) ?? now;
  final at = date == todayLabel()
      ? now
      : DateTime(d.year, d.month, d.day, _mealHour[meal] ?? 12);
  await NutritionDb.put(
    await LocalDb.instance,
    FoodEntry(
      id: NutritionDb.newId(),
      date: date,
      meal: meal,
      label: name,
      atTs: at.millisecondsSinceEpoch ~/ 1000,
      quantity: n == null ? null : servings,
      unit: 'Portion',
      kcal: n?.kcal,
      proteinG: n?.protein,
      carbsG: n?.carbs,
      fatG: n?.fat,
      fibreG: n?.fibre,
      confirmed: true,
    ),
  );
}

/// Log a planned meal as eaten and take it out of the plan.
Future<void> eatPlanned(String date, PlannedMeal m) async {
  await logEaten(
    date: date,
    meal: m.meal,
    name: m.name,
    servings: m.servings,
    n: m.kcal == null
        ? null
        : Nutrients(m.kcal!, m.proteinG ?? 0, m.carbsG ?? 0, m.fatG ?? 0,
            m.fibreG ?? 0),
  );
  MealPlanStore.remove(date, m.id);
}

String _num(double v) {
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  return s.replaceAll('.', ',');
}

String servingsLabel(BuildContext c, double s) =>
    '${_num(s)} ${s == 1 ? tr(c, 'Portion', 'serving') : tr(c, 'Portionen', 'servings')}';

String _macroLine(BuildContext c, Nutrients n) =>
    '${n.kcal.round()} kcal · ${n.protein.round()} g ${tr(c, 'Eiweiß', 'protein')}';

// ══════════════════ PICKER ══════════════════

class RecipePickerPage extends StatefulWidget {
  const RecipePickerPage({
    super.key,
    required this.meal,
    this.canEat = true,
    this.canPlan = true,
  });

  final String meal;
  final bool canEat, canPlan;

  static Future<RecipePick?> open(BuildContext c,
          {required String meal, bool canEat = true, bool canPlan = true}) =>
      Navigator.of(c).push<RecipePick>(MaterialPageRoute(
          builder: (_) =>
              RecipePickerPage(meal: meal, canEat: canEat, canPlan: canPlan)));

  @override
  State<RecipePickerPage> createState() => _RecipePickerPageState();
}

class _RecipePickerPageState extends State<RecipePickerPage> {
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Recipe> get _list {
    final q = _q.text.trim().toLowerCase();
    final hits = [
      for (final r in kRecipes)
        if (q.isEmpty ||
            r.name.toLowerCase().contains(q) ||
            r.items.any((i) => i.ingredient.name.toLowerCase().contains(q)))
          r,
    ];
    int rank(Recipe r) {
      final i = r.meals.indexOf(widget.meal);
      return i < 0 ? 9 : i;
    }

    hits.sort((a, b) => rank(a).compareTo(rank(b)));
    return hits;
  }

  Future<void> _open(Recipe r) async {
    final pick = await RecipeDetailPage.open(context, r,
        canEat: widget.canEat, canPlan: widget.canPlan);
    if (pick != null && mounted) Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.text.trim();
    final list = _list;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(tr(c, 'Rezepte', 'Recipes')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x3),
            child: Container(
              constraints: const BoxConstraints(minHeight: S.tap),
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
              child: Row(children: [
                Icon(LucideIcons.search, size: 17, color: p.ink3),
                const SizedBox(width: S.x2),
                Expanded(
                  child: TextField(
                    controller: _q,
                    style: F.body.copyWith(color: p.ink),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: tr(c, 'Suchen', 'Search'),
                      hintStyle: F.body.copyWith(color: p.ink3),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16),
              children: [
                if (q.isNotEmpty && widget.canPlan)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.x3),
                    child: Surface(
                      onTap: () => Navigator.of(c)
                          .pop(RecipePick(name: q, servings: 1)),
                      semanticLabel: tr(c, '„$q“ einplanen', 'Plan “$q”'),
                      child: Row(children: [
                        Icon(LucideIcons.calendarPlus,
                            size: 18, color: p.on(C.domFood)),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Text(tr(c, '„$q“ einplanen', 'Plan “$q”'),
                              style: F.body.copyWith(color: p.ink)),
                        ),
                      ]),
                    ),
                  ),
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(children: [
                    for (final r in list) _RecipeRow(r, onTap: () => _open(r)),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow(this.r, {this.onTap});
  final Recipe r;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = perServing(r);
    return Pressable(
      onTap: onTap,
      semanticLabel: r.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: F.body.copyWith(color: p.ink)),
              Text('${_macroLine(c, n)} · ${r.minutes} min',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
      ),
    );
  }
}

// ══════════════════ RECIPE PAGE ══════════════════

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({
    super.key,
    required this.recipe,
    this.servings = 1,
    this.canEat = true,
    this.canPlan = true,
    this.planned = false,
  });

  final Recipe recipe;
  final double servings;
  final bool canEat, canPlan;

  /// Opened from a planned meal: offers removing it from the plan.
  final bool planned;

  static Future<RecipePick?> open(BuildContext c, Recipe r,
          {double servings = 1,
          bool canEat = true,
          bool canPlan = true,
          bool planned = false}) =>
      Navigator.of(c).push<RecipePick>(MaterialPageRoute(
          builder: (_) => RecipeDetailPage(
              recipe: r,
              servings: servings,
              canEat: canEat,
              canPlan: canPlan,
              planned: planned)));

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late double _servings = widget.servings;

  RecipePick _pick({bool eat = false, bool remove = false}) => RecipePick(
        recipe: widget.recipe,
        name: widget.recipe.name,
        servings: _servings,
        eat: eat,
        remove: remove,
      );

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = widget.recipe;
    final n = perServing(r) * _servings;
    final factor = _servings / r.servings;
    Widget step(IconData icon, VoidCallback? onTap, String label) => Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Container(
            width: S.tap,
            height: S.tap,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: onTap == null ? p.card2 : p.wash(C.domFood),
                shape: BoxShape.circle),
            child: Icon(icon,
                size: 18, color: onTap == null ? p.ink3 : p.on(C.domFood)),
          ),
        );
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(
              r.name,
              trailing: widget.planned
                  ? Pressable(
                      semanticLabel: tr(c, 'Aus dem Plan entfernen',
                          'Remove from the plan'),
                      onTap: () => Navigator.of(c).pop(_pick(remove: true)),
                      child: Icon(LucideIcons.trash2, size: 20, color: p.ink2),
                    )
                  : null,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x8),
              children: [
                Surface(
                  child: Column(children: [
                    Row(children: [
                      step(LucideIcons.minus,
                          _servings <= 0.5
                              ? null
                              : () => setState(() => _servings -= 0.5),
                          tr(c, 'Weniger', 'Less')),
                      Expanded(
                        child: Text(servingsLabel(c, _servings),
                            textAlign: TextAlign.center,
                            style: F.head.copyWith(color: p.ink)),
                      ),
                      step(LucideIcons.plus,
                          _servings >= 12
                              ? null
                              : () => setState(() => _servings += 0.5),
                          tr(c, 'Mehr', 'More')),
                    ]),
                    const SizedBox(height: S.x4),
                    InlineMetrics([
                      ('KCAL', '${n.kcal.round()}', C.domFood),
                      (tr(c, 'EIWEISS', 'PROTEIN'), '${n.protein.round()} g', C.red),
                      (tr(c, 'KH', 'CARBS'), '${n.carbs.round()} g', C.orange),
                      (tr(c, 'FETT', 'FAT'), '${n.fat.round()} g', C.yellow),
                    ]),
                  ]),
                ),
                _Head(tr(c, 'Zutaten', 'Ingredients'),
                    trailing: '${r.minutes} min', icon: LucideIcons.clock),
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
                  child: Column(children: [
                    for (final it in r.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: S.x2),
                        child: Row(children: [
                          Expanded(
                            child: Text(it.ingredient.name,
                                style: F.body.copyWith(color: p.ink)),
                          ),
                          Text(amountLabel(it, factor),
                              style: F.cap.copyWith(color: p.ink2)),
                        ]),
                      ),
                  ]),
                ),
                _Head(tr(c, 'Zubereitung', 'Method')),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < r.steps.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: i == r.steps.length - 1 ? 0 : S.x3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text('${i + 1}',
                                    style: F.body.copyWith(
                                        color: p.on(C.domFood),
                                        fontWeight: FontWeight.w600)),
                              ),
                              Expanded(
                                child: Text(r.steps[i],
                                    style: F.body
                                        .copyWith(color: p.ink, height: 1.4)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: S.x5),
                if (widget.canEat)
                  BigButton(tr(c, 'Gegessen', 'Eaten'),
                      icon: LucideIcons.check,
                      color: C.domFood,
                      onTap: () => Navigator.of(c).pop(_pick(eat: true))),
                if (widget.canEat && widget.canPlan)
                  const SizedBox(height: S.x3),
                if (widget.canPlan)
                  BigButton(tr(c, 'Einplanen', 'Plan it'),
                      icon: LucideIcons.calendarPlus,
                      color: C.domFood,
                      soft: widget.canEat,
                      onTap: () => Navigator.of(c).pop(_pick())),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.title, {this.trailing, this.icon});
  final String title;
  final String? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x1, S.x5, S.x1, S.x2),
      child: Row(children: [
        Expanded(child: Text(title, style: F.head.copyWith(color: p.ink))),
        if (icon != null) ...[
          Icon(icon, size: 15, color: p.ink3),
          const SizedBox(width: S.x1),
        ],
        if (trailing != null)
          Text(trailing!, style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }
}

// ══════════════════ SHOPPING LIST ══════════════════

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key, required this.days});

  /// Day labels whose planned recipes go on the list.
  final List<String> days;

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  static const _key = 'edgeplus.shopping_checked.v1';

  late Set<String> _checked = _load();

  Set<String> _load() {
    try {
      final v = jsonDecode(Prefs.getString(_key, '[]'));
      return {if (v is List) for (final s in v) if (s is String) s};
    } catch (_) {
      return {};
    }
  }

  void _toggle(String k) {
    setState(() => _checked.contains(k) ? _checked.remove(k) : _checked.add(k));
    Prefs.setString(_key, jsonEncode(_checked.toList()));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final de = Localizations.localeOf(c).languageCode == 'de';
    final planned = [
      for (final d in widget.days)
        for (final m in MealPlanStore.forDay(d))
          if (recipeById(m.recipeId) case final r?) (r, m.servings),
    ];
    final list = shoppingList(planned);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(
              tr(c, 'Einkaufsliste', 'Shopping list'),
              trailing: _checked.isEmpty
                  ? null
                  : Pressable(
                      semanticLabel: tr(c, 'Haken entfernen', 'Clear ticks'),
                      onTap: () {
                        setState(() => _checked = {});
                        Prefs.setString(_key, '[]');
                      },
                      child: Icon(LucideIcons.rotateCcw, size: 20, color: p.ink2),
                    ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(tr(c, 'Keine Rezepte eingeplant', 'No recipes planned'),
                        style: F.body.copyWith(color: p.ink3)),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16),
                    children: [
                      for (final e in list.entries) ...[
                        _Head(aisleLabel(e.key, de: de)),
                        Surface(
                          pad: const EdgeInsets.symmetric(horizontal: S.x4),
                          child: Column(children: [
                            for (final l in e.value)
                              Pressable(
                                onTap: () => _toggle(l.key),
                                semanticLabel: l.ingredient.name,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: S.x3),
                                  child: Row(children: [
                                    Icon(
                                      _checked.contains(l.key)
                                          ? LucideIcons.circleCheck
                                          : LucideIcons.circle,
                                      size: 20,
                                      color: _checked.contains(l.key)
                                          ? p.on(C.green)
                                          : p.ink3,
                                    ),
                                    const SizedBox(width: S.x3),
                                    Expanded(
                                      child: Text(
                                        l.ingredient.name,
                                        style: F.body.copyWith(
                                          color: _checked.contains(l.key)
                                              ? p.ink3
                                              : p.ink,
                                          decoration: _checked.contains(l.key)
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                    Text(amountLabel(RecipeItem(l.key, l.g), 1),
                                        style: F.cap.copyWith(color: p.ink2)),
                                  ]),
                                ),
                              ),
                          ]),
                        ),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}
