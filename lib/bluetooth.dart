import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';


class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  _BluetoothScreenState createState() => _BluetoothScreenState();
}
class _BluetoothScreenState extends State<BluetoothScreen> {
  List<ScanResult> scanResults = [];
  List<BluetoothDevice> pairedDevices = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _getPairedDevices();
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }
  Future<void> _getPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluePlus.bondedDevices;
      setState(() {
        pairedDevices = devices;
      });
    } catch (e) {
      print('Error getting paired devices: $e');
    }
  }
  Future<void> _startScan() async {
    if (await FlutterBluePlus.isSupported == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth not supported')),
      );
      return;
    }

    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

    setState(() {
      isScanning = false;
    });
  }
  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );

      // Discover services after connection
      List<BluetoothService> services = await device.discoverServices();
      print('Discovered ${services.length} services');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }
  Future<void> _disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnected')),
      );
    }
  }

  Widget _buildPairedDevicesTab() {
    return Column(
      children: [
        // Connection status
        if (connectedDevice != null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.0),
            color: Colors.green,
            child: Text(
              'Connected to: ${connectedDevice!.platformName.isNotEmpty ? connectedDevice!.name : "Unknown Device"}',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // Paired devices header
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paired Devices (${pairedDevices.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _getPairedDevices,
                icon: Icon(Icons.refresh),
                label: Text('Refresh'),
              ),
            ],
          ),
        ),

        // Paired devices list
        Expanded(
          child: pairedDevices.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No paired devices found',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: pairedDevices.length,
            itemBuilder: (context, index) {
              final device = pairedDevices[index];
              final isConnected = connectedDevice == device;

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    Icons.bluetooth,
                    color: isConnected ? Colors.green : Colors.blue,
                  ),
                  title: Text(
                    device.platformName.isNotEmpty ? device.platformName : 'Unknown Device',
                    style: TextStyle(
                      fontWeight: isConnected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${device.remoteId}'),
                      Text('Status: ${isConnected ? "Connected" : "Paired"}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isConnected)
                        Chip(
                          label: Text('Connected'),
                          backgroundColor: Colors.green.withOpacity(0.2),
                          labelStyle: TextStyle(color: Colors.green),
                        ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isConnected ? _disconnect : () => _connectToDevice(device),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isConnected ? Colors.red : Colors.blue,
                        ),
                        child: Text(
                          isConnected ? 'Disconnect' : 'Connect',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
  Widget _buildScanResultsTab() {
    return Column(
      children: [
        // Control buttons
        Padding(
          padding: EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: isScanning ? null : _startScan,
                icon: Icon(isScanning ? Icons.hourglass_empty : Icons.search),
                label: Text(isScanning ? 'Scanning...' : 'Start Scan'),
              ),
              ElevatedButton.icon(
                onPressed: isScanning ? _stopScan : null,
                icon: Icon(Icons.stop),
                label: Text('Stop Scan'),
              ),
            ],
          ),
        ),

        // Scan results header
        if (scanResults.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Found ${scanResults.length} device(s)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        // Scan results
        Expanded(
          child: scanResults.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  isScanning ? 'Scanning for devices...' : 'No devices found\nTap "Start Scan" to search',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: scanResults.length,
            itemBuilder: (context, index) {
              final result = scanResults[index];
              final device = result.device;
              final isConnected = connectedDevice == device;
              final isPaired = pairedDevices.any((d) => d.id == device.id);

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    isPaired ? Icons.bluetooth_connected : Icons.bluetooth,
                    color: isConnected ? Colors.green : (isPaired ? Colors.orange : Colors.blue),
                  ),
                  title: Text(
                    device.name.isNotEmpty ? device.name : 'Unknown Device',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: ${device.id}'),
                      Text('RSSI: ${result.rssi} dBm'),
                      if (isPaired)
                        Text(
                          'Previously Paired',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: isConnected ? null : () => _connectToDevice(device),
                    child: Text(
                        isConnected ? 'Connected' : 'Connect'
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Select Bluetooth'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Paired Devices'),
              Tab(text: 'Scan Results'),
            ],
          ),
          actions: [
            if (connectedDevice != null)
              IconButton(
                icon: Icon(Icons.bluetooth_connected),
                onPressed: _disconnect,
              ),
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _getPairedDevices,
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildPairedDevicesTab(),
            _buildScanResultsTab(),
          ],
        ),
      ),
    );
  }
}


class BluetoothInteraction extends StatefulWidget {
  final BluetoothDevice device;

  const BluetoothInteraction({super.key, required this.device});

  @override
  _BluetoothInteractionState createState() => _BluetoothInteractionState();
}
class _BluetoothInteractionState extends State<BluetoothInteraction> {
  List<BluetoothService> services = [];

  @override
  void initState() {
    super.initState();
    _discoverServices();
  }

  Future<void> _discoverServices() async {
    services = await widget.device.discoverServices();
    setState(() {});
  }
  Future<void> _readCharacteristic(BluetoothCharacteristic characteristic) async {
    try {
      List<int> value = await characteristic.read();
      print('Read value: $value');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Read: ${value.toString()}')),
      );
    } catch (e) {
      print('Error reading characteristic: $e');
    }
  }
  Future<void> _writeCharacteristic(BluetoothCharacteristic characteristic) async {
    try {
      List<int> dataToWrite = [0x01, 0x02, 0x03]; // Example data
      await characteristic.write(dataToWrite);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data written successfully')),
      );
    } catch (e) {
      print('Error writing characteristic: $e');
    }
  }
  Future<void> _enableNotifications(BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);

      characteristic.value.listen((value) {
        print('Notification received: $value');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification: ${value.toString()}')),
        );
      });
    } catch (e) {
      print('Error enabling notifications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Device Services'),
      ),
      body: ListView.builder(
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          return ExpansionTile(
            title: Text('Service: ${service.uuid.toString()}'),
            children: service.characteristics.map((characteristic) {
              return ListTile(
                title: Text('Characteristic: ${characteristic.uuid.toString()}'),
                subtitle: Text('Properties: ${characteristic.properties.toString()}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (characteristic.properties.read)
                      IconButton(
                        icon: Icon(Icons.file_download),
                        onPressed: () => _readCharacteristic(characteristic),
                      ),
                    if (characteristic.properties.write)
                      IconButton(
                        icon: Icon(Icons.file_upload),
                        onPressed: () => _writeCharacteristic(characteristic),
                      ),
                    if (characteristic.properties.notify)
                      IconButton(
                        icon: Icon(Icons.notifications),
                        onPressed: () => _enableNotifications(characteristic),
                      ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}