import 'package:flutter/material.dart';
import 'config.dart';

class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('DEBUG: NewsPage build');
    return Scaffold(
      appBar: AppBar(
        title: const Text('News'),
        backgroundColor: Colors.red,
      ),
      body: const Center(
        child: Text(
          'News & Updates',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}