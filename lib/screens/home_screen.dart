import 'package:flutter/material.dart';
import '../constants.dart';
import 'chat_screen.dart';
import '../widgets/sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _sidebarController;
  double _dragProgress = 0.0; // 0.0 = closed, 1.0 = open
  bool _isSidebarOpen = false;

  @override
  void initState() {
    super.initState();
    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    // Close keyboard when opening sidebar
    if (!_isSidebarOpen) {
      FocusScope.of(context).unfocus();
    }
    
    if (_isSidebarOpen) {
      _closeSidebar();
    } else {
      _openSidebar();
    }
  }

  void _openSidebar() {
    setState(() => _isSidebarOpen = true);
    _sidebarController.animateTo(1.0, curve: Curves.easeOutCubic);
  }

  void _closeSidebar() {
    setState(() => _isSidebarOpen = false);
    _sidebarController.animateTo(0.0, curve: Curves.easeOutCubic);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // Close keyboard when starting to drag
    FocusScope.of(context).unfocus();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.primaryDelta ?? 0;
    
    setState(() {
      // Update drag progress based on finger movement
      _dragProgress = (_sidebarController.value + (delta / screenWidth)).clamp(0.0, 1.0);
      _sidebarController.value = _dragProgress;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    
    // Determine whether to open or close based on velocity and position
    if (velocity.abs() > 300) {
      // Fast swipe - use velocity direction
      if (velocity > 0) {
        _openSidebar();
      } else {
        _closeSidebar();
      }
    } else {
      // Slow drag - use threshold
      if (_sidebarController.value > 0.5) {
        _openSidebar();
      } else {
        _closeSidebar();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return PopScope(
      canPop: !_isSidebarOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSidebarOpen) {
          _closeSidebar();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.sidebarBg(context),
        body: AnimatedBuilder(
          animation: _sidebarController,
          builder: (context, child) {
            final progress = _sidebarController.value;
            
            return Stack(
              children: [
                // Sidebar (full width, always in the background)
                Positioned.fill(
                  child: Sidebar(onClose: _closeSidebar),
                ),
                
                // Chat screen that slides over the sidebar
                Transform.translate(
                  offset: Offset(screenWidth * progress, 0),
                  child: GestureDetector(
                    onHorizontalDragStart: _onHorizontalDragStart,
                    onHorizontalDragUpdate: _onHorizontalDragUpdate,
                    onHorizontalDragEnd: _onHorizontalDragEnd,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: progress > 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3 * progress),
                                  blurRadius: 20,
                                  offset: const Offset(-4, 0),
                                ),
                              ]
                            : null,
                      ),
                      child: ChatScreen(onMenuTap: _toggleSidebar),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
