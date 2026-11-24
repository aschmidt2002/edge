// Nutrition.
//
// Three things this screen refuses to do, and they shape everything else:
//
//   1. It never shows a total it cannot stand behind. A day where any occasion
//      has no energy attached is a FLOOR, labelled "at least", and it is
//      excluded from every average on the Week tab.
//   2. Partial days are detected, not declared. There is no "I logged
//      everything" checkbox, because nobody ticks it and every average then
//      quietly rots.
//   3. Daily is the detail view. The seven-day rolling average is the hero —
//      one day of intake is noise, seven is a habit.
//
// Water is NOT re-invented here: it is the existing `water_ml` journal field
// (`lib/data/journal_fields.dart`), read and written through the repo.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../../models/metric.dart';
import '../../data/journal_fields.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import '../onboarding/profile_setup.dart' show formatDay;
import 'journal_compose.dart' show OsTextField;
import 'log_food.dart';
import 'fasting.dart';
import 'nutrition_plus.dart';
import '../profile/profile.dart' show ProfileAvatar, SetRow;
import 'food_ai_key_sheet.dart';
import 'recipes_screen.dart';
import '../../data/meal_plan_store.dart';
import '../../data/recipes.dart' show recipeById;

class NutritionScreen extends StatefulWidget {
  /// Pushed from the Activity tab rather than shown as a tab: a page with a
  /// back arrow. Nutrition is a section of Activity now; the band measures
  /// nothing about food, so it no longer holds a tab of its own.
  final bool page;
  const NutritionScreen({super.key, this.page = false});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> with RevisionReload {
  /// Edge+: 0 is the day view under the week calendar, 1 History (the old
  /// Week tab), 2 Goals.
  int _tab = 0;

  /// Read on every use, never captured once: the shell keeps this tab alive in
  /// its IndexedStack, so a field initialiser would still be yesterday after
  /// midnight and an occasion logged at 00:05 would land on the wrong day.
  String get _date => todayLabel();

  /// Edge+: the day picked in the week calendar. Null follows today, so a
  /// tab left open past midnight moves on with the clock.
  String? _picked;
  String get _day => _picked ?? _date;
  bool get _isToday => _day == _date;
  bool get _isFuture => _day.compareTo(_date) > 0;

  /// Weeks away from the current one in the calendar.
  int _weekOffset = 0;

  /// Entries for the seven days of the calendar week on screen.
  Map<String, List<FoodEntry>> _weekEntries = const {};

  NutritionWindow? _week;
  Metric? _burned;

  /// Whole-day total burn per local day label, for the weekly balance. Kept
  /// apart from [_burned], which is today's running total and only fits the
  /// per-day card.
  Map<String, double> _burnedByDate = const {};
  Map<String, double> _wornMinByDate = const {};
  double? _waterMl;
  double? _caffeineMg;
  /// The day [_waterMl] was read for. Past midnight on a tab nobody reloaded
  /// it is still yesterday's, and a full yesterday disabled today's + button.
  String? _waterDate;
  bool _loading = true;

  /// The local profile map, read once per load. Targets live here rather than
  /// in a new table: they are two numbers the user typed, the same shape as
  /// `step_goal` next to them.
  Map<String, dynamic> _profile = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Burned calories and water come from the derived store and the journal,
  /// both of which are written from elsewhere in the app — an import, a derive
  /// after a sync, water logged on Wellness. This tab is never disposed, so
  /// without this it showed launch-time figures all day.
  @override
  void reload() => _load();

  /// Monday of the calendar week on screen.
  DateTime get _monday {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + 7 * _weekOffset);
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  List<String> get _weekDays => [
        for (var i = 0; i < 7; i++)
          dayLabelOf(DateTime(_monday.year, _monday.month, _monday.day + i)),
      ];

  Future<void> _load() async {
    final t = beginRead(#nutrition);
    final app = context.read<AppState>();
    final db = await LocalDb.instance;
    final week = await NutritionDb.window(db, days: 7);
    final days = _weekDays;
    final since = await NutritionDb.entriesSince(db, days.first);
    final weekEntries = {
      for (final d in days) d: since[d] ?? const <FoodEntry>[],
    };
    final weekDates = {for (final d in week.days) d.date};
    // Measured days only: an imported vendor total is a different estimate,
    // and averaging it with ours mixes two scales in one figure.
    Map<String, double> weekOf(List<Map<String, dynamic>> rows) => {
          for (final r in rows)
            if (weekDates.contains(r['date']))
              r['date'] as String: (r['value'] as num).toDouble(),
        };
    final burnedByDate = weekOf(
        await LocalDb.metricSeries('calories_total', measuredOnly: true));
    final wornMinByDate = weekOf(await LocalDb.metricSeries('worn_min'));
    Metric? burned;
    double? water, caffeine;
    final date = _date;
    final repo = app.repo;
    if (repo != null) {
      final today = await repo.getToday();
      final daily = today['daily'];
      if (daily is Map) burned = Metric.parse(daily['calories_total']);
      final j = await repo.getJournalMetrics(date);
      water = j['water_ml']?.value;
      caffeine = j['caffeine_mg']?.value;
    }
    if (!stillNewest(#nutrition, t)) return;
    setState(() {
      _week = week;
      _weekEntries = weekEntries;
      _burned = burned;
      _burnedByDate = burnedByDate;
      _wornMinByDate = wornMinByDate;
      _waterMl = water;
      _caffeineMg = caffeine;
      _waterDate = date;
      _profile = {...?app.user};
      _loading = false;
    });
    ensureCreatineReminder(_profile);
  }

  /// The picked day, rolled up. Read from the calendar week's entries.
  NutritionDay get _dayRollup => rollupDay(
      _day, _weekEntries[_day] ?? const [], today: _date);

  NutritionDay? get _today {
    final w = _week;
    if (w == null) return null;
    for (final d in w.days) {
      if (d.date == _date) return d;
    }
    return null;
  }

  /// The + on a meal. A future day plans; today and earlier log, and the log
  /// sheet's recipe row can plan today too.
  Future<void> _logFood({String meal = 'snack'}) async {
    if (_isFuture) {
      final pick =
          await RecipePickerPage.open(context, meal: meal, canEat: false);
      if (pick == null) return;
      MealPlanStore.add(_day, pick.toPlanned(meal));
      await _load();
      return;
    }
    final ok = await LogFoodSheet.show(context, date: _day, meal: meal);
    if (ok == true) await _load();
  }

  /// A planned meal: its recipe page, or for a meal planned by name a small
  /// sheet. Either can log it as eaten or take it out of the plan.
  Future<void> _openPlanned(PlannedMeal m) async {
    final day = _day;
    final canEat = !_isFuture;
    final r = recipeById(m.recipeId);
    bool? eat;
    if (r != null) {
      final pick = await RecipeDetailPage.open(context, r,
          servings: m.servings, canEat: canEat, canPlan: false, planned: true);
      if (pick == null) return;
      eat = pick.eat ? true : (pick.remove ? false : null);
    } else {
      eat = await showModalBottomSheet<bool>(
        context: context,
        sheetAnimationStyle: sheetMotion(context),
        backgroundColor: P.of(context).card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
        ),
        builder: (s) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(m.name, style: F.head.copyWith(color: P.of(s).ink)),
                const SizedBox(height: S.x4),
                if (canEat) ...[
                  BigButton(tr(s, 'Gegessen', 'Eaten'),
                      icon: LucideIcons.check,
                      color: C.domFood,
                      onTap: () => Navigator.of(s).pop(true)),
                  const SizedBox(height: S.x3),
                ],
                BigButton(tr(s, 'Aus dem Plan entfernen', 'Remove from the plan'),
                    icon: LucideIcons.trash2,
                    color: C.domFood,
                    soft: true,
                    onTap: () => Navigator.of(s).pop(false)),
              ],
            ),
          ),
        ),
      );
    }
    if (eat == null) return;
    if (eat) {
      await eatPlanned(day, m);
    } else {
      MealPlanStore.remove(day, m.id);
    }
    if (mounted) await _load();
  }

  /// One write at a time. `_stepDose` reads the day, then awaits, then writes
  /// it back — and `postJournalMetrics` replaces the whole day — so two taps
  /// during that await both read the same map and the second write silently
  /// eats the first tap. Same guard the wellness screen already uses for its
  /// journal fields.
  bool _writingWater = false;

  /// Caffeine per cup of coffee, the step of the coffee row. A typical cup of
  /// filter coffee; stored as `caffeine_mg` so sleep insights see it.
  static const double kCaffeinePerCup = 80;

  /// Step a journal dose (water or coffee) for today up or down, in place.
  ///
  /// A step down off the last unit lands on a logged ZERO ("none today"), and
  /// a step down from zero clears the field, because absence and zero are
  /// different answers.
  Future<void> _stepDose(String key, double step, int dir) async {
    final repo = context.read<AppState>().repo;
    if (repo == null || _writingWater) return;
    _writingWater = true;
    try {
      // Step from what is stored for today, not from the last load's figure:
      // on a tab left open past midnight that is still yesterday's total.
      //
      // Drop the key rather than omitting it from a spread: `putJournalMetrics`
      // clears the day and re-inserts what it is handed, so leaving the key
      // out is what "no answer today" looks like on disk.
      final date = _date;
      final max = kJournalFieldsByKey[key]!.max;
      final now = DateTime.now();
      await repo.editJournalMetrics(date, (fields) {
        final old = fields.remove(key);
        final v = old?.value;
        double? next;
        if (dir > 0) {
          next = ((v ?? 0) + step).clamp(0, max).toDouble();
        } else {
          final down = (v ?? 0) - step;
          next = down <= 0 ? (v == null || v == 0 ? null : 0.0) : down;
        }
        if (next != null) {
          fields[key] = JournalMetricValue(next,
              atMinuteOfDay: kJournalFieldsByKey[key]!.hasTime
                  ? (dir > 0 ? now.hour * 60 + now.minute : old?.atMinuteOfDay)
                  : null);
        }
      });
      await _load();
    } finally {
      // Cleared unconditionally; the setState is only for the repaint.
      _writingWater = false;
      if (mounted) setState(() {});
    }
  }

  /// Edit an entry — amount, meal, time — or remove it from the same sheet.
  Future<void> _editFood(FoodEntry e) async {
    final ok = await LogFoodSheet.show(context, entry: e);
    if (ok == true) await _load();
  }

  /// Today's protein against the typed target. The Goals tab compares the
  /// seven-day mean; this is the number to act on before the day ends. A
  /// floor says "at least", and no figure at all is said, never drawn as 0 g.
  Widget? _proteinToday(BuildContext c, NutritionDay? day) {
    final target = _target('protein_target');
    if (target == null || target <= 0 || day == null || !day.logged) {
      return null;
    }
    final l = AppLocalizations.of(c);
    final label = l?.nutritionProteinToday ?? 'Protein today';
    final goal = '${target.round()} g';
    final v = day.protein.value;
    if (v == null) {
      return GoalTrajectory(label, l?.nutritionNotRecorded ?? 'Not recorded',
          goal, l?.nutritionAddNumbersFix ?? 'Add the numbers to an occasion',
          0, C.red, rateDown: false);
    }
    // Rounded up: 99.6 of 100 g is still 1 g to go, never "reached".
    final left = (target - v).ceil();
    return GoalTrajectory(
      label,
      '${day.protein.isFloor ? (l?.nutritionAtLeastPrefix ?? 'at least ') : ''}'
          '${v.round()} g',
      goal,
      left > 0
          ? (l?.nutritionProteinToGo(left) ?? '$left g to go')
          : (l?.nutritionTargetReached ?? 'Target reached'),
      (v / target).clamp(0, 1).toDouble(),
      C.red,
      rateDown: false,
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final list = PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(S.x4, widget.page ? 0 : S.x4, S.x4, S.x16),
        children: [
          if (!widget.page)
            ScreenTitle(l?.nutritionTitle ?? 'Nutrition',
                trailing: const ProfileAvatar(accent: C.domFood)),
          if (_tab != 0)
            _backHeader(
                c,
                _tab == 1
                    ? tr(c, 'Verlauf', 'History')
                    : tr(c, 'Ziele', 'Goals')),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            [_todayTab, _weekTab, _goalsTab][_tab](c),
        ],
      ),
    );
    if (!widget.page) return list;
    return Scaffold(
      backgroundColor: P.of(c).bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.nutritionTitle ?? 'Nutrition'),
          ),
          Expanded(child: list),
        ]),
      ),
    );
  }

  /// Back from History or Goals to the day view.
  Widget _backHeader(BuildContext c, String title) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x4),
      child: Pressable(
        onTap: () => setState(() => _tab = 0),
        semanticLabel: title,
        child: Row(children: [
          Icon(LucideIcons.chevronLeft, size: 20, color: p.ink2),
          const SizedBox(width: S.x1),
          Text(title, style: F.head.copyWith(color: p.ink)),
        ]),
      ),
    );
  }

  // ── TODAY ────────────────────────────────────────────────────────────────

  Widget _todayTab(BuildContext c) {
    final p = P.of(c);
    final day = _dayRollup;
    final days = _weekDays;
    final plans = {for (final d in days) d: MealPlanStore.forDay(d)};
    final planned = plans[_day] ?? const <PlannedMeal>[];
    Widget smallButton(IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
            onTap: onTap,
            semanticLabel: label,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: p.on(C.domFood)),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text(label,
                    style: F.body.copyWith(color: p.ink),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Surface(
              pad: const EdgeInsets.fromLTRB(S.x1, S.x3, S.x1, S.x3),
              child: _WeekStrip(
                days: days,
                today: _date,
                selected: _day,
                planned: {
                  for (final d in days)
                    if (plans[d]!.isNotEmpty) d,
                },
                onPick: (d) => setState(() => _picked = d == _date ? null : d),
                onShift: (dir) {
                  setState(() {
                    _weekOffset += dir;
                    _picked = _weekOffset == 0 ? null : _weekDays.first;
                  });
                  _load();
                },
              ),
            ),
          ),
          const SizedBox(width: S.x2),
          // The same card as the week, as tall as it.
          SizedBox(
            width: 76,
            child: Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x3),
            onTap: () => setState(() => _tab = 1),
            semanticLabel: tr(c, 'Verlauf', 'History'),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.history, size: 20, color: p.ink2),
                  const SizedBox(height: S.x1),
                  Text(tr(c, 'Verlauf', 'History'),
                      style: F.cap.copyWith(color: p.ink2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
          )),
        ])),
        const SizedBox(height: S.x3),
        Row(children: [
          smallButton(LucideIcons.target, tr(c, 'Ziele', 'Goals'),
              () => setState(() => _tab = 2)),
          const SizedBox(width: S.x3),
          smallButton(
              LucideIcons.shoppingCart,
              tr(c, 'Einkaufsliste', 'Shopping list'),
              () => Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => ShoppingListPage(
                      days: [for (final d in days) if (d.compareTo(_date) >= 0) d])))),
        ]),
        if (!_isFuture && day.logged) ...[
          const SizedBox(height: S.x4),
          DayEnergyCard(day: day, burned: _isToday ? _burned : null),
        ],
        if (_isToday)
          if (_proteinToday(c, _today) case final protein?) ...[
            const SizedBox(height: S.x4),
            protein,
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x1, S.x5, 0, S.x2),
          child: Row(children: [
            Expanded(
              child: Text(
                  _isToday
                      ? tr(c, 'Mahlzeiten', 'Meals')
                      : _dayShort(_day, AppLocalizations.of(c)),
                  style: F.head.copyWith(color: p.ink)),
            ),
          ]),
        ),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (final m in kMeals) ...[
                MealRow(
                  meal: m,
                  entries: day.mealEntries(m),
                  onTap: () => _logFood(meal: m),
                ),
                // The individual entries, indented under the occasion they
                // belong to, each one editable and removable. A mistyped
                // 2,000 kcal used to be permanent and it silently poisoned
                // every seven-day mean it fell into.
                for (final e in day.mealEntries(m))
                  Padding(
                    padding: const EdgeInsets.only(left: S.x8),
                    child: FoodRow(
                      entry: e,
                      trailing: LucideIcons.pencil,
                      onTap: () => _editFood(e),
                    ),
                  ),
                for (final pm in planned.where((x) => x.meal == m))
                  Padding(
                    padding: const EdgeInsets.only(left: S.x8),
                    child: _PlannedRow(pm, onTap: () => _openPlanned(pm)),
                  ),
              ],
            ],
          ),
        ),
        if (_isToday) ...[
          const SizedBox(height: S.x4),
          // Gated on the repository too: with no repo `_stepDose` returns at
          // its first line, so an enabled + button was a control that did
          // nothing — worse than a disabled one, which at least says so.
          Builder(builder: (bc) {
            final live = bc.select<AppState, bool>((a) => a.repo != null) &&
                !_writingWater;
            final fresh = _waterDate == _date;
            final ml = fresh ? _waterMl : null;
            final mg = fresh ? _caffeineMg : null;
            final waterStep = kJournalFieldsByKey['water_ml']!.step;
            final cups = mg == null ? null : mg / kCaffeinePerCup;
            return Row(children: [
              Expanded(
                child: _DoseTile(
                  icon: LucideIcons.glassWater,
                  color: C.blue,
                  value: '${((ml ?? 0) / 1000).toStringAsFixed(1)} L',
                  empty: ml == null,
                  addLabel: AppLocalizations.of(c)?.nutritionAddWater ?? 'Add water',
                  removeLabel:
                      AppLocalizations.of(c)?.nutritionRemoveWater ?? 'Remove water',
                  onDown: (!live || ml == null)
                      ? null
                      : () => _stepDose('water_ml', waterStep, -1),
                  onUp: (!live || (ml ?? 0) >= kJournalFieldsByKey['water_ml']!.max)
                      ? null
                      : () => _stepDose('water_ml', waterStep, 1),
                ),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: _DoseTile(
                  icon: LucideIcons.coffee,
                  color: C.orange,
                  value: cups == null
                      ? '0'
                      : (cups == cups.roundToDouble()
                          ? cups.round().toString()
                          : cups.toStringAsFixed(1).replaceAll('.', ',')),
                  empty: mg == null,
                  addLabel: tr(c, 'Tasse Kaffee hinzufügen', 'Add a cup of coffee'),
                  removeLabel: tr(c, 'Tasse Kaffee entfernen', 'Remove a cup of coffee'),
                  onDown: (!live || mg == null)
                      ? null
                      : () => _stepDose('caffeine_mg', kCaffeinePerCup, -1),
                  onUp: (!live ||
                          (mg ?? 0) >= kJournalFieldsByKey['caffeine_mg']!.max)
                      ? null
                      : () => _stepDose('caffeine_mg', kCaffeinePerCup, 1),
                ),
              ),
            ]);
          }),
          const SizedBox(height: S.x3),
          CreatineRow(
            taken: creatineTakenToday(_profile),
            onTap: () async {
              await setCreatineTaken(c, !creatineTakenToday(_profile));
              if (mounted) await _load();
            },
          ),
          const SizedBox(height: S.x3),
          const FastingCard(),
        ],
      ],
    );
  }



  // ── WEEK ─────────────────────────────────────────────────────────────────

  Widget _weekTab(BuildContext c) {
    final l = AppLocalizations.of(c);
    final w = _week;
    if (w == null) return const SizedBox.shrink();
    final counted = w.counted.length;
    final balance = weeklyEnergyBalance(w, _burnedByDate, _wornMinByDate);
    // PARTIAL, not "excluded": today is excluded from the averages too, and it
    // is not partial — a day cannot be judged incomplete while it is still
    // happening (see `DayLogState.inProgress`).
    final partial = _partialDays(w);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Surface(
          child: Consistency(
            w.daysLogged,
            w.span,
            partial == 0
                ? (l?.nutritionDaysLoggedLabel ?? 'Days with something logged')
                : (l?.nutritionPartialExcluded(partial) ??
                    '$partial logged but partial, so excluded from '
                        'every average below'),
            C.domFood,
          ),
        ),
        Section(l?.nutritionEnergyByDay ?? 'Energy, day by day', _weekChart(c, w)),
        Section(
          l?.nutritionSevenDayAvg ?? 'Seven-day average',
          counted == 0
              ? StatusCard(
                  l?.nutritionNoCompleteDayTitle ?? 'No complete day to average yet',
                  l?.nutritionNoCompleteDayBody ?? 'You have none.',
                  icon: LucideIcons.chartNoAxesColumn,
                )
              : Surface(
                  child: Column(
                    children: [
                      _Mean(l?.nutritionLabelEnergy ?? 'Energy', w.meanKcal,
                          'kcal', C.domFood),
                      _Mean(l?.nutritionLabelProtein ?? 'Protein',
                          w.meanProtein, 'g', C.red),
                      _Mean(l?.nutritionLabelCarbs ?? 'Carbs', w.meanCarbs,
                          'g', C.orange),
                      _Mean(l?.nutritionLabelFat ?? 'Fat', w.meanFat, 'g',
                          C.yellow),
                      _Mean(l?.nutritionLabelFibre ?? 'Fibre', w.meanFibre,
                          'g', C.green),
                    ],
                  ),
                ),
        ),
        if (balance != null)
          Section(
            l?.nutritionEnergyBalance ?? 'Energy balance',
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InlineMetrics([
                    (l?.nutritionLabelEaten ?? 'EATEN',
                        '${balance.eaten.round()} kcal', C.domFood),
                    (l?.nutritionLabelBurned ?? 'BURNED',
                        '${balance.burned.round()} kcal', C.purple),
                    (
                      l?.nutritionLabelBalance ?? 'BALANCE',
                      '${balance.balance.round()} kcal',
                      C.teal,
                    ),
                  ]),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Logged days that are genuinely partial. Today is deliberately not one of
  /// them — it is unfinished, not incomplete.
  static int _partialDays(NutritionWindow w) =>
      w.days.where((d) => d.state == DayLogState.partial).length;

  /// Seven bars of logged energy, today highlighted. A day with nothing logged
  /// draws no bar rather than a zero — zero kcal is a claim, and an unlogged
  /// day is an absence. A PARTIAL day still draws, because its total is a real
  /// floor; the footnote says it is one and that the mean below excluded it.
  Widget _weekChart(BuildContext c, NutritionWindow w) {
    final l = AppLocalizations.of(c);
    // `?? 0.0` here was the whole absence-versus-zero bug in one operator: an
    // unlogged day became a real zero, and `Bars`' 2 pt visibility floor drew
    // it as a measured day with almost nothing in it. Null is a hole.
    final vals = [for (final d in w.days) d.kcal.value?.toDouble()];
    final real = vals.whereType<double>().where((v) => v > 0).toList();
    final drawn = real.length;
    final axis = drawn == 0 ? null : AxisSpec.of(real, floor: 0);
    return Surface(
      child: ChartFrame(
        title: l?.nutritionEnergyLoggedTitle ?? 'Energy logged',
        unit: 'kcal',
        height: 120,
        yAxis: axis,
        // The window is built oldest-first ending today, so these labels are
        // the range actually drawn rather than a hardcoded guess.
        xLabels: drawn == 0
            ? const []
            : [
                _dayShort(w.days.first.date, l),
                l?.nutritionTabToday ?? 'Today',
              ],
        footnote: _partialDays(w) == 0
            ? null
            : l?.nutritionPartialFootnote(_partialDays(w)) ??
                '${_partialDays(w)} partial, left out of the averages below.',
        // The bars are ENERGY. A week of one-tap occasions is a fully logged
        // week with no energy in it, and "Nothing logged yet" called the user
        // a liar directly under a card counting those same days.
        empty: axis == null
            ? NoData(
                message: w.daysLogged == 0
                    ? (l?.nutritionNothingLoggedYet ?? 'Nothing logged yet')
                    : (l?.nutritionNoEnergyFiguresYet ?? 'No energy figures yet'))
            : null,
        series: vals,
        child: axis == null
            ? const SizedBox.shrink()
            : CustomPaint(
                size: Size.infinite,
                painter: Bars(vals, C.domFood,
                    highlight: vals.length - 1, t: animate(c, 1), axis: axis),
              ),
      ),
    );
  }

  // ── GOALS ────────────────────────────────────────────────────────────────

  /// A target the user TYPES. Adaptive targets need weight history and ~21
  /// complete days and stay deferred; a typed one needs no science at all, and
  /// the tab is named Goals.
  static List<(String, String, String, Color)> _goalSpecs(BuildContext c) {
    final l = AppLocalizations.of(c);
    return [
      ('kcal_target', l?.nutritionDailyEnergy ?? 'Daily energy', 'kcal', C.domFood),
      ('protein_target', l?.nutritionDailyProtein ?? 'Daily protein', 'g', C.red),
    ];
  }

  double? _target(String key) => (_profile[key] as num?)?.toDouble();

  /// The same gated mean the Week tab prints, so goal progress and the average
  /// can never disagree — including about how many days went into it.
  NutrientMean? _meanFor(String key) =>
      key == 'kcal_target' ? _week?.meanKcal : _week?.meanProtein;

  Future<void> _editTargets() async {
    final specs = _goalSpecs(context);
    final ctrls = {
      for (final g in specs)
        g.$1: TextEditingController(text: _target(g.$1)?.round().toString() ?? ''),
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(context),
      backgroundColor: P.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) {
        final l = AppLocalizations.of(s);
        return Padding(
          padding: EdgeInsets.only(
              left: S.x5,
              right: S.x5,
              top: S.x5,
              bottom: MediaQuery.of(s).viewInsets.bottom + S.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l?.nutritionYourTargetsSection ?? 'Your targets',
                  style: F.head.copyWith(color: P.of(s).ink)),
              const SizedBox(height: S.x4),
              for (final g in specs) ...[
                OsTextField(
                  controller: ctrls[g.$1]!,
                  label: '${g.$2} (${g.$3})',
                  hint: l?.nutritionHintNone ?? 'none',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: S.x3),
              ],
              const SizedBox(height: S.x2),
              BigButton(l?.actionSave ?? 'Save',
                  color: C.domFood, onTap: () => Navigator.of(s).pop(true)),
            ],
          ),
        );
      },
    );
    // Blank clears the target; a typo does NOT. "2,000" used to clear it and
    // the sheet closed as if it had saved.
    final typed = {
      for (final g in specs) g.$1: Typed.of(ctrls[g.$1]!.text),
    };
    final fields = {
      for (final g in specs) g.$1: typed[g.$1]!.value,
    };
    for (final ctrl in ctrls.values) {
      ctrl.dispose();
    }
    if (saved != true || !mounted) return;
    final bad = [for (final g in specs) if (typed[g.$1]!.bad) g.$2];
    if (bad.isNotEmpty) {
      sayUnreadable(context, bad);
      return;
    }
    await context.read<AppState>().updateProfile(fields);
    await _load();
  }

  Future<void> _editWeightGoal() async {
    if (await editWeightGoal(context) && mounted) await _load();
  }

  Widget _goalsTab(BuildContext c) {
    final l = AppLocalizations.of(c);
    final specs = _goalSpecs(c);
    final set = [for (final g in specs) if (_target(g.$1) != null) g];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (set.isEmpty)
          StatusCard(
            l?.nutritionNoTargetsTitle ?? 'No targets set',
            l?.nutritionNoTargetsBody ?? 'A target here is one you type.',
            fix: l?.nutritionSetTargetFix ?? 'Set a target',
            icon: LucideIcons.target,
            onFix: _editTargets,
          )
        else
          Section(
            l?.nutritionYourTargetsSection ?? 'Your targets',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final g in set) ...[
                  _goalCard(c, g),
                  const SizedBox(height: S.x3),
                ],
              ],
            ),
            action: l?.nutritionEditAction ?? 'Edit',
            onAction: _editTargets,
          ),
        Section(
          tr(c, 'Zielgewicht', 'Target weight'),
          WeightGoalSection(
            profile: _profile,
            forecast: weightBalance(
              week: _week,
              burnedByDate: _burnedByDate,
              wornMinByDate: _wornMinByDate,
              kcalTarget: _target('kcal_target'),
              today: _date,
            ),
            onEdit: _editWeightGoal,
          ),
          action: l?.nutritionEditAction ?? 'Edit',
          onAction: _editWeightGoal,
        ),
        const SizedBox(height: S.x4),
        // Edge+: the API key for the meal photo estimate.
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: SetRow(
            LucideIcons.camera,
            C.domFood,
            tr(c, 'KI für Essensfotos', 'AI for meal photos'),
            onTap: () => editFoodAiKeys(c),
          ),
        ),
      ],
    );
  }

  /// Current → target → the rate between them. The "current" is the mean of
  /// COMPLETE days only, the same denominator the Week tab uses, so the goal
  /// and the average can never disagree about what was counted.
  Widget _goalCard(BuildContext c, (String, String, String, Color) g) {
    final l = AppLocalizations.of(c);
    final target = _target(g.$1)!;
    final m = _meanFor(g.$1);
    final mean = m?.value;
    // A stable per-goal noun, not `g.$2`'s last word: the label is a full
    // localized phrase ("Énergie quotidienne" in French puts the adjective
    // AFTER the noun), so slicing it grabs "quotidienne", not "énergie".
    final nutrient = g.$1 == 'kcal_target'
        ? (l?.nutritionEnergyWord ?? 'energy')
        : (l?.nutritionProteinWord ?? 'protein');
    if (mean == null || target <= 0) {
      return StatusCard(
        l?.nutritionNothingToMeasure(nutrient) ??
            'Nothing to measure $nutrient against yet',
        // Two different absences, and the difference matters: the day never
        // qualified, or it qualified on energy while this nutrient was only a
        // floor. Progress against a floor would read low every single day.
        // Three, actually — the third is a day that DID qualify while this
        // nutrient was never typed at all, and blaming that on day
        // completeness is a sentence the user can see is false.
        (m?.floorDays ?? 0) > 0
            ? (l?.nutritionFloorAverageBody(nutrient) ??
                'Every complete day had an occasion logged without a '
                    '$nutrient figure, so the average would only be a lower '
                    'bound.')
            : (_week?.counted.length ?? 0) > 0
                ? (l?.nutritionCountedNoFigureBody(
                        _week!.counted.length, _week!.span, nutrient) ??
                    '${_week!.counted.length} of the last ${_week!.span} days '
                        'counted, but none of them carried a $nutrient '
                        'figure.')
                : (l?.nutritionDayCountsRuleFull(_week?.span ?? 7) ??
                    'A day counts once every occasion carries a figure and '
                        'the log reaches the evening. None of the last '
                        '${_week?.span ?? 7} days has.'),
        fix: (m?.floorDays ?? 0) > 0 || (_week?.counted.length ?? 0) > 0
            ? (l?.nutritionAddNumbersFix ?? 'Add the numbers to an occasion')
            : (l?.nutritionLogOccasionFix ?? 'Log an eating occasion'),
        icon: LucideIcons.target,
        onFix: _logFood,
      );
    }
    // The nutrient's OWN denominator, not the window's count of complete days:
    // protein can be measured on fewer days than energy was.
    final days = m!.days;
    final diff = mean - target;
    final rate = diff.abs() < 1
        ? (l?.nutritionOnTarget ?? 'On target')
        : (diff > 0
            ? (l?.nutritionRateAbove(diff.abs().round(), g.$3) ??
                '${diff.abs().round()} ${g.$3}/day above')
            : (l?.nutritionRateBelow(diff.abs().round(), g.$3) ??
                '${diff.abs().round()} ${g.$3}/day below'));
    final meanNote = l?.nutritionMeanOfDays(days) ??
        'mean of $days complete day${days == 1 ? '' : 's'}';
    return GoalTrajectory(
      g.$2,
      '${mean.round()} ${g.$3}',
      '${target.round()} ${g.$3}',
      '$rate · $meanNote',
      (mean / target).clamp(0, 1).toDouble(),
      g.$4,
      rateDown: diff > 0,
    );
  }
}

