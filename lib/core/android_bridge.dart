import 'dart:io';

import 'package:flutter/services.dart';

const methodChannel = MethodChannel("com.xxyxxdmc.bloret_launcher");

Future<void> setNightIcon(bool night) async {
  if (!Platform.isAndroid) return;
  await methodChannel.invokeMethod(
    'changeIcon',
    {
      'isNight': night,
    },
  );
}