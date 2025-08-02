// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/role.dart';

class RoleSelectionScreen extends StatefulWidget {
  @override
  _RoleSelectionScreenState createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final FirestoreService _fs = FirestoreService();
  static const String _adminPassword = '123456789';

  List<String> _usernames = [];
  bool _loading = true;
  String? _error;
  int _hunterCount = 0;
  bool _mrXExists = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final users = await _fs.getAllUsernames();
      final hunters = await _fs.getAllHunterLocations();
      final mrx = await _fs.getMrXLocation();
      setState(() {
        _usernames = users;
        _hunterCount = hunters.length;
        _mrXExists = mrx != null;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Konnte Daten nicht laden.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndDeleteAllData() async {
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String pw = '';
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Admin-Passwort',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            autofocus: true,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Passwort',
              hintStyle: TextStyle(color: Colors.white70),
            ),
            onChanged: (v) => pw = v,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen',
                    style: TextStyle(color: Colors.white70))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, pw),
                child: const Text('OK',
                    style: TextStyle(color: Colors.deepPurpleAccent))),
          ],
        );
      },
    );
    if (input != _adminPassword) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Falsches Passwort!')));
      return;
    }
    setState(() => _loading = true);
    try {
      await _fs.deleteAllGameData();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alle Spieldaten gelöscht.')));
      await _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: \$e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final accent = Colors.deepPurpleAccent;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Rolle wählen'),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        leading: BackButton(onPressed: () => auth.clearGameUsername()),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => auth.logout(deleteData: true)),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage('lib/assets/map_background3.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black26, BlendMode.darken),
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _loadData,
                color: accent,
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  children: [
                    if (_error != null)
                      Center(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 16))),
                    Card(
                      color: Colors.grey[900]!.withOpacity(0.85),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Aktive Spieler',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: accent)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (var u in _usernames)
                                  Chip(
                                    label: Text(u,
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    backgroundColor:
                                        Colors.deepPurple.withOpacity(0.7),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Card(
                      color: Colors.grey[900]!.withOpacity(0.85),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text('Bitte Rolle wählen',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: accent)),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _mrXExists
                                        ? null
                                        : () => auth.setRole(Role.mrx),
                                    icon: const Icon(Icons.person_outline),
                                    label: const Text('Mr. X'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accent,
                                      disabledBackgroundColor:
                                          accent.withOpacity(0.5),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => auth.setRole(Role.hunter),
                                    icon: const Icon(Icons.search),
                                    label: const Text('Hunter'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Colors.greenAccent.shade400,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    'Mr. X: ${_mrXExists ? 'vorhanden' : 'frei'}',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70)),
                                Text('Hunter: $_hunterCount',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70)),
                              ],
                            ),
                            if (_mrXExists)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('Mr. X ist bereits vergeben',
                                    style: TextStyle(color: Colors.redAccent)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                Container(
                  color: Colors.black45,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: Colors.deepPurpleAccent)),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: 16,
            left: 24,
            right: 24,
          ),
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _confirmAndDeleteAllData,
              icon: const Icon(Icons.delete_forever,
                  size: 20, color: Colors.redAccent),
              label: const Text('Delete Data',
                  style: TextStyle(color: Colors.redAccent, fontSize: 16)),
              style: TextButton.styleFrom(
                backgroundColor: Colors.black.withOpacity(0.6),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
