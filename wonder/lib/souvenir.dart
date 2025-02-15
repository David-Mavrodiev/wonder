import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

class Souvenir extends StatefulWidget {
  final String prompt;

  const Souvenir({Key? key, required this.prompt}) : super(key: key);

  @override
  _SouvenirState createState() => _SouvenirState();
}

class _SouvenirState extends State<Souvenir> {
  String? imageUrl;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    generateImage(widget.prompt);
  }

  Future<void> generateImage(String prompt) async {
    setState(() {
      isLoading = true;
      imageUrl = null;
    });

    final String apiKey =
        "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"; // Replace with your API key
    final Uri url = Uri.parse("https://api.openai.com/v1/images/generations");

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "dall-e-3",
          "prompt": prompt,
          "n": 1,
          "size": "1024x1024"
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          imageUrl = data["data"][0]["url"];
        });
      } else {
        print("Error: ${response.body}");
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void shareImage() {
    if (imageUrl != null) {
      Share.share(
        "Can you guess this location: $imageUrl",
        subject: "Mystery location",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      body: Padding(
        padding: const EdgeInsets.all(1.0),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator()
              : imageUrl != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.network(
                          imageUrl!,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) => Text(
                            "Failed to load image",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: shareImage,
                          child: const Text("Share"),
                        ),
                      ],
                    )
                  : const Text(
                      "Failed to generate image",
                      style: TextStyle(color: Colors.red),
                    ),
        ),
      ),
    );
  }
}
