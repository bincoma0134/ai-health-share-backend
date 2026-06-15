import 'package:flutter/material.dart';
import '../../data/services/wallet_api_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/auth_guard.dart';
import '../widgets/guest_profile_view.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _amountController = TextEditingController();
  
  void _handleWithdraw() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount < 50000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tối thiểu 50k")));
      return;
    }
    final success = await WalletApiService.requestWithdrawal(amount, "Vietcombank", "001102...");
    if (!mounted) return;
    if (success) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AuthGuardWidget(
      fallbackBuilder: (context) => Scaffold(
        appBar: AppBar(title: const Text("Ví Partner")),
        body: GuestProfileView(onSuccess: () => AuthNotifier.instance.refresh()),
      ),
      builder: (context, token, userId) {
        return Scaffold(
          appBar: AppBar(title: const Text("Ví Partner")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Thẻ hiển thị số dư
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.zinc900, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Text("Số dư khả dụng", style: TextStyle(color: Colors.grey)),
                  FutureBuilder(
                    future: WalletApiService.getWallet(),
                    builder: (context, snapshot) => Text(
                      snapshot.hasData ? "${snapshot.data!.balance} đ" : "...",
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.blue500)
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(controller: _amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Số tiền rút")),
            ElevatedButton(onPressed: _handleWithdraw, child: const Text("Xác nhận rút tiền"))
          ],
        ),
          ),
        );
      },
    );
  }
}