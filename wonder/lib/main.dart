import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart'
    show rootBundle; // Import for loading assets
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for async main
  await Config.load(); // Load API keys from config.json
  runApp(const MyApp());
}

// Config class to load API keys from config.json
class Config {
  static String openAiApiKey = '';
  static String googleDirectionsApiKey = '';

  static Future<void> load() async {
    final String jsonString = await rootBundle.loadString('assets/config.json');
    final Map<String, dynamic> jsonData = json.decode(jsonString);
    openAiApiKey = jsonData['openAiApiKey'];
    googleDirectionsApiKey = jsonData['googleDirectionsApiKey'];
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wonder',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.tealAccent,
          secondary: Colors.cyanAccent,
        ),
        scaffoldBackgroundColor: const Color(0xFF101010),
        // A dark gray background
        appBarTheme: const AppBarTheme(color: Color(0xFF1F1F1F)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.tealAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  // Recognized speech text
  String _recognizedText = '';

  String _lastRecognizedText = "";

  // Raw response from OpenAI
  String _openAiResponse = '';

  // List of locations from OpenAI
  List<Map<String, dynamic>> _locations = [];

  // Map objects
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  GoogleMapController? _mapController;
  Position? _currentPosition;

  // Add this as a state variable
  final TextEditingController _textController = TextEditingController();

  final DraggableScrollableController _bottomSheetController =
      DraggableScrollableController();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false; // Track if TTS is speaking

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _getCurrentLocation();
  }

  // ✅ Function to get current location
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // ✅ Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

