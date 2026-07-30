import 'package:flutter/material.dart';

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
    // TODO: Backend.getLaunchItemsSortedByPlayTime()
    setState(() {
      launchItems = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(
          left: 32,
          right: 16,
          top: 16,
          bottom: 16,
        ),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 8),
            child: Text(
              "核心",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 8, bottom: 10),
            child: Text(
              "右键单击启动项可进行管理。",
              style: TextStyle(
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
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "暂无核心",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "下载 Minecraft 核心或添加自定义启动项",
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
                  child: Row(
                    children: [
                      // 原来的内容
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