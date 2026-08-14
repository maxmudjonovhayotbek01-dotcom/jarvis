import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/live_chat_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'services/app_update.dart';
import 'services/wake_word_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('uz_UZ', null);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const JarvisApp());
  // Native kanal tayyor bo'lgach "Hey Jarvis"ni ulaymiz.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final wake = WakeWordService.instance
      ..onWakeWord = _openWakeConversation;
    wake.init();
    _maybeStartWake();
  });
}

/// "Hey Jarvis" eshitilganda ovozli suhbatni ochadi.
void _openWakeConversation() {
  final nav = _navKey.currentState;
  if (nav == null) return;
  nav.popUntil((r) => r.isFirst);
  nav.push(
    MaterialPageRoute(
      builder: (_) => const LiveConversationScreen(onMessage: _wakeNoop),
    ),
  );
}

void _wakeNoop(String role, String text) {}

/// Foydalanuvchi yoqib qo'ygan bo'lsa, ilova ochilganda xizmatni avtomatik
/// ishga tushiradi.
Future<void> _maybeStartWake() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool('wake_word_enabled') ?? false;
  if (enabled) {
    await WakeWordService.instance.start();
  }
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: buildAppTheme(),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  static const _donePref = 'onboarding_done';

  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_donePref) ?? false;
    if (mounted) setState(() => _showOnboarding = !done);
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_donePref, true);
    if (mounted) setState(() => _showOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (_showOnboarding!) {
      return OnboardingScreen(onDone: _finishOnboarding);
    }
    return const _MainShell();
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Avtomatik yangilanish tekshiruvi (faqat yangi versiya bor bo'lsa ko'rsatadi)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) AppUpdate.checkAndPrompt(context, manual: false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          ChatScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Eslatmalar',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Suhbat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
