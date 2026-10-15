import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waka_vpn/server_directory.dart';

void main() {
  test('country picker data includes every country returned by the directory', () {
    String row(String ip, String country) {
      final profile = base64.encode(
        utf8.encode('client\nremote $ip 1194\n'),
      );
      return <String>[
        'host-$ip',
        ip,
        '1000',
        '20',
        '1000000',
        country,
        'XX',
        '1',
        '1000',
        '10',
        '100000',
        '0',
        'operator',
        'message',
        profile,
      ].join(',');
    }

    final servers = parseVpnGateResponse([
      row('198.51.100.1', 'France'),
      row('198.51.100.2', 'United States'),
    ].join('\n'));
    final countries = servers.map((server) => server.country).toSet();

    expect(countries, containsAll(['France', 'United States']));
  });
}
