import 'package:flutter/material.dart';
import '../widgets/verified_badge.dart';

class UserName extends StatelessWidget {
  final String name;
  final String role;

  const UserName({
    Key? key,
    required this.name,
    required this.role,
  }) : super(key: key);

  bool get isTipster => role == "tipster";

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name),
        VerifiedBadge(show: isTipster),
      ],
    );
  }
}
