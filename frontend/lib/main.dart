import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'screens/home.dart' ;
import 'screens/all_news_screen.dart';
import 'screens/contact_screen.dart' ;
import 'widgets/bottom_nav_bar.dart';
import 'providers/navigation_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb && Platform.isAndroid) {
    HttpOverrides.global = MyHttpOverrides();
  }
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    
    if (!kIsWeb) {
      client.connectionTimeout = const Duration(seconds: 30);
    }
    
    return client;
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'FST Assistant',
      theme: ThemeData.light().copyWith(
        primaryColor: const Color(0xFFE65100),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFE65100),
          secondary: Color(0xFFFF8F00),
        ),
      ),
      home: const MainNavigationWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationWrapper extends ConsumerWidget {
  const MainNavigationWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationIndexProvider);
    
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
           HomeScreen(),
           AllNewsScreen(),
           ContactScreen(),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}
