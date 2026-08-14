import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_update.dart';
import '../services/notification_service.dart';
import '../services/tts_service.dart';
import '../services/wake_word_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _wakePref = 'wake_word_enabled';

  bool _wakeEnabled = false;
  String _version = '1.0.0';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await TtsService.instance.init();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_wakePref) ?? false;
    if (mounted) setState(() => _wakeEnabled = enabled);
    final version = await AppUpdate.currentVersion();
    if (mounted) setState(() => _version = version);
  }

  Future<void> _toggleWake(bool value) async {
    setState(() => _wakeEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wakePref, value);
    if (value) {
      await WakeWordService.instance.start();
      await WakeWordService.instance.requestIgnoreBatteryOptimizations();
    } else {
      await WakeWordService.instance.stop();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? '"Hey Jarvis" yoqildi' : '"Hey Jarvis" o\'chirildi')),
    );
  }

  void _comingSoon() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu sozlama tez orada qo\'shiladi')),
    );
  }

  Future<void> _testVoice() async {
    await TtsService.instance.speak('Salom! Men Jarvis yordamchisiman.');
  }

  Future<void> _enableNotifications() async {
    await NotificationService.instance.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bildirishnomalar yoqilgan')),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Jarvis',
      applicationVersion: _version,
      applicationIcon: const Icon(Icons.eco, color: AppColors.primary, size: 40),
      children: const [
        SizedBox(height: 8),
        Text('Ovoz. Eslatma. AI. Siz bilan.'),
        SizedBox(height: 4),
        Text('Sizning shaxsiy ovozli AI yordamchingiz.'),
      ],
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yordam'),
        content: const Text(
          'Qanday ishlaydi?\n\n'
          '• "Eslatmalar" bo\'limida mikrofonni bosing va gapiring: '
          'masalan "ertaga soat 10 da shifokorga boraman".\n\n'
          '• "Suhbat" bo\'limida Gemini AI dan istalgan savolga javob oling.\n\n'
          '• Eslatmalar vaqtida bildirishnoma bilan eslatiladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Yangilanish tekshirilmoqda...')),
    );
    await AppUpdate.checkAndPrompt(context, manual: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(
              'Sozlamalar va ma\'lumotlar',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [AppShadows.card],
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.mint, AppColors.pistachio],
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Foydalanuvchi',
                            style: theme.textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          'Foydalanuvchi',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _WakeTile(
              enabled: _wakeEnabled,
              onChanged: _toggleWake,
            ),
            const SizedBox(height: 12),
            _SettingTile(
              icon: Icons.volume_up_outlined,
              title: 'Ovoz sozlamalari',
              subtitle: 'TTS va ovoz',
              onTap: _testVoice,
            ),
            _SettingTile(
              icon: Icons.notifications_outlined,
              title: 'Bildirishnomalar',
              subtitle: 'Eslatmalar va ogohlantirishlar',
              onTap: _enableNotifications,
            ),
            _SettingTile(
              icon: Icons.palette_outlined,
              title: 'Tema',
              subtitle: 'Yashil (pista)',
              onTap: _comingSoon,
            ),
            _SettingTile(
              icon: Icons.language_outlined,
              title: 'Til',
              subtitle: 'O\'zbekcha',
              onTap: _comingSoon,
            ),
            _SettingTile(
              icon: Icons.help_outline,
              title: 'Yordam',
              subtitle: 'Savollar va qo\'llab-quvvatlash',
              onTap: _showHelp,
            ),
            _SettingTile(
              icon: Icons.system_update_alt_outlined,
              title: 'Yangilanish',
              subtitle: 'Yangi versiyani tekshirish (avtomatik)',
              onTap: _checkUpdate,
            ),
            _SettingTile(
              icon: Icons.info_outline,
              title: 'Ilova haqida',
              subtitle: 'Versiya $_version',
              onTap: _showAbout,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [AppShadows.card],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WakeTile extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _WakeTile({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [AppShadows.card],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hearing, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hey Jarvis', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  enabled
                      ? 'Doimiy eshityapman. Ekran o\'chiq bo\'lsa ham'
                      : 'Ilova yopiq bo\'lsa ham eshitish',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
