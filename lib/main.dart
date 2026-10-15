import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  final List<VpnServer> _servers = [
    VpnServer(countryLong: 'United States (New York)', countryShort: 'US', ip: '104.28.14.92', ping: 32, speedMbps: 140),
    VpnServer(countryLong: 'Germany (Frankfurt)', countryShort: 'DE', ip: '141.101.90.96', ping: 41, speedMbps: 125),
    VpnServer(countryLong: 'Singapore (Jurong)', countryShort: 'SG', ip: '172.67.182.31', ping: 46, speedMbps: 110),
    VpnServer(countryLong: 'United Kingdom (London)', countryShort: 'GB', ip: '185.199.108.153', ping: 50, speedMbps: 115),
    VpnServer(countryLong: 'Japan (Tokyo)', countryShort: 'JP', ip: '219.100.37.214', ping: 65, speedMbps: 130),
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

  void _toggleVpnConnection() {
    HapticFeedback.mediumImpact();

    if (_connectionState == 0) {
      setState(() => _connectionState = 1);

      // Connect simulation
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        setState(() {
          _connectionState = 2;
          _connectedDuration = Duration.zero;
        });
        _startLiveTelemetry();
      });
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

  void _startLiveTelemetry() {
    final random = Random();
    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _connectedDuration += const Duration(seconds: 1);
        _downloadSpeed = 22.5 + random.nextDouble() * 38.0;
        _uploadSpeed = 6.2 + random.nextDouble() * 14.0;
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
                        ? 'ESTABLISHING TUNNEL...'
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
                    builder: (context) {
                      return SizedBox(
                        height: 300,
                        child: ListView.builder(
                          itemCount: _servers.length,
                          itemBuilder: (context, index) {
                            final s = _servers[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: Text(s.countryShort,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                              title: Text(s.countryLong),
                              subtitle:
                                  Text('${s.speedMbps} Mbps • ${s.ping} ms'),
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
