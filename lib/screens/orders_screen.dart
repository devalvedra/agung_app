import 'package:flutter/material.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Colors.orange,
      ),
      body: const Center(
        child: Text('Orders Screen', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