/// "Thu 4 Sep" from a `YYYY-MM-DD` day label, for an axis end-label.
String _dayShort(String ymd, [AppLocalizations? l]) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : formatDay(d, l);
}

// ── components ─────────────────────────────────────────────────────────────

/// Today's energy, with its honesty state on the face of it. `at least` is not
/// a hedge — it is arithmetic: a total that summed past unknown values is a
/// lower bound and nothing more.
class DayEnergyCard extends StatelessWidget {
  const DayEnergyCard({super.key, required this.day, this.burned});

  final NutritionDay day;
  final Metric? burned;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final k = day.kcal;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  k.value == null
                      ? (l?.nutritionLoggedToday ?? 'LOGGED TODAY')
                      : (l?.nutritionEatenToday ?? 'EATEN TODAY'),
                  style: F.over.copyWith(color: p.ink3),
                ),
              ),
              if (k.isFloor)
                Flexible(child: Pill(l?.nutritionAtLeast ?? 'At least', C.yellow)),
            ],
          ),
          const SizedBox(height: S.x2),
          // With no energy anywhere in the day, the occasion count IS the
          // measurement. A dash here would read as a failure to record when
          // the day was in fact recorded exactly as designed.
          // A Wrap rather than a Row with a Spacer: `2,310 kcal` beside the
          // occasion count overflowed by 168 px at 3.1x, which is a day's
          // energy pushed off the card for the people who chose that size.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: S.x1,
            runSpacing: S.x1,
            children: [
              Text(
                k.value == null
                    ? day.entries.length.toString()
                    : k.value!.round().toString(),
                style: F.n34.copyWith(color: p.ink),
              ),
              Text(
                k.value == null
                    ? (l?.nutritionOccasionsUnit(day.entries.length) ??
                        'occasion${day.entries.length == 1 ? '' : 's'}')
                    : 'kcal',
                style: F.cap.copyWith(color: p.ink3),
              ),
              if (k.value != null)
                Text(
                  '· ${l?.nutritionOccasionsCount(day.entries.length) ??
                      '${day.entries.length} occasion'
                          '${day.entries.length == 1 ? '' : 's'}'}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
            ],
          ),
          if (burned?.value != null) ...[
            const SizedBox(height: S.x4),
            InlineMetrics([
              (l?.nutritionLabelBurned ?? 'BURNED',
                  '${burned!.value!.round()} kcal', C.purple),
              if (k.value != null)
                (
                  // Eaten is a FLOOR when occasions were logged without an
                  // energy figure, so eaten minus burned is a floor too: the
                  // balance is AT LEAST this, never at most. The pill on this
                  // same card says "At least".
                  k.isFloor
                      ? (l?.nutritionLabelBalanceAtLeast ?? 'BALANCE AT LEAST')
                      : (l?.nutritionLabelBalance ?? 'BALANCE'),
                  '${(k.value! - burned!.value!).round()} kcal',
                  C.teal,
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// One meal slot. An empty slot is an invitation, not a gap — the row never
/// implies you failed to log something you may simply not have eaten.
class MealRow extends StatelessWidget {
  const MealRow({
    super.key,
    required this.meal,
    required this.entries,
    this.onTap,
  });

  final String meal;
  final List<FoodEntry> entries;
  final VoidCallback? onTap;

  static const _icons = {
    'breakfast': LucideIcons.eggFried,
    'lunch': LucideIcons.salad,
    'dinner': LucideIcons.beef,
    'snack': LucideIcons.apple,
  };

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final known = [
      for (final e in entries)
        if (e.kcal != null) e.kcal!,
    ];
    final total = known.isEmpty ? null : known.reduce((a, b) => a + b);
    final anyUnknown = entries.any((e) => e.kcal == null);
    return Pressable(
      onTap: onTap,
      semanticLabel: _mealLabel(c, meal),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
              child: Icon(
                _icons[meal] ?? LucideIcons.utensils,
                size: 17,
                color: p.ink2,
              ),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mealLabel(c, meal),
                    style: F.body.copyWith(color: p.ink),
                  ),
                  // Edge+: no caption for an empty meal; the + says it.
                  if (total != null)
                    Text(
                      '${anyUnknown ? (l?.nutritionAtLeastPrefix ?? 'at least ') : ''}'
                          '${total.round()} kcal',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                ],
              ),
            ),
            Icon(LucideIcons.plus, size: 20, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

String _mealLabel(BuildContext c, String m) {
  final l = AppLocalizations.of(c);
  return switch (m) {
    'breakfast' => l?.nutritionMealBreakfast ?? 'Breakfast',
    'lunch' => l?.nutritionMealLunch ?? 'Lunch',
    'dinner' => l?.nutritionMealDinner ?? 'Dinner',
    _ => l?.nutritionMealSnacks ?? 'Snacks',
  };
}

/// One nutrient's seven-day mean, with its own denominator.
///
/// The denominator is the nutrient's, not the window's: a day counts toward the
/// ENERGY average on complete kcal alone, so protein can be a floor on a day
/// that qualified. Those days are excluded and NAMED here — a mean built on
/// floors is understated, and printing it beside the energy mean as though both
/// were measured the same way is the failure this row exists to prevent. There
/// is deliberately no "at least" pill: the gated mean is not a floor, so a floor
/// marker would be as wrong as the understatement it replaced.
class _Mean extends StatelessWidget {
  const _Mean(this.label, this.mean, this.unit, this.color);
  final String label;
  final NutrientMean mean;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final floors = mean.floorDays;
    return MetricRow(
      LucideIcons.chartNoAxesColumn,
      color,
      label,
      mean.value == null
          ? (floors > 0
              ? (l?.nutritionNotCounted ?? 'Not counted')
              : (l?.nutritionNotRecorded ?? 'Not recorded'))
          : mean.value!.round().toString(),
      unit: mean.value == null ? '' : unit,
      sub: '',
    );
  }
}

/// Edge+: water or coffee, with the minus and plus on the tile. The icon
/// says which; no caption.
class _DoseTile extends StatelessWidget {
  const _DoseTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.empty,
    required this.addLabel,
    required this.removeLabel,
    this.onDown,
    this.onUp,
  });

  final IconData icon;
  final Color color;
  final String value;

  /// Nothing logged today: the figure is drawn muted.
  final bool empty;
  final String addLabel, removeLabel;
  final VoidCallback? onDown, onUp;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget step(IconData i, VoidCallback? onTap, String label) => Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onTap != null ? p.wash(color) : p.card2,
              shape: BoxShape.circle,
            ),
            child: Icon(i, size: 16, color: onTap != null ? p.on(color) : p.ink3),
          ),
        );
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: p.on(color)),
          const SizedBox(width: S.x2),
          Flexible(
            child: Text(
              value,
              style: F.n24.copyWith(color: empty ? p.ink3 : p.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        const SizedBox(height: S.x2),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          step(LucideIcons.minus, onDown, removeLabel),
          step(LucideIcons.plus, onUp, addLabel),
        ]),
      ]),
    );
  }
}

