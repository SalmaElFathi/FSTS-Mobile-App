import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:salomon_bottom_bar/salomon_bottom_bar.dart';
import '../providers/navigation_provider.dart';
import '../providers/theme_provider.dart';

class BottomNavBar extends ConsumerStatefulWidget {
  const BottomNavBar({Key? key}) : super(key: key);

  @override
  ConsumerState createState() => _BottomNavBarState();
}

class _BottomNavBarState extends ConsumerState {
  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(navigationIndexProvider);
    final isDarkMode = ref.watch(themeProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: isDarkMode ? Colors.black26 : Colors.grey.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SalomonBottomBar(
        currentIndex: currentIndex,
        onTap: (index) {
          ref.read(navigationIndexProvider.notifier).setIndex(index);
        },
        itemPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 14,
        ),
        unselectedItemColor: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade600,
        items: [
          /// Accueil
          SalomonBottomBarItem(
            icon: const Icon(Icons.home_outlined, size: 24),
            title: const Text(
              "Accueil", 
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            selectedColor: isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
          ),

          /// Actualités
          SalomonBottomBarItem(
            icon: const Icon(Icons.article_outlined, size: 24),
            title: const Text(
              "Actualités", 
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            selectedColor: isDarkMode ? Colors.indigoAccent : const Color(0xFFE65100),
          ),

          /// Contact
          SalomonBottomBarItem(
            icon: const Icon(Icons.contact_mail_outlined, size: 24),
            title: const Text(
              "Contact", 
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            selectedColor: isDarkMode ? Colors.indigoAccent:  const Color(0xFFE65100),
          ),
        ],
      ),
    );
  }
}