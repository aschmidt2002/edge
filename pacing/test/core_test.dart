import 'dart:io';

import 'package:akku/core/alerts.dart';
import 'package:akku/core/energy_model.dart';
import 'package:akku/core/envelope.dart';
import 'package:akku/core/hr_threshold.dart';
import 'package:akku/core/ideas.dart';
import 'package:akku/core/models.dart';
import 'package:akku/core/pem_lookback.dart';
import 'package:akku/data/store.dart';
import 'package:akku/sources/ble_heart_rate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const m = EnergyModel();

  group('minuteCost', () {
    double cost(double hr) =>
        m.minuteCost(hr: hr, resting: 60, ceiling: 80, envelope: 100);

    test('rest is free', () => expect(cost(62), 0));
    test('rises towards the ceiling', () {
      expect(cost(70), greaterThan(0));
      expect(cost(78), greaterThan(cost(70)));
    });
    test('over the ceiling costs a lot more than just under it', () {
      expect(cost(85), greaterThan(cost(79) * 3));
    });
    test('scales with the envelope', () {
      expect(
          m.minuteCost(hr: 85, resting: 60, ceiling: 80, envelope: 200),
          closeTo(cost(85) * 2, 1e-9));
    });
  });

  group('morningCharge', () {
    test('no evidence keeps a full battery', () {
      expect(m.morningCharge(), 1.0);
    });
    test('a bad check-in lowers it', () {
      final good = m.morningCharge(checkIn: CheckIn(day: 'd', feeling: 4));
      final bad = m.morningCharge(checkIn: CheckIn(day: 'd', feeling: 0));
      expect(good, 1.0);
      expect(bad, lessThan(0.5));
    });
    test('resting HR above baseline lowers it, HRV is ignored without baseline', () {
      final base = List.generate(7, (_) => const MorningVitals(restingHr: 60));
      final f = m.morningCharge(
          today: const MorningVitals(restingHr: 66, hrv: 10), baseline: base);
      expect(f, closeTo(1 - 0.15, 1e-9));
    });
    test('yesterday overspent carries a debt', () {
      final f = m.morningCharge(recentDays: [
        DaySummary(day: '2026-01-02', envelope: 100, startCharge: 100, used: 150),
      ]);
      expect(f, closeTo(0.75, 1e-9));
    });
    test('a crash caps the day', () {
      final f = m.morningCharge(
          checkIn: CheckIn(day: 'd', feeling: 4, crash: true, crashSeverity: 3));
      expect(f, lessThanOrEqualTo(0.3));
    });
  });

  group('threshold', () {
    test('resting + 15', () {
      expect(computeThreshold(PacingSettings(restingHr: 62)).ceiling, 77);
    });
    test('measured resting wins over the setting', () {
      expect(
          computeThreshold(PacingSettings(restingHr: 62), measuredRestingHr: 58)
              .ceiling,
          73);
    });
    test('age rule', () {
      expect(
          computeThreshold(PacingSettings(
                  age: 30, thresholdMode: ThresholdMode.agePercent))
              .ceiling,
          105);
    });
    test('no input, no ceiling', () {
      expect(computeThreshold(PacingSettings()).ceiling, isNull);
    });
    test('HR-lowering meds warn', () {
      expect(
          computeThreshold(PacingSettings(restingHr: 60), hrAffectingMeds: true)
              .warning,
          isNotNull);
    });
  });

  group('envelope', () {
    final today = DateTime(2026, 3, 20);
    List<DaySummary> days(double used) => [
          for (var n = 1; n <= 14; n++)
            DaySummary(
                day: dayKey(today.subtract(Duration(days: n))),
                envelope: 100,
                startCharge: 100,
                used: used),
        ];
    List<CheckIn> checks({bool crash = false}) => [
          for (var n = 1; n <= 14; n++)
            CheckIn(
                day: dayKey(today.subtract(Duration(days: n))),
                feeling: 3,
                crash: crash && n == 1,
                crashSeverity: 2),
        ];

    test('grows 5 % after 14 stable, well-used days', () {
      final d = adaptEnvelope(
          envelope: 100, days: days(80), checkIns: checks(), today: today);
      expect(d.newEnvelope, closeTo(105, 1e-9));
    });
    test('does not grow when the envelope was barely used', () {
      final d = adaptEnvelope(
          envelope: 100, days: days(40), checkIns: checks(), today: today);
      expect(d.changed, isFalse);
    });
    test('does not grow when days were overspent', () {
      final d = adaptEnvelope(
          envelope: 100, days: days(120), checkIns: checks(), today: today);
      expect(d.changed, isFalse);
    });
    test('shrinks right after a crash', () {
      final d = adaptEnvelope(
          envelope: 100,
          days: days(80),
          checkIns: checks(crash: true),
          today: today);
      expect(d.newEnvelope, closeTo(85, 1e-9));
    });
    test('the same crash is applied once', () {
      final d = adaptEnvelope(
          envelope: 85,
          days: days(80),
          checkIns: checks(crash: true),
          today: today,
          lastChange: dayKey(today));
      expect(d.changed, isFalse);
    });
    test('no growth without enough check-ins', () {
      final d = adaptEnvelope(
          envelope: 100, days: days(80), checkIns: [], today: today);
      expect(d.changed, isFalse);
    });
  });

  group('alerts', () {
    final noon = DateTime(2026, 3, 20, 12);
    test('over the ceiling fires once, re-arms after a clear drop', () {
      final p = AlertPolicy();
      AlertEvent? at(double hr, int secs, int minute) => p.evaluate(AlertInput(
          now: noon.add(Duration(minutes: minute)),
          batteryShare: 0.8,
          hr: hr,
          ceiling: 80,
          secondsOverCeiling: secs));
      expect(at(85, 10, 0), isNull);
      expect(at(85, 40, 0)?.level, AlertLevel.stop);
      expect(at(86, 60, 1), isNull);
      expect(at(70, 0, 2), isNull); // clears
      expect(at(85, 40, 3)?.level, AlertLevel.stop);
    });
    test('quiet hours mute the battery warning but not the ceiling', () {
      final p = AlertPolicy();
      final night = DateTime(2026, 3, 20, 23);
      expect(
          p.evaluate(AlertInput(now: night, batteryShare: 0.1)), isNull);
      expect(
          p
              .evaluate(AlertInput(
                  now: night,
                  batteryShare: 0.1,
                  hr: 90,
                  ceiling: 80,
                  secondsOverCeiling: 60))
              ?.level,
          AlertLevel.stop);
    });
    test('battery warning fires once', () {
      final p = AlertPolicy();
      expect(p.evaluate(AlertInput(now: noon, batteryShare: 0.18))?.level,
          AlertLevel.warn);
      expect(
          p.evaluate(AlertInput(
              now: noon.add(const Duration(hours: 1)), batteryShare: 0.17)),
          isNull);
    });
  });

  test('crash look-back lists the days before, biggest first', () {
    final logs = [
      ActivityLog(
          id: '1',
          start: DateTime(2026, 3, 18, 10),
          minutes: 60,
          kind: EffortKind.emotional,
          intensity: 3,
          label: 'Arzttermin'),
      ActivityLog(
          id: '2',
          start: DateTime(2026, 3, 19, 10),
          minutes: 10,
          kind: EffortKind.cognitive,
          intensity: 1,
          label: 'Telefonat'),
      ActivityLog(
          id: '3',
          start: DateTime(2026, 3, 10, 10),
          minutes: 120,
          kind: EffortKind.physical,
          intensity: 3,
          label: 'zu früh'),
    ];
    final r = crashLookback(
        crashDay: '2026-03-20',
        days: const [],
        logs: logs,
        costOf: (l) => m.logCost(l, envelope: 100));
    expect(r.map((e) => e.label), ['Arzttermin', 'Telefonat']);
  });

  test('ideas shrink to rest when the battery is low or in a crash', () {
    expect(ideasFor(Severity.mild, 0.1).every((i) => i.cost == 0), isTrue);
    expect(ideasFor(Severity.mild, 0.9, inCrash: true).every((i) => i.cost == 0),
        isTrue);
    expect(ideasFor(Severity.verySevere, 0.9).any((i) => i.id == 'walk_short'),
        isFalse);
    expect(ideasFor(Severity.mild, 0.9).any((i) => i.id == 'walk_short'),
        isTrue);
  });

  test('heart rate packet parsing', () {
    expect(parseHeartRate([0x00, 72]), 72);
    expect(parseHeartRate([0x01, 0x2C, 0x01]), 300);
    expect(parseHeartRate([0x01, 0x2C]), isNull);
    expect(parseHeartRate([]), isNull);
  });

  test('store round-trips', () async {
    final dir = await Directory.systemTemp.createTemp('akku');
    final s = PacingStore(File('${dir.path}/p.json'));
    final d = PacingData()
      ..checkIns.add(CheckIn(day: '2026-03-20', feeling: 2, crash: true))
      ..meds.add(Medication(id: 'a', name: 'Test', affectsHeartRate: true))
      ..vitals['2026-03-20'] = const MorningVitals(restingHr: 61);
    d.settings.envelope = 120;
    await s.save(d);
    final back = await s.load();
    expect(back.settings.envelope, 120);
    expect(back.checkIns.single.crash, isTrue);
    expect(back.meds.single.affectsHeartRate, isTrue);
    expect(back.vitals['2026-03-20']!.restingHr, 61);
  });
}
