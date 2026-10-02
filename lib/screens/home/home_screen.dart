import 'package:flutter/material.dart';

import '../../models/store.dart';

/// Main screen of the app for the selected [store]. Content comes later.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  /// Store chosen on the previous screen; `store.idStore` is used by
  /// future features.
  final Store store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(store.nameStore)),
      body: const SizedBox.expand(),
    );
  }
}
