import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class WakaHomeScreen extends StatefulWidget {
  const WakaHomeScreen({super.key});

  @override
  State<WakaHomeScreen> createState() => _WakaHomeScreenState();
}

class _WakaHomeScreenState extends State<WakaHomeScreen> {
  bool _isConnected = false;

  void _toggleConnection() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isConnected = !_isConnected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color glowColor = _isConnected ? const Color(0xFF00F5D4) : const Color(0xFF3A86FF);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'WAKA VPN',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isConnected ? 'SECURE TUNNEL ACTIVE' : 'DISCONNECTED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: glowColor,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 60),
              Center(
                child: GestureDetector(
                  onTap: _toggleConnection,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          glowColor.withOpacity(0.4),
                          const Color(0xFF0A0E1A),
                        ],
                      ),
                      border: Border.all(
                        color: glowColor,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _isConnected ? Icons.shield_rounded : Icons.power_settings_new_rounded,
                        size: 70,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 60),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Selected Node', style: TextStyle(color: Colors.white54)),
                    Text('United States (US)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F5D4))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
