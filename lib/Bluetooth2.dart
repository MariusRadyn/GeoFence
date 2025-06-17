import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothDeviceDropdown extends StatefulWidget {
  final Function(BluetoothDevice?)? onDeviceSelected;

  const BluetoothDeviceDropdown({
    Key? key,
    this.onDeviceSelected,
  }) : super(key: key);

  @override
  State<BluetoothDeviceDropdown> createState() => _BluetoothDeviceDropdownState();
}
class _BluetoothDeviceDropdownState extends State<BluetoothDeviceDropdown> {
  List<BluetoothDevice> pairedDevices = [];
  BluetoothDevice? selectedDevice;
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Check if Bluetooth is supported
      if (await FlutterBluePlus.isSupported == false) {
        setState(() {
          errorMessage = "Bluetooth not supported by this device";
          isLoading = false;
        });
        return;
      }

      // Request permissions
      await _requestPermissions();

      // Check if Bluetooth is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        setState(() {
          errorMessage = "Please turn on Bluetooth";
          isLoading = false;
        });
        return;
      }

      // Get bonded/paired devices
      await _loadPairedDevices();
    } catch (e) {
      setState(() {
        errorMessage = "Error initializing Bluetooth: $e";
        isLoading = false;
      });
    }
  }
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    // Check if any critical permissions were denied
    if (permissions[Permission.bluetoothConnect] != PermissionStatus.granted ||
        permissions[Permission.bluetoothScan] != PermissionStatus.granted) {
      throw Exception("Bluetooth permissions not granted");
    }
  }
  Future<void> _loadPairedDevices() async {
    try {
      // Get system devices (bonded/paired devices)
      List<BluetoothDevice> systemDevices = await FlutterBluePlus.bondedDevices;

      setState(() {
        pairedDevices = systemDevices;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Error loading paired devices: $e";
        isLoading = false;
      });
    }
  }
  Future<void> _refreshDevices() async {
    await _loadPairedDevices();
  }
  String _getDeviceDisplayName(BluetoothDevice device) {
    String name = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.toString();
    return "$name (${device.remoteId})";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDropdown(),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: isLoading ? null : _refreshDevices,
              icon: isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.refresh),
              tooltip: 'Refresh paired devices',
            ),
          ],
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (selectedDevice != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.bluetooth_connected, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected: ${_getDeviceDisplayName(selectedDevice!)}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdown() {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading paired devices...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 12),
            const Expanded(child: Text('Unable to load devices')),
          ],
        ),
      );
    }

    if (pairedDevices.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.grey),
            SizedBox(width: 12),
            Expanded(child: Text('No paired devices found')),
          ],
        ),
      );
    }

    return DropdownButtonFormField<BluetoothDevice>(
      value: selectedDevice,
      decoration: InputDecoration(
        labelText: 'Select Bluetooth Device',
        prefixIcon: const Icon(Icons.bluetooth),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      hint: const Text('Choose a paired device'),
      items: pairedDevices.map((BluetoothDevice device) {
        return DropdownMenuItem<BluetoothDevice>(
          value: device,
          child: Row(
            children: [
              Icon(
                Icons.bluetooth,
                size: 20,
                color: device.isConnected ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.platformName.isNotEmpty
                          ? device.platformName
                          : 'Unknown Device',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      device.remoteId.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (device.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Connected',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
      onChanged: (BluetoothDevice? device) {
        setState(() {
          selectedDevice = device;
        });
        if (widget.onDeviceSelected != null) {
          widget.onDeviceSelected!(device);
        }
      },
      isExpanded: true,
    );
  }
}

// Example usage widget
class BluetoothDeviceSelector extends StatefulWidget {
  @override
  State<BluetoothDeviceSelector> createState() => _BluetoothDeviceSelectorState();
}
class _BluetoothDeviceSelectorState extends State<BluetoothDeviceSelector> {
  BluetoothDevice? selectedDevice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Device Selector'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a Bluetooth Device',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            BluetoothDeviceDropdown(
              onDeviceSelected: (device) {
                setState(() {
                  selectedDevice = device;
                });
                if (device != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected: ${device.platformName}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 24),
            if (selectedDevice != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow('Name', selectedDevice!.platformName.isNotEmpty
                          ? selectedDevice!.platformName
                          : 'Unknown'),
                      _buildDetailRow('ID', selectedDevice!.remoteId.toString()),
                      _buildDetailRow('Status', selectedDevice!.isConnected
                          ? 'Connected'
                          : 'Paired'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}