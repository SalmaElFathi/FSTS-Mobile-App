import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  final String message;
  
  const LoadingIndicator({
    Key? key,
    this.message = 'Chargement...',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}