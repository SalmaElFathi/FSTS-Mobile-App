import 'package:flutter/material.dart';
import '../screens/home.dart';
import '../screens/news_screen.dart';
import '../screens/contact_screen.dart';

class AppRoutes {
  static const String home = '/';
  static const String news = '/news';
  static const String contact = '/contact';

  static Map<String, WidgetBuilder> get routes => {
        home: (context) => const HomeScreen(),
        news: (context) => const NewsScreen(),
        contact: (context) => const ContactScreen(),
      };

  static List<String> get routeNames => [home, news, contact];
}
