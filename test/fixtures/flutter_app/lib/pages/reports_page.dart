import 'package:flutter/material.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final TextEditingController _search;
  bool isPro = false;

  @override
  void initState() {
    super.initState();
    if (!isPro) {
      return;
    }
    _search = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
        children: [Text(l10n.home_badge), TextField(controller: _search)]);
  }
}
