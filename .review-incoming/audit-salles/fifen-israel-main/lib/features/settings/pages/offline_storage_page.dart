import 'package:flutter/material.dart';

import '../../../core/offline/course_offline_service.dart';
import '../../../core/offline/offline_settings.dart';
import '../../../models/user_profile.dart';

class OfflineStoragePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  const OfflineStoragePage({super.key, required this.locale, required this.profile});

  @override
  State<OfflineStoragePage> createState() => _OfflineStoragePageState();
}

class _OfflineStoragePageState extends State<OfflineStoragePage> {
  final OfflineSettings _settings = OfflineSettings();
  final CourseOfflineService _offline = CourseOfflineService();
  bool _wifiOnly = false;
  int _limitMb = 500;
  int _used = 0;
  bool _loading = true;

  bool get _fr => widget.locale.languageCode != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wifi = await _settings.wifiOnly();
    final limit = await _settings.limitMb();
    final used = await _offline.usedBytes(widget.profile.id);
    if (!mounted) {
      return;
    }
    setState(() { _wifiOnly = wifi; _limitMb = limit; _used = used; _loading = false; });
  }

  String _size(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _chooseLimit() async {
    final controller = TextEditingController(text: '$_limitMb');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_fr ? 'Limite de stockage' : 'Storage limit'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _fr ? 'Mo (100 à 5000)' : 'MB (100 to 5000)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(controller.text)), child: Text(_fr ? 'Enregistrer' : 'Save')),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await _settings.setLimitMb(value);
    await _offline.enforceStorageLimit(widget.profile.id);
    await _load();
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_fr ? 'Supprimer tous les fichiers ?' : 'Delete all files?'),
        content: Text(_fr ? 'Les fichiers seront téléchargés à nouveau lorsque vous ouvrirez les cours en ligne.' : 'Files will be downloaded again when you open courses online.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_fr ? 'Annuler' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_fr ? 'Tout supprimer' : 'Delete all')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _offline.deleteAll(widget.profile.id);
    await _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _limitMb <= 0 ? 0.0 : (_used / (_limitMb * 1024 * 1024)).clamp(0, 1).toDouble();
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF166534), foregroundColor: Colors.white, title: Text(_fr ? 'Stockage hors ligne' : 'Offline storage')),
      backgroundColor: const Color(0xFFF5F8F6),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_fr ? 'Espace utilisé' : 'Space used', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: ratio),
            const SizedBox(height: 8),
            Text('${_size(_used)} / $_limitMb Mo'),
          ]))),
          const SizedBox(height: 12),
          Card(child: SwitchListTile(
            value: _wifiOnly,
            onChanged: (value) async { await _settings.setWifiOnly(value); if (mounted) setState(() => _wifiOnly = value); },
            secondary: const Icon(Icons.wifi_rounded, color: Color(0xFF166534)),
            title: Text(_fr ? 'Télécharger seulement en Wi-Fi' : 'Download only on Wi-Fi'),
            subtitle: Text(_fr ? 'Désactivé par défaut pour permettre les données mobiles.' : 'Disabled by default so mobile data can be used.'),
          )),
          Card(child: ListTile(
            leading: const Icon(Icons.storage_rounded, color: Color(0xFF166534)),
            title: Text(_fr ? 'Limite de stockage' : 'Storage limit'),
            subtitle: Text('$_limitMb Mo'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _chooseLimit,
          )),
          const SizedBox(height: 8),
          Card(child: ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            title: Text(_fr ? 'Tout supprimer' : 'Delete all'),
            subtitle: Text(_fr ? 'Supprimer les fichiers hors ligne de cet appareil.' : 'Delete this user’s offline files from this device.'),
            onTap: _deleteAll,
          )),
        ],
      ),
    );
  }
}
