import 'dart:io';
import 'package:flutter/material.dart';
import '../core/i18n.dart';

class CoresPage extends StatefulWidget {
  const CoresPage({super.key});

  @override
  State<CoresPage> createState() => _CoresPageState();
}

class _CoresPageState extends State<CoresPage> {
  List<dynamic> launchItems = [];

  @override
  void initState() {
    super.initState();
    refreshLaunchItems();
  }

  void refreshLaunchItems() {
    setState(() {
      launchItems = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.only(
          left: Platform.isAndroid ? 16 : 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: Text(
              "Cores".tl,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8, bottom: 10),
            child: Text(
              "Right-click on launch items to manage.".tl,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          if (launchItems.isEmpty)
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "No cores found".tl,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Download Minecraft cores or add custom launch items".tl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...launchItems.map((item) {
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onSecondaryTap: () {

                },
                child: Container(
                  height: 60,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
