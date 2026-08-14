import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Avtomatik yangilanish (auto-update) xizmati.
///
/// Yangi versiyani GitHub Releases'dan tekshiradi, topilsa yuklab olib
/// Android o'rnatuvchisi orqali o'rnatadi. USB sim kerak emas.
///
/// ## Yangi versiya chiqarish:
/// 1. `pubspec.yaml` da versiyani oshiring (masalan `1.2.0+3`).
/// 2. `flutter build apk --release` bilan APK quring.
/// 3. GitHub'da Release yarating:
///    - Tag: `v1.2.0+3`  (versiya + build raqami; build har doim o'ssin)
///    - Fayl biriktiriladi: `yordamchi.apk` (qurilgan APK)
/// 4. Foydalanuvchilar app'ni ochganda avtomatik tekshiriladi.
///
/// Repo yopiq (private) bo'lsa ham ishlaydi, chunki GitHub API orqali
/// faqat Release ma'lumoti olinadi (60 soatiga so'rov chegarasi bor).
class AppUpdate {
  AppUpdate._();

  /// GitHub repo nomi (Release'lar shu yerdan olinadi).
  ///
  /// Yangi versiya chiqarganda GitHub'da Release yarating — tag `v1.2.0+3`
  /// ko'rinishida va `yordamchi.apk` faylini biriktiring.
  ///
  /// Agar GitHub o'rniga o'z serveringizdan foydalansangiz, bu yerga
  /// to'liq URL yozing (masalan `'https://misol.com/yordamchi'`) — u holda
  /// manifest `{base}/releases/latest` manzilidan olinadi.
  static const githubRepo = 'maxmudjonovhayotbek01-dotcom/jarvis';

  /// Yangilanish manifestining manzili.
  static final Uri _manifestUri = Uri.parse(
    githubRepo.startsWith('http')
        ? '$githubRepo/releases/latest'
        : 'https://api.github.com/repos/$githubRepo/releases/latest',
  );

  /// Yuklab olinadigan va o'rnatiladigan APK fayl nomi.
  static const _assetName = 'yordamchi.apk';

  static const _channel = MethodChannel('yordamchi/wake_word');

