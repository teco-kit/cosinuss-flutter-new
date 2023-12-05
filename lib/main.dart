import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Cosinuss° One - Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _connectionStatus = "Disconnected";
  String _heartRate = "- bpm";
  String _bodyTemperature = '- °C';

  String _accX = "-";
  String _accY = "-";
  String _accZ = "-";

  String _ppgGreen = "-";
  String _ppgRed = "-";
  String _ppgAmbient = "-";

  bool _isConnected = false;

  bool earConnectFound = false;

  void updateHeartRate(rawData) {
    Uint8List bytes = Uint8List.fromList(rawData);
    
    // based on GATT standard
    var bpm = bytes[1];
    if (!((bytes[0] & 0x01) == 0)) {
        bpm = (((bpm >> 8) & 0xFF) | ((bpm << 8) & 0xFF00));
    }

    var bpmLabel = "- bpm";
    if (bpm != 0) {
      bpmLabel = bpm.toString() + " bpm";
    }

    setState(() {
      _heartRate = bpmLabel;
    });
  }

  void updateBodyTemperature(rawData) {
    var flag = rawData[0];

    // based on GATT standard
    double temperature = twosComplimentOfNegativeMantissa(((rawData[3] << 16) | (rawData[2] << 8) | rawData[1]) & 16777215) / 100.0;
    if ((flag & 1) != 0) {
      temperature = ((98.6 * temperature) - 32.0) * (5.0 / 9.0); // convert Fahrenheit to Celsius
    }

    setState(() {
      _bodyTemperature = temperature.toString() + " °C"; // todo update body temp
    });
  }

  void updatePPGRaw(rawData) {
    Uint8List bytes = Uint8List.fromList(rawData);
    
    // corresponds to the raw reading of the PPG sensor from which the heart rate is computed
    // 
    // example plot https://e2e.ti.com/cfs-file/__key/communityserver-discussions-components-files/73/Screen-Shot-2019_2D00_01_2D00_24-at-19.30.24.png 
    // (image just for illustration purpose, obtained from a different sensor! Sensor value range differs.)

    var ppg_red = bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 32; // raw green color value of PPG sensor
    var ppg_green = bytes[4] | bytes[5] << 8 | bytes[6] << 16 | bytes[7] << 32; // raw red color value of PPG sensor

    var ppg_green_ambient = bytes[8] | bytes[9] << 8 | bytes[10] << 16 | bytes[11] << 32; // ambient light sensor (e.g., if sensor is not placed correctly)
  
    setState(() {
      _ppgGreen = ppg_red.toString() + " (unknown unit)";
      _ppgRed = ppg_green.toString() + " (unknown unit)";
      _ppgAmbient = ppg_green_ambient.toString() + " (unknown unit)";
    });
  }

  void updateAccelerometer(rawData) {
    Int8List bytes = Int8List.fromList(rawData);

    // description based on placing the earable into your right ear canal
    int acc_x = bytes[14];
    int acc_y = bytes[16];
    int acc_z = bytes[18];

    setState(() {
      _accX = acc_x.toString() + " (unknown unit)";
      _accY = acc_y.toString() + " (unknown unit)";
      _accZ = acc_z.toString() + " (unknown unit)";
    });
  }

  int twosComplimentOfNegativeMantissa(int mantissa) {
    if ((4194304 & mantissa) != 0) {
      return (((mantissa ^ -1) & 16777215) + 1) * -1;
    }

    return mantissa;
  }

  void _connect() {


    // start scanning
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));

    // listen to scan results
    var subscription = FlutterBluePlus.scanResults.listen((results) async {

      // do something with scan results
      for (ScanResult r in results) {
        if (r.device.name == "earconnect" && !earConnectFound) {
          earConnectFound = true; // avoid multiple connects attempts to same device

          await FlutterBluePlus.stopScan();

          r.device.state.listen((state) { // listen for connection state changes
            setState(() {
              _isConnected = state == BluetoothDeviceState.connected;
              _connectionStatus = (_isConnected) ? "Connected" : "Disconnected";
            });
          });

          await r.device.connect();

          var services = await r.device.discoverServices();

          for (var service in services) { // iterate over services
            for (var characteristic in service.characteristics) { // iterate over characterstics
              switch (characteristic.uuid.toString()) {
                case "0000a001-1212-efde-1523-785feabcd123":
                  print("Starting sampling ...");
                  await characteristic.write([0x32, 0x31, 0x39, 0x32, 0x37, 0x34, 0x31, 0x30, 0x35, 0x39, 0x35, 0x35, 0x30, 0x32, 0x34, 0x35]);
                  await Future.delayed(new Duration(seconds: 2)); // short delay before next bluetooth operation otherwise BLE crashes
                  characteristic.value.listen((rawData) => {
                    updateAccelerometer(rawData),
                    updatePPGRaw(rawData)
                  });
                  await characteristic.setNotifyValue(true);
                  await Future.delayed(new Duration(seconds: 2));
                  break;

                case "00002a37-0000-1000-8000-00805f9b34fb":
                  characteristic.value.listen((rawData) => {
                    updateHeartRate(rawData)
                  });
                  await characteristic.setNotifyValue(true);
                  await Future.delayed(new Duration(seconds: 2)); // short delay before next bluetooth operation otherwise BLE crashes
                  break;

                case "00002a1c-0000-1000-8000-00805f9b34fb":
                  characteristic.value.listen((rawData) => {
                    updateBodyTemperature(rawData)
                  });
                  await characteristic.setNotifyValue(true);
                  await Future.delayed(new Duration(seconds: 2)); // short delay before next bluetooth operation otherwise BLE crashes
                  break;
              }
            };
          };
        }
        
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(children: [
              const Text(
              'Status: ',
              ),
              Text(
                '$_connectionStatus'
              ),
            ]),
            Row(children: [
              const Text(
                'Heart Rate: '
              ), 
              Text(
                '$_heartRate'
              ),
            ]),
            Row(children: [
              const Text(
                'Body Temperature: '
              ), 
              Text(
                '$_bodyTemperature'
              ),
            ]),
            Row(children: [
              const Text(
                'Accelerometer X: '
              ), 
              Text(
                '$_accX'
              ),
            ]),
            Row(children: [
              const Text(
                'Accelerometer Y: '
              ), 
              Text(
                '$_accY'
              ),
            ]),
            Row(children: [
              const Text(
                'Accelerometer Z: '
              ), 
              Text(
                '$_accZ'
              ),
            ]),
            Row(children: [
              const Text(
                'PPG Raw Red: '
              ), 
              Text(
                '$_ppgRed'
              ),
            ]),
            Row(children: [
              const Text(
                'PPG Raw Green: '
              ), 
              Text(
                '$_ppgGreen'
              ),
            ]),
            Row(children: [
              const Text(
                'PPG Ambient: '
              ), 
              Text(
                '$_ppgAmbient'
              ),
            ]),
            Row(children: [
              const Text(
                '\nNote: You have to insert the earbud in your  \n ear in order to receive heart rate values.'
              )
            ]),
            Row(children: [
              const Text(
                '\nNote: Accelerometer and PPG have unknown units. \n They were reverse engineered. \n Use with caution!'
              )
            ]),
          ],
        ),
        ),
      ),
      floatingActionButton: Visibility(visible: !_isConnected, 
        child: FloatingActionButton(
          onPressed: _connect,
          tooltip: 'Increment',
          child: const Icon(Icons.bluetooth_searching_sharp),
        ),
       ),
    );
  }
}
