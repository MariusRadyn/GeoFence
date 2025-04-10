import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geofence/utils.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({Key? key}) : super(key: key);

  @override
  _VehiclesPageState createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _addVehicle() {
    _showVehicleDialog();
  }
  void _editVehicle(DocumentSnapshot vehicle) {
    _showVehicleDialog(vehicle: vehicle);
  }
  void _deleteVehicle(QueryDocumentSnapshot vehicle) async {
    showDialog(
        context: context,
        builder: (context){
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(
                color: Colors.blue, // Border color
                width: 2, // Border width
              ),
            ),
            backgroundColor: APP_TILE_COLOR,
            shadowColor: Colors.black,
            title: const Text(
              "Delete",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              "${vehicle['name']}\n${vehicle['registrationNumber']}\n\nAre you sure?",
              style: const TextStyle(
                  color: Colors.grey,
                fontSize: 18,
              ),
            ),
            actions: [
              TextButton(
                child: const Text(
                  'No',
                  style: TextStyle(
                    color:  Colors.white,
                    fontFamily: "Poppins",
                    fontSize: 20,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                  child: const Text(
                    'Yes',
                    style: TextStyle(
                      color:  Colors.white,
                      fontFamily: "Poppins",
                      fontSize: 20,
                    ),
                  ),
                onPressed: () async {
                  User? user = _auth.currentUser;

                  await _firestore
                      .collection('users')
                      .doc(user?.uid)
                      .collection('vehicles')
                      .doc(vehicle.id)
                      .delete();

                  Navigator.pop(context);
                }
              ),
            ],
          );
        }
    );
  }
  void _showVehicleDialog({DocumentSnapshot? vehicle}) {
    TextEditingController nameController = TextEditingController(
        text: vehicle != null ? vehicle['name'] : '');
    TextEditingController fuelController = TextEditingController(
        text: vehicle != null ? vehicle['fuelConsumption'].toString() : '');
    TextEditingController regController = TextEditingController(
        text: vehicle != null ? vehicle['registrationNumber'] : '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(
              color: Colors.blue, // Border color
              width: 2, // Border width
            ),
          ),
          backgroundColor: APP_TILE_COLOR,
          shadowColor: Colors.black,
          title: Text(
            vehicle == null ? 'Add Vehicle' : 'Edit Vehicle',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Vehicle Name',
                    labelStyle: TextStyle(color: Colors.grey)
                ),

              ),
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
                controller: fuelController,
                decoration: const InputDecoration(
                    labelText: 'Fuel Consumption (L/100km)',
                    labelStyle: TextStyle(color: Colors.grey)
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),controller: regController,
                decoration: const InputDecoration(
                    labelText: 'Registration Number',labelStyle:
                    TextStyle(color: Colors.grey)
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:const Text(
                'Cancel',
                style: TextStyle(
                  color:  Colors.white70,
                  fontFamily: "Poppins",
                  fontSize: 20,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                User? user = _auth.currentUser;
                if (user != null) {
                  if (vehicle == null) {
                    // Add new vehicle
                    await _firestore
                        .collection('users')
                        .doc(user.uid)
                        .collection('vehicles')
                        .add({
                      'name': nameController.text,
                      'fuelConsumption': double.parse(fuelController.text),
                      'registrationNumber': regController.text,
                    });
                  } else {
                    // Update existing vehicle
                    await _firestore
                        .collection('users')
                        .doc(user.uid)
                        .collection('vehicles')
                        .doc(vehicle.id)
                        .update({
                      'name': nameController.text,
                      'fuelConsumption': double.parse(fuelController.text),
                      'registrationNumber': regController.text,
                    });
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(
                vehicle == null ? 'Add' : 'Update',
                style: const TextStyle(
                  color:  Colors.white70,
                  fontFamily: "Poppins",
                  fontSize: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: APP_BAR_COLOR,
        foregroundColor: Colors.white,
        title: MyAppbarTitle('Vehicles'),
      ),
      body: Container(
        color: APP_BACKGROUND_COLOR,
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .doc(user?.uid)
              .collection('vehicles')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }

            var vehicles = snapshot.data!.docs;
            if (vehicles.isEmpty) {
              return const Center(
                  child: Text(
                      "No vehicles found",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 20,
                    ),
                  ),
              );
            }

            return ListView.builder(
              itemCount: vehicles.length,
              itemBuilder: (context, index) {
                var vehicle = vehicles[index];
                return Column(
                  children: [
                    SizedBox(height: 20,),

                    MyVehicleTile(
                      text: vehicle['name'],
                      subtext: 'Fuel Consumption: ${vehicle['fuelConsumption']} L/100km\nRegistration: ${vehicle['registrationNumber']}',
                      onTapEdit: (){
                        _editVehicle(vehicle);
                      },
                      onTapDelete: (){
                        _deleteVehicle(vehicle);
                      } ,
                    ),
                    SizedBox(height: 1,)
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: COLOR_ORANGE,
        onPressed: _addVehicle,
        child: Icon(Icons.add,color: Colors.white,),
      ),
    );
  }
}