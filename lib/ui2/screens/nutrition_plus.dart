// Edge+: target weight with a forecast date, and a daily creatine check-off.
//
// Kept in its own file so the upstream nutrition screen only carries a few
// hook lines (the fork merges upstream daily). Copy is German on purpose:
// these are fork-only features with no strings in the upstream ARB files.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/profile.dart' show plausibleWeightKg;
import '../../data/day_label.dart';
import '../../data/nutrition_store.dart';
import '../../notify/notification_event.dart' show NotifCategory;
import '../../notify/notification_prefs.dart';
import '../../notify/notification_service.dart';
import '../../notify/tap_router.dart' show kRouteWater;
import '../../state/app_state.dart';
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;

// ══════════════════ WEIGHT GOAL: PURE MATH ══════════════════

/// Energy in one kilogram of body weight. The textbook ~7,700 kcal rule: a
/// rough average of fat and lean tissue, good for a date, not for a promise.
const double kKcalPerKg = 7700;

/// Forecasts further out than this read as "not in sight".
const int kMaxForecastDays = 3650;

/// Where the daily balance behind a forecast came from.
enum BalanceSource {
  /// Eaten (food log) minus burned (band), over the same complete days.
  logged,

  /// The typed daily energy target minus the average burned per whole day.
  target,
}

class WeightForecast {
  const WeightForecast(this.balance, this.days, this.source);

  /// kcal per day; negative is a deficit.
  final double balance;

  /// Days the balance is averaged over.
  final int days;
  final BalanceSource source;
}

/// The daily balance a forecast can stand on, or null when there is none.
/// Logged intake wins; with no complete logged day the typed kcal target
/// stands in for "what I eat", against the band's whole-day burn.
WeightForecast? weightBalance({
  required NutritionWindow? week,
  required Map<String, double> burnedByDate,
  required Map<String, double> wornMinByDate,
  required double? kcalTarget,
  required String today,
}) {
  if (week != null) {
    final b = weeklyEnergyBalance(week, burnedByDate, wornMinByDate);
    if (b != null) return WeightForecast(b.balance, b.days, BalanceSource.logged);
  }
  if (kcalTarget == null || kcalTarget <= 0) return null;
  final burns = [
    for (final e in burnedByDate.entries)
      if (e.key != today && (wornMinByDate[e.key] ?? 0) >= kWholeDayWornMin)
        e.value,
  ];
  if (burns.isEmpty) return null;
  final burned = burns.reduce((a, b) => a + b) / burns.length;
  return WeightForecast(kcalTarget - burned, burns.length, BalanceSource.target);
}

/// The day [target] kg is reached from [current] kg at [balance] kcal/day.
/// Null when the balance points the wrong way, is zero, or the date is
/// further out than [kMaxForecastDays].
DateTime? weightReachDate({
  required double current,
  required double target,
  required double balance,
  required DateTime today,
}) {
  final delta = target - current;
  final day = DateTime(today.year, today.month, today.day);
  if (delta.abs() < 0.05) return day;
  final kgPerDay = balance / kKcalPerKg;
  if (kgPerDay == 0 || kgPerDay.sign != delta.sign) return null;
  final days = (delta / kgPerDay).ceil();
  if (days > kMaxForecastDays) return null;
  // Calendar days, not 24 h steps: DST-safe.
  return DateTime(day.year, day.month, day.day + days);
}

/// The kcal/day balance needed to go from [current] to [target] by [by].
/// Null when [by] is not after [today].
double? balanceNeededBy({
  required double current,
  required double target,
  required DateTime today,
  required DateTime by,
}) {
  final from = DateTime.utc(today.year, today.month, today.day);
  final to = DateTime.utc(by.year, by.month, by.day);
  final days = to.difference(from).inDays;
  if (days <= 0) return null;
  return (target - current) * kKcalPerKg / days;
}

const _months = [
  'Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni',
  'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.',
];
String _date(DateTime d) => '${d.day}. ${_months[d.month - 1]} ${d.year}';
String _kg(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} kg';
String _kcal(double v) =>
    '${v >= 0 ? '+' : '−'}${v.abs().round()} kcal/Tag';

// ══════════════════ WEIGHT GOAL: UI ══════════════════

/// The "Zielgewicht" section on the Goals tab.
class WeightGoalSection extends StatelessWidget {
  const WeightGoalSection({
    super.key,
    required this.profile,
    required this.forecast,
    required this.onEdit,
  });

