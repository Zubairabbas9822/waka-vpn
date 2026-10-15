import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';

import 'server_directory.dart';

const _serverDirectoryUri = 'https://www.vpngate.net/api/iphone/';
const _serverRequestTimeout = Duration(seconds: 20);
const _maxDirectoryBytes = 12 * 1024 * 1024;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const WakaVpnApp());
}

class WakaVpnApp extends StatelessWidget {
  const WakaVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WAKA VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00F5D4)),
      ),
      home: const WakaHome(),
    );
  }
}

class WakaHome extends StatefulWidget {
  const WakaHome({super.key});

  @override
  State<WakaHome> createState() => _WakaHomeState();
}

class _WakaHomeState extends State<WakaHome> {
  late final OpenVPN _openVPN;
  VPNStage _vpnStage = VPNStage.disconnected;
  List<VpnServer> _servers = const [];
  List<String> _countries = const [];
  String? _selectedCountry;
  VpnServer? _selectedServer;
  String? _serverError;
  String? _connectionError;
  bool _isLoadingServers = true;
  bool _isVpnReady = false;
  bool _isStartingConnection = false;

  bool get _isConnecting =>
      _isStartingConnection ||
      _vpnStage == VPNStage.connecting ||
      _vpnStage == VPNStage.authenticating;

  @override
  void initState() {
    super.initState();
    _openVPN = OpenVPN(
      onVpnStageChanged: _onVpnStageChanged,
      onVpnStatusChanged: (_) {},
    );
    unawaited(_initializeVpn());
    unawaited(_loadServers());
  }

  void _onVpnStageChanged(VPNStage stage, String _) {
    if (!mounted) return;
    setState(() {
      _vpnStage = stage;
      if (stage == VPNStage.connected) _connectionError = null;
    });
  }

  Future<void> _initializeVpn() async {
    try {
      await _openVPN.initialize(
        groupIdentifier: 'group.com.wakavpn.app',
        providerBundleIdentifier: 'com.wakavpn.app.VPNExtension',
        localizedDescription: 'WAKA VPN',
      );
      if (!mounted) return;
      setState(() => _isVpnReady = true);
    } catch (error) {
      debugPrint('VPN initialization failed: $error');
      if (!mounted) return;
      setState(() => _connectionError = 'VPN service could not start. Restart the app and try again.');
    }
  }

