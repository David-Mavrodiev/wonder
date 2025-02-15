import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class Quiz extends StatefulWidget {
  final String text;
  final String anthropicApiKey;

  const Quiz({Key? key, required this.anthropicApiKey, required this.text})
      : super(key: key);

  @override
  _QuizState createState() => _QuizState();
}

class _QuizState extends State<Quiz> {
  List<Map<String, dynamic>> _quizData = [];
  bool _isLoading = true;
  Map<int, int?> _selectedAnswers = {}; // Stores user answers
  Map<int, bool?> _isCorrect = {}; // Stores correct/incorrect state
  Map<String, String> _cache = {};

  @override
  void initState() {
    super.initState();
    _fetchQuizData(widget.text);
  }

  Future<void> _fetchQuizData(String text) async {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');
    setState(() {
      _isLoading = true;
    });

    if (!_cache.containsKey(text)) {
      debugPrint('Not found quiz in cache');
      try {
        final response = await http.post(
          url,
          headers: {
            'x-api-key': widget.anthropicApiKey,
            'Content-Type': 'application/json',
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "system":
                "You are a quiz generator AI. Generate a JSON array of quiz questions based on the given text. "
                    "Each quiz object should have: question (string), answers (array of strings), correctAnswerIndex (integer). "
                    "Respond ONLY with valid JSON, nothing else.",
            "messages": [
              {"role": "user", "content": text}
            ]
          }),
        );

        if (response.statusCode == 200) {
          _cache[text] = response.body;
        }
      } catch (e) {
        debugPrint(e.toString());
      }
    }

    if (_cache.containsKey(text)) {
      final Map<String, dynamic> data = jsonDecode(_cache[text]!);
      final String rawQuizJson = data["content"][0]["text"];
      final List<Map<String, dynamic>> quizList =
          List<Map<String, dynamic>>.from(jsonDecode(rawQuizJson));

      setState(() {
        _quizData = quizList;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleAnswer(int questionIndex, int selectedIndex) {
    setState(() {
      _selectedAnswers[questionIndex] = selectedIndex;
      _isCorrect[questionIndex] =
          selectedIndex == _quizData[questionIndex]["correctAnswerIndex"];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(10),
      child: Column(
        children: [
          if (_isLoading)
            Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_quizData.isEmpty)
            Expanded(child: Center(child: Text("No quiz data available.")))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _quizData.length,
                itemBuilder: (context, index) {
                  var question = _quizData[index];
                  int? selectedAnswer = _selectedAnswers[index];
                  bool? isCorrect = _isCorrect[index];

                  return Card(
                    color: Color(0xFF1A1A1A),
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question["question"],
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          Column(
                            children: List.generate(
                              question["answers"].length,
                              (i) => ListTile(
                                title: Text(
                                  question["answers"][i],
                                  style: TextStyle(
                                    color: selectedAnswer == i
                                        ? (isCorrect == true
                                            ? Colors.green
                                            : Colors.redAccent)
                                        : Colors.white,
                                  ),
                                ),
                                leading: Radio<int>(
                                  value: i,
                                  groupValue: selectedAnswer,
                                  onChanged: selectedAnswer == null
                                      ? (_) => _handleAnswer(index, i)
                                      : null, // Disable change after selection
                                ),
                              ),
                            ),
                          ),
                          if (selectedAnswer != null && isCorrect == false)
                            Padding(
                              padding: const EdgeInsets.only(top: 5.0),
                              child: Text(
                                "Correct Answer: ${question["answers"][question["correctAnswerIndex"]]}",
                                style: TextStyle(
                                    color: Colors.tealAccent,
                                    fontWeight: FontWeight.bold),
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
      ),
    );
  }
}
