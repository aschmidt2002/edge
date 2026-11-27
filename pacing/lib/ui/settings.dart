import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../sources/ble_heart_rate.dart';
import 'common.dart';

const kSeverityNames = {
  Severity.mild: 'leicht',
  Severity.moderate: 'mittel',
  Severity.severe: 'schwer',
  Severity.verySevere: 'sehr schwer',
};

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final s = st.settings;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle('Schweregrad (selbst eingeschätzt)'),
          SegmentedButton<Severity>(
            segments: [
              for (final v in Severity.values)
                ButtonSegment(value: v, label: Text(kSeverityNames[v]!)),
            ],
            selected: {s.severity},
            onSelectionChanged: (v) =>
                st.updateSettings((x) => x.severity = v.first),
          ),
          Text('Bestimmt nur, welche Ideen angezeigt werden.', style: t.bodySmall),
          const SectionTitle('Pulsgrenze'),
          RadioGroup<ThresholdMode>(
            groupValue: s.thresholdMode,
            onChanged: (v) => st.updateSettings((x) => x.thresholdMode = v!),
            child: const Column(children: [
              RadioListTile(
                value: ThresholdMode.restingPlus15,
                title: Text('Ruhepuls + 15'),
                subtitle: Text('Faustregel. Ruhepuls kommt aus Apple Health / Health Connect oder von dir.'),
              ),
              RadioListTile(
                value: ThresholdMode.agePercent,
                title: Text('55 % von (220 − Alter)'),
                subtitle: Text('Vorsichtigere Faustregel über das Alter.'),
              ),
              RadioListTile(
                value: ThresholdMode.manual,
                title: Text('Eigener Wert'),
                subtitle: Text('Z. B. aus einem 2-Tages-CPET oder mit Ärztin/Arzt festgelegt.'),
              ),
            ]),
          ),
          _NumberTile(
            label: 'Ruhepuls (falls nicht gemessen)',
            value: s.restingHr?.round(),
            onChanged: (v) =>
                st.updateSettings((x) => x.restingHr = v?.toDouble()),
          ),
          _NumberTile(
            label: 'Alter',
            value: s.age,
            onChanged: (v) => st.updateSettings((x) => x.age = v),
          ),
          if (s.thresholdMode == ThresholdMode.manual)
            _NumberTile(
              label: 'Pulsgrenze (bpm)',
              value: s.manualThreshold,
              onChanged: (v) => st.updateSettings((x) => x.manualThreshold = v),
            ),
          Text('Aktuelle Grenze: ${st.threshold.ceiling ?? '—'}', style: t.bodyLarge),
          const SectionTitle('Energie-Rahmen'),
          _NumberTile(
            label: 'Rahmen in Punkten',
            value: s.envelope.round(),
            onChanged: (v) {
              if (v != null && v >= 30 && v <= 300) {
                st.updateSettings((x) => x.envelope = v.toDouble());
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rahmen automatisch anpassen'),
            subtitle: const Text(
                'Wächst nur nach 14 stabilen Tagen ohne Crash um 5 %, schrumpft nach einem Crash sofort.'),
            value: s.autoAdaptEnvelope,
            onChanged: (v) => st.updateSettings((x) => x.autoAdaptEnvelope = v),
          ),
          const SectionTitle('Vibration'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Warnungen mit Vibration'),
            value: s.vibrationAlerts,
            onChanged: (v) async {
              st.updateSettings((x) => x.vibrationAlerts = v);
              if (v) await st.alerter.requestPermission();
            },
          ),
          _NumberTile(
            label: 'Warnen ab Akku-Stand (%)',
            value: s.alertAtBatteryPercent,
            onChanged: (v) {
              if (v != null && v >= 5 && v <= 60) {
                st.updateSettings((x) => x.alertAtBatteryPercent = v);
              }
            },
          ),
          Text(
              'Ruhezeit ${s.quietHoursStart}–${s.quietHoursEnd} Uhr: nur die Warnung "über der Grenze" kommt dann durch.',
              style: t.bodySmall),
          const SectionTitle('Datenquellen'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bluetooth),
            title: Text(s.hrDeviceName ?? 'Pulssensor verbinden'),
            subtitle: Text(s.hrDeviceId == null
                ? 'WHOOP (mit "Herzfrequenz übertragen"), Polar, Brustgurt …'
                : st.sensorConnected
                    ? 'verbunden'
                    : 'getrennt – verbindet sich automatisch'),
            trailing: s.hrDeviceId == null
                ? const Icon(Icons.chevron_right)
                : TextButton(
                    onPressed: st.forgetSensor, child: const Text('Trennen')),
            onTap: s.hrDeviceId == null
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PairSensorScreen()))
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Apple Health / Health Connect'),
            subtitle: const Text('Ruhepuls, HRV, Schlaf und Schritte lesen (nur lesen).'),
            value: s.useHealthData,
            onChanged: (v) async {
              if (v && !await st.health.requestAccess()) return;
              st.updateSettings((x) => x.useHealthData = v);
              if (v) await st.refreshHealth();
            },
          ),
          const SectionTitle('Daten'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.copy),
            title: const Text('Alle Daten als JSON kopieren'),
            subtitle: const Text('Alles liegt nur auf diesem Gerät.'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: st.exportJson()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('In die Zwischenablage kopiert')));
              }
            },
          ),
          const SizedBox(height: 16),
          Text(kDisclaimer, style: t.bodySmall),
        ],
      ),
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.label, required this.value, required this.onChanged});
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        trailing: Text(value?.toString() ?? '—',
            style: Theme.of(context).textTheme.titleMedium),
        onTap: () async {
          final c = TextEditingController(text: value?.toString());
          final r = await showDialog<String>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(label),
              content: TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d, ''),
                    child: const Text('Leeren')),
                FilledButton(
                    onPressed: () => Navigator.pop(d, c.text),
                    child: const Text('OK')),
              ],
            ),
          );
          if (r == null) return;
          onChanged(int.tryParse(r.trim()));
        },
      );
}

class PairSensorScreen extends StatefulWidget {
  const PairSensorScreen({super.key});
  @override
  State<PairSensorScreen> createState() => _PairSensorScreenState();
}

class _PairSensorScreenState extends State<PairSensorScreen> {
  StreamSubscription<List<FoundSensor>>? _sub;
  List<FoundSensor> found = [];
  bool scanning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) _scan();
  }

  void _scan() {
    final st = AppScope.of(context);
    _sub?.cancel();
    setState(() => scanning = true);
    _sub = st.ble.scan().listen((r) => setState(() => found = r));
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => scanning = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pulssensor')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              'WHOOP: In der WHOOP-App "Herzfrequenz übertragen" (Heart Rate Broadcast) einschalten. '
              'Polar & Brustgurte: einfach anlegen.'),
          const SizedBox(height: 12),
          if (scanning) const LinearProgressIndicator(),
          for (final f in found)
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text(f.name),
              subtitle: Text('Signal ${f.rssi} dBm'),
              onTap: () async {
                await st.ble.stopScan();
                await st.pairSensor(f.id, f.name);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          if (!scanning)
            TextButton(onPressed: _scan, child: const Text('Erneut suchen')),
        ],
      ),
    );
  }
}
