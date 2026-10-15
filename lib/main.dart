import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
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
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF7B2CBF),
        ),
      ),
      home: const WakaHomeScreen(),
    );
  }
}

class VpnServer {
  final String countryLong;
  final String countryShort;
  final String ip;
  final int speed;
  final String ovpnConfig;

  VpnServer({
    required this.countryLong,
    required this.countryShort,
    required this.ip,
    required this.speed,
    required this.ovpnConfig,
  });
}

class WakaHomeScreen extends StatefulWidget {
  const WakaHomeScreen({super.key});

  @override
  State<WakaHomeScreen> createState() => _WakaHomeScreenState();
}

class _WakaHomeScreenState extends State<WakaHomeScreen> {
  late OpenVPN _openVPN;
  VPNStage _vpnStage = VPNStage.disconnected;
  VpnStatus? _vpnStatus;
  
  List<VpnServer> _servers = [];
  VpnServer? _selectedServer;
  bool _isLoadingServers = true;

  @override
  void initState() {
    super.initState();
    _initOpenVPN();
    _fetchServers();
  }

  void _initOpenVPN() {
    _openVPN = OpenVPN(
      onVpnStatusChanged: (data) {
        setState(() => _vpnStatus = data);
      },
      onVpnStageChanged: (stage, rawStage) {
        setState(() => _vpnStage = stage);
        if (stage == VPNStage.connected) {
          HapticFeedback.heavyImpact();
        }
      },
    );
    _openVPN.initialize(
      groupIdentifier: "group.com.wakavpn.app",
      providerBundleIdentifier: "com.wakavpn.app.VPNExtension",
      localizedDescription: "WAKA VPN Shield",
    );
  }

  Future<void> _fetchServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final response = await http.get(Uri.parse('http://www.vpngate.net/api/iphone/'));
      if (response.statusCode == 200) {
        final lines = const LineSplitter().convert(response.body);
        final List<VpnServer> parsedServers = [];

        for (int i = 2; i < lines.length; i++) {
          final cols = lines[i].split(',');
          if (cols.length > 14 && cols[14].isNotEmpty) {
            parsedServers.add(
              VpnServer(
                countryLong: cols[5],
                countryShort: cols[6],
                ip: cols[1],
                speed: (int.parse(cols[4]) / 1000000).round(),
                ovpnConfig: cols[14],
              ),
            );
          }
        }
        
        if (parsedServers.isNotEmpty) {
          setState(() {
            _servers = parsedServers;
            _selectedServer = parsedServers.first;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching: $e");
    }
    setState(() => _isLoadingServers = false);
  }

  void _toggleConnection() {
    HapticFeedback.mediumImpact();
    if (_vpnStage == VPNStage.disconnected) {
      if (_selectedServer == null) return;
      
      try {
        final decodedConfig = utf8.decode(base64Decode(_selectedServer!.ovpnConfig));
        _openVPN.connect(
          decodedConfig,
          "WAKA - ${_selectedServer!.countryLong}",
          username: "vpn",
          password: "vpn",
          certIsRequired: false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load server config')),
        );
      }
    } else {
      _openVPN.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _vpnStage == VPNStage.connected;
    final bool isConnecting = _vpnStage == VPNStage.connecting || _vpnStage == VPNStage.authenticating || _vpnStage == VPNStage.tcp_connect;
    final Color primaryGlow = isConnected ? const Color(0xFF00F5D4) : (isConnecting ? const Color(0xFFFFBE0B) : const Color(0xFF3A86FF));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('WAKA VPN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  if (_isLoadingServers)
                    const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F5D4)))
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(20)),
                      child: Text('${_servers.length} SERVERS', style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                isConnected ? 'REAL SECURE SHIELD ACTIVE' : (isConnecting ? 'CONNECTING REAL TUNNEL...' : 'TAP ORB TO CONNECT'),
                style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700, color: primaryGlow),
              ),
              const SizedBox(height: 8),
              Text(
                _vpnStatus?.duration ?? "00:00:00",
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w300, letterSpacing: 3),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _toggleConnection,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [primaryGlow.withOpacity(0.45), const Color(0xFF0D1322)]),
                    border: Border.all(color: primaryGlow.withOpacity(0.8), width: 2.5),
                  ),
                  child: Center(
                    child: Icon(isConnected ? Icons.shield_rounded : Icons.power_settings_new_rounded, size: 64, color: Colors.white),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF0B0F19),
                    builder: (context) {
                      return ListView.builder(
                        itemCount: _servers.length,
                        itemBuilder: (context, index) {
                          final s = _servers[index];
                          return ListTile(
                            leading: Text(s.countryShort, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white54)),
                            title: Text(s.countryLong),
                            subtitle: Text('IP: ${s.ip} • Speed: ${s.speed} Mbps'),
                            onTap: () {
                              Navigator.pop(context);
                              setState(() => _selectedServer = s);
                            },
                          );
                        },
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: primaryGlow.withOpacity(0.35), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedServer?.countryLong ?? 'Select Server...',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