  /// Hozirgi o'rnatilgan versiya haqida ma'lumot.
  static Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '1.0.0';
    }
  }

  /// GitHub'dagi eng oxirgi versiyani tekshiradi.
  ///
  /// Yangi versiya bor bo'lsa [UpdateInfo] qaytaradi, aks holda `null`.
  /// Xato yoki internet yo'q bo'lsa ham `null` qaytadi (og'ishsiz).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final res = await http
          .get(_manifestUri, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      final parsed = _parseVersion(tag);
      if (parsed == null) return null;

      final assets = (json['assets'] as List?) ?? const [];
      Map<String, dynamic>? apkAsset;
      for (final asset in assets) {
        final m = asset as Map<String, dynamic>;
        final name = (m['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkAsset = m;
          break;
        }
      }
      if (apkAsset == null) return null;
      final url = (apkAsset['browser_download_url'] as String?) ?? '';
      if (url.isEmpty) return null;

      final current = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(current.buildNumber) ?? 0;
      if (parsed.versionCode <= currentCode) return null;

      return UpdateInfo(
        versionName: parsed.versionName,
        versionCode: parsed.versionCode,
        url: url,
        notes: (json['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Yangilanishni tekshiradi va topilsa foydalanuvchiga ko'rsatadi.
  ///
  /// [manual] `true` bo'lsa — xato yoki yangilanish bo'lmaganda ham
  /// SnackBar orqali habar beriladi (Profil tugmasi uchun).
  static Future<void> checkAndPrompt(BuildContext context,
      {bool manual = false}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    UpdateInfo? info;
    try {
      info = await checkForUpdate();
    } catch (_) {}
    if (!context.mounted) return;

    if (info == null) {
      if (manual && messenger != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Siz eng yangi versiyada turibsiz')),
        );
      }
      return;
    }
    final update = info;

    final proceed = await _confirmUpdate(context, update);
    if (proceed != true || !context.mounted) return;

    // Android 8+ da "noma'lum manbalardan o'rnatish" ruxsati kerak.
    final canInstall = await _canRequestInstalls();
    if (!canInstall) {
      if (!context.mounted) return;
      final go = await _askInstallPermission(context);
      if (go == true) {
        await _openInstallSettings();
      }
      return;
    }

    if (!context.mounted) return;
    final path = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(info: update),
    );

    if (path == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yuklab olishda xatolik yuz berdi')),
        );
      }
      return;
    }

    final installed = await _installApk(path);
    if (!installed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O\'rnatuvchini ochib bo\'lmadi. Qo\'lda sinab ko\'ring'),
        ),
      );
    }
  }

  static Future<bool> _confirmUpdate(
      BuildContext context, UpdateInfo info) async {
    final notes = info.notes.trim();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Yangi versiya bor!'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Jarvis ${info.versionName} chiqdi',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(notes),
                  ],
                  const SizedBox(height: 12),
                  const Text('Yuklab olish va o\'rnatish?'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keyinroq'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yangilash'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<bool> _askInstallPermission(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ruxsat kerak'),
            content: const Text(
              'Yangi versiyani o\'rnatish uchun ilovaga '
              '"noma\'lum manbalardan o\'rnatish" ruxsatini bering.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Bekor'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Ruxsat berish'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<bool> _canRequestInstalls() async {
    try {
      return await _channel
              .invokeMethod<bool>('canRequestInstalls') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _openInstallSettings() async {
    try {
      await _channel.invokeMethod('openInstallSettings');
    } catch (_) {}
  }

  static Future<bool> _installApk(String path) async {
    try {
      return await _channel
              .invokeMethod<bool>('installApk', {'path': path}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// APK'ni streaming yuklab oladi. [onProgress] 0.0..1.0 oralig'ida.
  static Future<File> downloadApk(
    String url,
    String directory, {
    required void Function(double) onProgress,
  }) async {
    final streamed = await http.Client()
        .send(http.Request('GET', Uri.parse(url)));
    if (streamed.statusCode != 200) {
      throw Exception('HTTP ${streamed.statusCode}');
    }
    final total = streamed.contentLength ?? -1;
    final file = File('$directory/$_assetName');
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(received / total);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    }
    if (total > 0 && received != total) {
      throw Exception('Yuklab olish tugallanmadi');
    }
    return file;
  }

  /// `v1.2.3+4` yoki `1.2.3` ko'rinishidagi tegni parslaydi.
  static ({int versionCode, String versionName})? _parseVersion(String tag) {
    final t = tag.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?').firstMatch(t);
    if (m == null) return null;
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    final patch = int.parse(m.group(3)!);
    final build = m.group(4) != null
        ? int.parse(m.group(4)!)
        : major * 10000 + minor * 100 + patch;
    return (versionCode: build, versionName: '$major.$minor.$patch');
  }
}

class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String url;
  final String notes;

  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.url,
    required this.notes,
  });
}

/// Yuklab olish jarayonini ko'rsatuvchi dialog.
class _DownloadDialog extends StatefulWidget {
  final UpdateInfo info;

  const _DownloadDialog({required this.info});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final dir = await getExternalStorageDirectory();
      final path = dir?.path;
      if (path == null) throw Exception('Saqlash joyi topilmadi');
      final file = await AppUpdate.downloadApk(
        widget.info.url,
        path,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yuklab olinmoqda...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error)
            const Text(
              'Yuklab olishda xatolik. Internetni tekshirib qaytadan urinib '
              'ko\'ring.',
            )
          else ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _error ? () => Navigator.of(context).pop(null) : null,
          child: const Text('Yopish'),
        ),
      ],
    );
  }
}
