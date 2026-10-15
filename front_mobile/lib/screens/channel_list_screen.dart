import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../background/beacon_controller.dart';
import '../ui.dart';
import '../models.dart';
import '../session_store.dart';
import '../widgets/profile_avatar.dart';
import 'login_screen.dart';
import 'room_screen.dart';
import 'profile_screen.dart';

class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key, required this.api, required this.user});

  final ApiClient api;
  final PublicUser user;

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  List<Channel>? _channels;
  String? _error;
  bool _creating = false;
  int _tab = 0;
  late PublicUser _user;
  Timer? _refreshTimer;

  static const _refreshInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load();
    // Atualiza a contagem de pessoas online periodicamente. Sem isso, a lista
    // fica com o valor de quando foi aberta — por exemplo, ainda mostrando a
    // própria pessoa logo depois de sair de um canal.
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _error = null;
      });
    }
    try {
      final channels = await widget.api.listChannels();
      if (!mounted) return;
      setState(() => _channels = channels);
    } on ApiException catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _channels = const [];
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _channels = const [];
        _error = 'Falha de rede ou servidor inacessível: $e';
      });
    }
  }

  Future<void> _createChannel() async {
    if (_creating) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo canal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome do canal',
          ),
        ),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'Meu perfil',
              onPressed: () => setState(() => _tab = 1),
              icon: ProfileAvatar(
                name: _user.username,
                avatar: _user.avatar,
                radius: 16,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final channel = await widget.api.createChannel(name);
      if (!mounted) return;
      setState(() {
        _channels = [...?_channels, channel];
        _creating = false;
      });
      _openChannel(channel);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openChannel(Channel channel) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RoomScreen(api: widget.api, channel: channel, myUser: _user),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _logout() async {
    await BeaconController.stop();
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = _channels;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Canais' : 'Meu perfil'),
        actions: [
          TextButton(onPressed: _logout, child: const Text('Sair')),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radio_outlined),
            selectedIcon: Icon(Icons.radio),
            label: 'Canais',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
      floatingActionButton: _tab != 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _createChannel,
              icon: const Icon(Icons.add),
              label: Text(_creating ? 'Criando...' : 'Novo canal'),
            ),
      body: IndexedStack(
        index: _tab,
        children: [
          RefreshIndicator(
            onRefresh: () => _load(),
            child: channels == null
                ? const Center(child: CircularProgressIndicator())
                : channels.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(
                        Icons.radio_outlined,
                        size: 64,
                        color: Colors.white24,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error ?? 'A conversa começa com um canal.\nCrie o primeiro abaixo.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      if (_error != null)
                        TextButton(
                          onPressed: _load,
                          child: const Text('Tentar novamente'),
                        ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    separatorBuilder: (_, _) => const Divider(),
                    itemCount: channels.length,
                    itemBuilder: (ctx, i) {
                      final ch = channels[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.tag, color: pxAccent, size: 20),
                        ),
                        title: Text(ch.name),
                        subtitle: Row(
                          children: [
                            if (ch.online > 0) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF3DD68C),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              ch.online == 0
                                  ? 'Ninguém online agora'
                                  : '${ch.online} online agora',
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openChannel(ch),
                      );
                    },
                  ),
          ),
          ProfileScreen(
            api: widget.api,
            user: _user,
            onSaved: (user) {
              if (mounted) setState(() => _user = user);
            },
          ),
        ],
      ),
    );
  }
}
