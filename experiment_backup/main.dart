import 'dart:isolate';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:path_provider/path_provider.dart';

import 'services/embedding_service.dart';
import 'services/sms_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Semantic SMS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SearchExperimentScreen(),
    );
  }
}

class SmsItem {
  final SmsMessage message;
  final List<double> embedding;
  bool isMoney;
  bool isOtp;
  double moneyScore;
  double otpScore;
  double searchScore;

  SmsItem(
    this.message,
    this.embedding, {
    this.isMoney = false,
    this.isOtp = false,
    this.moneyScore = 0.0,
    this.otpScore = 0.0,
    this.searchScore = 0.0,
  });
}

class SearchExperimentScreen extends StatefulWidget {
  const SearchExperimentScreen({super.key});

  @override
  State<SearchExperimentScreen> createState() => _SearchExperimentScreenState();
}

class _SearchExperimentScreenState extends State<SearchExperimentScreen> {
  final SmsService _smsService = SmsService();
  final EmbeddingService _embeddingService = EmbeddingService();

  List<SmsItem> _allMessages = [];
  List<SmsItem> _displayedAllMessages = [];
  List<SmsItem> _moneyMessages = [];
  List<SmsItem> _otpMessages = [];

  bool _isLoading = false;
  String _statusTitle = 'Ready';
  String _statusDetail = 'Tap the download icon to start.';
  double _progress = 0.0;
  bool _isSearching = false;

