// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
//
// class WithdrawalScreen extends StatefulWidget {
//   final String userId;
//
//   const WithdrawalScreen({Key? key, required this.userId}) : super(key: key);
//
//   @override
//   State<WithdrawalScreen> createState() => _WithdrawalScreenState();
// }
//
// class _WithdrawalScreenState extends State<WithdrawalScreen> {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final TextEditingController _amountController = TextEditingController();
//   final String razorpayKeyId = 'YOUR_RAZORPAY_KEY_ID'; // .env में स्टोर करें
//   final String razorpayKeySecret = 'YOUR_RAZORPAY_KEY_SECRET'; // .env में स्टोर करें
//   double? _balance;
//   bool _canWithdraw = false;
//   Map<String, dynamic>? _paymentDetails;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadBalanceAndPaymentDetails();
//   }
//
//   Future<void> _loadBalanceAndPaymentDetails() async {
//     final workerDoc = await _firestore.collection('workers').doc(widget.userId).get();
//     if (workerDoc.exists) {
//       final data = workerDoc.data()!;
//       final lastTransaction = (data['transactions'] as List<dynamic>?)?.last;
//       if (lastTransaction != null && lastTransaction['creditedAt'] != null) {
//         final creditedAt = (lastTransaction['creditedAt'] as Timestamp).toDate();
//         final now = DateTime.now();
//         _canWithdraw = now.difference(creditedAt).inHours >= 24; // 24 घंटे का रिस्ट्रिक्शन
//       }
//       setState(() {
//         _balance = double.tryParse(data['balance']?.toString() ?? '0.0') ?? 0.0;
//         _paymentDetails = data['payment_details'] as Map<String, dynamic>?;
//       });
//     }
//   }
//
//   Future<void> _requestWithdrawal() async {
//     final amount = double.tryParse(_amountController.text) ?? 0.0;
//     if (amount <= 0 || amount > (_balance ?? 0.0)) {
//       _showErrorSnackBar('अमान्य अमाउंट');
//       return;
//     }
//
//     if (!_canWithdraw) {
//       _showErrorSnackBar('पेमेंट क्रेडिट होने के 24 घंटे बाद विड्रॉल कर सकते हैं');
//       return;
//     }
//
//     if (_paymentDetails == null || (_paymentDetails!['type'] != 'upi' && _paymentDetails!['type'] != 'bank_account')) {
//       _showErrorSnackBar('UPI ID या बैंक डिटेल्स जोड़ें');
//       return;
//     }
//
//     try {
//       // 2% प्लेटफॉर्म फी काटें
//       final platformFee = amount * 0.02;
//       final finalAmount = amount - platformFee;
//
//       // Razorpay Payouts API के लिए पेमेंट डिटेल्स तैयार करें
//       Map<String, dynamic> fundAccount;
//       String mode;
//
//       if (_paymentDetails!['type'] == 'upi') {
//         fundAccount = {
//           'account_type': 'vpa',
//           'vpa': {'address': _paymentDetails!['upi_id']},
//         };
//         mode = 'UPI';
//       } else {
//         fundAccount = {
//           'account_type': 'bank_account',
//           'bank_account': {
//             'name': _paymentDetails!['bank_account']['account_holder_name'],
//             'account_number': _paymentDetails!['bank_account']['account_number'],
//             'ifsc': _paymentDetails!['bank_account']['ifsc_code'],
//           },
//         };
//         mode = 'IMPS';
//       }
//
//       final response = await http.post(
//         Uri.parse('https://api.razorpay.com/v1/payouts'),
//         headers: {
//           'Content-Type': 'application/json',
//           'Authorization': 'Basic ${base64Encode(utf8.encode('$razorpayKeyId:$razorpayKeySecret'))}',
//         },
//         body: jsonEncode({
//           'account_number': 'YOUR_RAZORPAY_ACCOUNT_NUMBER', // तुम्हारा Razorpay अकाउंट नंबर
//           'amount': (finalAmount * 100).toInt(), // फाइनल अमाउंट (पैसे में)
//           'currency': 'INR',
//           'mode': mode,
//           'purpose': 'payout',
//           'fund_account': fundAccount,
//           'queue_if_low_balance': true,
//           'reference_id': 'withdrawal_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}',
//           'narration': 'Withdrawal for job payment',
//         }),
//       );
//
//       if (response.statusCode == 200) {
//         final payoutData = jsonDecode(response.body);
//         // Firestore में बैलेंस और ट्रांजेक्शन अपडेट करें
//         await _firestore.collection('workers').doc(widget.userId).update({
//           'balance': FieldValue.increment(-amount),
//           'transactions': FieldValue.arrayUnion([
//             {
//               'type': 'withdrawal',
//               'amount': amount.toStringAsFixed(2),
//               'platform_fee': platformFee.toStringAsFixed(2),
//               'final_amount': finalAmount.toStringAsFixed(2),
//               'payout_id': payoutData['id'],
//               'createdAt': FieldValue.serverTimestamp(),
//               'status': 'processed',
//             }
//           ]),
//         });
//
//         // payment_history में विड्रॉल रिकॉर्ड करें
//         await _firestore.collection('payment_history').add({
//           'worker_id': widget.userId,
//           'amount': amount.toStringAsFixed(2),
//           'platform_fee': platformFee.toStringAsFixed(2),
//           'final_amount': finalAmount.toStringAsFixed(2),
//           'payout_id': payoutData['id'],
//           'payout_date': FieldValue.serverTimestamp(),
//           'type': 'withdrawal',
//         });
//
//         _showSuccessSnackBar('विड्रॉल सक्सेसफुल: ₹${finalAmount.toStringAsFixed(2)} ट्रांसफर हो गया।');
//         _loadBalanceAndPaymentDetails();
//       } else {
//         _showErrorSnackBar('विड्रॉल फेल: ${response.body}');
//       }
//     } catch (e) {
//       _showErrorSnackBar('विड्रॉल प्रोसेस करने में एरर: $e');
//     }
//   }
//
//   void _showErrorSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message), backgroundColor: Colors.red),
//     );
//   }
//
//   void _showSuccessSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text(message), backgroundColor: Colors.green),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final withdrawalAmount = double.tryParse(_amountController.text) ?? 0.0;
//     final platformFee = withdrawalAmount * 0.02;
//     final finalAmount = withdrawalAmount - platformFee;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('विड्रॉल'),
//         backgroundColor: const Color(0xFF6A11CB),
//         flexibleSpace: Container(
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
//               begin: Alignment.topLeft,
//               end: Alignment.bottomRight,
//             ),
//           ),
//         ),
//       ),
//       body: Container(
//         decoration: const BoxDecoration(
//           gradient: LinearGradient(
//             colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
//             begin: Alignment.topLeft,
//             end: Alignment.bottomRight,
//           ),
//         ),
//         child: Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: SingleChildScrollView(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'वर्तमान बैलेंस: ₹${_balance?.toStringAsFixed(2) ?? '0.00'}',
//                   style: const TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.white,
//                   ),
//                 ),
//                 const SizedBox(height: 16),
//                 TextField(
//                   controller: _amountController,
//                   keyboardType: TextInputType.number,
//                   decoration: const InputDecoration(
//                     labelText: 'विड्रॉल अमाउंट (₹)',
//                     labelStyle: TextStyle(color: Colors.white70),
//                     filled: true,
//                     fillColor: Color.fromRGBO(255, 255, 255, 0.05),
//                     border: OutlineInputBorder(),
//                   ),
//                   style: const TextStyle(color: Colors.white),
//                   onChanged: (value) {
//                     setState(() {}); // फी और फाइनल अमाउंट अपडेट के लिए
//                   },
//                 ),
//                 const SizedBox(height: 16),
//                 Text(
//                   _paymentDetails != null
//                       ? _paymentDetails!['type'] == 'upi'
//                       ? 'UPI ID: ${_paymentDetails!['upi_id']}'
//                       : 'बैंक: ${_paymentDetails!['bank_account']['account_holder_name']} (****${_paymentDetails!['bank_account']['account_number'].substring(_paymentDetails!['bank_account']['account_number'].length - 4)})'
//                       : 'पेमेंट डिटेल्स जोड़ें',
//                   style: const TextStyle(fontSize: 16, color: Colors.white70),
//                 ),
//                 const SizedBox(height: 16),
//                 if (_amountController.text.isNotEmpty) ...[
//                   Text(
//                     'प्लेटफॉर्म फी (2%): ₹${platformFee.toStringAsFixed(2)}',
//                     style: const TextStyle(fontSize: 16, color: Colors.white70),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     'फाइनल ट्रांसफर अमाउंट: ₹${finalAmount.toStringAsFixed(2)}',
//                     style: const TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                   const SizedBox(height: 16),
//                 ],
//                 SizedBox(
//                   width: double.infinity,
//                   child: ElevatedButton(
//                     onPressed: _canWithdraw && _paymentDetails != null && withdrawalAmount > 0 ? _requestWithdrawal : null,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: _canWithdraw && _paymentDetails != null && withdrawalAmount > 0
//                           ? const Color(0xFF6A11CB)
//                           : Colors.grey,
//                       padding: const EdgeInsets.symmetric(vertical: 12),
//                     ),
//                     child: const Text(
//                       'विड्रॉल रिक्वेस्ट',
//                       style: TextStyle(color: Colors.white, fontSize: 16),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 if (!_canWithdraw)
//                   const Text(
//                     'नोट: पेमेंट क्रेडिट होने के 24 घंटे बाद विड्रॉल कर सकते हैं।',
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.white70,
//                       fontStyle: FontStyle.italic,
//                     ),
//                   ),
//                 if (_paymentDetails == null)
//                   const Text(
//                     'नोट: कृपया अपने प्रोफाइल में UPI ID या बैंक डिटेल्स जोड़ें।',
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.white70,
//                       fontStyle: FontStyle.italic,
//                     ),
//                   ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// 
