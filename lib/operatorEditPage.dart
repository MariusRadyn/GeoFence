import 'package:flutter/material.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';

class OperatorEditPage extends StatefulWidget {
  OperatorData? operatorData;

  OperatorEditPage({
    required operatorData,
    super.key
  });

  @override
  State<OperatorEditPage> createState() => _OperatorEditPageState();
}

class _OperatorEditPageState extends State<OperatorEditPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return  Consumer<OperatorService>(
      builder: (_, operatorService, __) {
        return Scaffold(
          backgroundColor: APP_BACKGROUND_COLOR,
          appBar: AppBar(
            backgroundColor: APP_BAR_COLOR,
            foregroundColor: Colors.white,
            title: MyAppbarTitle('Operator'),
          ),
          bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedIndex,
              backgroundColor: APP_BAR_COLOR,
              unselectedItemColor: Colors.grey,
              selectedItemColor: Colors.grey,
              onTap: (index) {
                setState(() => _selectedIndex = index);
                if(index == 0) ;
                if(index == 1) Navigator.pop(context);
              },
              items: [
                // Save Button
                BottomNavigationBarItem(
                    icon: Icon(Icons.save),
                    label: 'Save',
                    backgroundColor: Colors.grey
                ),

                // Cancel Button
                BottomNavigationBarItem(
                  icon: Icon(Icons.cancel_outlined),
                  label: 'Cancel',
                  backgroundColor: Colors.grey,
                ),
              ]
          ),
          body: SafeArea(
            child: // Avatar
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        // Navigation logic could go here
                      },
                      child: CircleAvatar(
                        radius: 55,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          backgroundImage: (widget.operatorData!.photoURL.isEmpty ?? true)
                              ? AssetImage(IMAGE_PROFILE)
                              : NetworkImage(widget.operatorData!.photoURL) as ImageProvider,
                          radius: 50,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
  }
}
