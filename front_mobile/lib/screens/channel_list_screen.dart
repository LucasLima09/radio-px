import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';
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
    } catch (e) {
      if (!mounted) return;
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
        builder: (_) => RoomScreen(
          api: widget.api,
          channel: channel,
          myUser: widget.user,
        ),
      ),
    );
    if (mounted) await _load();
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
        title: const Row(children: [
          RadioMark(size: 32),
          SizedBox(width: 10),
          Text('Radio PX'),
        ]),
        actionsPadding: const EdgeInsets.only(right: 8),
        actions: [
          TextButton(onPressed: _logout, child: const Text('Sair')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: ContentWidth(child: FilledButton(
          onPressed: _creating ? null : _createChannel,
          child: Text(_creating ? 'Criando...' : 'Novo canal'),
        )),
      ),
      body: ContentWidth(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: PageHeading(
              title: 'Seus canais',
              subtitle: 'Entre para ver quem está no canal, ouvir e falar.',
            ),
          ),
          Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: channels == null
            ? const Center(child: CircularProgressIndicator())
            : channels.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Text(
                        _error ?? 'A conversa começa com um canal.\nCrie o primeiro abaixo.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      if (_error != null)
                        TextButton(onPressed: _load, child: const Text('Tentar novamente')),
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
                        subtitle: Text(
                          '${ch.members} inscritos · toque para entrar',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openChannel(ch),
                      );
                    },
                  ),
          )),
        ],
      )),
    );
  }
}