  final Map<String, dynamic> profile;
  final WeightForecast? forecast;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final current = (profile['weight_kg'] as num?)?.toDouble();
    final target = (profile['weight_target_kg'] as num?)?.toDouble();
    final start =
        (profile['weight_target_start_kg'] as num?)?.toDouble() ?? current;
    final wish = DateTime.tryParse(profile['weight_target_date'] as String? ?? '');
    if (target == null) {
      return StatusCard(
        'Kein Zielgewicht',
        'Gib dein Wunschgewicht ein. Edge+ rechnet aus deinem Grundumsatz, '
            'deiner Aktivität und dem, was du isst, aus, wann du es erreichst.',
        fix: 'Zielgewicht setzen',
        icon: LucideIcons.scale,
        onFix: onEdit,
      );
    }
    if (current == null) {
      return StatusCard(
        'Aktuelles Gewicht fehlt',
        'Ohne dein aktuelles Gewicht gibt es keine Prognose.',
        fix: 'Gewicht eintragen',
        icon: LucideIcons.scale,
        onFix: onEdit,
      );
    }
    final today = DateTime.now();
    final f = forecast;
    final reach = f == null
        ? null
        : weightReachDate(
            current: current, target: target, balance: f.balance, today: today);
    final String rate;
    if ((target - current).abs() < 0.05) {
      rate = 'Ziel erreicht';
    } else if (f == null) {
      rate = 'Noch keine Prognose möglich';
    } else if (reach == null) {
      rate = 'Mit deinem aktuellen Verhalten nicht in Sicht';
    } else {
      rate = 'Prognose: ${_date(reach)}';
    }
    final total = (start ?? current) - target;
    final frac = total.abs() < 0.05
        ? 1.0
        : (((start ?? current) - current) / total).clamp(0, 1).toDouble();

    final needed = wish == null
        ? null
        : balanceNeededBy(
            current: current, target: target, today: today, by: wish);
    final lines = <String>[
      if (f == null)
        'Für eine Prognose brauche ich entweder vollständig geloggte Tage '
            '(Essen + Band ganztägig getragen) oder ein Tagesenergie-Ziel '
            'oben bei "Deine Ziele".'
      else
        'Bilanz: ${_kcal(f.balance)}, ${f.source == BalanceSource.logged ? 'gegessen minus verbraucht' : 'dein Kalorienziel minus Verbrauch'} '
            '(Ø ${f.days} ${f.days == 1 ? 'Tag' : 'Tage'}). Verbrauch = Grundumsatz + Aktivität vom Band.',
      if (wish != null)
        needed == null
            ? 'Dein Wunschdatum (${_date(wish)}) ist schon vorbei.'
            : 'Für dein Wunschdatum ${_date(wish)} bräuchtest du ${_kcal(needed)}'
                '${f == null ? '' : ' (${reach != null && !reach.isAfter(wish) ? 'du liegst im Plan' : 'aktuell ${_kcal(f.balance)}'})'}.',
      'Faustregel: 7.700 kcal ≈ 1 kg. Eine Schätzung, keine Garantie.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoalTrajectory(
          'Zielgewicht',
          _kg(current),
          _kg(target),
          rate,
          frac,
          C.teal,
          rateDown: target < current,
        ),
        const SizedBox(height: S.x3),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in lines) ...[
                Text(s, style: F.cap.copyWith(color: p.ink2, height: 1.45)),
                if (s != lines.last) const SizedBox(height: S.x2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Edit current weight, target weight and an optional wish date. Returns
/// true when something was saved.
Future<bool> editWeightGoal(BuildContext context) async {
  final app = context.read<AppState>();
  final prof = {...?app.user};
  String fmt(Object? v) => v is num ? v.toStringAsFixed(1) : '';
  final currentCtl = TextEditingController(text: fmt(prof['weight_kg']));
  final targetCtl = TextEditingController(text: fmt(prof['weight_target_kg']));
  DateTime? wish =
      DateTime.tryParse(prof['weight_target_date'] as String? ?? '');
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(context),
    backgroundColor: P.of(context).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (s) => StatefulBuilder(builder: (s, set) {
      final p = P.of(s);
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
            Text('Zielgewicht', style: F.head.copyWith(color: p.ink)),
            const SizedBox(height: S.x4),
            OsTextField(
              controller: currentCtl,
              label: 'Aktuelles Gewicht (kg)',
              hint: 'z. B. 82,5',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: S.x3),
            OsTextField(
              controller: targetCtl,
              label: 'Wunschgewicht (kg)',
              hint: 'leer = kein Ziel',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: S.x3),
            Pressable(
              semanticLabel: 'Wunschdatum wählen',
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: s,
                  initialDate: wish ?? DateTime(now.year, now.month + 3, now.day),
                  firstDate: DateTime(now.year, now.month, now.day + 1),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) set(() => wish = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(S.x3),
                decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
                child: Row(children: [
                  Icon(LucideIcons.calendar, size: 18, color: p.ink2),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      wish == null
                          ? 'Wunschdatum (optional)'
                          : 'Wunschdatum: ${_date(wish!)}',
                      style: F.body.copyWith(color: p.ink),
                    ),
                  ),
                  if (wish != null)
                    Pressable(
                      semanticLabel: 'Wunschdatum entfernen',
                      onTap: () => set(() => wish = null),
                      child: Icon(LucideIcons.x, size: 18, color: p.ink3),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: S.x5),
            BigButton('Speichern',
                color: C.teal, onTap: () => Navigator.of(s).pop(true)),
          ],
        ),
      );
    }),
  );
  final current = Typed.of(currentCtl.text);
  final target = Typed.of(targetCtl.text);
  currentCtl.dispose();
  targetCtl.dispose();
  if (saved != true || !context.mounted) return false;
  final bad = [
    if (current.bad || (current.value != null && !plausibleWeightKg(current.value!)))
      'Aktuelles Gewicht',
    if (target.bad || (target.value != null && !plausibleWeightKg(target.value!)))
      'Wunschgewicht',
  ];
  if (bad.isNotEmpty) {
    sayUnreadable(context, bad);
    return false;
  }
  final now = current.value ?? (prof['weight_kg'] as num?)?.toDouble();
  final changedTarget = target.value != prof['weight_target_kg'];
  await app.updateProfile({
    // Blank leaves the profile weight alone: it feeds BMR and calories.
    if (current.value != null) 'weight_kg': current.value,
    'weight_target_kg': target.value,
    'weight_target_date': target.value == null || wish == null
        ? null
        : dayLabelOf(wish!),
    // The start of the progress bar: where you stood when the goal was set.
    if (changedTarget) 'weight_target_start_kg': target.value == null ? null : now,
  });
  return true;
}

