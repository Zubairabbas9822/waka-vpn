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

  // Replace with your Supabase Project URL and Anon Key
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
  final int freeDailyLimitMinutes;
  final String announcementBanner;

  RemoteAppConfig({
    required this.isSubscriptionEnabled,
    required this.monthlyPricePkr,
    required this.freeDailyLimitMinutes,
    required this.announcementBanner,
  });

  factory RemoteAppConfig.fromMap(Map<String, dynamic> map) {
    return RemoteAppConfig(
      isSubscriptionEnabled: map['is_subscription_enabled'] ?? false,
      monthlyPricePkr: map['monthly_price_pkr'] ?? 350,
      freeDailyLimitMinutes: map['free_daily_limit_minutes'] ?? 0,
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
    freeDailyLimitMinutes: 0,
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
      localizedDescription: "WAKA VPN Quantum Shield",
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
    } catch (_) {
      // Keeps running in 100% Free Mode if Supabase is offline/unconfigured
    }
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
            _selectedServer = parsedServers.firstWhere(
              (s) => !s.isVipLocked,
              orElse: () => parsedServers.first,
            );
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

      if (_remoteConfig.isSubscriptionEnabled &&
          _selectedServer!.isVipLocked &&
          !_isUserVip) {
        _showVipPaywallModal();
        return;
      }

      try {
        final String decodedOvpnConfig =
            utf8.decode(base64Decode(_selectedServer!.ovpnConfigBase64));

        _openVpnEngine.connect(
          decodedOvpnConfig,
          "WAKA VPN - ${_selectedServer!.countryLong}",
          username: "vpn",
          password: "vpn",
          certIsRequired: false,
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Refreshing node configuration, tap again...')),
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

  void _showVipPaywallModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: const Color(0xFF0E131F).withOpacity(0.95),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                color: const Color(0xFF00F5D4).withOpacity(0.35),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F5D4), Color(0xFF7B2CBF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'WAKA VIP PASS',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Unlock Ultra-Fast Global Nodes',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Zero speed limits, dedicated low-ping gaming servers, and unlimited encrypted bandwidth.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00F5D4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WAKA Monthly Pro',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Instant activation • Cancel anytime',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Rs. ${_remoteConfig.monthlyPricePkr}/mo',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00F5D4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Activate VIP — Rs. ${_remoteConfig.monthlyPricePkr}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryGlow.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7B2CBF).withOpacity(0.15),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
            child: const SizedBox.expand(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primaryGlow,
                              boxShadow: [
                                BoxShadow(color: primaryGlow, blurRadius: 10)
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'WAKA VPN',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                      if (_remoteConfig.isSubscriptionEnabled)
                        GestureDetector(
                          onTap: _showVipPaywallModal,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00F5D4), Color(0xFF7B2CBF)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'VIP • Rs.${_remoteConfig.monthlyPricePkr}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Text(
                            '100% FREE GLOBAL',
                            style: TextStyle(
                              color: Color(0xFF00F5D4),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_remoteConfig.announcementBanner.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        _remoteConfig.announcementBanner,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    isConnected
                        ? 'WAKA SHIELD ACTIVE'
                        : (isConnecting
                            ? 'CONNECTING (${_vpnStage.name.toUpperCase()})...'
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
                    child: AnimatedBuilder(
                      animation: _orbController,
                      builder: (context, child) {
                        final double pulse =
                            1.0 + (_orbController.value * 0.08);
                        return Transform.scale(
                          scale: pulse,
                          child: Container(
                            width: 190,
                            height: 190,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                 