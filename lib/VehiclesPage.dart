import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({Key? key}) : super(key: key);

  @override
  _VehiclesPageState createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            //return const Center(child: Text("No vehicles found"));
          }

          return ListView.builder(
            itemCount: vehicles.length,
            itemBuilder: (context, index) {
              var vehicle = vehicles[index];
              return ListTile(
                title: Text(vehicle['name']),
                subtitle: Text(
                    'Fuel Consumption: ${vehicle['fuelConsumption']} L/100km\nRegistration: ${vehicle['registrationNumber']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () => _editVehicle(vehicle),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () => _deleteVehicle(vehicle.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addVehicle,
        child: Icon(Icons.add),
      ),
    );
  }

  void _addVehicle() {
    _showVehicleDialog();
  }

  void _editVehicle(DocumentSnapshot vehicle) {
    _showVehicleDialog(vehicle: vehicle);
  }
  void _deleteVehicle(String vehicleId) async {
    User? user = _auth.currentUser;
    await _firestore
        .collection('users')
        .doc(user?.uid)
        .collection('vehicles')
        .doc(vehicleId)
        .delete();
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
          title: Text(vehicle == null ? 'Add Vehicle' : 'Edit Vehicle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Vehicle Name'),
              ),
              TextField(
                controller: fuelController,
                decoration: InputDecoration(labelText: 'Fuel Consumption (L/100km)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: regController,
                decoration: InputDecoration(labelText: 'Registration Number'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
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
              child: Text(vehicle == null ? 'Add' : 'Update'),
            ),
          ],
        );
      },
    );
  }
}