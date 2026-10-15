import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07090E),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00F5D4)),
      ),
      home: const WakaHome(),
    );
  }
}

class VpnServer {
  final String country;
  final String ip;
  final String config;

  VpnServer(this.country, this.ip, this.config);
}

class WakaHome extends StatefulWidget {
  const WakaHome({super.key});

  @override
  State<WakaHome> createState() => _WakaHomeState();
}

class _WakaHomeState extends State<WakaHome> {
  late OpenVPN openVPN;
  VPNStage vpnStage = VPNStage.disconnected;
  List<VpnServer> servers = [];
  VpnServer? selectedServer;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    openVPN = OpenVPN(
      onVpnStageChanged: (stage, _) => setState(() => vpnStage = stage),
      onVpnStatusChanged: (_) {},
    );
    openVPN.initialize(
      groupIdentifier: "group.com.wakavpn.app",
      providerBundleIdentifier: "com.wakavpn.app.VPNExtension",
      localizedDescription: "WAKA VPN",
    );
    _loadServers();
  }

  Future<void> _loadServers() async {
    try {
      final res = await http.get(Uri.parse('http://www.vpngate.net/api/iphone/'));
      if (res.statusCode == 200) {
        final lines = const LineSplitter().convert(res.body);
        for (int i = 2; i < lines.length; i++) {
          final cols = lines[i].split(',');
          if (cols.length > 14 && cols[14].isNotEmpty) {
            servers.add(VpnServer(cols[5], cols[1], cols[14]));
          }
        }
        if (servers.isNotEmpty) selectedServer = servers.first;
      }
    } catch (e) {
      debugPrint("Error fetching API");
    }
    setState(() => isLoading = false);
  }

  void _toggle() {
    if (vpnStage == VPNStage.disconnected && selectedServer != null) {
      HapticFeedback.heavyImpact();
      final config = utf8.decode(base64Decode(selectedServer!.config));
      openVPN.connect(
        config,
        selectedServer!.country,
        username: "vpn",
        password: "vpn",
        certIsRequired: false,
      );
    } else {
      openVPN.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = vpnStage == VPNStage.connected;
    final isConnecting = vpnStage == VPNStage.connecting || vpnStage == VPNStage.authenticating;

    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'WAKA VPN',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF00F5D4), letterSpacing: 2),
            ),
            const SizedBox(height: 10),
            Text(
              isConnected ? 'SHIELD SECURED' : (isConnecting ? 'REQUESTING PERMISSION...' : 'TAP TO SECURE'),
              style: TextStyle(color: isConnected ? const Color(0xFF00F5D4) : Colors.white70, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 60),
            GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? const Color(0xFF00F5D4) : const Color(0xFF151A25),
                  border: Border.all(color: const Color(0xFF00F5D4), width: 3),
                  boxShadow: [
                    if (isConnected) BoxShadow(color: const Color(0xFF00F5D4).withOpacity(0.5), blurRadius: 40)
                  ],
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 80,
                  color: isConnected ? Colors.black : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 60),
            if (isLoading)
              const CircularProgressIndicator(color: Color(0xFF00F5D4))
            else if (servers.isEmpty)
              const Text('No Servers Found', style: TextStyle(color: Colors.redAccent))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<VpnServer>(
                  value: selectedServer,
                  dropdownColor: const Color(0xFF0B0F19),
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00F5D4)),
                  items: servers.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('${s.country} • IP: ${s.ip}', style: const TextStyle(fontSize: 14)),
                  )).toList(),
                  onChanged: (val) => setState(() => selectedServer = val),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
