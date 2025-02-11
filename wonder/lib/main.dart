import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart'
    show rootBundle; // Import for loading assets
import 'package:url_launcher/url_launcher.dart';

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

  // Raw response from OpenAI
  String _openAiResponse = '';

  // List of locations from OpenAI
  List<Map<String, dynamic>> _locations = [];

  // Map objects
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  GoogleMapController? _mapController;

  // Add this as a state variable
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSpeech();
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
    setState(() {
      _recognizedText = result.recognizedWords;
      _textController.text = _recognizedText;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(
            offset: _textController.text.length), // Keep cursor at the end
      );
    });
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
  }

  /// Send recognized text to OpenAI
  Future<void> _sendToOpenAi(String userText) async {
    if (userText.isEmpty) return;
    setState(() {
      _openAiResponse = 'Loading...';
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
        setState(() {
          _openAiResponse = content.trim();
        });

        _parseLocations(content.trim());
      } else {
        setState(() {
          _openAiResponse = 'Error: ${response.statusCode}\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _openAiResponse = 'Error: $e';
      });
    }
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
          'Wonder',
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
