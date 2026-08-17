import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/theme/glass.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActivateRiyaPlayTVScreen extends StatefulWidget {
  const ActivateRiyaPlayTVScreen({super.key});

  @override
  ActivateRiyaPlayTVScreenState createState() =>
      ActivateRiyaPlayTVScreenState();
}

class ActivateRiyaPlayTVScreenState extends State<ActivateRiyaPlayTVScreen> {
  MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _isProcessing = false;
  bool _isCameraActive = true;
  bool _hasCameraError = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _checkAndShowInstructions();
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Kamera ruxsati kerak")));
      Navigator.pop(context);
    }
  }

  Future<void> _checkAndShowInstructions() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownInstructions =
        prefs.getBool('has_shown_instructions') ?? false;
    if (!hasShownInstructions && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showInstructionsDialog();
        prefs.setBool('has_shown_instructions', true);
      });
    }
  }

  void _showInstructionsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              "RiyaPlay TVni faollashtirish",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color:
                    Provider.of<ThemeProvider>(context).isDarkMode
                        ? Colors.white
                        : Colors.black87,
              ),
            ),
            content: Text(
              "TV ekranidagi QR kodni skanerlang. Kodni skanerlash uchun telefoningiz kamerasini TV ekraniga yo‘naltiring.",
              style: TextStyle(
                fontSize: 14,
                color:
                    Provider.of<ThemeProvider>(context).isDarkMode
                        ? Colors.grey[400]
                        : Colors.grey[600],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Tushundim",
                  style: TextStyle(
                    color:
                        Provider.of<ThemeProvider>(context).isDarkMode
                            ? Colors.blue[300]
                            : Colors.blue,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing || !mounted) return;
    setState(() {
      _isProcessing = true;
      _isCameraActive = false;
      _hasCameraError = false;
    });
    await controller.stop();

    final code = capture.barcodes.first.rawValue;
    if (code != null) {
      try {
        final response = await ApiService.checkQR(hash: code);
        if (response is List && response.isNotEmpty && mounted) {
          final currentDeviceId = await ApiService.getCurrentDeviceId();
          final currentDevice = response.firstWhere(
            (device) => device['id'].toString() == currentDeviceId,
            orElse: () => null,
          );
          final otherDevices =
              response
                  .where((device) => device['id'].toString() != currentDeviceId)
                  .toList();
          _showDeviceSelectionDialog(code, otherDevices, currentDevice);
        } else if (response is Map && response['id'] != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("RiyaPlay TV muvaffaqiyatli faollashtirildi!"),
            ),
          );
          Navigator.pop(context);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Faollashtirishda xatolik")),
          );
          _resumeCamera();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Xatolik: $e")));
          _resumeCamera();
        }
      }
    } else {
      _resumeCamera();
    }
  }

  void _showDeviceSelectionDialog(
    String hash,
    List<dynamic> otherDevices,
    dynamic currentDevice,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            // Qolgan dialoglar bilan bir xil shisha yuza.
            decoration: BoxDecoration(
              gradient: GlassSurface.gradient,
              borderRadius: GlassSurface.borderRadius,
              border: GlassSurface.border,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    "Qurilma tanlang",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color:
                          themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Tizimda 2 tadan ko‘p qurilma mavjud. Davom etish uchun quyidagi qurilmalardan birini o‘chirish kerak:",
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                themeProvider.isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (currentDevice != null) ...[
                          _buildDeviceCard(
                            currentDevice,
                            themeProvider,
                            isCurrent: true,
                            hash: hash,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (otherDevices.isNotEmpty) ...[
                          Text(
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
                          const SizedBox(height: 8),
                          ...otherDevices.asMap().entries.map((entry) {
                            final device = entry.value;
                            return _buildDeviceCard(
                              device,
                              themeProvider,
                              isCurrent: false,
                              hash: hash,
                            );
                          }).toList(),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _resumeCamera();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            themeProvider.isDarkMode
                                ? Colors.grey[700]
                                : Colors.grey[300],
                        foregroundColor:
                            themeProvider.isDarkMode
                                ? Colors.white
                                : Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        "Bekor qilish",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceCard(
    dynamic device,
    ThemeProvider themeProvider, {
    required bool isCurrent,
    required String hash,
  }) {
    final deviceName = device['device_name'] ?? "Noma'lum qurilma";
    final deviceId = device['id']?.toString() ?? "ID yo‘q";
    final createdAt =
        device['created_at'] != null
            ? DateFormat('yyyy-MM-dd HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(device['created_at'] * 1000),
            )
            : "Vaqt ma'lumoti yo‘q";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            isCurrent
                ? (themeProvider.isDarkMode
                    ? const Color(0xFF2A3447)
                    : Colors.white)
                : (themeProvider.isDarkMode
                    ? const Color(0xFF1F2937)
                    : Colors.grey[100]),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color:
              isCurrent
                  ? (themeProvider.isDarkMode
                      ? Colors.blue[300]!
                      : Colors.blue[500]!)
                  : (themeProvider.isDarkMode
                      ? Colors.grey[700]!
                      : Colors.grey[300]!),
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
                  isCurrent
                      ? (themeProvider.isDarkMode
                          ? Colors.blue[300]
                          : Colors.blue[600])
                      : (themeProvider.isDarkMode
                          ? Colors.grey[400]
                          : Colors.grey[700]),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrent ? "Joriy qurilma" : "Qurilma",
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        isCurrent
                            ? (themeProvider.isDarkMode
                                ? Colors.blue[300]
                                : Colors.blue[600])
                            : (themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600]),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deviceName,
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
                  "Kirish vaqti: $createdAt",
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
          if (!isCurrent)
            GestureDetector(
              onTap: () async {
                try {
                  final success = await ApiService.kickDevice(
                    device['id'].toString(),
                  );
                  if (success) {
                    Navigator.pop(context);
                    final response = await ApiService.checkQR(hash: hash);
                    if (response is Map && response['id'] != null && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "RiyaPlay TV muvaffaqiyatli faollashtirildi!",
                          ),
                        ),
                      );
                      Navigator.pop(context);
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Qurilma ro‘yxatga olishda xatolik"),
                        ),
                      );
                      _resumeCamera();
                    }
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Qurilma o‘chirishda xatolik"),
                      ),
                    );
                    _resumeCamera();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Xatolik: $e")));
                    _resumeCamera();
                  }
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
                child: const Icon(Icons.delete, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _resumeCamera() async {
    if (!mounted) return;

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Kamera ruxsati kerak")));
          Navigator.pop(context);
        }
        return;
      }
    }

    try {
      if (!controller.value.isInitialized) {
        await controller.dispose();
        controller = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: controller.torchEnabled,
        );
      }
      await controller.start();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isCameraActive = true;
          _hasCameraError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isCameraActive = false;
          _hasCameraError = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Kamera qayta ishga tushirishda xatolik: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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
          'RiyaPlay TVni faollashtirish',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_isCameraActive && !_hasCameraError)
            MobileScanner(
              controller: controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                return Center(
                  child: Text(
                    'Kamera xatosi: $error',
                    style: TextStyle(
                      color:
                          themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                );
              },
            ),
          if (_hasCameraError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 48,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Kamera ishga tushmadi",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color:
                          themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Iltimos, qayta urinib ko‘ring yoki kamera ruxsatlarini tekshiring",
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          themeProvider.isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _resumeCamera,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          themeProvider.isDarkMode
                              ? Colors.blue[700]
                              : Colors.blue[500],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: 5,
                    ),
                    child: const Text(
                      "Qayta urinish",
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      themeProvider.isDarkMode
                          ? Colors.black.withOpacity(0.7)
                          : Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(
                        themeProvider.isDarkMode ? 0.3 : 0.1,
                      ),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'TV ekranidagi QR kodni skanerlang',
                  style: TextStyle(
                    color:
                        themeProvider.isDarkMode
                            ? Colors.white
                            : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (_isCameraActive && !_hasCameraError)
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color:
                          themeProvider.isDarkMode
                              ? Colors.blue[300]!
                              : Colors.blue[500]!,
                      width: 4,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          if (_isProcessing) const Center(child: CircularProgressIndicator()),
          if (!_isCameraActive && !_isProcessing && !_hasCameraError)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton(
                  onPressed: _resumeCamera,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        themeProvider.isDarkMode
                            ? Colors.blue[700]
                            : Colors.blue[500],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    "Qayta urinish",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          if (_isCameraActive && !_hasCameraError)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[800]
                            : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          themeProvider.isDarkMode ? 0.3 : 0.1,
                        ),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      controller.torchEnabled
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color:
                          themeProvider.isDarkMode
                              ? Colors.yellow[300]
                              : Colors.yellow[700],
                      size: 32,
                    ),
                    onPressed: () async {
                      try {
                        await controller.toggleTorch();
                        if (mounted) {
                          setState(() {});
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Chiroqni yoqishda xatolik: $e"),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
