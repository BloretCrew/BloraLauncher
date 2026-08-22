import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../services/config_service.dart';

class BloraHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    return _configureClient(client);
  }

  static HttpClient _configureClient(HttpClient client) {
    client.connectionTimeout = const Duration(seconds: 15);

    final proxy = ConfigService.get("proxy") as String?;
    if (proxy != null && proxy.isNotEmpty) {
      client.findProxy = (uri) {
        String effectiveProxy = proxy;
        if (proxy.startsWith("http://")) {
          effectiveProxy = proxy.replaceFirst("http://", "");
        } else if (proxy.startsWith("https://")) {
          effectiveProxy = proxy.replaceFirst("https://", "");
        }
        return "PROXY $effectiveProxy; DIRECT";
      };

      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    } else {
      client.findProxy = null;
    }

    return client;
  }

  static void applyToDio(Dio dio) {
    final _ = ConfigService.get("proxy") as String?;
    if (dio.httpClientAdapter is IOHttpClientAdapter) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        return _configureClient(client);
      };
    }
  }
}