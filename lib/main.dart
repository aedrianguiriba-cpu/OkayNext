import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ableton_provider.dart';
import 'providers/midi_provider.dart';
import 'screens/home_screen.dart';
import 'screens/monitor_screen.dart';
import 'services/ableton_service.dart';
import 'services/midi_service.dart';
import 'services/monitor_server.dart';
import 'providers/key_bindings_provider.dart';
import 'providers/locator_groups_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop app: start the built-in phone monitor (a no-op in the browser).
  MonitorServer.instance.init();
  runApp(const SetlistManagerApp());
}

class SetlistManagerApp extends StatelessWidget {
  const SetlistManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => KeyBindingsProvider()),
        ChangeNotifierProvider(create: (_) => LocatorGroupsProvider()),
        // In a browser the app is a read-only monitor: it never sends
        // commands to Ableton.
        ChangeNotifierProvider(
          create: (_) => AbletonProvider(AbletonService(readOnly: kIsWeb)),
        ),
        // MIDI (and its permission prompts) only on the real app.
        if (!kIsWeb)
          ChangeNotifierProxyProvider2<AbletonProvider, LocatorGroupsProvider,
              MidiProvider>(
            lazy: false, // must exist at startup to listen for MIDI input
            create: (ctx) => MidiProvider(
              MidiService(),
              ctx.read<AbletonProvider>(),
              ctx.read<LocatorGroupsProvider>(),
            ),
            update: (_, ableton, groups, prev) =>
                prev!..updateAbleton(ableton)..updateGroups(groups),
          ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProvider, _) => MaterialApp(
          title: 'OkayNext',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.mode,
          home: kIsWeb ? const MonitorScreen() : const HomeScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
