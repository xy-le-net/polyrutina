import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectedTabProvider = NotifierProvider<SelectedTabController, int>(
  SelectedTabController.new,
);

class SelectedTabController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int tab) {
    state = tab;
  }
}
