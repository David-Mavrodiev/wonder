import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class Facts extends StatefulWidget {
  final String elevenlabsApiKey;
  final String openAiApiKey;
  final String factsText;

  const Facts(
      {Key? key,
      required this.elevenlabsApiKey,
      required this.openAiApiKey,
      required this.factsText})
      : super(key: key);

  @override
  _FactsWidgetState createState() => _FactsWidgetState();
}

class _FactsWidgetState extends State<Facts> {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false; // Track if TTS is speaking

  // Eleven Labs
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
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
          'xi-api-key': widget.elevenlabsApiKey,
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

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Color(0xFF1A1A1A),
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: widget.factsText.isEmpty // Show loading spinner if empty
            ? Center(
                child: CircularProgressIndicator(),
              )
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.factsText,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isPlaying
                                ? _stopSpeaking
                                : () => _speakText(widget.factsText),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.tealAccent),
                            icon: Icon(
                                color: Colors.white,
                                _isPlaying ? Icons.stop : Icons.play_arrow),
                            label: Text(_isPlaying ? 'Stop' : 'Listen'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
