import 'package:flutter/material.dart';


// The top appbar
class CustomBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
          margin: const EdgeInsets.only(top: 12.0, left: 8.0, right: 8.0),

        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CampusBite',style: TextStyle(
                    color: Color.fromARGB(255, 1, 167, 53),
                    letterSpacing: .5,
                    fontSize: 20,
                    fontStyle: FontStyle.normal,
                  ),
                ),
              IconButton(onPressed: () { 
            Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => Notify(),
                ),
                );
                }, icon: Icon(Icons.notifications)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(60.0);
}


// notification screen
class Notify extends StatelessWidget {
  const Notify({super.key});

  @override
  Widget build(BuildContext context) {
   return Scaffold(
      appBar: AppBar(title: Text('Notifications'),),
    );
  }
}