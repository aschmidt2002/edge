// Edge+: recipes, the week plan and the planned meal on the Nutrition tab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/meal_plan_store.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/recipes.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/nutrition_screen.dart';
import 'package:openstrap_edge/ui2/screens/recipes_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every recipe is well formed and its nutrition is plausible', () {
    final ids = <String>{};
    for (final r in kRecipes) {
      expect(ids.add(r.id), isTrue, reason: 'duplicate id ${r.id}');
      for (final it in r.items) {
        expect(kIngredients.containsKey(it.key), isTrue,
            reason: '${r.id}: unknown ingredient ${it.key}');
      }
      expect(r.meals, isNotEmpty);
      for (final m in r.meals) {
        expect(kMeals, contains(m), reason: r.id);
      }
      expect(r.steps, isNotEmpty);
      final n = perServing(r);
      expect(n.kcal, inInclusiveRange(100, 1100), reason: r.id);
      // Atwater: the macros account for the energy within a margin.
      final atwater = 4 * n.protein + 4 * n.carbs + 9 * n.fat + 2 * n.fibre;
      expect((atwater - n.kcal).abs() / n.kcal, lessThan(0.15), reason: r.id);
    }
  });

  test('a shopping list sums the same ingredient across recipes', () {
    final porridge = recipeById('porridge')!;
    final oats = recipeById('overnight_oats')!;
    final list = shoppingList([(porridge, 2), (oats, 1)]);
    final pantry = list[Aisle.pantry]!;
    final hafer = pantry.singleWhere((l) => l.key == 'haferflocken');
    expect(hafer.g, 60 * 2 + 50);
    expect(amountLabel(const RecipeItem('ei', 120), 1), '2 Stück (120 g)');
    expect(amountLabel(const RecipeItem('salz'), 1), '');
  });

  test('the meal plan round-trips through Prefs', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.reload();
    final day = todayLabel();
    final pick = RecipePick(recipe: recipeById('bolognese'), name: 'Bolo');
    MealPlanStore.add(day, pick.toPlanned('dinner'));
    final got = MealPlanStore.forDay(day).single;
    expect(got.meal, 'dinner');
    expect(got.recipeId, 'bolognese');
    expect(got.kcal, closeTo(perServing(recipeById('bolognese')!).kcal, 0.01));
    MealPlanStore.remove(day, got.id);
    expect(MealPlanStore.forDay(day), isEmpty);
  });

  group('on the tab', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.reload();
      await LocalDb.close();
      LocalDb.dbName = 'nutrition_recipes_plan_test.db';
      await databaseFactory.deleteDatabase(
          p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName));
      await LocalDb.instance;
    });
    tearDown(LocalDb.close);

    testWidgets('a planned meal shows today and eating it logs it', (t) async {
      MealPlanStore.add(
          todayLabel(),
          RecipePick(recipe: recipeById('porridge'), name: 'Porridge')
              .toPlanned('breakfast'));
      t.view.physicalSize = const Size(390 * 3, 2400 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ChangeNotifierProvider<AppState>.value(
            value: app, child: const Scaffold(body: NutritionScreen())),
      ));
      await _settle(t);
      expect(find.text('Porridge'), findsOneWidget);

      await t.tap(find.text('Porridge'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Eaten'));
      await t.tap(find.text('Eaten'));
      await _settle(t);

      final entries = await t.runAsync(() async => NutritionDb.entriesForDay(
          await LocalDb.instance, todayLabel()));
      expect(entries!.single.label, 'Porridge');
      expect(entries.single.kcal,
          closeTo(perServing(recipeById('porridge')!).kcal, 0.01));
      expect(MealPlanStore.forDay(todayLabel()), isEmpty,
          reason: 'eaten meals leave the plan');
    });
  });
}
