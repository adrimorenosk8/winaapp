import 'package:flutter/material.dart';

class VerifiedBadge extends StatelessWidget {
  final bool show;

  const VerifiedBadge({Key? key, required this.show}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(left: 4.0),
      child: Icon(Icons.verified, color: Colors.green, size: 18),
    );
  }
}
