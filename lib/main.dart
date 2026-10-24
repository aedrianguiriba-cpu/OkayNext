import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/ableton_provider.dart';
import 'providers/midi_provider.dart';
import 'screens/home_screen.dart';
import 'services/ableton_service.dart';
import 'services/midi_service.dart';
import 'providers/key_bindings_provider.dart';
import 'providers/locator_groups_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        ChangeNotifierProvider(
          create: (_) => AbletonProvider(AbletonService()),
        ),
        ChangeNotifierProxyProvider<AbletonProvider, MidiProvider>(
          lazy: false, // must exist at startup to listen for MIDI input
          create: (ctx) =>
              MidiProvider(MidiService(), ctx.read<AbletonProvider>()),
          update: (_, ableton, prev) => prev!..updateAbleton(ableton),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, themeProvider, _) => MaterialApp(
          title: 'OkayNext',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.mode,
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
