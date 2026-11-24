import '../../l10n/display_text.dart';
// Logging an eating occasion.
//
// The primary unit is the OCCASION, not the food. The big button at the top
// writes a complete, valid entry with no numbers in it at all — a trial
// comparing detailed against simplified logging found 49% of days logged
// versus 97%, with identical six-month weight loss. Macro detail is the tier
// underneath, opened deliberately, and never the path a new user is walked
// down.
//
// Edge+: there IS a photo estimate. A meal photo goes to Gemini (free key)
// or Claude with the user's own API key (lib/ai/food_photo.dart) and its estimate PRE-FILLS the
// number boxes; the model may ask up to two short questions, answered here, to
// refine it. Nothing is written until the user presses Save, which is the
// confirmation `FoodEntry.sanitised` asks of a photo entry.
//
// There IS a barcode scan, and it lives inside "Add the numbers" rather than
// beside the occasion button. A scan is macro detail, and macro detail is the
// tier underneath — a new user is not walked down it.
//
// A SCAN PART-FILLS. That is the normal case, not a failure: only about 12% of
// products carry all seven core fields, and everything Open Food Facts hands
// over goes through `gateNutrients` first, which drops a physically impossible
// value rather than round it into range. Every box the lookup could not stand
// behind is left EMPTY for the user to type. None of it is a measurement —
// see `FoodSource.barcode`.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ai/food_photo.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../data/nutrition_store.dart';
import '../../data/off_lookup.dart';
import '../../l10n/app_localizations.dart';
import '../profile/profile.dart' show SetRow;
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;
import 'log_workout.dart' show dayLabel;
import 'food_ai_key_sheet.dart';
import 'scan_barcode.dart';
import 'recipes_screen.dart';
import '../../data/meal_plan_store.dart';

class LogFoodSheet extends StatefulWidget {
  const LogFoodSheet({super.key, this.date, this.meal = 'snack', this.entry});

  final String? date;
  final String meal;

  /// An existing entry to EDIT instead of logging a new one. Same id on save,
  /// and the sheet can remove it.
  final FoodEntry? entry;