/// Edge+: a planned meal under its occasion, drawn apart from what was eaten.
class _PlannedRow extends StatelessWidget {
  const _PlannedRow(this.m, {this.onTap});
  final PlannedMeal m;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: m.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: p.wash(C.domFood),
              borderRadius: R.rSm,
            ),
            child: Icon(LucideIcons.calendarClock, size: 16, color: p.on(C.domFood)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: F.body.copyWith(color: p.ink2)),
              if (m.kcal != null)
                Text(
                  '${m.kcal!.round()} kcal'
                  '${m.servings == 1 ? '' : ' · ${servingsLabel(c, m.servings)}'}',
                  style: F.over.copyWith(color: p.ink3),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Edge+: the week calendar at the top of the tab. Seven days, Monday first;
/// a day with something planned has its number in green. Chevrons move a week.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.today,
    required this.selected,
    required this.planned,
    required this.onPick,
    required this.onShift,
  });

  final List<String> days;
  final String today, selected;
  final Set<String> planned;
  final ValueChanged<String> onPick;
  final ValueChanged<int> onShift;

  static const _de = ['M', 'D', 'M', 'D', 'F', 'S', 'S'];
  static const _en = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final letters =
        Localizations.localeOf(c).languageCode == 'de' ? _de : _en;
    Widget chevron(IconData i, int dir) => Pressable(
          onTap: () => onShift(dir),
          semanticLabel: dir < 0
              ? tr(c, 'Vorherige Woche', 'Previous week')
              : tr(c, 'Nächste Woche', 'Next week'),
          child: SizedBox(
            width: 20,
            height: 48,
            child: Icon(i, size: 16, color: p.ink3),
          ),
        );
    return Row(children: [
      chevron(LucideIcons.chevronLeft, -1),
      for (var i = 0; i < days.length; i++)
        Expanded(
          child: Pressable(
            onTap: () => onPick(days[i]),
            semanticLabel: days[i],
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(letters[i], style: F.over.copyWith(color: p.ink3)),
              const SizedBox(height: S.x1),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: days[i] == selected
                      ? p.fill(planned.contains(days[i]) ? C.green : C.domFood)
                      : null,
                  border: days[i] == today && days[i] != selected
                      ? Border.all(color: p.on(C.domFood), width: 1.5)
                      : null,
                ),
                child: Text(
                  '${DateTime.parse(days[i]).day}',
                  style: F.cap.copyWith(
                    color: days[i] == selected
                        ? p.inkOnFill
                        : planned.contains(days[i])
                            ? p.on(C.green)
                            : p.ink,
                    fontWeight: planned.contains(days[i])
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ),
      chevron(LucideIcons.chevronRight, 1),
    ]);
  }
}
