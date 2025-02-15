import 'dart:convert';
import 'dart:io';
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
//import 'package:dio/dio.dart';
//import 'package:audioplayers/audioplayers.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:wonder/quiz.dart';
import 'loading_provider.dart';
import 'panel_tabs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for async main
  await Config.load(); // Load API keys from config.json
  // runApp(const MyApp());
  runApp(
    ChangeNotifierProvider(
      create: (_) => LoadingProvider(),
      child: MyApp(),
    ),
  );
}

class Config {
  static String openAiApiKey = '';
  static String googleDirectionsApiKey = '';
  static String elevenlabsApiKey = '';
  static String anthropicApiKey = '';

  static Future<void> load() async {
    final String jsonString = await rootBundle.loadString('assets/config.json');
    final Map<String, dynamic> jsonData = json.decode(jsonString);
    openAiApiKey = jsonData['openAiApiKey'];
    googleDirectionsApiKey = jsonData['googleDirectionsApiKey'];
    elevenlabsApiKey = jsonData['elevenLabsKey'];
    anthropicApiKey = jsonData['anthropicApiKey'];
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
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            Consumer<LoadingProvider>(
              builder: (_, loadingProvider, __) {
                return loadingProvider.isLoading
                    ? Container(
                        color: Colors.black.withOpacity(0.3),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SizedBox.shrink();
              },
            ),
          ],
        );
      },
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

  // Eleven Labs
  final AudioPlayer _audioPlayer = AudioPlayer();

  Map<String, String> _locationInfoCache = {}; // Cache for location info

  late String _destinationName = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

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

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          14.0,
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

  // Future<void> _speakText(String text) async {
  //   if (text.isEmpty) return;

  //   await _flutterTts.setLanguage("en-US");
  //   await _flutterTts.setPitch(1.0); // Normal pitch
  //   await _flutterTts.setSpeechRate(0.5); // Normal speed

  //   _flutterTts.setCompletionHandler(() {
  //     setState(() {
  //       _isPlaying = false; // Reset state when speaking is done
  //     });
  //   });

  //   setState(() {
  //     _isPlaying = true;
  //   });

  //   await _flutterTts.speak(text);
  // }

  // Future<void> _stopSpeaking() async {
  //   await _flutterTts.stop();
  //   setState(() {
  //     _isPlaying = false;
  //   });
  // }

  Future<void> _speakText(String text) async {
    try {
      final url = Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb/stream');

      final request = http.Request("POST", url)
        ..headers.addAll({
          'xi-api-key': Config.elevenlabsApiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        })
        ..body = jsonEncode({
          'text': text,
        });

      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final stream = response.stream;
        final List<int> audioBytes = [];
        final completer = Completer<void>();

        stream.listen(
          (chunk) {
            audioBytes.addAll(chunk);
            final audioSource = AudioSource.uri(
              Uri.dataFromBytes(
                Uint8List.fromList(audioBytes),
                mimeType: 'audio/mpeg',
              ),
            );

            _audioPlayer.setAudioSource(audioSource).then((_) {
              _audioPlayer.play();
              setState(() {
                _isPlaying = true;
              });
            });
          },
          onDone: () {
            completer.complete();
            setState(() {
              _isPlaying = false;
            });
          },
          onError: (error) {
            setState(() {
              _isPlaying = false;
            });
            completer.completeError(error);
          },
        );

        await completer.future;
      } else {
        print('Error: ${await response.stream.bytesToString()}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  void _stopSpeaking() async {
    await _audioPlayer.stop();
    setState(() {
      _isPlaying = false;
    });
  }

  void _onMarkerTapped(String name) async {
    _bottomSheetController.animateTo(
      0.8, // Fully expanded
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    setState(() {
      _destinationName = name;
    });

    // if (_locationInfoCache.containsKey(name)) {
    //   // If cached, use stored response
    //   setState(() {
    //     _openAiResponse = _locationInfoCache[name]!;
    //   });
    //   return;
    // }

    // setState(() {
    //   _openAiResponse = 'Loading...'; // Show loading text
    // });

    // try {
    //   final response = await http.post(
    //     Uri.parse('https://api.openai.com/v1/chat/completions'),
    //     headers: {
    //       'Content-Type': 'application/json',
    //       'Authorization': 'Bearer ${Config.openAiApiKey}',
    //     },
    //     body: jsonEncode({
    //       'model': 'gpt-3.5-turbo',
    //       'messages': [
    //         {
    //           'role': 'user',
    //           'content':
    //               'Based on this query "$_recognizedText", places were found. One of them was "$name". Give me more intresting information about it.',
    //         }
    //       ],
    //       'temperature': 0.7,
    //     }),
    //   );
    //   if (response.statusCode == 200) {
    //     final data = jsonDecode(response.body);
    //     final content = data['choices'][0]['message']['content'] as String;

    //     setState(() {
    //       _openAiResponse = content.trim();
    //       _locationInfoCache[name] = content.trim();
    //     });
    //   } else {
    //     setState(() {
    //       _openAiResponse = 'Error! Try again!';
    //     });
    //   }
    // } catch (e) {
    //   setState(() {
    //     _openAiResponse = 'Error! Try again!';
    //   });
    // }
  }

  /// Send recognized text to OpenAI
  Future<void> _sendToOpenAi(String userText) async {
    if (userText.isEmpty) return;

    final loadingProvider =
        Provider.of<LoadingProvider>(context, listen: false);
    loadingProvider.show();

    _locationInfoCache.clear();

    _bottomSheetController.animateTo(
      0.2, // Collapse to minimum size
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    // Append user location if available
    String locationContext = "";
    if (_currentPosition != null) {
      locationContext =
          "The user's current location is (${_currentPosition!.latitude}, ${_currentPosition!.longitude}).";
    }

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
                  '$locationContext Based on the following context "$userText", return a list of locations in the following JSON format: '
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
        loadingProvider.hide();
        setState(() {
          _destinationName = '';
        });
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
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10), // Adjust corner radius
              child: Image.asset(
                'assets/icon.png', // Path to your icon
                height: 40, // Adjust size
                width: 40, // Ensure width and height match for a square icon
                fit: BoxFit.cover, // Ensures the image covers the space
              ),
            ),
            const SizedBox(width: 8), // Spacing between icon and text
            const Text(
              'Wonder AI',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
            maxChildSize: 0.8,
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
                          hintText: 'Type or speak where you want to go...',
                          filled: true,
                          fillColor: Colors.grey[900],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (text) {
                          setState(() {
                            _recognizedText = text;
                            _destinationName = '';
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
                                _recognizedText = "";
                                _textController.clear();
                                _lastRecognizedText = "";
                                _destinationName = "";
                              });
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                      if (_destinationName.isNotEmpty)
                        PanelTabs(
                          elevenlabsApiKey: Config.elevenlabsApiKey,
                          anthropicApiKey: Config.anthropicApiKey,
                          openAiApiKey: Config.openAiApiKey,
                          context: _recognizedText,
                          destinationName: _destinationName,
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
