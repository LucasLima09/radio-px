import 'package:flutter/material.dart';

import '../../controllers/channel_list_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../di.dart';
import '../../models/active_session.dart';
import '../../models/channel.dart';
import '../../routes.dart';
import '../../theme/app_colors.dart';
import 'profile_screen.dart';

/// Tela principal: lista de canais e, na outra aba, o perfil.
class ChannelListScreen extends StatefulWidget {
  const ChannelListScreen({super.key, required this.session});

  final ActiveSession session;

  @override
  State<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends State<ChannelListScreen> {
  ChannelListController? _channels;
  ProfileController? _profile;
  int _tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_channels != null) return;
    final deps = AppScope.of(context);
    _channels = ChannelListController(
      api: widget.session.api,
      user: widget.session.user,
      deps: deps,
    );
    _profile = ProfileController(
      api: widget.session.api,
      user: widget.session.user,
      onUserChanged: (user) => _channels!.updateUser(user),
    );
    _channels!.start();
  }

  @override
  void dispose() {
    _channels?.dispose();
    _profile?.dispose();
    super.dispose();
  }

  Future<void> _createChannel() async {
    final controller = _channels!;
    if (controller.isCreating) return;
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo canal'),
        content: TextField(
          controller: nameCtrl,
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
            onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final channel = await controller.create(name);
    if (!mounted) return;
    if (channel == null) {
      final error = controller.error;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    await _openChannel(channel);
  }

  Future<void> _openChannel(Channel channel) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.room,
      arguments: RoomArgs(session: widget.session, channel: channel),
    );
    if (mounted) await _channels!.load();
  }

  Future<void> _logout() async {
    await _channels!.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _channels!;
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
              label: Text(
                controller.isCreating ? 'Criando...' : 'Novo canal',
              ),
            ),
      body: IndexedStack(
        index: _tab,
        children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _channelsBody(controller),
          ),
          ProfileScreen(controller: _profile!),
        ],
      ),
    );
  }

  Widget _channelsBody(ChannelListController controller) {
    final channels = controller.channels;
    if (channels == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (channels.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(
            Icons.radio_outlined,
            size: 64,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            controller.error ??
                'A conversa começa com um canal.\nCrie o primeiro abaixo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          if (controller.error != null)
            TextButton(
              onPressed: controller.load,
              child: const Text('Tentar novamente'),
            ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        separatorBuilder: (_, _) => const Divider(),
        itemCount: channels.length,
        itemBuilder: (ctx, i) {
          final ch = channels[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: pxIconTile,
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
                      color: pxOnline,
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
    );
  }
}
