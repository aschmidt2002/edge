// Edge+: the week's meal plan.
//
// Fork-only, kept out of the upstream schema: plans live in Prefs as JSON,
// a map of day label (YYYY-MM-DD) to that day's planned meals. A plan is not
// a log — nothing here counts toward any total until it is eaten and written
// to `food_entry` like every other occasion.

import 'dart:convert';

import '../state/prefs.dart';

class PlannedMeal {
  const PlannedMeal({
    required this.id,
    required this.meal,
    required this.name,
    this.recipeId,
    this.servings = 1,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fibreG,
  });

  final String id;

  /// One of `kMeals`: breakfast, lunch, dinner, snack.
  final String meal;
  final String name;

  /// A `kRecipes` id when the plan came from a recipe.
  final String? recipeId;
  final double servings;

  /// For the planned servings, not per serving. Null is unknown, never zero.
  final double? kcal, proteinG, carbsG, fatG, fibreG;

  Map<String, Object?> toJson() => {
    'id': id,
    'meal': meal,
    'name': name,
    'recipe': recipeId,
    'servings': servings,
    'kcal': kcal,
    'protein': proteinG,
    'carbs': carbsG,
    'fat': fatG,
    'fibre': fibreG,
  };

  static double? _d(Object? v) => v is num ? v.toDouble() : null;

  static PlannedMeal? fromJson(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], meal = m['meal'], name = m['name'];
    if (id is! String || meal is! String || name is! String) return null;
    return PlannedMeal(
      id: id,
      meal: meal,
      name: name,
      recipeId: m['recipe'] is String ? m['recipe'] as String : null,
      servings: _d(m['servings']) ?? 1,
      kcal: _d(m['kcal']),
      proteinG: _d(m['protein']),
      carbsG: _d(m['carbs']),
      fatG: _d(m['fat']),
      fibreG: _d(m['fibre']),
    );
  }
}

class MealPlanStore {
  MealPlanStore._();

  static const key = 'edgeplus.meal_plan.v1';

  static Map<String, List<PlannedMeal>> _all() {
    final raw = Prefs.getString(key, '');
    if (raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          if (e.key is String && e.value is List)
            e.key as String: [
              for (final p in e.value as List) ?PlannedMeal.fromJson(p),
            ],
      };
    } catch (_) {
      return {};
    }
  }

  /// The meals planned for [day] (YYYY-MM-DD), in meal order.
  static List<PlannedMeal> forDay(String day) => _all()[day] ?? const [];

  /// Replace [day]'s plan. An empty list removes the day.
  static void setDay(String day, List<PlannedMeal> meals) {
    final all = _all();
    if (meals.isEmpty) {
      all.remove(day);
    } else {
      all[day] = meals;
    }
    // Days more than two weeks gone are dropped so the blob stays small.
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    all.removeWhere((d, _) => (DateTime.tryParse(d) ?? cutoff).isBefore(cutoff));
    Prefs.setString(key, jsonEncode({
      for (final e in all.entries) e.key: [for (final p in e.value) p.toJson()],
    }));
  }

  static void add(String day, PlannedMeal m) => setDay(day, [...forDay(day), m]);

  static void remove(String day, String id) =>
      setDay(day, [for (final p in forDay(day)) if (p.id != id) p]);
}
