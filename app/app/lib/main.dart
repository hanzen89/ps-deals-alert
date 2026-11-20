import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String dealsUrl = String.fromEnvironment(
  'DEALS_URL',
  defaultValue: 'https://example.github.io/ps-deals-alert/deals.json',
);

void main() {
  runApp(const PsDealsApp());
}

class PsDealsApp extends StatelessWidget {
  const PsDealsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PS Deals Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0070D1),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B111E),
        useMaterial3: true,
      ),
      home: const DealsHomePage(),
    );
  }
}

class GameDeal {
  final String id;
  final String name;
  final List<String> platforms;
  final String basePriceDisplay;
  final String discountedPriceDisplay;
  final int discountPercent;
  final bool isAllTimeLow;
  final String coverUrl;
  final String storeUrl;

  GameDeal({
    required this.id,
    required this.name,
    required this.platforms,
    required this.basePriceDisplay,
    required this.discountedPriceDisplay,
    required this.discountPercent,
    required this.isAllTimeLow,
    required this.coverUrl,
    required this.storeUrl,
  });

  factory GameDeal.fromJson(Map<String, dynamic> json) {
    return GameDeal(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Game',
      platforms: List<String>.from(json['platforms'] ?? []),
      basePriceDisplay: json['base_price_display'] ?? '',
      discountedPriceDisplay: json['discounted_price_display'] ?? '',
      discountPercent: json['discount_percent'] ?? 0,
      isAllTimeLow: json['is_all_time_low'] ?? false,
      coverUrl: json['cover_url'] ?? '',
      storeUrl: json['store_url'] ?? '',
    );
  }
}

class DealsResponse {
  final String updatedAt;
  final List<GameDeal> topDiscounts;
  final List<GameDeal> allTimeLows;

  DealsResponse({
    required this.updatedAt,
    required this.topDiscounts,
    required this.allTimeLows,
  });

  factory DealsResponse.fromJson(Map<String, dynamic> json) {
    return DealsResponse(
      updatedAt: json['updated_at'] ?? '',
      topDiscounts: (json['top_discounts'] as List<dynamic>? ?? [])
          .map((e) => GameDeal.fromJson(e))
          .toList(),
      allTimeLows: (json['all_time_lows'] as List<dynamic>? ?? [])
          .map((e) => GameDeal.fromJson(e))
          .toList(),
    );
  }
}

class DealsHomePage extends StatefulWidget {
  const DealsHomePage({super.key});

  @override
  State<DealsHomePage> createState() => _DealsHomePageState();
}

class _DealsHomePageState extends State<DealsHomePage> {
  late Future<DealsResponse> _dealsFuture;

  @override
  void initState() {
    super.initState();
    _dealsFuture = _fetchDeals();
  }

  Future<DealsResponse> _fetchDeals() async {
    final uri = Uri.parse('$dealsUrl?t=${DateTime.now().millisecondsSinceEpoch}');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Gagal memuat data (HTTP ${res.statusCode})');
    }
    final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return DealsResponse.fromJson(data);
  }

  Future<void> _refresh() async {
    setState(() {
      _dealsFuture = _fetchDeals();
    });
    await _dealsFuture;
  }

  Future<void> _openStore(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return 'Update: $d/$m/${dt.year} $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF003791),
          title: const Text(
            'PS Deals Alert',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refresh,
              tooltip: 'Refresh',
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.lightBlueAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.local_offer), text: 'Top 20 Diskon'),
              Tab(icon: Icon(Icons.trending_down), text: 'All-Time Low'),
            ],
          ),
        ),
        body: FutureBuilder<DealsResponse>(
          future: _dealsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final deals = snapshot.data!;
            final updatedLabel = _formatDate(deals.updatedAt);

            return TabBarView(
              children: [
                _buildList(deals.topDiscounts, updatedLabel),
                _buildList(deals.allTimeLows, updatedLabel),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(List<GameDeal> items, String updatedLabel) {
    if (items.isEmpty) {
      return const Center(child: Text('Belum ada data diskon.'));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                updatedLabel,
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
            );
          }
          final game = items[index - 1];
          return Card(
            color: const Color(0xFF151E32),
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openStore(game.storeUrl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: game.coverUrl.isNotEmpty
                        ? Image.network(
                            game.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.videogame_asset, size: 40),
                          )
                        : const Icon(Icons.videogame_asset, size: 40),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              ...game.platforms.map(
                                (p) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    p,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                              if (game.isAllTimeLow)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade700,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ALL-TIME LOW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0070D1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '-${game.discountPercent}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                game.discountedPriceDisplay,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.lightBlueAccent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  game.basePriceDisplay,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white54,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
