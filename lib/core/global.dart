import 'package:bloret_launcher/services/bloriko.dart';

String get agentName => switch (Bloriko.type) {
  "bloriko" => "络可",
  "bloriko_r18" => "络可(R18)",
  _ => "Blora Agent",
};