  String? _modelPath;
  String? _tokenizerPath;
  int _selectedLimit = 50;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    setState(() {
      _isLoading = true;
      _statusTitle = 'Extracting MiniLM...';
      _statusDetail = 'Copying 22MB model to storage (this only happens once).';
    });
    try {
      await EmbeddingService.extractAssets();

      final tempDir = await getTemporaryDirectory();
      _modelPath = '${tempDir.path}/minilm_nihal.tflite';
      _tokenizerPath = '${tempDir.path}/vocab.txt';

      await _embeddingService.initialize(_modelPath!, _tokenizerPath!);

      setState(() {
        _isLoading = false;
        _statusTitle = 'Model Ready';
        _statusDetail = 'You can now load your SMS for categorization.';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusTitle = 'Error Initialization';
        _statusDetail = e.toString();
      });
    }
  }

  double _otpThreshold = 0.20;
  double _moneyThreshold = 0.20;

  void _applyFilters() {
    setState(() {
      _moneyMessages = _allMessages
          .where((m) => m.moneyScore > _moneyThreshold)
          .toList();
      _otpMessages = _allMessages
          .where((m) => m.otpScore > _otpThreshold)
          .toList();
      _displayedAllMessages = List.from(_allMessages);

      if (_isSearching) {
        // Optional: filter out completely irrelevant search results
        _displayedAllMessages = _displayedAllMessages
            .where((m) => m.searchScore > 0.15)
            .toList();
        _moneyMessages = _moneyMessages
            .where((m) => m.searchScore > 0.15)
            .toList();
        _otpMessages = _otpMessages.where((m) => m.searchScore > 0.15).toList();

        _displayedAllMessages.sort(
          (a, b) => b.searchScore.compareTo(a.searchScore),
        );
        _moneyMessages.sort((a, b) => b.searchScore.compareTo(a.searchScore));
        _otpMessages.sort((a, b) => b.searchScore.compareTo(a.searchScore));
      } else {
        _moneyMessages.sort((a, b) => b.moneyScore.compareTo(a.moneyScore));
        _otpMessages.sort((a, b) => b.otpScore.compareTo(a.otpScore));
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      _isSearching = false;
      _applyFilters();
      return;
    }

    if (_allMessages.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusTitle = 'Searching...';
      _statusDetail = 'Calculating semantic similarity for "$query"';
      _progress = 0.0;
    });

    try {
      final queryEmbedding = await _embeddingService.getEmbedding(
        query,
        isQuery: true,
      );

      for (var item in _allMessages) {
        item.searchScore = _embeddingService.cosineSimilarity(
          queryEmbedding,
          item.embedding,
        );
      }

      _isSearching = true;
      _applyFilters();

      setState(() {
        _isLoading = false;
        _statusTitle = 'Search Complete';
        _statusDetail = 'Showing results for "$query" inside all tabs.';
        _progress = 1.0;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusTitle = 'Search Error';
        _statusDetail = e.toString();
      });
    }
  }

  Future<void> _loadAndEmbedMessages() async {
    if (_modelPath == null || _tokenizerPath == null) return;

    setState(() {
      _isLoading = true;
      _progress = 0.0;
      _statusTitle = 'Reading SMS...';
      _statusDetail = 'Requesting permissions and fetching inbox.';
    });

    try {
      final messages = await _smsService.getRecentMessages(
        limit: _selectedLimit,
      );

      setState(() {
        _statusTitle = 'Starting Background Isolate...';
        _statusDetail = 'Categorizing messages using MiniLM Anchors.';
      });

      final receivePort = ReceivePort();

      await Isolate.spawn(
        _backgroundEmbeddingTask,
        _IsolateData(
          receivePort.sendPort,
          _modelPath!,
          _tokenizerPath!,
          messages,
        ),
      );

      await for (final message in receivePort) {
        if (message is _IsolateProgress) {
          setState(() {
            _statusTitle = 'Categorizing (${message.current}/${message.total})';
            _statusDetail = 'Processing: "${message.preview}"';
            _progress = message.current / message.total;
          });
        } else if (message is _IsolateResult) {
          _allMessages = message.results;
          _applyFilters();

          setState(() {
            _isLoading = false;
            _statusTitle = 'Categorization Complete!';
            _statusDetail = 'Ready to tune thresholds.';
            _progress = 1.0;
          });
          receivePort.close();
          break;
        } else if (message is _IsolateError) {
          throw Exception(message.error);
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusTitle = 'Error';
        _statusDetail = e.toString();
      });
    }
  }

  Widget _buildMessageList(List<SmsItem> items, String scoreType) {
    if (items.isEmpty) {
      return const Center(child: Text("No messages in this category."));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final score = _isSearching
            ? item.searchScore
            : (scoreType == 'money'
                  ? item.moneyScore
                  : (scoreType == 'otp' ? item.otpScore : 0.0));
        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          child: ListTile(
            title: SelectableText(
              item.message.address ?? 'Unknown Sender',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: SelectableText(item.message.body ?? ''),
            trailing: score > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(score * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Semantic Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Money'),
              Tab(text: 'OTP'),
            ],
          ),
          actions: [
            DropdownButton<int>(
              value: _selectedLimit,
              items: const [
                DropdownMenuItem(value: 50, child: Text("50 SMS")),
                DropdownMenuItem(value: 500, child: Text("500 SMS")),
                DropdownMenuItem(value: 100000, child: Text("All SMS")),
              ],
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) setState(() => _selectedLimit = value);
                    },
            ),
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Load & Embed SMS',
              onPressed: _isLoading ? null : _loadAndEmbedMessages,
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusDetail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                    ),
                  ],
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search within categories...',
                  hintText: 'e.g. "package arriving" or "bank otp"',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: _performSearch,
              ),
            ),
            const SizedBox(height: 8),

            if (_allMessages.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Money Threshold: ${_moneyThreshold.toStringAsFixed(2)}',
                        ),
                        Expanded(
                          child: Slider(
                            value: _moneyThreshold,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) {
                              setState(() => _moneyThreshold = val);
                              _applyFilters();
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          'OTP Threshold: ${_otpThreshold.toStringAsFixed(2)}',
                        ),
                        Expanded(
                          child: Slider(
                            value: _otpThreshold,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (val) {
                              setState(() => _otpThreshold = val);
                              _applyFilters();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            Expanded(
              child: TabBarView(
                children: [
                  _buildMessageList(_displayedAllMessages, 'none'),
                  _buildMessageList(_moneyMessages, 'money'),
                  _buildMessageList(_otpMessages, 'otp'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Background Isolate Logic ---

class _IsolateData {
  final SendPort sendPort;
  final String modelPath;
  final String tokenizerPath;
  final List<SmsMessage> messages;
  _IsolateData(
    this.sendPort,
    this.modelPath,
    this.tokenizerPath,
    this.messages,
  );
}

class _IsolateProgress {
  final int current;
  final int total;
  final String preview;
  _IsolateProgress(this.current, this.total, this.preview);
}

class _IsolateResult {
  final List<SmsItem> results;
  _IsolateResult(this.results);
}

class _IsolateError {
  final String error;
  _IsolateError(this.error);
}

Future<void> _backgroundEmbeddingTask(_IsolateData data) async {
  try {
    final embeddingService = EmbeddingService();
    await embeddingService.initialize(data.modelPath, data.tokenizerPath);

    final moneyAnchorText =
        "Bank transaction, money debited, credited, account balance update, payment received, INR, Rs, amount.";
    final otpAnchorText =
        "OTP, one time password, security code, verification pin, login authentication code.";

    final moneyAnchorVector = await embeddingService.getEmbedding(
      moneyAnchorText,
      isQuery: true,
    );
    final otpAnchorVector = await embeddingService.getEmbedding(
      otpAnchorText,
      isQuery: true,
    );

    List<SmsItem> embedded = [];

    for (int i = 0; i < data.messages.length; i++) {
      final msg = data.messages[i];
      final text = msg.body ?? '';

      if (text.isNotEmpty) {
        final vector = await embeddingService.getEmbedding(
          text,
          isQuery: false,
          metadata: msg,
        );

        final moneyScore = embeddingService.cosineSimilarity(
          vector,
          moneyAnchorVector,
        );
        final otpScore = embeddingService.cosineSimilarity(
          vector,
          otpAnchorVector,
        );

        embedded.add(
          SmsItem(msg, vector, moneyScore: moneyScore, otpScore: otpScore),
        );
      }

      String preview = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      data.sendPort.send(
        _IsolateProgress(i + 1, data.messages.length, preview),
      );
    }

    data.sendPort.send(_IsolateResult(embedded));
  } catch (e) {
    data.sendPort.send(_IsolateError(e.toString()));
  }
}
