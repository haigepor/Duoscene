Uri? apiEndpoint(
  String value, {
  required bool debug,
  bool allowLanHttp = false,
}) {
  final origin = Uri.tryParse(value);
  if (origin == null ||
      !origin.hasAuthority ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      (origin.path.isNotEmpty && origin.path != '/'))
    return null;
  final loopback = [
    '127.0.0.1',
    'localhost',
    '10.0.2.2',
    '::1',
  ].contains(origin.host);
  final parts = origin.host.split('.');
  final octets = parts.map(int.tryParse).toList();
  final private =
      parts.length == 4 &&
      parts.every((part) => RegExp(r'^(0|[1-9]\d{0,2})$').hasMatch(part)) &&
      octets.every((part) => part != null && part >= 0 && part <= 255) &&
      (octets[0] == 10 ||
          octets[0] == 192 && octets[1] == 168 ||
          octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31);
  return origin.scheme == 'https' ||
          debug &&
              (loopback || allowLanHttp && private) &&
              origin.scheme == 'http'
      ? origin
      : null;
}
