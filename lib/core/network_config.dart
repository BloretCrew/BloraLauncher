import 'dart:io';
import '../services/config_service.dart';

class BloraHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    
    // Set connection timeout globally
    client.connectionTimeout = const Duration(seconds: 15);
    
    final proxy = ConfigService.get("proxy") as String?;
    if (proxy != null && proxy.isNotEmpty) {
      client.findProxy = (uri) {
        // Example proxy: http://127.0.0.1:7890 or 127.0.0.1:7890
        String effectiveProxy = proxy;
        if (proxy.startsWith("http://")) {
          effectiveProxy = proxy.replaceFirst("http://", "");
        } else if (proxy.startsWith("https://")) {
          effectiveProxy = proxy.replaceFirst("https://", "");
        }
        return "PROXY $effectiveProxy; DIRECT";
      };
      
      // Allow self-signed certificates if proxy is enabled (common for debugging proxies)
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    }
    
    return client;
  }
}
