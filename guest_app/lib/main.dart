import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'screens/guest_registration_screen.dart';

void main() {
  runApp(const GuestApp());
}

class GuestApp extends StatelessWidget {
  const GuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      // Same design base as the main Essential Homes app (360×800 dp)
      designSize: const Size(360, 800),
      minTextAdapt: true,
      builder: (context, child) => MaterialApp(
        title: 'EH Guest',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D1B2A)),
          useMaterial3: true,
        ),
        home: const GuestRegistrationScreen(),
      ),
    );
  }
}
