import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../session_store.dart';
import 'login_screen.dart';
import 'room_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
    });
    try {
      final channels = await widget.api.listChannels();
      if (!mounted) return;
      setState(() => _channels = channels);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _channels = const [];
        _error = e.message;
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
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openChannel(Channel channel) async {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomScreen(
          api: widget.api,
          channel: channel,
          myUser: widget.user,
        ),
      ),
    );
  }

  Future<void> _logout() async {
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
        title: const Text('Canais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createChannel,
        icon: const Icon(Icons.add),
        label: Text(_creating ? 'Criando...' : 'Novo canal'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: channels == null
            ? const Center(child: CircularProgressIndicator())
            : channels.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.radio_outlined,
                          size: 64, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text(
                        _error ?? 'Nenhum canal ainda',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      if (_error != null)
                        TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: channels.length,
                    itemBuilder: (ctx, i) {
                      final ch = channels[i];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.wifi_tethering),
                        ),
                        title: Text(ch.name),
                        subtitle: Text(
                          '${ch.members} membro(s)',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openChannel(ch),
                      );
                    },
                  ),
      ),
    );
  }
}