  Future<void> _loadServers() async {
    if (mounted) {
      setState(() {
        _isLoadingServers = true;
        _serverError = null;
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse(_serverDirectoryUri),
            headers: const {'Accept': 'text/plain'},
          )
          .timeout(_serverRequestTimeout);

      if (response.statusCode != 200) {
        throw StateError('Server directory returned HTTP ${response.statusCode}.');
      }
      if (response.bodyBytes.length > _maxDirectoryBytes) {
        throw const FormatException('Server directory response is too large.');
      }

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final loadedServers = parseVpnGateResponse(body);
      if (loadedServers.isEmpty) {
        throw const FormatException('No valid VPN servers were returned.');
      }

      final loadedCountries = loadedServers
          .map((server) => server.country)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _servers = loadedServers;
        _countries = loadedCountries;
        _selectedCountry = loadedCountries.first;
        _selectedServer = loadedServers.firstWhere(
          (server) => server.country == loadedCountries.first,
        );
        _isLoadingServers = false;
      });
    } on TimeoutException {
      _setServerLoadError('Server list request timed out. Check your connection and retry.');
    } catch (error) {
      debugPrint('Server list loading failed: $error');
      _setServerLoadError('Could not load the secure server list. Check your connection and retry.');
    }
  }

  void _setServerLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoadingServers = false;
      _serverError = message;
    });
  }

  void _selectCountry(String? country) {
    if (country == null) return;
    setState(() {
      _selectedCountry = country;
      _selectedServer = _servers.firstWhere(
        (server) => server.country == country,
      );
    });
  }

  Future<void> _toggleVpn() async {
    if (!_isVpnReady || _isConnecting) return;

    if (_vpnStage == VPNStage.connected) {
      try {
        _openVPN.disconnect();
      } catch (error) {
        debugPrint('VPN disconnect failed: $error');
        if (mounted) {
          setState(() => _connectionError = 'Could not disconnect. Please try again.');
        }
      }
      return;
    }

    final server = _selectedServer;
    if (server == null) return;

    setState(() {
      _isStartingConnection = true;
      _connectionError = null;
    });
    unawaited(HapticFeedback.mediumImpact());

    try {
      final profile = utf8.decode(
        base64.decode(base64.normalize(server.config)),
        allowMalformed: false,
      );
      final filteredProfile = await OpenVPN.filteredConfig(profile);
      if (filteredProfile == null || filteredProfile.trim().isEmpty) {
        throw const FormatException('VPN profile is invalid.');
      }
      await _openVPN.connect(
        filteredProfile,
        server.country,
        username: 'vpn',
        password: 'vpn',
        certIsRequired: false,
      );
    } catch (error) {
      debugPrint('VPN connection failed: $error');
      if (mounted) {
        setState(() => _connectionError = 'Connection failed. Choose another server or try again.');
      }
    } finally {
      if (mounted) setState(() => _isStartingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _vpnStage == VPNStage.connected;
    final isBusy = _isConnecting;
    final canChooseServer =
        !_isLoadingServers && !isConnected && !isBusy && _countries.isNotEmpty;
    final serversInCountry = _selectedCountry == null
        ? const <VpnServer>[]
        : _servers
            .where((server) => server.country == _selectedCountry)
            .toList(growable: false);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'WAKA VPN',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00F5D4),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isConnected
                        ? 'CONNECTED • ${_selectedCountry ?? 'VPN'}'
                        : (isBusy ? 'CONNECTING…' : 'SELECT A SERVER TO CONNECT'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isConnected
                          ? const Color(0xFF00F5D4)
                          : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Semantics(
                    button: true,
                    label: isConnected ? 'Disconnect VPN' : 'Connect VPN',
                    child: GestureDetector(
                      onTap: _isVpnReady && !isBusy && _selectedServer != null
                          ? () => unawaited(_toggleVpn())
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 176,
                        height: 176,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected
                              ? const Color(0xFF00F5D4)
                              : const Color(0xFF151A25),
                          border: Border.all(
                            color: const Color(0xFF00F5D4),
                            width: 3,
                          ),
                          boxShadow: isConnected
                              ? const [
                                  BoxShadow(
                                    color: Color(0x8000F5D4),
                                    blurRadius: 36,
                                  ),
                                ]
                              : const [],
                        ),
                        child: Icon(
                          isBusy
                              ? Icons.sync_rounded
                              : Icons.power_settings_new_rounded,
                          size: 76,
                          color: isConnected ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  if (_isLoadingServers)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: Color(0xFF00F5D4),
                      ),
                    )
                  else if (_serverError != null)
                    _ServerError(
                      message: _serverError!,
                      onRetry: () => unawaited(_loadServers()),
                    )
                  else if (_servers.isEmpty)
                    const Text(
                      'No VPN servers are currently available.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    )
                  else ...[
                    _PickerLabel('COUNTRY (${_countries.length} AVAILABLE)'),
                    const SizedBox(height: 8),
                    _PickerContainer(
                      child: DropdownButton<String>(
                        value: _selectedCountry,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0B0F19),
                        underline: const SizedBox.shrink(),
                        hint: const Text('Choose a country'),
                        items: _countries
                            .map(
                              (country) => DropdownMenuItem<String>(
                                value: country,
                                child: Text(
                                  country,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: canChooseServer ? _selectCountry : null,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PickerLabel('SERVER (${serversInCountry.length} IN COUNTRY)'),
                    const SizedBox(height: 8),
                    _PickerContainer(
                      child: DropdownButton<VpnServer>(
                        value: _selectedServer,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0B0F19),
                        underline: const SizedBox.shrink(),
                        hint: const Text('Choose a server'),
                        items: serversInCountry
                            .map(
                              (server) => DropdownMenuItem<VpnServer>(
                                value: server,
                                child: Text(
                                  '${server.country} • ${server.ip}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: canChooseServer
                            ? (server) => setState(() => _selectedServer = server)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${_servers.length} servers across ${_countries.length} countries in the live directory',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                  if (_connectionError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _connectionError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0x0DFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x24FFFFFF)),
                    ),
                    child: const Text(
                      'Community VPN servers are operated by third parties. Their operators may see your IP address and connection metadata. A VPN does not replace HTTPS or guarantee anonymity. Only countries currently listed by the live directory can be selected.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerLabel extends StatelessWidget {
  const _PickerLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF00F5D4),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _PickerContainer extends StatelessWidget {
  const _PickerContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: child,
      );
}

class _ServerError extends StatelessWidget {
  const _ServerError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
}