  /// Show as a bottom sheet. Resolves true when something was logged, edited
  /// or removed.
  static Future<bool?> show(
    BuildContext c, {
    String? date,
    String meal = 'snack',
    FoodEntry? entry,
  }) => showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (_) => LogFoodSheet(date: date, meal: meal, entry: entry),
  );

  @override
  State<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<LogFoodSheet> {
  FoodEntry? get _editing => widget.entry;
  late String _date = _editing?.date ?? widget.date ?? todayLabel();
  late String _meal = _editing?.meal ?? widget.meal;

  /// When it was eaten, on [_date]. Defaults to now so the one-tap path is
  /// unchanged; picking one is how a meal gets logged after the fact. Null
  /// only for an edited entry that never had a time — it stays unrecorded
  /// rather than gaining one nobody chose.
  late TimeOfDay? _time = switch (widget.entry) {
    null => TimeOfDay.now(),
    FoodEntry(atTs: final ts?) =>
      TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ts * 1000)),
    _ => null,
  };


  final _label = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fibre = TextEditingController();

  /// Grams. Only on screen once a scan has landed — the numbers arrive per
  /// 100 g and somebody who ate one 33 g packet should not have to do the
  /// arithmetic themselves.
  final _portion = TextEditingController();


  /// The last scan's product, when it produced one. Holds the per-100 g
  /// figures the portion field rescales from, and its barcode becomes the
  /// entry's `foodKey`.
  OffProduct? _scanned;

  /// What the last lookup did, for the card that says so. Null before the
  /// first scan of this sheet.
  OffOutcome? _outcome;
  bool _looking = false;

  // ── Edge+: photo estimate ──
  List<int>? _photo;
  FoodPhotoEstimate? _estimate;
  bool _estimating = false;
  String? _photoError;
  FoodAi _ai = FoodAi.gemini;
  List<TextEditingController> _answers = const [];

  @override
  void initState() {
    super.initState();
    final e = _editing;
    if (e != null) {
      _label.text = e.label;
      _kcal.text = _plain(e.kcal);
      _protein.text = _plain(e.proteinG);
      _carbs.text = _plain(e.carbsG);
      _fat.text = _plain(e.fatG);
      _fibre.text = _plain(e.fibreG);
      _loadScanned(e);
    }
    _portion.addListener(_rescale);
  }

  /// A scanned entry reopens with its product attached, so changing the
  /// portion rescales the numbers the same way it did when it was logged.
  /// The portion is set BEFORE the product, so the listener does not
  /// overwrite numbers the user may have typed over since.
  Future<void> _loadScanned(FoodEntry e) async {
    final key = e.foodKey;
    if (e.source != FoodSource.barcode || key == null) return;
    final row = await NutritionDb.foodDef(await LocalDb.instance, key);
    if (row == null || row['source'] != 'barcode' || !mounted) return;
    setState(() {
      _portion.text = _plain(e.quantity);
      _scanned = OffProduct.fromDefRow(row);
    });
  }

  @override
  void dispose() {
    _portion.removeListener(_rescale);
    for (final t in [
      _label,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fibre,
      _portion,
      ..._answers,
    ]) {
      t.dispose();
    }
    super.dispose();
  }



  /// Set while a write is in flight and kept through the pop that follows:
  /// a second tap before the sheet closes would otherwise insert the same
  /// meal twice under a fresh id.
  bool _writing = false;

  Future<void> _write(FoodEntry e) async {
    if (_writing) return;
    _writing = true;
    try {
      final db = await LocalDb.instance;
      if (_editing != null) {
        await NutritionDb.update(db, e);
      } else {
        await NutritionDb.put(db, e);
      }
    } catch (err) {
      // Every caller is a fire-and-forget onTap, so a rethrow only reached
      // the global error log: the sheet sat there unchanged and a locked or
      // full database looked exactly like a save that worked.
      debugPrint('log food: save failed: $err');
      _writing = false;
      _sayFailed((l) => l?.nutritionSaveFailed ??
          'Not saved — the meal is still here. Try again.');
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  void _sayFailed(String Function(AppLocalizations?) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text(AppLocalizations.of(context)))));
  }

  /// Removing is destructive and there is no undo, so the entry is named back
  /// before it goes.
  Future<void> _remove(FoodEntry e) async {
    final l = AppLocalizations.of(context);
    final ok = await confirmRemove(
      context,
      title: l?.nutritionRemoveTitle(e.label) ?? 'Remove ${e.label}?',
      body: l?.nutritionRemoveBody ??
          'It leaves the day and every average that counted it. There is no '
              'undo.',
    );
    if (!ok) return;
    try {
      await NutritionDb.delete(await LocalDb.instance, e.id);
    } catch (err) {
      debugPrint('log food: remove failed: $err');
      _sayFailed((l) => l?.nutritionRemoveFailed ??
          'Not removed — the meal is still there. Try again.');
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Epoch seconds for [_time] on [_date], or null when no time is set.
  int? get _atTs {
    final t = _time;
    final d = DateTime.tryParse(_date);
    if (t == null || d == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute)
            .millisecondsSinceEpoch ~/
        1000;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = dayLabelOf(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  FoodEntry _base({
    required String label,
    FoodSource source = FoodSource.manual,
  }) => FoodEntry(
    id: NutritionDb.newId(),
    date: _date,
    meal: _meal,
    label: label,
    atTs: _atTs,
    source: source,
  );

  /// Blank is unknown, never zero — and a typo is NEITHER. "1,200" or
  /// "850 kcal" used to arrive here as the same null as an empty field and the
  /// meal was written with the energy silently dropped.
  double? _num(TextEditingController t) => Typed.of(t.text).value;

  // ── Edge+: recipes ──
  Future<void> _pickRecipe() async {
    final today = todayLabel();
    final pick = await RecipePickerPage.open(context,
        meal: _meal,
        canEat: _date.compareTo(today) <= 0,
        canPlan: _date.compareTo(today) >= 0);
    if (pick == null || !mounted) return;
    if (!pick.eat) {
      MealPlanStore.add(_date, pick.toPlanned(_meal));
      Navigator.of(context).pop(true);
      return;
    }
    if (pick.repeat case final r?) {
      await _write(FoodEntry(
        id: NutritionDb.newId(),
        date: _date,
        meal: _meal,
        label: r.label,
        atTs: _atTs,
        foodKey: r.foodKey,
        quantity: r.quantity,
        unit: r.unit,
        kcal: r.kcal,
        proteinG: r.proteinG,
        carbsG: r.carbsG,
        fatG: r.fatG,
        fibreG: r.fibreG,
        source: FoodSource.repeat,
        confirmed: r.confirmed,
      ));
      return;
    }
    final n = pick.nutrients;
    await _write(FoodEntry(
      id: NutritionDb.newId(),
      date: _date,
      meal: _meal,
      label: pick.name,
      atTs: _atTs,
      quantity: n == null ? null : pick.servings,
      unit: 'Portion',
      kcal: n?.kcal,
      proteinG: n?.protein,
      carbsG: n?.carbs,
      fatG: n?.fat,
      fibreG: n?.fibre,
      confirmed: true,
    ));
  }

  // ── Edge+: the photo path ──────────────────────────────────────────────────

  String _lang(BuildContext c) =>
      Localizations.localeOf(c).languageCode == 'de' ? 'de' : 'en';

  /// Take (or pick) a photo and ask the AI for an estimate. Asks for an API
  /// key first when none is stored.
  Future<void> _takePhoto() async {
    var ai = await activeFoodAi();
    if (ai == null) {
      if (!mounted) return;
      await editFoodAiKeys(context);
      ai = await activeFoodAi();
      if (ai == null || !mounted) return;
    }
    if (!mounted) return;
    final source = await _askPhotoSource(context);
    if (source == null || !mounted) return;
    final XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
    } catch (e) {
      debugPrint('food photo: picker failed: $e');
      if (mounted) {
        setState(() => _photoError = tr(context,
            'Kamera oder Galerie konnte nicht geöffnet werden.',
            'Could not open the camera or gallery.'));
      }
      return;
    }
    if (shot == null || !mounted) return;
    _photo = await shot.readAsBytes();
    await _estimatePhoto(ai);
  }

  /// Ask again from the same photo, with the answers typed so far.
  Future<void> _reestimate() async {
    final ai = await activeFoodAi();
    if (ai == null || !mounted) return;
    await _estimatePhoto(ai, withAnswers: true);
  }

  Future<void> _estimatePhoto((FoodAi, String) ai,
      {bool withAnswers = false}) async {
    final photo = _photo;
    if (photo == null) return;
    final qs = _estimate?.questions ?? const <String>[];
    final answers = withAnswers
        ? [
            for (var i = 0; i < qs.length && i < _answers.length; i++)
              if (_answers[i].text.trim().isNotEmpty)
                FoodQa(qs[i], _answers[i].text.trim()),
          ]
        : const <FoodQa>[];
    setState(() {
      _estimating = true;
      _ai = ai.$1;
      _photoError = null;
    });
    try {
      final est = await estimateFoodPhotoWith(
        ai.$1,
        apiKey: ai.$2,
        jpeg: photo,
        lang: _lang(context),
        answers: answers,
        hint: withAnswers ? _label.text : '',
      );
      if (!mounted) return;
      setState(() {
        _estimating = false;
        if (est.label.isEmpty) {
          _photoError = tr(context, 'Auf dem Foto ist kein Essen zu erkennen.',
              'No food could be recognised in the photo.');
          return;
        }
        _estimate = est;
        // A photo replaces a scan: the numbers are no longer the pack's.
        _scanned = null;
        _outcome = null;
        _label.text = est.label;
        _kcal.text = _plain(est.kcal);
        _protein.text = _plain(est.proteinG);
        _carbs.text = _plain(est.carbsG);
        _fat.text = _plain(est.fatG);
        _fibre.text = _plain(est.fibreG);
        for (final a in _answers) {
          a.dispose();
        }
        _answers = [
          for (final _ in withAnswers ? const <String>[] : est.questions)
            TextEditingController(),
        ];
      });
    } on FoodPhotoException catch (e) {
      if (mounted) {
        setState(() {
          _estimating = false;
          _photoError = e.message;
        });
      }
    } catch (e) {
      debugPrint('food photo: $e');
      if (mounted) {
        setState(() {
          _estimating = false;
          _photoError = '$e';
        });
      }
    }
  }

  /// The questions the AI asked, with a box each, and what it assumed.
  List<Widget> _photoBlock(BuildContext c) {
    final p = P.of(c);
    final est = _estimate;
    final out = <Widget>[];
    if (_estimating) {
      out.addAll([
        const SizedBox(height: S.x3),
        StatusCard(
          tr(c, '${foodAiName(_ai)} schaut sich das Foto an',
              '${foodAiName(_ai)} is looking at the photo'),
          tr(c, 'Das dauert meist 10 bis 30 Sekunden.',
              'This usually takes 10 to 30 seconds.'),
          icon: LucideIcons.camera,
          leading: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ]);
      return out;
    }
    if (_photoError != null) {
      out.addAll([
        const SizedBox(height: S.x3),
        StatusCard(tr(c, 'Keine Schätzung', 'No estimate'), _photoError!,
            icon: LucideIcons.triangleAlert),
      ]);
    }
    if (est == null) return out;
    final conf = switch (est.confidence) {
      'high' => tr(c, 'ziemlich sicher', 'fairly sure'),
      'medium' => tr(c, 'mittel sicher', 'somewhat sure'),
      _ => tr(c, 'grobe Schätzung', 'rough guess'),
    };
    final portion = est.portionG == null ? '' : ' · ~${_plain(est.portionG)} g';
    out.addAll([
      const SizedBox(height: S.x3),
      Text(
        '${tr(c, '${foodAiName(_ai)}-Schätzung', '${foodAiName(_ai)} estimate')} ($conf)$portion'
        '${est.note.isEmpty ? '' : '. ${est.note}'}',
        style: F.cap.copyWith(color: p.ink3, height: 1.45),
      ),
    ]);
    if (_answers.isNotEmpty) {
      out.add(const SizedBox(height: S.x3));
      for (var i = 0; i < _answers.length && i < est.questions.length; i++) {
        out.addAll([
          OsTextField(controller: _answers[i], label: est.questions[i]),
          const SizedBox(height: S.x3),
        ]);
      }
      out.add(BigButton(
        tr(c, 'Mit Antworten neu schätzen', 'Re-estimate with answers'),
        icon: LucideIcons.refreshCw,
        color: C.domFood,
        soft: true,
        onTap: _reestimate,
      ));
    }
    return out;
  }

  // ── the barcode path ──────────────────────────────────────────────────────

  /// Scan, then look the code up.
  ///
  /// Lookup is on by default, so this normally goes straight to the camera.
  /// The prompt below is for the person who turned it OFF and then tapped
  /// Scan: refusing silently there reads as a broken scanner. It is asked
  /// BEFORE the camera opens, not after — someone who would decline should not
  /// have pointed their phone at a packet first.
  Future<void> _scan() async {
    if (!offLookupAllowed) {
      final agreed = await _askLookupConsent(context);
      if (agreed != true || !mounted) return;
      // Awaited so the consent is on disk before the camera opens. A write
      // that fails only means being asked again next launch — the direction
      // that cannot hurt anyone.
      await setOffLookupAllowed(true);
      if (!mounted) return;
    }
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    setState(() {
      _looking = true;
      _outcome = null;
    });
    final res = await _lookup(code);
    if (!mounted) return;
    setState(() {
      _looking = false;
      _outcome = res.outcome;
      final p = res.product;
      if (p != null) {
        _apply(p);
      } else {
        // A scan that found nothing must not leave the PREVIOUS packet
        // attached. `_scanned` is what writes `foodKey` and stamps
        // `FoodSource.barcode` on the saved row, so keeping it here filed the
        // entry under the wrong barcode AND claimed a barcode provenance for
        // numbers that may have been typed over since. The form drops back to
        // manual, which is what it now is; the boxes keep whatever is in them,
        // because clearing a value the user typed would be its own bug.
        _scanned = null;
      }
    });
  }

  /// Cache first. `food_def` is keyed by barcode, so the second scan of the
  /// same packet is a local read and openfoodfacts.org hears nothing.
  Future<OffResult> _lookup(String code) async {
    final db = await LocalDb.instance;
    final cached = await NutritionDb.foodDef(db, code);
    // Only a row this path wrote. Crediting Open Food Facts for a dictionary
    // entry that came from somewhere else would be an attribution in the
    // wrong direction, which is its own kind of licence problem.
    if (cached != null && cached['source'] == 'barcode') {
      return OffResult(OffOutcome.ok, OffProduct.fromDefRow(cached));
    }
    final res = await fetchOffProduct(code);
    final p = res.product;
    if (p != null) await NutritionDb.putFoodDef(db, p.toDefRow());
    return res;
  }

  /// Fill the form from a product. Every box the gates could not stand behind
  /// is CLEARED rather than left holding the previous scan's number.
  void _apply(OffProduct p) {
    _scanned = p;
    _label.text = _productLabel(p);
    _portion.text = _plain(p.defaultPortionG);
    _fillFrom(p, p.defaultPortionG);
  }

  /// The portion field changed, so the five numbers change with it. Only when
  /// a scan is what put them there — a typed number is the user's and is never
  /// overwritten.
  void _rescale() {
    final p = _scanned;
    final g = Typed.of(_portion.text).value;
    if (p == null || g == null) return;
    _fillFrom(p, g);
  }

  /// What to say about the last lookup, or null when there is nothing to say
  /// — which is the case when it worked.
  ///
  /// Every branch ends in the same place on purpose: type the numbers off the
  /// pack. That is the fallback, it always was, and none of these are errors
  /// the user did anything to cause.
  StatusCard? _lookupProblem(BuildContext c) {
    final o = _outcome;
    if (o == null) return null;
    // A product whose numbers all survived needs no card; the filled boxes
    // are the answer.
    if (o == OffOutcome.ok && _scanned?.isBare != true) return null;
    final l = AppLocalizations.of(c);
    return switch (o) {
      OffOutcome.ok => StatusCard(
          l?.logFoodNoNumbersTitle ?? 'No numbers for this one',
          l?.logFoodNoNumbersBody ??
              'Open Food Facts has the product but nothing usable on its '
                  'nutrition — or what it had did not survive a sanity check.',
          icon: LucideIcons.scanBarcode,
        ),
      OffOutcome.notFound => StatusCard(
          l?.logFoodNotFoundTitle ?? 'Not in Open Food Facts',
          l?.logFoodNotFoundBody ?? 'Nobody has added this barcode yet.',
          icon: LucideIcons.scanBarcode,
        ),
      OffOutcome.flagged => StatusCard(
          l?.logFoodFlaggedTitle ?? 'This record is flagged as wrong',
          l?.logFoodFlaggedBody ??
              'Open Food Facts marks this product as containing errors, so none '
                  'of its numbers were filled in.',
          icon: LucideIcons.triangleAlert,
        ),
      OffOutcome.unreachable => StatusCard(
          l?.logFoodUnreachableTitle ?? 'No answer from Open Food Facts',
          l?.logFoodUnreachableBody ??
              'The lookup could not reach openfoodfacts.org.',
          icon: LucideIcons.cloudOff,
        ),
      OffOutcome.refused => StatusCard(
          l?.logFoodRefusedTitle ?? 'Barcode lookup is off',
          l?.logFoodRefusedBody ??
              'Nothing was sent. You can turn it on in Settings › Privacy.',
          icon: LucideIcons.scanBarcode,
        ),
    };
  }



  void _fillFrom(OffProduct p, double grams) {
    final v = p.forPortion(grams);
    _kcal.text = _plain(v.kcal);
    _protein.text = _plain(v.proteinG);
    _carbs.text = _plain(v.carbsG);
    _fat.text = _plain(v.fatG);
    _fibre.text = _plain(v.fibreG);
  }

  /// The number fields that were typed into and cannot be read.
  List<String> _unreadable(BuildContext c) {
    final l = AppLocalizations.of(c);
    return [
      for (final (name, ctl) in [
        (l?.logFoodEnergyLabel ?? 'Energy', _kcal),
        (l?.logFoodProteinLabel ?? 'Protein', _protein),
        (l?.logFoodCarbsLabel ?? 'Carbs', _carbs),
        (l?.logFoodFatLabel ?? 'Fat', _fat),
        (l?.logFoodFibreLabel ?? 'Fibre', _fibre),
        if (_scanned != null) (l?.logFoodPortionLabel ?? 'Portion', _portion),
      ])
        if (Typed.of(ctl.text).bad) name,
    ];
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x5, S.x6),
          children: [
            Row(
              children: [
                for (final m in kMeals) ...[
                  Expanded(
                    child: Pressable(
                      onTap: () => setState(() => _meal = m),
                      semanticLabel: _mealLabel(c, m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: S.x3),
                        decoration: BoxDecoration(
                          color: m == _meal ? p.fill(C.domFood) : p.card2,
                          borderRadius: R.rSm,
                        ),
                        child: Center(
                          child: Text(
                            _mealLabel(c, m),
                            style: F.cap.copyWith(
                              color: m == _meal ? p.inkOnFill : p.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (m != kMeals.last) const SizedBox(width: S.x2),
                ],
              ],
            ),
            const SizedBox(height: S.x3),
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Column(
                children: [
                  // Edge+: the day comes from the day picked on the tab; only
                  // an edit can move an entry to another day.
                  if (_editing != null)
                    SetRow(LucideIcons.calendar, C.domFood,
                        l?.logFoodDateLabel ?? 'Date',
                        value: dayLabel(
                            DateTime.tryParse(_date) ?? DateTime.now(),
                            l: l),
                        onTap: _pickDate),
                  SetRow(LucideIcons.clock, C.domFood,
                      l?.logFoodTimeLabel ?? 'Time',
                      value: _time == null
                          ? (l?.nutritionNotRecorded ?? 'Not recorded')
                          : formatMinuteOfDay(_time!.hour * 60 + _time!.minute),
                      onTap: _pickTime),
                ],
              ),
            ),
            if (_editing == null) ...[
              const SizedBox(height: S.x3),
              Surface(
                pad: const EdgeInsets.symmetric(horizontal: S.x4),
                child: Column(children: [
                  SetRow(
                    LucideIcons.camera,
                    C.domFood,
                    tr(c, 'Foto vom Essen', 'Photo of the meal'),
                    chevron: false,
                    onTap: _estimating ? null : _takePhoto,
                  ),
                  SetRow(
                    LucideIcons.chefHat,
                    C.domFood,
                    tr(c, 'Rezept', 'Recipe'),
                    onTap: _pickRecipe,
                  ),
                  SetRow(
                    LucideIcons.scanBarcode,
                    C.domFood,
                    l?.logFoodScanBarcode ?? 'Scan a barcode',
                    chevron: false,
                    onTap: _looking ? null : _scan,
                  ),
                ]),
              ),
              ..._photoBlock(c),
            ],
              if (_looking) ...[
                const SizedBox(height: S.x3),
                StatusCard(
                  l?.logFoodLookingUpTitle ?? 'Looking it up',
                  '',
                  icon: LucideIcons.scanBarcode,
                ),
              ] else if (_lookupProblem(c) != null) ...[
                const SizedBox(height: S.x3),
                _lookupProblem(c)!,
              ],
              const SizedBox(height: S.x4),
              OsTextField(
                controller: _label,
                label: l?.logFoodWhatLabel ?? 'What',
                hint: _mealLabel(c, _meal),
              ),
              if (_scanned != null) ...[
                const SizedBox(height: S.x4),
                _NumberRow(
                  fields: [(l?.logFoodPortionLabel ?? 'Portion', 'g', _portion)],
                  hint: '100',
                ),
              ],
              const SizedBox(height: S.x4),
              _NumberRow(
                fields: [
                  (l?.logFoodEnergyLabel ?? 'Energy', 'kcal', _kcal),
                  (l?.logFoodProteinLabel ?? 'Protein', 'g', _protein),
                ],
                hint: '–',
              ),
              const SizedBox(height: S.x4),
              _NumberRow(
                fields: [
                  (l?.logFoodCarbsLabel ?? 'Carbs', 'g', _carbs),
                  (l?.logFoodFatLabel ?? 'Fat', 'g', _fat),
                ],
                hint: '–',
              ),
              const SizedBox(height: S.x4),
              _NumberRow(
                fields: [(l?.logFoodFibreLabel ?? 'Fibre', 'g', _fibre)],
                hint: '–',
              ),
              // ODbL asks for attribution "reasonably calculated" to make a
              // viewer aware. It goes HERE, on the screen where the numbers
              // are, and not only in the licences page.
              if (_scanned != null) ...[
                const SizedBox(height: S.x3),
                const _OffCredit(),
              ],
              const SizedBox(height: S.x4),
              BigButton(
                _editing != null
                    ? (l?.actionSave ?? 'Save')
                    : (l?.logFoodIAte(_mealLabel(c, _meal)) ??
                        'I ate ${_mealLabel(c, _meal).toLowerCase()}'),
                icon: _editing != null ? null : LucideIcons.check,
                color: C.domFood,
                onTap: () {
                  // Edge+: one button. Nothing typed is the one-tap bare
                  // occasion, named after the meal, exactly as before.
                  final typed = _label.text.trim();
                  final label = typed.isEmpty ? _mealLabel(c, _meal) : typed;
                  final bad = _unreadable(c);
                  if (bad.isNotEmpty) {
                    sayUnreadable(c, bad);
                    return;
                  }
                  final b = _base(label: label);
                  final scan = _scanned;
                  // An edit keeps its id and everything this form does not
                  // show — the nutrients only the coach writes, the note —
                  // rather than dropping them as a side effect.
                  final o = _editing;
                  _write(
                    FoodEntry(
                      id: o?.id ?? b.id,
                      date: b.date,
                      meal: b.meal,
                      label: label,
                      atTs: b.atTs,
                      // The barcode, so a repeat of this food is a local
                      // read — and so the row can say where its numbers came
                      // from. NOT `verified`: see FoodSource.barcode.
                      foodKey: scan?.barcode ?? o?.foodKey,
                      quantity: scan != null
                          ? _num(_portion)
                          : (_estimate?.portionG ?? o?.quantity),
                      unit: scan == null ? (o?.unit ?? 'g') : 'g',
                      sugarG: o?.sugarG,
                      satFatG: o?.satFatG,
                      sodiumMg: o?.sodiumMg,
                      ironMg: o?.ironMg,
                      calciumMg: o?.calciumMg,
                      note: o?.note ?? '',
                      source: scan != null
                          ? FoodSource.barcode
                          : _estimate != null
                              ? FoodSource.photo
                              : (o?.source == FoodSource.photo
                                  ? FoodSource.photo
                                  : FoodSource.manual),
                      kcal: _num(_kcal),
                      proteinG: _num(_protein),
                      carbsG: _num(_carbs),
                      fatG: _num(_fat),
                      fibreG: _num(_fibre),
                      confirmed: true,
                    ),
                  );
                },
              ),
              if (_editing != null) ...[
                const SizedBox(height: S.x3),
                BigButton(
                  l?.logFoodRemoveEntry ?? 'Remove this entry',
                  icon: LucideIcons.trash2,
                  color: C.red,
                  soft: true,
                  onTap: () => _remove(_editing!),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// A number in a text box. Trailing zeros trimmed, because "33" is what the
/// pack says and "33.0" is what a float says.
String _plain(double? v) {
  if (v == null) return '';
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble()
      ? r.round().toString()
      : r.toStringAsFixed(1);
}

/// Brand in front of the product name, unless the name already carries it —
/// "Parle Parle-G" is how that goes wrong.
String _productLabel(OffProduct p) {
  final name = p.label;
  if (p.brand.isEmpty) return name;
  return name.toLowerCase().contains(p.brand.toLowerCase())
      ? name
      : '${p.brand} $name';
}

/// The disclosure, before the first lookup ever happens.
///
/// Asked once, then remembered; revocable from Settings › Privacy. It states
/// what leaves the phone — the barcode, and nothing else — because this app's
/// whole claim is that nothing does unless you said so.
Future<bool?> _askLookupConsent(BuildContext c) => showModalBottomSheet<bool>(
      context: c,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) {
        final p = P.of(s);
        final l = AppLocalizations.of(s);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l?.logFoodConsentTitle ?? 'Look barcodes up online?',
                    style: F.t2.copyWith(color: p.ink)),
                const SizedBox(height: S.x4),
                Text(
                  l?.logFoodConsentBody1 ??
                      'A scan sends the barcode to openfoodfacts.org, a free, '
                          'open food database. They see the barcode and your IP '
                          'address. Nothing about you, your meals or your health '
                          'leaves this phone, and a barcode you have scanned before '
                          'is answered from your own copy without asking them again.',
                  style: F.body.copyWith(color: p.ink2, height: 1.5),
                ),
                const SizedBox(height: S.x3),
                Text(
                  l?.logFoodConsentBody2 ??
                      'Their numbers are typed in by the public and a fair few of '
                          'them are wrong, so anything that fails a sanity check is '
                          'left blank rather than filled in. Everything it does fill '
                          'in is yours to edit before you save.',
                  style: F.body.copyWith(color: p.ink2, height: 1.5),
                ),
                const SizedBox(height: S.x3),
                Text(
                  l?.logFoodConsentBody3 ??
                      'You can turn this back off in Settings › Privacy. Typing '
                          'the numbers off the pack works either way.',
                  style: F.cap.copyWith(color: p.ink3, height: 1.45),
                ),
                const SizedBox(height: S.x5),
                BigButton(l?.logFoodAllowLookups ?? 'Allow lookups',
                    color: C.domFood, onTap: () => Navigator.of(s).pop(true)),
                const SizedBox(height: S.x3),
                BigButton(l?.logFoodNotNow ?? 'Not now',
                    color: C.domFood,
                    soft: true,
                    onTap: () => Navigator.of(s).pop(false)),
              ],
            ),
          ),
        );
      },
    );

/// The ODbL credit, wherever Open Food Facts numbers are shown. Both links
/// are the licence's, not decoration — the notice names the source and the
/// terms, and a user has to be able to reach both.
class _OffCredit extends StatelessWidget {
  const _OffCredit();

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kOffAttribution,
            style: F.cap.copyWith(color: p.ink3, height: 1.45)),
        const SizedBox(height: S.x1),
        // Wrap, not Row: "Open Database License" beside a URL runs off the
        // right of the sheet at accessibility text sizes, and a link that has
        // overflowed is a link nobody can follow.
        const Wrap(
          spacing: S.x3,
          runSpacing: S.x1,
          children: [
            _Link('openfoodfacts.org', kOffSite),
            _Link('Open Database License', kOffLicence),
          ],
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.url);
  final String label, url;

  @override
  Widget build(BuildContext c) => Pressable(
        semanticLabel: AppLocalizations.of(c)?.logFoodOpensInBrowser(label) ??
            '$label, opens in your browser',
        onTap: () => launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication),
        child: Text(
          label,
          style: F.cap.copyWith(
            color: P.of(c).on(C.domFood),
            decoration: TextDecoration.underline,
          ),
        ),
      );
}

String _mealLabel(BuildContext c, String m) {
  final l = AppLocalizations.of(c);
  return switch (m) {
    'breakfast' => l?.logFoodBreakfast ?? 'Breakfast',
    'lunch' => l?.logFoodLunch ?? 'Lunch',
    'dinner' => l?.logFoodDinner ?? 'Dinner',
    _ => l?.logFoodSnack ?? 'Snack',
  };
}

/// One logged entry. The provenance line is not decoration: a manufacturer
/// panel and a typed guess are different claims, and the row says which it is.
class FoodRow extends StatelessWidget {
  const FoodRow({
    super.key,
    required this.entry,
    this.trailing,
    this.onTap,
  });

  final FoodEntry entry;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final stacked = bigText(c);
    // Edge+: only a source that is not the user's own gets a pill.
    final showBadge = entry.source == FoodSource.barcode ||
        entry.source == FoodSource.photo;
    final badge = Pill(
              switch (entry.source) {
                FoodSource.barcode =>
                  l?.logFoodPillOpenFoodFacts ?? 'Open Food Facts',
                FoodSource.photo => tr(c, 'Foto', 'Photo'),
                _ => l?.logFoodPillYours ?? 'Yours',
              },
      C.n400,
      wrap: stacked,
    );
    return Pressable(
      onTap: onTap,
      semanticLabel: '${entry.label}. ${_detail(c, entry)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
              child: Icon(LucideIcons.utensils, size: 16, color: p.ink3),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.label, style: F.body.copyWith(color: p.ink)),
                  Text(
                    _detail(c, entry),
                    style: F.over.copyWith(color: p.ink3),
                  ),
                  if (stacked && showBadge) ...[const SizedBox(height: S.x1), badge],
                ],
              ),
            ),
            // "Verified" is still unreachable — there is no manufacturer feed
            // and a crowd-sourced record is not one. A barcode row says so by
            // name, which is also the ODbL credit at the point of display;
            // everything else here is the user's own.
            if (!stacked && showBadge) ...[const SizedBox(width: S.x2), badge],
            if (trailing != null) ...[
              const SizedBox(width: S.x2),
              Icon(trailing, size: 20, color: p.on(C.domFood)),
            ],
          ],
        ),
      ),
    );
  }

  static String _detail(BuildContext c, FoodEntry e) {
    if (e.isBareOccasion) {
      return AppLocalizations.of(c)?.logFoodBareOccasion ??
          'LOGGED · ENERGY NOT RECORDED';
    }
    final parts = <String>['${e.kcal!.round()} ${uiText(c, 'kcal')}'];
    if (e.proteinG != null) {
      parts.add(
        '${e.proteinG!.round()}${AppLocalizations.of(c)?.supplementProteinShort ?? 'P'}',
      );
    }
    if (e.carbsG != null) {
      parts.add(
        '${e.carbsG!.round()}${AppLocalizations.of(c)?.supplementCarbsShort ?? 'C'}',
      );
    }
    if (e.fatG != null) {
      parts.add(
        '${e.fatG!.round()}${AppLocalizations.of(c)?.supplementFatShort ?? 'F'}',
      );
    }
    return parts.join(' · ');
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.fields, this.hint = 'unknown'});
  final List<(String, String, TextEditingController)> fields;
  final String hint;

  @override
  Widget build(BuildContext c) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        Expanded(
          child: OsTextField(
            controller: fields[i].$3,
            label: '${fields[i].$1} (${uiText(c, fields[i].$2)})',
            hint: uiText(c, hint),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        if (i < fields.length - 1) const SizedBox(width: S.x3),
      ],
    ],
  );
}

/// Edge+: camera or gallery for the meal photo.
Future<ImageSource?> _askPhotoSource(BuildContext c) =>
    showModalBottomSheet<ImageSource>(
      context: c,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BigButton(tr(s, 'Foto aufnehmen', 'Take a photo'),
                  icon: LucideIcons.camera,
                  color: C.domFood,
                  onTap: () => Navigator.of(s).pop(ImageSource.camera)),
              const SizedBox(height: S.x3),
              BigButton(tr(s, 'Aus der Galerie', 'From the gallery'),
                  icon: LucideIcons.image,
                  color: C.domFood,
                  soft: true,
                  onTap: () => Navigator.of(s).pop(ImageSource.gallery)),
            ],
          ),
        ),
      ),
    );
