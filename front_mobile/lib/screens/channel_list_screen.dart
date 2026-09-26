import 'dart:async';
import 'package:flutter/material.dart';
import '../driver_location.dart';

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
  bool _nearby = true;
  double _radiusKm = 50;
  int _loadVersion = 0;
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _nearby && _error == null && !_creating &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    final nearby = _nearby;
    final radius = _radiusKm;
    setState(() {
      _error = null;
    });
    try {
      final position = nearby ? await DriverLocation.current() : null;
      if (!mounted || version != _loadVersion) return;
      final channels = await widget.api.listChannels(
        latitude: position?.latitude, longitude: position?.longitude, radiusKm: radius);
      if (!mounted || version != _loadVersion) return;
      setState(() => _channels = channels);
    } on ApiException catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _channels = const [];
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _channels = const [];
        _error = e is StateError ? e.message.toString() : 'Falha ao carregar canais. Tente novamente.';
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

    if (!mounted || name == null || name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final position = await DriverLocation.current();
      if (!mounted) return;
      final channel = await widget.api.createChannel(name,
        latitude: position.latitude, longitude: position.longitude);
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
          .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e is StateError ? e.message.toString() : 'Falha ao criar canal. Tente novamente.')));
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
        onPressed: _creating ? null : _createChannel,
        icon: const Icon(Icons.add),
        label: Text(_creating ? 'Criando...' : 'Novo canal'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(label: const Text('Próximos'), selected: _nearby,
              onSelected: (_) { setState(() { _nearby = true; _channels = null; }); _load(); }),
            ChoiceChip(label: const Text('Todos'), selected: !_nearby,
              onSelected: (_) { setState(() { _nearby = false; _channels = null; }); _load(); }),
            if (_nearby) DropdownButton<double>(
              value: _radiusKm,
              items: [5, 10, 25, 50, 100, 250, 500].map((km) => DropdownMenuItem(
                value: km.toDouble(), child: Text('$km km'))).toList(),
              onChanged: (value) { if (value == null) return; setState(() { _radiusKm = value; _channels = null; }); _load(); },
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Atualizar localização e canais'),
          ]),
        ),
        if (_nearby) const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Distância em linha reta até o local de criação do canal.')),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: channels == null
            ? const Center(child: CircularProgressIndicator())
            : channels.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.radio_outlined,
                          size: 64, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text(
                        _error ?? (_nearby ? 'Nenhum canal em até ${_radiusKm.toInt()} km. Amplie o raio ou veja Todos.' : 'Nenhum canal ainda'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                      if (_error != null)
                        TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                          '${ch.members} membro(s)${ch.distanceKm == null ? '' : ' - ${ch.distanceKm!.toStringAsFixed(1)} km'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openChannel(ch),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}
