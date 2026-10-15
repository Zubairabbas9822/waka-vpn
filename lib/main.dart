import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart';
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

class RemoteAppConfig {
  final bool isSubscriptionEnabled;
  final int monthlyPricePkr;
  final String announcementBanner;

  RemoteAppConfig({
    required this.isSubscriptionEnabled,
    required this.monthlyPricePkr,
    required this.announcementBanner,
  });

  factory RemoteAppConfig.fromMap(Map<String, dynamic> map) {
    return RemoteAppConfig(
      isSubscriptionEnabled: map['is_subscription_enabled'] ?? false,
      monthlyPricePkr: map['monthly_price_pkr'] ?? 350,
      announcementBanner: map['announcement_banner'] ?? '',
    );
  }
}

class VpnServer {
  final String countryLong;
  final String countryShort;
  final String ip;
  final int ping;
  final int speedMbps;
  final String ovpnConfigBase64;
  final bool isVipLocked;

  VpnServer({
    required this.countryLong,
    required this.countryShort,
    required this.ip,
    required this.ping,
    required this.speedMbps,
    required this.ovpnConfigBase64,
    this.isVipLocked = false,
  });
}

class WakaHomeScreen extends StatefulWidget {
  const WakaHomeScreen({super.key});

  @override
  State<WakaHomeScreen> createState() => _WakaHomeScreenState();
}

class _WakaHomeScreenState extends State<WakaHomeScreen>
    with TickerProviderStateMixin {
  late OpenVPN _openVpnEngine;
  VPNStage _vpnStage = VPNStage.disconnected;
  VpnStatus? _vpnStatus;
  bool _isUserVip = false;

  RemoteAppConfig _remoteConfig = RemoteAppConfig(
    isSubscriptionEnabled: false,
    monthlyPricePkr: 350,
    announcementBanner: '',
  );

  List<VpnServer> _servers = [];
  VpnServer? _selectedServer;
  bool _isLoadingServers = true;

  final List<double> _wavePoints = List.generate(24, (_) => 0.12);
  Timer? _waveTimer;
  late AnimationController _orbController;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _initOpenVpnEngine();
    _initializeApp();
  }

  void _initOpenVpnEngine() {
    _openVpnEngine = OpenVPN(
      onVpnStatusChanged: (data) {
        if (!mounted) return;
        setState(() => _vpnStatus = data);
      },
      onVpnStageChanged: (stage, rawStage) {
        if (!mounted) return;
        setState(() => _vpnStage = stage);
        if (stage == VPNStage.connected) {
          HapticFeedback.heavyImpact();
          _startWaveAnimation();
        } else if (stage == VPNStage.disconnected) {
          _waveTimer?.cancel();
        }
      },
    );

    _openVpnEngine.initialize(
      groupIdentifier: "group.com.wakavpn.app",
      providerBundleIdentifier: "com.wakavpn.app.VPNExtension",
      localizedDescription: "WAKA VPN Shield",
    );
  }

  Future<void> _initializeApp() async {
    await _fetchRemoteConfig();
    await _fetchFreePublicServers();
  }

  Future<void> _fetchRemoteConfig() async {
    try {
      final response = await Supabase.instance.client
          .from('app_config')
          .select()
          .eq('id', 1)
          .single();
      setState(() {
        _remoteConfig = RemoteAppConfig.fromMap(response);
      });
    } catch (_) {}
  }

  Future<void> _fetchFreePublicServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final response = await http
          .get(Uri.parse('http://www.vpngate.net/api/iphone/'))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final lines = const LineSplitter().convert(response.body);
        final List<VpnServer> parsedServers = [];

        for (int i = 2; i < lines.length; i++) {
          final cols = lines[i].split(',');
          if (cols.length > 14 && cols[14].isNotEmpty) {
            final int speedBits = int.tryParse(cols[4]) ?? 15000000;
            final int pingMs = int.tryParse(cols[3]) ?? 42;
            parsedServers.add(
              VpnServer(
                countryLong: cols[5],
                countryShort: cols[6],
                ip: cols[1],
                ping: pingMs,
                speedMbps: max(1, (speedBits / 1000000).round()),
                ovpnConfigBase64: cols[14],
                isVipLocked: _remoteConfig.isSubscriptionEnabled &&
                    parsedServers.length < 3,
              ),
            );
          }
          if (parsedServers.length >= 20) break;
        }

        if (parsedServers.isNotEmpty) {
          setState(() {
            _servers = parsedServers;
            _selectedServer = parsedServers.first;
            _isLoadingServers = false;
          });
          return;
        }
      }
    } catch (_) {}

    setState(() => _isLoadingServers = false);
  }

  Future<void> _toggleVpnConnection() async {
    HapticFeedback.mediumImpact();
    await _fetchRemoteConfig();

    if (_vpnStage == VPNStage.disconnected) {
      if (_selectedServer == null) {
        await _fetchFreePublicServers();
        if (_selectedServer == null) return;
      }

      try {
        final String decodedConfig =
            utf8.decode(base64Decode(_selectedServer!.ovpnConfigBase64));

        _openVpnEngine.connect(
          decodedConfig,
          "WAKA VPN - ${_selectedServer!.countryLong}",
          username: "vpn",
          password: "vpn",
          certIsRequired: false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection failed, try another node')),
        );
      }
    } else {
      _openVpnEngine.disconnect();
      setState(() => _vpnStage = VPNStage.disconnected);
    }
  }

  void _startWaveAnimation() {
    final random = Random();
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _wavePoints.removeAt(0);
        _wavePoints.add(0.2 + random.nextDouble() * 0.75);
      });
    });
  }

  @override
  void dispose() {
    _orbController.dispose();
    _waveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _vpnStage == VPNStage.connected;
    final bool isConnecting =
        _vpnStage != VPNStage.disconnected && _vpnStage != VPNStage.connected;
    final Color primaryGlow = isConnected
        ? const Color(0xFF00F5D4)
        : (isConnecting ? const Color(0xFFFFBE0B) : const Color(0xFF3A86FF));

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
                isConnected
                    ? 'SECURE SHIELD ACTIVE'
                    : (isConnecting ? 'CONNECTING...' : 'TAP ORB TO CONNECT'),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: primaryGlow,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _vpnStatus?.duration ?? "00:00:00",
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
                      isConnected
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
                      return ListView.builder(
                        itemCount: _servers.length,
                        itemBuilder: (context, index) {
                          final s = _servers[index];
                          return ListTile(
                            title: Text(s.countryLong),
                            subtitle: Text('${s.speedMbps} Mbps • ${s.ping} ms'),
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
                        child: Text(
                          _selectedServer?.countryLong ?? 'Select Country',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
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
