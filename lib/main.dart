import 'package:flutter/material.dart';


void main(){


  runApp(Align(
    alignment: Alignment(0.5, -0.5 ),
    child: Text(
      'INIT?',
      textDirection: TextDirection.ltr,
      style: TextStyle(fontSize: 48),
    )

  )
  );
}