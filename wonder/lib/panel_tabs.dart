import 'package:flutter/material.dart';
import 'package:wonder/facts.dart';
import 'package:wonder/souvenir.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'quiz.dart';

class PanelTabs extends StatefulWidget {
  final String elevenlabsApiKey;
  final String openAiApiKey;
  final String anthropicApiKey;
  final String destinationName;
  final String context;

  const PanelTabs({
    Key? key,
    required this.elevenlabsApiKey,
    required this.openAiApiKey,
    required this.anthropicApiKey,
    required this.destinationName,
    required this.context,
  }) : super(key: key);

  @override
  _PanelTabsState createState() => _PanelTabsState();
}

class _PanelTabsState extends State<PanelTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _factsText = '';
  Map<String, String> _locationInfoCache = {};

  @override
  void initState() {
    super.initState();
    if (widget.destinationName.isNotEmpty) {
      debugPrint("Init state: ${widget.destinationName}");
      setState(() {
        _factsText = '';
      });
      _fetchFacts(widget.destinationName, widget.context);
    }
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didUpdateWidget(covariant PanelTabs oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.context != oldWidget.context) {
      _locationInfoCache.clear();
    }

    if (widget.destinationName != oldWidget.destinationName) {
      debugPrint("didUpdateWidget: ${widget.destinationName}");
      setState(() {
        _factsText = '';
      });
      _fetchFacts(widget.destinationName, widget.context);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchFacts(String destinationName, String context) async {
    if (_locationInfoCache.containsKey(destinationName)) {
      // If cached, use stored response
      setState(() {
        _factsText = _locationInfoCache[destinationName]!;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.openAiApiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'user',
              'content':
                  'Based on this query "$context", places were found. One of them was "$destinationName". Give me more intresting information about it.',
            }
          ],
          'temperature': 0.7,
        }),
      );

      debugPrint("Response debug: ${response.statusCode}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] as String;

        setState(() {
          _factsText = content.trim();
          _locationInfoCache[destinationName] = content.trim();
          //_isLoading = false;
        });
      } else {
        setState(() {
          _factsText = 'Error! Try again!';
          //_isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(e.toString());
      setState(() {
        _factsText = 'Error! Try again!';
        //_isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.destinationName.isEmpty) {
      return Center(child: Text("Tap a red marker to learn more"));
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          indicatorColor: Colors.tealAccent,
          dividerColor: Colors.tealAccent,
          dividerHeight: 2,
          tabs: [
            Tab(text: "Facts"),
            Tab(text: "Quiz"),
            Tab(text: "Souvenir"),
          ],
        ),
        SizedBox(
          height: 400,
          child: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                  child: Facts(
                elevenlabsApiKey: widget.elevenlabsApiKey,
                openAiApiKey: widget.openAiApiKey,
                factsText: _factsText,
              )),
              SizedBox(
                height: 300,
                child: Quiz(
                    anthropicApiKey: widget.anthropicApiKey, text: _factsText),
              ),
              SingleChildScrollView(
                  child: SizedBox(
                height: 600,
                child: Souvenir(prompt: _factsText),
              ))
            ],
          ),
        ),
      ],
    );
  }
}
