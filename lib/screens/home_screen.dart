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
  late Animation<Offset> _slideAnimation;
  bool _isSidebarOpen = false;

  @override
  void initState() {
    super.initState();
    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    if (_isSidebarOpen) {
      _sidebarController.reverse();
    } else {
      _sidebarController.forward();
    }
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Stack(
        children: [
          ChatScreen(onMenuTap: _toggleSidebar),
          IgnorePointer(
            ignoring: !_isSidebarOpen,
            child: GestureDetector(
              onTap: _toggleSidebar,
              child: AnimatedOpacity(
                opacity: _isSidebarOpen ? 0.4 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(color: Colors.black),
              ),
            ),
          ),
          SlideTransition(
            position: _slideAnimation,
            child: Sidebar(onClose: _toggleSidebar),
          ),
        ],
      ),
    );
  }
}
