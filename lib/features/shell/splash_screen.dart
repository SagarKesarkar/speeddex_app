import 'package:flutter/material.dart';

import '../../core/widgets/brand.dart';

/// Shown while the stored session is checked. No network work happens here.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Pinstripe()),
          Center(child: SdWordmark(size: 34)),
        ],
      ),
    );
  }
}
