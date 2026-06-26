import 'dart:io';
import 'package:http/io_client.dart';

/// Cliente HTTP que omite la verificación SSL.
/// Solo usar en debug / desarrollo con ngrok u otras URLs de desarrollo.
IOClient createDevHttpClient() {
  final inner = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  return IOClient(inner);
}
