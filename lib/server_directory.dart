import 'dart:convert';

class VpnServer {
  const VpnServer(this.country, this.ip, this.config);

  final String country;
  final String ip;
  final String config;
}

/// Parses the CSV response returned by VPN Gate's iPhone API.
///
/// The API includes comment/header lines and may contain malformed or stale
/// rows. Invalid profiles are skipped instead of reaching the VPN plugin.
List<VpnServer> parseVpnGateResponse(String response) {
  final servers = <VpnServer>[];
  final validBase64 = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
  final hasRemoteDirective = RegExp(r'^\s*remote\s+\S+', multiLine: true);

  for (final rawLine in const LineSplitter().convert(response)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('*')) {
      continue;
    }

    final columns = _parseCsvLine(line);
    if (columns.length < 15) continue;

    final ip = columns[1].trim();
    final country = columns[5].trim();
    final encodedConfig = columns[14].trim();
    if (ip.isEmpty || country.isEmpty || encodedConfig.isEmpty) continue;
    if (encodedConfig.length > 512 * 1024 ||
        !validBase64.hasMatch(encodedConfig) ||
        encodedConfig.length % 4 == 1) {
      continue;
    }

    try {
      final profile = utf8.decode(
        base64.decode(base64.normalize(encodedConfig)),
        allowMalformed: false,
      );
      if (profile.length > 256 * 1024 ||
          !hasRemoteDirective.hasMatch(profile)) {
        continue;
      }
    } on FormatException {
      continue;
    }

    servers.add(VpnServer(country, ip, encodedConfig));
  }

  servers.sort((a, b) {
    final countryOrder = a.country.toLowerCase().compareTo(b.country.toLowerCase());
    return countryOrder != 0 ? countryOrder : a.ip.compareTo(b.ip);
  });
  return servers;
}

List<String> _parseCsvLine(String line) {
  final fields = <String>[];
  final field = StringBuffer();
  var insideQuotes = false;

  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == '"') {
      if (insideQuotes && index + 1 < line.length && line[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        insideQuotes = !insideQuotes;
      }
    } else if (character == ',' && !insideQuotes) {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(character);
    }
  }

  if (insideQuotes) return const [];
  fields.add(field.toString());
  return fields;
}
