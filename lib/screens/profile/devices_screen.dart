import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/theme_provider.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  _DevicesScreenState createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> devices = [];
  bool isLoadingDevices = true;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  Map<String, dynamic>? currentDevice;
  String currentDeviceId = '';

  @override
  void initState() {
    super.initState();
    _fetchDevicesAndCurrentDevice();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchDevicesAndCurrentDevice() async {
    try {
      currentDeviceId = await ApiService.getCurrentDeviceId();
      final deviceList = await ApiService.getDevices();
      setState(() {
        currentDevice = deviceList.firstWhere(
          (device) => device['id'].toString() == currentDeviceId,
          orElse: () => null,
        );
        devices =
            deviceList
                .where((device) => device['id'].toString() != currentDeviceId)
                .toList();
        isLoadingDevices = false;
      });
    } catch (e) {
      setState(() => isLoadingDevices = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Qurilmalarni yuklashda xato: $e')),
        );
      }
    }
  }

  String _formatDateTime(int? timestamp) {
    if (timestamp == null) return "Noma'lum";
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
    } catch (e) {
      return "Noma'lum";
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor:
            themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Qurilmalar',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        top: true,
        child:
            isLoadingDevices
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color:
                            themeProvider.isDarkMode
                                ? Colors.white
                                : Colors.blue,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Qurilmalar yuklanmoqda...",
                        style: TextStyle(
                          color:
                              themeProvider.isDarkMode
                                  ? Colors.white
                                  : Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
                : RefreshIndicator(
                  onRefresh: _fetchDevicesAndCurrentDevice,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.blue,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (currentDevice != null) ...[
                            Container(
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color:
                                    themeProvider.isDarkMode
                                        ? const Color(0xFF2A3447)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.blue[300]!
                                          : Colors.blue[500]!,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(
                                      themeProvider.isDarkMode ? 0.3 : 0.1,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.white.withOpacity(0.2)
                                              : Colors.grey[200],
                                    ),
                                    child: Icon(
                                      Icons.devices,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.blue[300]
                                              : Colors.blue[600],
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Joriy qurilma",
                                          style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.blue[300]
                                                    : Colors.blue[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          currentDevice!['device_name'] ??
                                              "Noma'lum qurilma",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Qurilma ID: ${currentDevice!['id']?.toString() ?? 'ID yo‘q'}",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Kirish vaqti: ${_formatDateTime(currentDevice!['created_at'])}",
                                          style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (devices.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                "Boshqa seanslar",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                ),
                              ),
                            ),
                            ...devices.asMap().entries.map((entry) {
                              final index = entry.key;
                              final device = entry.value;
                              return _buildDeviceCard(device, index);
                            }).toList(),
                          ] else ...[
                            Center(
                              child: Text(
                                "Boshqa seanslar topilmadi",
                                style: TextStyle(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildDeviceCard(dynamic device, int index) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final deviceId = device['id']?.toString() ?? "ID yo‘q";
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTapDown: (_) => _animationController.forward(),
        onTapUp: (_) => _animationController.reverse(),
        onTapCancel: () => _animationController.reverse(),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      themeProvider.isDarkMode
                          ? const Color(0xFF1F2937)
                          : Colors.grey[100],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[700]!
                            : Colors.grey[300]!,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        themeProvider.isDarkMode ? 0.3 : 0.1,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            themeProvider.isDarkMode
                                ? Colors.white.withOpacity(0.2)
                                : Colors.grey[200],
                      ),
                      child: Icon(
                        Icons.devices,
                        color:
                            themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[700],
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device['device_name'] ?? "Noma'lum qurilma",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Qurilma ID: $deviceId",
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Kirish vaqti: ${_formatDateTime(device['created_at'])}",
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        try {
                          final success = await ApiService.kickDevice(
                            device['id'].toString(),
                          );
                          if (success) {
                            setState(() {
                              devices.removeAt(index);
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Qurilmani o‘chirishda xatolik yuz berdi',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Xatolik: $e')),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color:
                              themeProvider.isDarkMode
                                  ? Colors.red[700]
                                  : Colors.red[500],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