// ══════════════════ CREATINE ══════════════════

/// Fixed scheduled-notification id for the 22:00 creatine reminder.
const int kCreatineReminderId = NotificationService.idCreatine;

bool creatineTakenToday(Map<String, dynamic> profile) =>
    profile['creatine_day'] == todayLabel();

/// Whether creatine tracking was ever used (only then is a reminder armed).
bool creatineInUse(Map<String, dynamic> profile) =>
    profile.containsKey('creatine_day');

/// Arm the daily 22:00 reminder, skipping tonight when today is ticked off.
/// A daily repeat: it keeps firing on days nobody opens the app, which are
/// exactly the days it is not ticked.
Future<void> armCreatineReminder({
  required bool takenToday,
  bool prompt = false,
}) async {
  final svc = NotificationService.instance;
  try {
    final prefs = await NotificationPrefs.load();
    if (!prefs.remindersEnabled) {
      await svc.cancel(kCreatineReminderId);
      return;
    }
    if (prompt) await svc.ensurePermission();
    await svc.scheduleDaily(
      id: kCreatineReminderId,
      category: NotifCategory.reminders,
      title: 'Creatin',
      body: 'Du hast heute noch kein Creatin abgehakt.',
      hour: 22,
      minute: 0,
      route: kRouteWater,
      skipToday: takenToday,
    );
  } catch (_) {}
}

/// Re-arm once per app run, so a reminder lost to a reset or a revoked and
/// re-granted permission comes back without a tap.
bool _creatineArmedThisRun = false;
void ensureCreatineReminder(Map<String, dynamic> profile) {
  if (_creatineArmedThisRun || !creatineInUse(profile)) return;
  _creatineArmedThisRun = true;
  armCreatineReminder(takenToday: creatineTakenToday(profile));
}

/// Tick or untick today's creatine and re-arm tonight's reminder.
Future<void> setCreatineTaken(BuildContext context, bool taken) async {
  final app = context.read<AppState>();
  await app.updateProfile({'creatine_day': taken ? todayLabel() : ''});
  await armCreatineReminder(takenToday: taken, prompt: true);
}

/// The creatine row under water: one tap ticks it off for today.
class CreatineRow extends StatelessWidget {
  const CreatineRow({super.key, required this.taken, this.onTap});
  final bool taken;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: taken ? 'Creatin genommen' : 'Creatin abhaken',
      child: Surface(
        child: Row(children: [
          Icon(LucideIcons.pill, size: 18, color: p.on(C.purple)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Creatin', style: F.body.copyWith(color: p.ink)),
              Text(
                taken ? 'Heute genommen' : 'Erinnerung um 22 Uhr, falls offen',
                style: F.over.copyWith(color: p.ink3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Container(
            width: S.tap,
            height: S.tap,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: taken ? p.wash(C.green) : p.card2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              taken ? LucideIcons.check : LucideIcons.circle,
              size: 20,
              color: taken ? p.on(C.green) : p.ink3,
            ),
          ),
        ]),
      ),
    );
  }
}
