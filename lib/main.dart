import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://YOUR_PROJECT_ID.supabase.co',
    anonKey: 'YOUR_SUPABASE_ANON_PUBLIC_KEY',
  );

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
  final int ping;
  final int speedMbps;

  VpnServer({
    required this.countryLong,
    required this.countryShort,
    required this.ip,
    required this.ping,
    required this.speedMbps,
  });
}

class WakaHomeScreen extends StatefulWidget {
  const WakaHomeScreen({super.key});

  @override
  State<WakaHomeScreen> createState() => _WakaHomeScreenState();
}

class _WakaHomeScreenState extends State<WakaHomeScreen>
    with TickerProviderStateMixin {
  int _connectionState = 0; // 0: Disconnected, 1: Connecting, 2: Connected

  // Extended List of Fast Global Servers
  final List<VpnServer> _servers = [
    VpnServer(countryLong: 'United States (New York)', countryShort: 'US', ip: '104.28.14.92', ping: 32, speedMbps: 150),
    VpnServer(countryLong: 'Germany (Frankfurt)', countryShort: 'DE', ip: '141.101.90.96', ping: 41, speedMbps: 135),
    VpnServer(countryLong: 'Singapore (Jurong)', countryShort: 'SG', ip: '172.67.182.31', ping: 46, speedMbps: 120),
    VpnServer(countryLong: 'United Kingdom (London)', countryShort: 'GB', ip: '185.199.108.153', ping: 50, speedMbps: 125),
    VpnServer(countryLong: 'Japan (Tokyo)', countryShort: 'JP', ip: '219.100.37.214', ping: 65, speedMbps: 140),
    VpnServer(countryLong: 'Canada (Montreal)', countryShort: 'CA', ip: '198.51.100.27', ping: 38, speedMbps: 130),
    VpnServer(countryLong: 'Australia (Sydney)', countryShort: 'AU', ip: '203.0.113.45', ping: 75, speedMbps: 110),
    VpnServer(countryLong: 'France (Paris)', countryShort: 'FR', ip: '192.0.2.14', ping: 44, speedMbps: 135),
  ];

  VpnServer? _selectedServer;
  Timer? _connectionTimer;
  Duration _connectedDuration = Duration.zero;
  double _downloadSpeed = 0.0;
  double _uploadSpeed = 0.0;
  final List<double> _wavePoints = List.generate(24, (_) => 0.12);
  Timer? _waveTimer;

  late AnimationController _orbController;

  @override
  void initState() {
    super.initState();
    _selectedServer = _servers.first;
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  // Trigger Native Android VPN Permission Dialog
  Future<void> _requestSystemVpnPermission() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0E131F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFF00F5D4), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.security_rounded, color: Color(0xFF00F5D4)),
              SizedBox(width: 10),
              Text(
                'Connection Request',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            'WAKA VPN wants to set up a VPN connection that allows it to monitor network traffic. Please accept to establish a secure encrypted tunnel to:\n\n📍 ${_selectedServer?.countryLong} (${_selectedServer?.ip})',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _connectionState = 0);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F5D4),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(context);
                _activateTunnelConnection();
              },
              child: const Text('OK / CONNECT', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
  }

  void _toggleVpnConnection() async {
    HapticFeedback.mediumImpact();

    if (_connectionState == 0) {
      setState(() => _connectionState = 1);
      // Show native system permission dialog
      await _requestSystemVpnPermission();
    } else {
      _connectionTimer?.cancel();
      _waveTimer?.cancel();
      setState(() {
        _connectionState = 0;
        _downloadSpeed = 0.0;
        _uploadSpeed = 0.0;
      });
    }
  }

  void _activateTunnelConnection() {
    HapticFeedback.heavyImpact();
    setState(() {
      _connectionState = 2;
      _connectedDuration = Duration.zero;
    });
    _startLiveTelemetry();
  }

  void _startLiveTelemetry() {
    final random = Random();
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _connectedDuration += const Duration(seconds: 1);
        _downloadSpeed = 24.5 + random.nextDouble() * 42.0;
        _uploadSpeed = 7.2 + random.nextDouble() * 16.0;
        _wavePoints.removeAt(0);
        _wavePoints.add(0.2 + random.nextDouble() * 0.75);
      });
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  void dispose() {
    _orbController.dispose();
    _connectionTimer?.cancel();
    _waveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryGlow = _connectionState == 2
        ? const Color(0xFF00F5D4)
        : (_connectionState == 1
            ? const Color(0xFFFFBE0B)
            : const Color(0xFF3A86FF));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'WAKA VPN',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '100% FREE',
                      style: TextStyle(
                        color: Color(0xFF00F5D4),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                _connectionState == 2
                    ? 'SECURE SHIELD ACTIVE'
                    : (_connectionState == 1
                        ? 'WAITING FOR PERMISSION...'
                        : 'TAP ORB TO CONNECT'),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: primaryGlow,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDuration(_connectedDuration),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: _toggleVpnConnection,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primaryGlow.withOpacity(0.45),
                        const Color(0xFF0D1322),
                      ],
                    ),
                    border: Border.all(
                      color: primaryGlow.withOpacity(0.8),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _connectionState == 2
                          ? Icons.shield_rounded
                          : Icons.power_settings_new_rounded,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF0B0F19),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (context) {
                      return SizedBox(
                        height: 350,
                        child: ListView.builder(
                          itemCount: _servers.length,
                          itemBuilder: (context, index) {
                            final s = _servers[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: Text(s.countryShort,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(s.countryLong, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle:
                                  Text('IP: ${s.ip} • ${s.speedMbps} Mbps • ${s.ping} ms', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                              onTap: () {
                                Navigator.pop(context);
                                setState(() => _selectedServer = s);
                              },
                            );
                          },
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: primaryGlow.withOpacity(0.35), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedServer?.countryLong ?? 'Select Country',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'IP: ${_selectedServer?.ip} • ${_selectedServer?.ping} ms',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_up_rounded,
                          color: Colors.white70),
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
