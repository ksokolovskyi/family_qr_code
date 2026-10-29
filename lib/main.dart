import 'package:family_qr_code/qr/family_qr_code.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family QR Code',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(
        backgroundColor: Color(0xFF090909),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: FamilyQrCode(
              size: 300,
              data: '0x0000000000000000000000000000000000000000',
              minVersion: 4,
            ),
          ),
        ),
      ),
    );
  }
}
