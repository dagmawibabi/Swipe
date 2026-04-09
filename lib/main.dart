import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _showCounterKey = 'settings.show_counter';
const _colorChangeKey = 'settings.color_change';
const _showFeedTabsKey = 'settings.show_feed_tabs';
const _dailyStatsKey = 'stats.daily_history';
const _feedStartingPage = 0;
const _superLikeEvery = 5;

const _feedColors = <ColorEntry>[
  ColorEntry('Coal', Color(0xFF101820)),
  ColorEntry('Ember', Color(0xFFE94F37)),
  ColorEntry('Slate', Color(0xFF393E41)),
  ColorEntry('Mint', Color(0xFF44BBA4)),
  ColorEntry('Amber', Color(0xFFF6AE2D)),
  ColorEntry('Indigo', Color(0xFF3D348B)),
  ColorEntry('Teal', Color(0xFF1B998B)),
  ColorEntry('Plum', Color(0xFF2E294E)),
  ColorEntry('Coral', Color(0xFFFF6B6B)),
  ColorEntry('Sky', Color(0xFF4EA8DE)),
  ColorEntry('Lime', Color(0xFF8AC926)),
  ColorEntry('Rose', Color(0xFFE63946)),
];

int _wrapPaletteIndex(int rawIndex) {
  return (rawIndex % _feedColors.length + _feedColors.length) %
      _feedColors.length;
}

Color _paletteColor(int paletteIndex, bool enableColorChange) {
  if (!enableColorChange) {
    return const Color(0xFF050505);
  }

  return _feedColors[_wrapPaletteIndex(paletteIndex)].color;
}

List<int> _homeTimelineOrder(FeedTabChoice choice) {
  return switch (choice) {
    FeedTabChoice.forYou => List<int>.generate(
      _feedColors.length,
      (index) => index,
    ),
    FeedTabChoice.following => <int>[3, 9, 1, 7, 11, 5, 0, 8, 2, 10, 4, 6],
  };
}

List<int> _searchTimelineOrder(int startingPaletteIndex) {
  return List<int>.generate(
    _feedColors.length,
    (index) => _wrapPaletteIndex(startingPaletteIndex + index),
  );
}

bool _sameOrder(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}

List<int> _reshuffledOrder(List<int> currentOrder, {int? pinnedStart}) {
  final random = math.Random(DateTime.now().microsecondsSinceEpoch);
  final nextOrder = List<int>.from(currentOrder);

  if (pinnedStart != null) {
    nextOrder
      ..clear()
      ..add(pinnedStart);

    final remaining = List<int>.generate(_feedColors.length, (index) => index)
      ..remove(pinnedStart)
      ..shuffle(random);

    nextOrder.addAll(remaining);
    return nextOrder;
  }

  var attempts = 0;
  do {
    nextOrder
      ..clear()
      ..addAll(currentOrder);
    nextOrder.shuffle(random);
    attempts += 1;
  } while ((_sameOrder(nextOrder, currentOrder) ||
          nextOrder.first == currentOrder.first) &&
      attempts < 10);

  if ((nextOrder.first == currentOrder.first ||
          _sameOrder(nextOrder, currentOrder)) &&
      nextOrder.length > 1) {
    final first = nextOrder.removeAt(0);
    nextOrder.add(first);
  }

  return nextOrder;
}

Color timelineColorForPage(
  int pageIndex,
  bool enableColorChange,
  List<int> order,
) {
  final relativePage = pageIndex - _feedStartingPage;
  return _paletteColor(order[relativePage % order.length], enableColorChange);
}

class ColorEntry {
  const ColorEntry(this.name, this.color);

  final String name;
  final Color color;
}

enum FeedTabChoice { following, forYou }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(SwipeApp(preferences: preferences));
}

class SwipeApp extends StatefulWidget {
  const SwipeApp({super.key, required this.preferences});

  final SharedPreferences preferences;

