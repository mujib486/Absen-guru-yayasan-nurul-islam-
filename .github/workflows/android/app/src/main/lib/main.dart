import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ================= KONFIGURASI YAYASAN NURUL ISLAM =================
const String namaSekolah = "Yayasan Nurul Islam";
const String scriptUrl = "https://script.google.com/macros/s/AKfycbwNKSUOHgCo-O3ZHZhVTjs_D4WCBd1utj3KO0POf-QOJaIxmjwckTpivaWeTia1Yvkl/exec";
const double sekolahLat = -7.737446;
const double sekolahLng = 113.416802;
const double radiusMaksimalMeter = 50.0;

// Palet Warna Tema (Hijau Teal, Putih, Kuning Lemon)
const Color warnaTealUtama = Color(0xFF00796B);
const Color warnaTealGelap = Color(0xFF004D40);
const Color warnaTealMuda = Color(0xFFE0F2F1);
const Color warnaKuningLemon = Color(0xFFFDE047);
const Color warnaPutih = Color(0xFFFFFFFF);
// ===================================================================

void main() {
  runApp(const AbsenGuruApp());
}

class AbsenGuruApp extends StatelessWidget {
  const AbsenGuruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Absen Guru Yayasan Nurul Islam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6FAF9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: warnaTealUtama,
          primary: warnaTealUtama,
          secondary: warnaKuningLemon,
          surface: warnaPutih,
        ),
        useMaterial3: true,
      ),
      home: const HalamanAbsen(),
    );
  }
}

class HalamanAbsen extends StatefulWidget {
  const HalamanAbsen({super.key});

  @override
  State<HalamanAbsen> createState() => _HalamanAbsenState();
}

class _HalamanAbsenState extends State<HalamanAbsen> {
  final TextEditingController _namaController = TextEditingController();
  bool _isLoading = false;
  String _statusPesan = "Siap melakukan absensi";
  String _riwayatHariIni = "Belum ada catatan absen di perangkat ini";

  @override
  void initState() {
    super.initState();
    _muatDataTersimpan();
  }

