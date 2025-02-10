import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() => runApp(const MyApp());

// Remember to keep your keys secure in production!
const openAiApiKey = '';
const googleDirectionsApiKey = '';

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Futuristic Speech + OpenAI + Google Maps',
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
          'Authorization': 'Bearer $openAiApiKey',
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
      );
      markers.add(marker);
    }

    setState(() {
      _markers = markers;
      _polylines.clear(); // or if you want to build a route, do that here
    });

    // Move camera to show markers
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

  @override
  Widget build(BuildContext context) {
    final isListening = _speechToText.isListening;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Futuristic Locations',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // 1) Map at the top
          Expanded(
            flex: 3,
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

          // 2) Bottom panel for recognized text and controls
          Expanded(
            flex: 2,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Recognized Text:',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.tealAccent,
                            fontFamily: 'monospace',
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _recognizedText,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),

                    // Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: _speechEnabled
                              ? (isListening ? _stopListening : _startListening)
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
                    const SizedBox(height: 16),

                    // OpenAI Response
                    Text(
                      'OpenAI Response:',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.tealAccent,
                            fontFamily: 'monospace',
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _openAiResponse,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
