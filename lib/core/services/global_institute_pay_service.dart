//Proses Pembayaran di sini
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

// ── Log helper ────────────────────────────────────────────────
void _log(String tag, String message) {
  debugPrint('[JajanSkuy/$tag] $message');
}

// ── A. Model data callback ────────────────────────────────────────────
class PaymentCallbackData {
  final String status; // 'success', 'failed', 'cancelled'
  final String? reference; // INV-123 (referensi dari merchant)
  final String? transactionId; // ID transaksi dari Dompet Kampus

  const PaymentCallbackData({
    required this.status,
    this.reference,
    this.transactionId,
  });

  bool get isSuccess => status == 'success';

  @override
  String toString() =>
      'PaymentCallbackData(status=$status, reference=$reference, transactionId=$transactionId)';
}
// Pola yang digunakan: Value Object — objek kecil yang hanya membawa data tanpa logika bisnis yang kompleks.

// ── B. Service menggunakan Singleton pattern───────────────────────────────────────────────────
/// Mengelola deeplink keluar ke Dompet Kampus Global dan deeplink masuk (callback pembayaran) ke Jajan Skuy.
class GlobalInstitutePayService {
  static final GlobalInstitutePayService _instance =
      GlobalInstitutePayService._(); //Instance statis — dibuat sekali, hidup sepanjang app
  factory GlobalInstitutePayService() =>
      _instance; // Factory constructor — selalu kembalikan instance yang sama
  GlobalInstitutePayService._(); // Private constructor — mencegah pembuatan dari luar

  static const _tag = 'GlobalInstitutePay';


  // C. Broadcast Stream (broadcast()) = bisa punya banyak listener sekaligus    
  final _callbackController = StreamController<PaymentCallbackData>.broadcast();

  // Expose sebagai read-only Stream   
  Stream<PaymentCallbackData> get onCallback => _callbackController.stream;

  // D. Penanganan Cold Start
  PaymentCallbackData? _pendingCallback; // Simpan callback cold start — bisa diambil sekali 

  /// Ambil callback cold-start, dikosongkan (dihapus) setelah dibaca (consume-once).
  PaymentCallbackData? consumePendingCallback() {
    final data = _pendingCallback;
    _pendingCallback = null;
    if (data != null) {
      _log(_tag, ' Mengonsumsi pending cold-start callback: $data');
    }
    return data;
  }
  /*Masalah yang Dipecahkan:
    Skenario: User ada di halaman PaymentPending → minimize app → Dompet Kampus
    mengirim callback → app restart dari cold start → callback sudah masuk
    sebelum initState() widget. Tanpa _pendingCallback, callback ini hilang.*/

  // ── E. Inisialisasi Listener ────────────────────────────────────────────────────
  Future<void> init() async {
    _log(_tag, ' Inisialisasi GlobalInstitutePayService...');

    final appLinks = AppLinks();

    // Kasus 1: cold start — app dibuka oleh deeplink
    try {
      _log(_tag, ' Mengambil initial link (cold start)...');
      final uri = await appLinks.getInitialLink();
      if (uri != null) {
        _log(_tag, ' Initial link ditemukan: $uri');
        _handleUri(uri, isColdStart: true);
      } else {
        _log(_tag, 'ℹ Tidak ada initial link (app dibuka normal)');
      }
    } catch (e) {
      _log(_tag, 'Error saat getInitialLink: $e');
    }

    // Kasus 2: app sudah berjalan — deeplink masuk via stream
    _log(_tag, ' Memulai listener uriLinkStream...');
    appLinks.uriLinkStream.listen(
      (uri) {
        _log(_tag, ' URI masuk via stream: $uri');
        _handleUri(uri);
      },
      onError: (Object e) {
        _log(_tag, 'Error pada uriLinkStream: $e');
      },
    );

    _log(_tag, ' Inisialisasi selesai.');
  }

  // ── F. Handle URI masuk (Parsing URI Callback) ─────────────────────────────────────────
  void _handleUri(Uri uri, {bool isColdStart = false}) {
    //Tambahkan logging (debugPrint) sementara di service untuk debugging:
    debugPrint('[GlobalInstitutePayService] URI diterima: $uri');    
    debugPrint('[GlobalInstitutePayService] Cold start: $isColdStart');   
    _log(
      _tag,
      ' Handle URI | scheme=${uri.scheme} host=${uri.host} '
      'path=${uri.path} params=${uri.queryParameters} | coldStart=$isColdStart',
    );

    // Filter: hanya proses callback Jajan Skuy atau hanya proses URI yang relevan
    if (uri.scheme != 'jajanskuy') {
      _log(_tag, '⏩ Diabaikan — bukan skema jajanskuy (scheme=${uri.scheme})');
      return;
    }
    if (uri.host != 'payment-callback') {
      _log(
        _tag,
        '⏩ Diabaikan — bukan host payment-callback (host=${uri.host})',
      );
      return;
    }
    debugPrint('[GlobalInstitutePayService] Callback params: ${uri.queryParameters}');

    final data = PaymentCallbackData(
      status: uri.queryParameters['status'] ?? 'unknown',
      reference: uri.queryParameters['reference'],
      transactionId: uri.queryParameters['transaction_id'],
    );

    _log(_tag, ' Callback diterima: $data');

    // Simpan untuk cold start
    if (isColdStart) {
      _pendingCallback = data;
      _log(_tag, ' Disimpan sebagai pending cold-start callback');
    }

    _callbackController.add(data); // Broadcast ke semua listener aktif 
    // URI lain (misal: skema (URI) lain yang tidak relevan) diabaikan    
    _log(_tag, ' Event dikirim ke stream (subscriber aktif)');
  }

  /// G. Membangun URL deeplink ke Dompet Kampus Global sesuai spesifikasi.
  static String buildDeeplinkUrl({
    required int orderId,
    required double amount,
    String? description,
  }) {
    const scheme = 'dompetkampus';
    const host = 'pay';
    final desc = (description != null && description.isNotEmpty)
        ? description
        : 'Order #$orderId';
    const callbackUrl = 'jajanskuy://payment-callback';

    _log(_tag, 'Membangun deeplink URL:');
    _log(_tag, 'merchant_id : MCH_JAJAN_SKUY');
    _log(_tag, 'merchant_name: Jajan Skuy');
    _log(_tag, 'amount : ${amount.toInt()}');
    _log(_tag, 'description : $desc');
    _log(_tag, 'reference : INV-$orderId');
    _log(_tag, 'callback : $callbackUrl');

    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: {
        'merchant_id': 'MCH_JAJAN_SKUY',
        'merchant_name': 'Jajan Skuy',
        'amount': amount.toInt().toString(),
        'description': desc,
        'reference': 'INV-$orderId',
        'callback': callbackUrl,
      },
    );
    /*Keunggulan `Uri()` constructor:
      Dart secara otomatis melakukan percent-encoding pada semua query parameter.
      Spasi → %20, / → %2F, dll. Tidak perlu manual.*/


    final result = uri.toString();
    _log(_tag, ' URL lengkap (sebelum launch): $result');
    return result;
  }
}