  Future<void> _muatDataTersimpan() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _namaController.text = prefs.getString('nama_guru') ?? '';
      _riwayatHariIni = prefs.getString('riwayat_terakhir') ?? 'Belum ada catatan absen di perangkat ini';
    });
  }

  Future<Position> _ambilPosisiGps({required bool wajibDalamRadius}) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw "GPS HP Anda mati. Silakan aktifkan GPS terlebih dahulu.";
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw "Izin lokasi ditolak. Aplikasi membutuhkan akses GPS.";
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw "Izin lokasi diblokir permanen. Aktifkan melalui Pengaturan HP.";
    }

    Position posisi = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (posisi.isMocked) {
      throw "Terdeteksi menggunakan Fake GPS / Lokasi Palsu! Proses dibatalkan.";
    }

    if (wajibDalamRadius) {
      double jarakMeter = Geolocator.distanceBetween(
        sekolahLat,
        sekolahLng,
        posisi.latitude,
        posisi.longitude,
      );

      if (jarakMeter > radiusMaksimalMeter) {
        throw "Anda berada di luar area $namaSekolah (${jarakMeter.toStringAsFixed(1)} meter dari titik sekolah). Batas maksimal adalah ${radiusMaksimalMeter.toInt()} meter.";
      }
    }

    return posisi;
  }

  Future<void> _prosesAbsenHadir(String statusAbsen) async {
    final namaGuru = _namaController.text.trim();
    if (namaGuru.isEmpty) {
      _tampilkanAlert("Peringatan", "Silakan isi Nama Lengkap Guru terlebih dahulu.");
      return;
    }

    setState(() {
      _isLoading = true;
      _statusPesan = "Memeriksa titik koordinat GPS...";
    });

    try {
      Position posisi = await _ambilPosisiGps(wajibDalamRadius: true);
      double jarakMeter = Geolocator.distanceBetween(
        sekolahLat,
        sekolahLng,
        posisi.latitude,
        posisi.longitude,
      );

      setState(() => _statusPesan = "Membuka kamera selfie...");
      final ImagePicker picker = ImagePicker();
      final XFile? foto = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 45,
        maxWidth: 640,
      );

      if (foto == null) {
        setState(() {
          _isLoading = false;
          _statusPesan = "Pengambilan foto selfie dibatalkan.";
        });
        return;
      }

      setState(() => _statusPesan = "Mengirim data & foto ke sistem...");
      final bytes = await File(foto.path).readAsBytes();
      final String base64Foto = base64Encode(bytes);

      await _kirimKeGoogleSheets(
        namaGuru: namaGuru,
        status: statusAbsen,
        keterangan: "Hadir di Sekolah",
        koordinat: "${posisi.latitude}, ${posisi.longitude}",
        jarak: jarakMeter.toStringAsFixed(1),
        base64Foto: base64Foto,
      );
    } catch (e) {
      setState(() => _statusPesan = "Gagal: $e");
      _tampilkanAlert("Absensi Gagal", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _bukaFormIzinSakit() {
    final namaGuru = _namaController.text.trim();
    if (namaGuru.isEmpty) {
      _tampilkanAlert("Peringatan", "Silakan isi Nama Lengkap Guru terlebih dahulu sebelum mengajukan Izin/Sakit.");
      return;
    }

    String jenisPengajuan = "SAKIT";
    final TextEditingController alasanController = TextEditingController();
    XFile? fotoBukti;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: warnaPutih,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: warnaKuningLemon,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.assignment_late, color: warnaTealGelap),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Form Pengajuan Izin / Sakit",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: warnaTealGelap),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Pilih Kategori:", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text("SAKIT")),
                            selected: jenisPengajuan == "SAKIT",
                            selectedColor: warnaKuningLemon,
                            onSelected: (val) {
                              if (val) setModalState(() => jenisPengajuan = "SAKIT");
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text("IZIN")),
                            selected: jenisPengajuan == "IZIN",
                            selectedColor: warnaKuningLemon,
                            onSelected: (val) {
                              if (val) setModalState(() => jenisPengajuan = "IZIN");
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: alasanController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Keterangan / Alasan",
                        hintText: "Contoh: Demam tinggi / Ada keperluan keluarga mendesak",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? gambar = await picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 50,
                          maxWidth: 800,
                        );
                        if (gambar != null) {
                          setModalState(() => fotoBukti = gambar);
                        }
                      },
                      icon: Icon(fotoBukti == null ? Icons.camera_alt : Icons.check_circle, color: warnaTealUtama),
                      label: Text(
                        fotoBukti == null
                            ? "Foto Surat Keterangan / Bukti (Opsional)"
                            : "Foto Bukti Terlampir (${fotoBukti!.name})",
                        style: const TextStyle(color: warnaTealUtama),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: () async {
                        final alasan = alasanController.text.trim();
                        if (alasan.isEmpty) {
                          _tampilkanAlert("Peringatan", "Mohon isi keterangan/alasan terlebih dahulu.");
                          return;
                        }
                        Navigator.of(ctx).pop();
                        await _kirimPengajuanIzinSakit(
                          namaGuru: namaGuru,
                          jenis: jenisPengajuan,
                          alasan: alasan,
                          fotoBukti: fotoBukti,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: warnaTealUtama,
                        foregroundColor: warnaPutih,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("KIRIM PENGAJUAN", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _kirimPengajuanIzinSakit({
    required String namaGuru,
    required String jenis,
    required String alasan,
    XFile? fotoBukti,
  }) async {
    setState(() {
      _isLoading = true;
      _statusPesan = "Mengirim pengajuan $jenis...";
    });

    try {
      String koordinatStr = "-";
      String jarakStr = "-";

      try {
        Position posisi = await _ambilPosisiGps(wajibDalamRadius: false);
        double jarakMeter = Geolocator.distanceBetween(
          sekolahLat,
          sekolahLng,
          posisi.latitude,
          posisi.longitude,
        );
        koordinatStr = "${posisi.latitude}, ${posisi.longitude}";
        jarakStr = jarakMeter.toStringAsFixed(1);
      } catch (_) {
        // Tetap izinkan kirim izin/sakit meskipun GPS tidak terkunci
      }

      String base64Foto = "";
      if (fotoBukti != null) {
        final bytes = await File(fotoBukti.path).readAsBytes();
        base64Foto = base64Encode(bytes);
      }

      await _kirimKeGoogleSheets(
        namaGuru: namaGuru,
        status: jenis,
        keterangan: alasan,
        koordinat: koordinatStr,
        jarak: jarakStr,
        base64Foto: base64Foto,
      );
    } catch (e) {
      setState(() => _statusPesan = "Gagal: $e");
      _tampilkanAlert("Pengajuan Gagal", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _kirimKeGoogleSheets({
    required String namaGuru,
    required String status,
    required String keterangan,
    required String koordinat,
    required String jarak,
    required String base64Foto,
  }) async {
    final now = DateTime.now();
    final String tanggalStr = DateFormat('yyyy-MM-dd').format(now);
    final String jamStr = DateFormat('HH:mm:ss').format(now);

    final response = await http.post(
      Uri.parse(scriptUrl),
      headers: {"Content-Type": "text/plain"},
      body: jsonEncode({
        "tanggal": tanggalStr,
        "jam": jamStr,
        "nama": namaGuru,
        "status": status,
        "keterangan": keterangan,
        "koordinat": koordinat,
        "jarak": jarak,
        "foto_base64": base64Foto,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 302) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nama_guru', namaGuru);
      String catatan = "$status pada $tanggalStr pukul $jamStr";
      await prefs.setString('riwayat_terakhir', catatan);

      setState(() {
        _riwayatHariIni = catatan;
        _statusPesan = "Berhasil! $catatan";
      });
      _tampilkanAlert("Sukses", "Data $status untuk $namaGuru berhasil dicatat.");
    } else {
      throw "Gagal terhubung ke server Google Sheets (Kode: ${response.statusCode})";
    }
  }

  void _tampilkanAlert(String judul, String isi) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: warnaPutih,
        title: Text(judul, style: const TextStyle(fontWeight: FontWeight.bold, color: warnaTealGelap)),
        content: Text(isi),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Tutup", style: TextStyle(color: warnaTealUtama, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: warnaTealUtama,
        foregroundColor: warnaPutih,
        elevation: 0,
        centerTitle: true,
        title: const Column(
          children: [
            Text("ABSENSI KEHADIRAN GURU", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              namaSekolah,
              style: TextStyle(fontSize: 13, color: warnaKuningLemon, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 16,
              decoration: const BoxDecoration(
                color: warnaTealUtama,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Kartu Identitas Guru
                  Card(
                    color: warnaPutih,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: warnaTealUtama.withOpacity(0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: warnaKuningLemon,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "Identitas Guru",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: warnaTealGelap),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _namaController,
                            decoration: InputDecoration(
                              labelText: "Nama Lengkap & Gelar",
                              hintText: "Ketik nama lengkap Anda...",
                              filled: true,
                              fillColor: warnaTealMuda.withOpacity(0.35),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.person, color: warnaTealUtama),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "*Nama akan tersimpan otomatis di HP ini untuk absen berikutnya.",
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tombol Aksi Utama
                  if (_isLoading)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: warnaPutih,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(color: warnaTealUtama),
                          const SizedBox(height: 14),
                          Text(
                            _statusPesan,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: warnaTealGelap),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _prosesAbsenHadir("ABSEN MASUK"),
                                icon: const Icon(Icons.login, size: 24),
                                label: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text("ABSEN\nMASUK", textAlign: TextAlign.center),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: warnaTealUtama,
                                  foregroundColor: warnaPutih,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _prosesAbsenHadir("ABSEN PULANG"),
                                icon: const Icon(Icons.logout, size: 24),
                                label: const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Text("ABSEN\nPULANG", textAlign: TextAlign.center),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: warnaTealGelap,
                                  foregroundColor: warnaPutih,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Tombol Khusus Izin / Sakit (Aksen Kuning Lemon)
                        ElevatedButton.icon(
                          onPressed: _bukaFormIzinSakit,
                          icon: const Icon(Icons.medical_services_outlined, color: warnaTealGelap),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text("AJUKAN IZIN / SAKIT"),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: warnaKuningLemon,
                            foregroundColor: warnaTealGelap,
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 22),

                  // Kotak Info Radius & Riwayat Terakhir
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: warnaPutih,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: warnaTealUtama.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 18, color: warnaTealUtama),
                            const SizedBox(width: 6),
                            Text(
                              "Radius Absensi: Maksimal ${radiusMaksimalMeter.toInt()}m dari Sekolah",
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warnaTealGelap),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        const Text(
                          "Catatan Terakhir di Perangkat Ini:",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: warnaTealUtama),
                        ),
                        const SizedBox(height: 4),
                        Text(_riwayatHariIni, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
