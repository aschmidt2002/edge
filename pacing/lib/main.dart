import 'package:flutter/material.dart';

import 'state/pacing_state.dart';
import 'ui/common.dart';
import 'ui/history.dart';
import 'ui/home.dart';
import 'ui/meds.dart';
import 'ui/onboarding.dart';
import 'ui/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = PacingState();
  await state.load();
  runApp(AkkuApp(state: state));
}

class AkkuApp extends StatelessWidget {
  const AkkuApp({super.key, required this.state});
  final PacingState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'Akku',
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: ThemeMode.dark,
          home: const _Root(),
        ),
      );
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final st = AppScope.of(context);
    if (s == AppLifecycleState.resumed && st.settings.useHealthData) {
      st.refreshHealth();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    if (!st.settings.onboarded) return const OnboardingScreen();
    return Scaffold(
      body: IndexedStack(index: tab, children: const [
        HomeScreen(),
        HistoryScreen(),
        MedsScreen(),
        SettingsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.battery_5_bar), label: 'Heute'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Verlauf'),
          NavigationDestination(icon: Icon(Icons.medication_outlined), label: 'Medis'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Einstellungen'),
        ],
      ),
    );
  }
}
