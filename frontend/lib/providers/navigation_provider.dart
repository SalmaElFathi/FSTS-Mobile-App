import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavigationNotifier extends StateNotifier<int> {
  NavigationNotifier() : super(0);

  void setIndex(int index) {
    state = index;
  }
}

final navigationIndexProvider = StateNotifierProvider<NavigationNotifier, int>((ref) {
  return NavigationNotifier();
});