    // ✅ Check for permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permission denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint(
          'Location permissions are permanently denied. Cannot access location.');
      return;
    }

    _bottomSheetController.animateTo(
      0.2, // Collapse to minimum size
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    // ✅ Get current position
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = position;
      _markers.add(
        Marker(
          markerId: const MarkerId("current_location"),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: "You are here"),
        ),
      );

      // ✅ Move camera to current location
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          14.0, // Zoom level
        ),
      );
    });
  }

  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (error) => debugPrint('Speech error: $error'),
      onStatus: (status) {
        setState(() {
          _isListening = (status == 'listening');
        });
      },
    );
    setState(() {});
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) return;
    await _speechToText.listen(
      onResult: _onSpeechResult,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(seconds: 60),
      partialResults: true,
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    String newText = result.recognizedWords;

    if (newText.length > _lastRecognizedText.length) {
      String appendedText = newText.substring(_lastRecognizedText.length);
      setState(() {
        _recognizedText += " " + appendedText.trim(); // Append new words only
        _textController.text = _recognizedText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(
              offset: _textController.text.length), // Keep cursor at the end
        );
      });
    }

    _lastRecognizedText = newText; // Update last recognized text
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
  }

  Future<void> _speakText(String text) async {
    if (text.isEmpty) return;

    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0); // Normal pitch
    await _flutterTts.setSpeechRate(0.5); // Normal speed

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false; // Reset state when speaking is done
      });
    });

    setState(() {
      _isPlaying = true;
    });

    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isPlaying = false;
    });
  }

  void _onMarkerTapped(String name) async {
    _bottomSheetController.animateTo(
      0.7, // Fully expanded
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    setState(() {
      _openAiResponse = 'Loading...'; // Show loading text
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Config.openAiApiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'user',
              'content':
                  'Based on this query "$_recognizedText", places were found. One of them was "$name". Give me more intresting information about it.',
            }
          ],
          'temperature': 0.7,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        setState(() {
          _openAiResponse = content.trim();
        });
      } else {
        setState(() {
          _openAiResponse = 'Error! Try again!';
        });
      }
    } catch (e) {
      setState(() {
        _openAiResponse = 'Error! Try again!';
      });
    }
  }

  /// Send recognized text to OpenAI
  Future<void> _sendToOpenAi(String userText) async {
    if (userText.isEmpty) return;

    _bottomSheetController.animateTo(
      0.2, // Collapse to minimum size
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Config.openAiApiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'user',
              'content':
                  'Based on the following context "$userText", return a list of locations in the following JSON format: '
                      '[{"name": "...", "lat": "12.34", "lon": "56.78"}]. '
                      'Only return valid JSON with no extra text.',
            }
          ],
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        _parseLocations(content.trim());
      }
    } catch (e) {}
  }

  /// Parse the JSON from OpenAI into _locations
  void _parseLocations(String jsonStr) {
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is List) {
        _locations = parsed.map<Map<String, dynamic>>((item) {
          return {
            'name': item['name'],
            'lat': double.tryParse(item['lat'].toString()) ?? 0.0,
            'lon': double.tryParse(item['lon'].toString()) ?? 0.0,
          };
        }).toList();

        _updateMapMarkers();
      }
    } catch (e) {
      debugPrint('JSON parse error: $e');
    }
  }

  void _updateMapMarkers() {
    final markers = <Marker>{};
    for (int i = 0; i < _locations.length; i++) {
      final loc = _locations[i];
      final lat = loc['lat'] as double;
      final lon = loc['lon'] as double;
      final name = loc['name'] as String;

      final marker = Marker(
        markerId: MarkerId('marker_$i'),
        position: LatLng(lat, lon),
        infoWindow: InfoWindow(title: name),
        onTap: () {
          setState(() {
            _selectedMarkerPosition = LatLng(lat, lon);
            _onMarkerTapped(name);
          });
        },
      );
      markers.add(marker);
    }

    setState(() {
      _markers = markers;
    });

    // Move camera to fit markers
    if (_mapController != null && markers.isNotEmpty) {
      final points = markers.map((m) => m.position).toList();
      _moveCameraToFitMarkers(points);
    }
  }

  void _moveCameraToFitMarkers(List<LatLng> points) async {
    if (points.isEmpty) return;

    final swLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final swLon =
        points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final neLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final neLon =
        points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    final bounds = LatLngBounds(
      southwest: LatLng(swLat, swLon),
      northeast: LatLng(neLat, neLon),
    );

    final cameraUpdate = CameraUpdate.newLatLngBounds(bounds, 80);
    await _mapController?.animateCamera(cameraUpdate);
  }

  LatLng? _selectedMarkerPosition;

  void _openGoogleMapsNavigation() async {
    if (_selectedMarkerPosition == null) {
      debugPrint("No marker selected.");
      return;
    }

    final double lat = _selectedMarkerPosition!.latitude;
    final double lon = _selectedMarkerPosition!.longitude;
    final Uri url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not open Google Maps');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isListening = _speechToText.isListening;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wonder AI',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Google Map
          Positioned.fill(
            child: GoogleMap(
              onMapCreated: (controller) => _mapController = controller,
              initialCameraPosition: const CameraPosition(
                target: LatLng(0, 0),
                zoom: 2,
              ),
              markers: _markers,
              polylines: _polylines,
            ),
          ),

          Positioned(
            top: 10, // Adjust position
            left: 10,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation,
              backgroundColor: Colors.tealAccent,
              child: const Icon(Icons.my_location, color: Colors.black),
            ),
          ),

          // Navigation Button - Only show if a marker is selected
          if (_selectedMarkerPosition != null)
            Positioned(
              top: 10, // Adjust position
              right: 10,
              child: FloatingActionButton(
                onPressed: _openGoogleMapsNavigation,
                backgroundColor: Colors.tealAccent,
                child: const Icon(Icons.navigation, color: Colors.black),
              ),
            ),

          // Expandable Bottom Panel
          DraggableScrollableSheet(
            controller: _bottomSheetController,
            initialChildSize: 0.2,
            minChildSize: 0.2,
            maxChildSize: 0.7,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Type or speak a location...',
                          filled: true,
                          fillColor: Colors.grey[900],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (text) {
                          setState(() {
                            _recognizedText = text;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _speechEnabled
                                ? (isListening
                                    ? _stopListening
                                    : _startListening)
                                : null,
                            child: Text(isListening ? 'Stop' : 'Speak'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () => _sendToOpenAi(_recognizedText),
                            child: const Text('Send'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _recognizedText =
                                    ""; // Clear the full recognized text
                                _textController.clear(); // Clear input field
                                _lastRecognizedText =
                                    ""; // Reset tracking variable
                              });
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16), // Add spacing
                      Text(
                        'Location Info:',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.tealAccent,
                              fontFamily: 'monospace',
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _openAiResponse.isNotEmpty
                            ? _openAiResponse
                            : "Tap a red marker to learn more",
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (_openAiResponse.isNotEmpty &&
                          _openAiResponse != "Loading...")
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isPlaying
                                  ? _stopSpeaking
                                  : () => _speakText(_openAiResponse),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyan),
                              icon: Icon(
                                  _isPlaying ? Icons.stop : Icons.play_arrow),
                              label: Text(_isPlaying ? 'Stop' : 'Listen'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
