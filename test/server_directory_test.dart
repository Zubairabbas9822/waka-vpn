import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:waka_vpn/server_directory.dart';

void main() {
  String row({
    required String ip,
    required String country,
    required String profile,
    String operator = 'operator',
    String message = 'message',
  }) {
    final encoded = base64.encode(utf8.encode(profile));
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
      '"$operator"',
      '"$message"',
      encoded,
    ].join(',');
  }

  test('parses all valid rows and sorts them by country', () {
    final response = [
      '*vpn_servers',
      '#HostName,IP,Score,Ping,Speed,CountryLong,CountryShort,NumVpnSessions,Uptime,TotalUsers,TotalTraffic,LogType,Operator,Message,OpenVPN_ConfigData_Base64',
      row(
        ip: '198.51.100.2',
        country: 'Japan',
        profile: 'client\nremote 198.51.100.2 1194\n',
      ),
      row(
        ip: '198.51.100.1',
        country: 'Canada',
        profile: 'client\nremote 198.51.100.1 1194\n',
        operator: 'Operator, Inc.',
        message: 'reliable, fast server',
      ),
    ].join('\n');

    final servers = parseVpnGateResponse(response);

    expect(servers, hasLength(2));
    expect(servers.map((server) => server.country), ['Canada', 'Japan']);
    expect(servers.first.ip, '198.51.100.1');
  });

  test('skips rows without valid OpenVPN profiles', () {
    final response = [
      row(ip: '198.51.100.1', country: 'Canada', profile: 'not an ovpn profile'),
      'short,row',
      <String>[
        'host',
        '198.51.100.2',
        '1000',
        '20',
        '1000000',
        'Japan',
        'JP',
        '1',
        '1000',
        '10',
        '100000',
        '0',
        'operator',
        'message',
        '%%%invalid-base64%%%',
      ].join(','),
    ].join('\n');

    expect(parseVpnGateResponse(response), isEmpty);
  });

  test('returns an empty list for an empty response', () {
    expect(parseVpnGateResponse(''), isEmpty);
  });
}