  @override
  State<SwipeApp> createState() => _SwipeAppState();
}

class _SwipeAppState extends State<SwipeApp> {
  late final SwipeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SwipeController(widget.preferences);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Swipe',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Color(0xFF7AE7C7),
          surface: Color(0xFF111111),
        ),
      ),
      home: SwipeShell(controller: _controller),
    );
  }
}

class SwipeShell extends StatefulWidget {
  const SwipeShell({super.key, required this.controller});

  final SwipeController controller;

  @override
  State<SwipeShell> createState() => _SwipeShellState();
}

class _SwipeShellState extends State<SwipeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SwipeFeed(controller: widget.controller),
          SearchPage(controller: widget.controller),
          SettingsPage(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: const Color(0xCC000000),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class SwipeFeed extends StatefulWidget {
  const SwipeFeed({super.key, required this.controller});

  final SwipeController controller;

  @override
  State<SwipeFeed> createState() => _SwipeFeedState();
}

class _SwipeFeedState extends State<SwipeFeed> {
  late final PageController _tabController;
  FeedTabChoice _selectedTab = FeedTabChoice.forYou;
  late List<int> _forYouOrder;
  late List<int> _followingOrder;

  @override
  void initState() {
    super.initState();
    _tabController = PageController(
      initialPage: _tabIndexForChoice(_selectedTab),
    );
    _forYouOrder = _homeTimelineOrder(FeedTabChoice.forYou);
    _followingOrder = _homeTimelineOrder(FeedTabChoice.following);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _tabIndexForChoice(FeedTabChoice choice) {
    return switch (choice) {
      FeedTabChoice.following => 0,
      FeedTabChoice.forYou => 1,
    };
  }

  FeedTabChoice _choiceForTabIndex(int index) {
    return switch (index) {
      0 => FeedTabChoice.following,
      _ => FeedTabChoice.forYou,
    };
  }

  void _switchTab(FeedTabChoice choice) {
    if (_selectedTab == choice) {
      return;
    }

    setState(() => _selectedTab = choice);
    unawaited(
      _tabController.animateToPage(
        _tabIndexForChoice(choice),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _refreshForYouTimeline() async {
    setState(() {
      _forYouOrder = _reshuffledOrder(_forYouOrder);
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  Future<void> _refreshFollowingTimeline() async {
    setState(() {
      _followingOrder = _reshuffledOrder(_followingOrder);
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  Widget _buildFeedTabs() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FeedModeChip(
              label: 'Following',
              selected: _selectedTab == FeedTabChoice.following,
              onTap: () => _switchTab(FeedTabChoice.following),
            ),
            FeedModeChip(
              label: 'For You',
              selected: _selectedTab == FeedTabChoice.forYou,
              onTap: () => _switchTab(FeedTabChoice.forYou),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        return Stack(
          children: [
            PageView(
              key: const ValueKey('home-tab-pager'),
              controller: _tabController,
              scrollDirection: Axis.horizontal,
              onPageChanged: (index) {
                setState(() => _selectedTab = _choiceForTabIndex(index));
              },
              children: [
                ColorTimelineView(
                  key: const ValueKey('timeline-following'),
                  controller: widget.controller,
                  initialPage: _feedStartingPage,
                  colorForPage: (pageIndex, enableColorChange) =>
                      timelineColorForPage(
                        pageIndex,
                        enableColorChange,
                        _followingOrder,
                      ),
                  onRefresh: _refreshFollowingTimeline,
                  pageKeyPrefix: 'following',
                ),
                ColorTimelineView(
                  key: const ValueKey('timeline-for-you'),
                  controller: widget.controller,
                  initialPage: _feedStartingPage,
                  colorForPage: (pageIndex, enableColorChange) =>
                      timelineColorForPage(
                        pageIndex,
                        enableColorChange,
                        _forYouOrder,
                      ),
                  onRefresh: _refreshForYouTimeline,
                  pageKeyPrefix: 'for-you',
                ),
              ],
            ),
            if (widget.controller.showFeedTabs)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: SafeArea(bottom: false, child: _buildFeedTabs()),
              ),
          ],
        );
      },
    );
  }
}

typedef TimelineColorResolver =
    Color Function(int pageIndex, bool enableColorChange);

class ColorTimelineView extends StatefulWidget {
  const ColorTimelineView({
    super.key,
    required this.controller,
    required this.initialPage,
    required this.colorForPage,
    required this.onRefresh,
    required this.pageKeyPrefix,
    this.topOverlay,
  });

  final SwipeController controller;
  final int initialPage;
  final TimelineColorResolver colorForPage;
  final Future<void> Function() onRefresh;
  final String pageKeyPrefix;
  final Widget? topOverlay;

  @override
  State<ColorTimelineView> createState() => _ColorTimelineViewState();
}

class _ColorTimelineViewState extends State<ColorTimelineView>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _superLikeController;
  Timer? _heartTimer;
  late int _currentPage;
  bool _showHeart = false;
  bool _showSpeedIndicator = false;
  Offset? _heartPosition;
  Offset? _superLikeOrigin;
  List<SuperLikeParticle> _superLikeParticles = const [];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
    _superLikeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
  }

  @override
  void dispose() {
    _heartTimer?.cancel();
    _pageController.dispose();
    _superLikeController.dispose();
    super.dispose();
  }

  void _handlePageChanged(int index) {
    if (index == _currentPage) {
      return;
    }

    setState(() => _currentPage = index);
    widget.controller.registerSwipe();
  }

  void _handleDoubleTap(Offset position) {
    final likeCount = widget.controller.registerLike();
    _heartTimer?.cancel();

    setState(() {
      _heartPosition = position;
      _showHeart = true;
    });

    if (likeCount % _superLikeEvery == 0) {
      _triggerSuperLike(position);
    }

    _heartTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) {
        return;
      }

      setState(() => _showHeart = false);
    });
  }

  void _setSpeedIndicator(bool visible) {
    if (_showSpeedIndicator == visible) {
      return;
    }

    setState(() => _showSpeedIndicator = visible);
  }

  void _triggerSuperLike(Offset origin) {
    final random = math.Random(DateTime.now().microsecondsSinceEpoch);
    final particleColors = <Color>[
      Colors.red,
      Colors.pinkAccent,
      const Color(0xFFFFC1CC),
      Colors.white,
      const Color(0xFFF6AE2D),
    ];

    setState(() {
      _superLikeOrigin = origin;
      _superLikeParticles = List<SuperLikeParticle>.generate(24, (index) {
        final angle = -math.pi / 2 + (random.nextDouble() - 0.5) * math.pi;
        return SuperLikeParticle(
          angle: angle,
          distance: 110 + random.nextDouble() * 120,
          size: 8 + random.nextDouble() * 9,
          rotation: (random.nextDouble() - 0.5) * 2.6,
          color: particleColors[index % particleColors.length],
        );
      });
    });

    unawaited(_superLikeController.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final currentPageColor = widget.colorForPage(
          _currentPage,
          widget.controller.colorChangeEnabled,
        );
        final foregroundColor =
            ThemeData.estimateBrightnessForColor(currentPageColor) ==
                Brightness.dark
            ? Colors.white
            : Colors.black87;

        return Stack(
          children: [
            RefreshIndicator(
              color: Colors.white,
              backgroundColor: const Color(0xFF151515),
              onRefresh: widget.onRefresh,
              child: PageView.builder(
                key: ValueKey('${widget.pageKeyPrefix}-timeline'),
                controller: _pageController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                scrollDirection: Axis.vertical,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) {
                  return ColoredBox(
                    key: ValueKey('${widget.pageKeyPrefix}-page-$index'),
                    color: widget.colorForPage(
                      index,
                      widget.controller.colorChangeEnabled,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTapDown: (details) =>
                    _handleDoubleTap(details.localPosition),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: widget.controller.showCounter ? 1 : 0,
                  child: Text(
                    '${widget.controller.sessionSwipes}',
                    style: TextStyle(
                      fontSize: 76,
                      fontWeight: FontWeight.w800,
                      color: foregroundColor,
                      shadows: const [
                        Shadow(
                          blurRadius: 12,
                          color: Colors.black54,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.topOverlay != null)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: SafeArea(bottom: false, child: widget.topOverlay!),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 112,
              child: SafeArea(
                top: false,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _showSpeedIndicator
                          ? Container(
                              key: const ValueKey('speed-indicator'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xAA000000),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Video is playing 2x the speed',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('speed-indicator-hidden'),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 56,
              child: EdgeLongPressStrip(
                onVisibilityChanged: _setSpeedIndicator,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 56,
              child: EdgeLongPressStrip(
                onVisibilityChanged: _setSpeedIndicator,
              ),
            ),
            if (_superLikeOrigin != null)
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _superLikeController,
                  builder: (context, child) {
                    if (_superLikeController.value == 0 &&
                        !_superLikeController.isAnimating) {
                      return const SizedBox.shrink();
                    }

                    final progress = Curves.easeOutCubic.transform(
                      _superLikeController.value,
                    );
                    final fade =
                        (1 -
                                Curves.easeIn.transform(
                                  _superLikeController.value,
                                ))
                            .clamp(0.0, 1.0);
                    final gravity =
                        90 *
                        _superLikeController.value *
                        _superLikeController.value;

                    return Stack(
                      children: [
                        ..._superLikeParticles.map((particle) {
                          final dx =
                              math.cos(particle.angle) *
                              particle.distance *
                              progress;
                          final dy =
                              math.sin(particle.angle) *
                                  particle.distance *
                                  progress -
                              gravity;

                          return Positioned(
                            left: _superLikeOrigin!.dx + dx,
                            top: _superLikeOrigin!.dy + dy,
                            child: Opacity(
                              opacity: fade,
                              child: Transform.rotate(
                                angle: particle.rotation * progress,
                                child: Container(
                                  width: particle.size,
                                  height: particle.size,
                                  decoration: BoxDecoration(
                                    color: particle.color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 118,
                          child: Opacity(
                            opacity: fade,
                            child: Transform.scale(
                              scale: 0.86 + 0.18 * progress,
                              child: const Center(
                                child: Text(
                                  'SUPER LIKE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            if (_heartPosition != null)
              Positioned(
                left: _heartPosition!.dx - 48,
                top: _heartPosition!.dy - 48,
                child: IgnorePointer(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    scale: _showHeart ? 1 : 0.6,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _showHeart ? 1 : 0,
                      child: const Icon(
                        Icons.favorite,
                        size: 96,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class EdgeLongPressStrip extends StatelessWidget {
  const EdgeLongPressStrip({super.key, required this.onVisibilityChanged});

  final ValueChanged<bool> onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => onVisibilityChanged(true),
      onLongPressEnd: (_) => onVisibilityChanged(false),
      onLongPressCancel: () => onVisibilityChanged(false),
      child: const SizedBox.expand(),
    );
  }
}

class SuperLikeParticle {
  const SuperLikeParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.rotation,
    required this.color,
  });

  final double angle;
  final double distance;
  final double size;
  final double rotation;
  final Color color;
}

class FeedModeChip extends StatelessWidget {
  const FeedModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});

  final SwipeController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  int? _selectedColorIndex;
  List<int>? _searchOrder;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearchTimeline(int paletteIndex) {
    setState(() {
      _selectedColorIndex = paletteIndex;
      _searchOrder = _searchTimelineOrder(paletteIndex);
    });
  }

  Future<void> _refreshSearchTimeline() async {
    if (_selectedColorIndex == null || _searchOrder == null) {
      return;
    }

    setState(() {
      _searchOrder = _reshuffledOrder(
        _searchOrder!,
        pinnedStart: _selectedColorIndex,
      );
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  Widget _buildSearchTimeline() {
    return ColorTimelineView(
      key: ValueKey('search-timeline-$_selectedColorIndex'),
      controller: widget.controller,
      initialPage: _feedStartingPage,
      colorForPage: (pageIndex, enableColorChange) =>
          timelineColorForPage(pageIndex, enableColorChange, _searchOrder!),
      onRefresh: _refreshSearchTimeline,
      pageKeyPrefix: 'search',
      topOverlay: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Material(
            color: const Color(0x66000000),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => setState(() {
                _selectedColorIndex = null;
                _searchOrder = null;
              }),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedColorIndex != null) {
      return _buildSearchTimeline();
    }

    final query = _searchController.text.trim().toLowerCase();
    final entries = _feedColors.asMap().entries.where((entry) {
      if (query.isEmpty) {
        return true;
      }

      return entry.value.name.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search colors',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFF151515),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          if (entries.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No colors matched that search.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = entries[index % entries.length];
                  return SearchColorTile(
                    entry: entry.value,
                    tileIndex: index,
                    onTap: () => _openSearchTimeline(entry.key),
                  );
                }),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SearchColorTile extends StatelessWidget {
  const SearchColorTile({
    super.key,
    required this.entry,
    required this.tileIndex,
    required this.onTap,
  });

  final ColorEntry entry;
  final int tileIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: entry.color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: ValueKey('search-color-$tileIndex'),
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Semantics(
          label: entry.name,
          button: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final SwipeController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep the feed bare and tune what gets shown.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: controller.showCounter,
                      title: const Text('Show counter'),
                      subtitle: const Text(
                        'Keep the swipe count at the center',
                      ),
                      onChanged: controller.setShowCounter,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      value: controller.colorChangeEnabled,
                      title: const Text('Change background color'),
                      subtitle: const Text(
                        'Rotate the background on every swipe',
                      ),
                      onChanged: controller.setColorChangeEnabled,
                    ),
                    const Divider(height: 1),
                    SwitchListTile.adaptive(
                      value: controller.showFeedTabs,
                      title: const Text('Show top tabs'),
                      subtitle: const Text(
                        'Display Following and For You at the top',
                      ),
                      onChanged: controller.setShowFeedTabs,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.query_stats_outlined),
                      title: const Text('Stats'),
                      subtitle: const Text('Current session and daily totals'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                StatsPage(controller: controller),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('Guide'),
                      subtitle: const Text('Gestures, tabs, and feature notes'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const GuidePage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guide'), backgroundColor: Colors.black),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: const [
          GuideSection(
            title: 'Gestures',
            items: [
              'Swipe up to move to the next screen.',
              'Swipe down to go back to a previous screen.',
              'Pull down at the very start to refresh and reshuffle the current timeline.',
              'Swipe left or right on Home to switch between Following and For You.',
              'Double tap anywhere to like that moment.',
              'Every 5 likes triggers a super-like burst.',
              'Long press either edge to show the 2x speed note.',
            ],
          ),
          SizedBox(height: 16),
          GuideSection(
            title: 'Tabs',
            items: [
              'Home opens the swipe feed.',
              'Following and For You switch between two different home timelines.',
              'Search opens an infinite color grid and each color can open its own timeline.',
              'Settings opens toggles, stats, and this guide.',
            ],
          ),
          SizedBox(height: 16),
          GuideSection(
            title: 'Features',
            items: [
              'The center counter tracks the current session swipe count.',
              'Background color changes can be turned on or off.',
              'The top Following and For You tabs can be hidden.',
              'Stats show the current session and total history across days.',
              'Stats and settings are stored locally on this device.',
            ],
          ),
        ],
      ),
    );
  }
}

class GuideSection extends StatelessWidget {
  const GuideSection({super.key, required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '- $item',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.controller});

  final SwipeController controller;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }

      setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final dailyTotals = controller.dailyTotalsIncludingCurrent;
    final totalSessions = dailyTotals.fold<int>(
      0,
      (sum, day) => sum + day.sessions,
    );
    final totalSwipes = dailyTotals.fold<int>(
      0,
      (sum, day) => sum + day.swipes,
    );
    final totalLikes = dailyTotals.fold<int>(0, (sum, day) => sum + day.likes);
    final totalDurationSeconds = dailyTotals.fold<int>(
      0,
      (sum, day) => sum + day.durationSeconds,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Stats'), backgroundColor: Colors.black),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text(
            'Current session',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatCard(label: 'Swipes', value: '${controller.sessionSwipes}'),
              StatCard(label: 'Likes', value: '${controller.sessionLikes}'),
              StatCard(
                label: 'Duration',
                value: formatDuration(controller.currentSessionDuration),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Across days',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatCard(label: 'Sessions', value: '$totalSessions'),
              StatCard(label: 'Swipes', value: '$totalSwipes'),
              StatCard(label: 'Likes', value: '$totalLikes'),
              StatCard(
                label: 'Time',
                value: formatDuration(Duration(seconds: totalDurationSeconds)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (dailyTotals.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'No history yet. Start swiping and your daily totals will appear here.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            ...dailyTotals.map(
              (day) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day.dayKey,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          MiniStat(label: 'Sessions', value: '${day.sessions}'),
                          MiniStat(label: 'Swipes', value: '${day.swipes}'),
                          MiniStat(label: 'Likes', value: '${day.likes}'),
                          MiniStat(
                            label: 'Time',
                            value: formatDuration(
                              Duration(seconds: day.durationSeconds),
                            ),
                          ),
                        ],
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

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(14),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label\n',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class SwipeController extends ChangeNotifier with WidgetsBindingObserver {
  SwipeController(this._preferences)
    : showCounter = _preferences.getBool(_showCounterKey) ?? true,
      colorChangeEnabled = _preferences.getBool(_colorChangeKey) ?? true,
      showFeedTabs = _preferences.getBool(_showFeedTabsKey) ?? true {
    WidgetsBinding.instance.addObserver(this);
    _loadHistory();
  }

  final SharedPreferences _preferences;
  final Map<String, DailyStats> _dailyStats = {};

  bool showCounter;
  bool colorChangeEnabled;
  bool showFeedTabs;
  int sessionSwipes = 0;
  int sessionLikes = 0;
  bool _sessionArchivedForBackground = false;
  bool _sessionStored = false;
  DateTime _sessionStartedAt = DateTime.now();

  Duration get currentSessionDuration =>
      DateTime.now().difference(_sessionStartedAt);

  List<DailyStats> get dailyTotalsIncludingCurrent {
    final mergedHistory = Map<String, DailyStats>.from(_dailyStats);
    if (_sessionHasMeaningfulActivity) {
      final todayKey = _dayKey(_sessionStartedAt);
      final archived = mergedHistory[todayKey] ?? DailyStats.empty(todayKey);
      mergedHistory[todayKey] = archived.merge(
        DailyStats(
          dayKey: todayKey,
          sessions: 1,
          swipes: sessionSwipes,
          likes: sessionLikes,
          durationSeconds: currentSessionDuration.inSeconds,
        ),
      );
    }

    final entries = mergedHistory.values.toList()
      ..sort((left, right) => right.dayKey.compareTo(left.dayKey));
    return entries;
  }

  bool get _sessionHasMeaningfulActivity =>
      sessionSwipes > 0 ||
      sessionLikes > 0 ||
      currentSessionDuration.inSeconds >= 5;

  void registerSwipe() {
    sessionSwipes += 1;
    notifyListeners();
  }

  int registerLike() {
    sessionLikes += 1;
    notifyListeners();
    return sessionLikes;
  }

  void setShowCounter(bool value) {
    if (showCounter == value) {
      return;
    }

    showCounter = value;
    unawaited(_preferences.setBool(_showCounterKey, value));
    notifyListeners();
  }

  void setColorChangeEnabled(bool value) {
    if (colorChangeEnabled == value) {
      return;
    }

    colorChangeEnabled = value;
    unawaited(_preferences.setBool(_colorChangeKey, value));
    notifyListeners();
  }

  void setShowFeedTabs(bool value) {
    if (showFeedTabs == value) {
      return;
    }

    showFeedTabs = value;
    unawaited(_preferences.setBool(_showFeedTabsKey, value));
    notifyListeners();
  }

  void _loadHistory() {
    final rawHistory = _preferences.getString(_dailyStatsKey);
    if (rawHistory == null || rawHistory.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(rawHistory) as List<dynamic>;
      for (final entry in decoded) {
        final stats = DailyStats.fromJson(
          Map<String, dynamic>.from(entry as Map),
        );
        _dailyStats[stats.dayKey] = stats;
      }
    } on FormatException {
      _dailyStats.clear();
    }
  }

  Future<void> _archiveCurrentSessionIfNeeded() async {
    if (_sessionStored || !_sessionHasMeaningfulActivity) {
      return;
    }

    final dayKey = _dayKey(_sessionStartedAt);
    final existing = _dailyStats[dayKey] ?? DailyStats.empty(dayKey);
    _dailyStats[dayKey] = existing.merge(
      DailyStats(
        dayKey: dayKey,
        sessions: 1,
        swipes: sessionSwipes,
        likes: sessionLikes,
        durationSeconds: currentSessionDuration.inSeconds,
      ),
    );
    _sessionStored = true;

    final encoded = jsonEncode(
      _dailyStats.values.map((stats) => stats.toJson()).toList(),
    );
    await _preferences.setString(_dailyStatsKey, encoded);
  }

  void _startNewSession() {
    sessionSwipes = 0;
    sessionLikes = 0;
    _sessionStored = false;
    _sessionStartedAt = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_sessionArchivedForBackground) {
        _sessionArchivedForBackground = false;
        _startNewSession();
        notifyListeners();
      }
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_sessionArchivedForBackground) {
        return;
      }

      _sessionArchivedForBackground = true;
      unawaited(_archiveCurrentSessionIfNeeded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_archiveCurrentSessionIfNeeded());
    super.dispose();
  }
}

class DailyStats {
  const DailyStats({
    required this.dayKey,
    required this.sessions,
    required this.swipes,
    required this.likes,
    required this.durationSeconds,
  });

  final String dayKey;
  final int sessions;
  final int swipes;
  final int likes;
  final int durationSeconds;

  factory DailyStats.empty(String dayKey) {
    return DailyStats(
      dayKey: dayKey,
      sessions: 0,
      swipes: 0,
      likes: 0,
      durationSeconds: 0,
    );
  }

  factory DailyStats.fromJson(Map<String, dynamic> json) {
    return DailyStats(
      dayKey: json['dayKey'] as String,
      sessions: json['sessions'] as int? ?? 0,
      swipes: json['swipes'] as int? ?? 0,
      likes: json['likes'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
    );
  }

  DailyStats merge(DailyStats other) {
    return DailyStats(
      dayKey: dayKey,
      sessions: sessions + other.sessions,
      swipes: swipes + other.swipes,
      likes: likes + other.likes,
      durationSeconds: durationSeconds + other.durationSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dayKey': dayKey,
      'sessions': sessions,
      'swipes': swipes,
      'likes': likes,
      'durationSeconds': durationSeconds,
    };
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }

  return '${duration.inMinutes.toString().padLeft(2, '0')}:$seconds';
}

String _dayKey(DateTime dateTime) {
  final year = dateTime.year.toString().padLeft(4, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
