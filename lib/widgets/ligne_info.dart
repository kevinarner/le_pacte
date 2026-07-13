import 'package:flutter/material.dart';

class LigneInfo extends StatelessWidget {
  final String label;
  final String valeur;
  const LigneInfo({super.key, required this.label, required this.valeur});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(valeur, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
