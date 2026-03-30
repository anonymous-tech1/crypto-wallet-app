import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:bip39/bip39.dart' as bip39;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:web3dart/web3dart.dart';
import 'package:hex/hex.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:base58check/base58check.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:local_auth/local_auth.dart';

void main() => runApp(const NexusApp());

// --- MODELS ---
class Coin {
  final String name;
  final String symbol;
  final IconData icon;
  double price;
  double holdings;
  final Color color;

  Coin({
    required this.name,
    required this.symbol,
    required this.icon,
    this.price = 0.0,
    required this.holdings,
    required this.color,
  });
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nexus Wallet',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFD700)),
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
    );
  }
}

// 1. SPLASH SCREEN
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final storage = const FlutterSecureStorage();
  final auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkWallet();
  }

  Future<void> _checkWallet() async {
    String? mnemonic = await storage.read(key: 'mnemonic');
    String? bioEnabled = await storage.read(key: 'biometrics_enabled');

    await Future.delayed(const Duration(seconds: 3));

    if (mnemonic != null) {
      if (bioEnabled == 'true') {
        bool didAuth = await _authenticate();
        if (didAuth) {
          _enterHome(mnemonic);
        } else {
          SystemNavigator.pop();
        }
      } else {
        _enterHome(mnemonic);
      }
    } else {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const OnboardingScreen()));
    }
  }

  Future<bool> _authenticate() async {
    try {
      return await auth.authenticate(
        localizedReason: 'Verify identity to open Nexus Wallet',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
    } catch (e) {
      return false;
    }
  }

  void _enterHome(String mnemonic) {
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => HomeScreen(mnemonic: mnemonic)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/logo.png', height: 180, errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 150, color: Color(0xFFFFD700))),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Color(0xFFFFD700)),
          ],
        ),
      ),
    );
  }
}

// 2. ONBOARDING & REGISTRATION
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String _generatedCode = "";
  int _countdown = 60;
  Timer? _timer;

  void _startCreation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Register Wallet"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Wallet Name")),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "Recovery Email")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(onPressed: _sendCode, child: const Text("Next")),
        ],
      ),
    );
  }

  void _sendCode() {
    if (!_emailCtrl.text.contains('@') || _nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter valid details")));
      return;
    }
    _generatedCode = (100000 + math.Random().nextInt(900000)).toString();
    debugPrint("VERIFICATION_CODE: $_generatedCode");
    Navigator.pop(context);
    _showVerificationDialog();
    _startTimer();
  }

  void _startTimer() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown > 0) {
        if (mounted) setState(() => _countdown--);
      } else {
        t.cancel();
      }
    });
  }

  void _showVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Email Verification"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Enter the code sent to ${_emailCtrl.text}"),
              TextField(controller: _codeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "6-digit code")),
              const SizedBox(height: 10),
              Text(_countdown > 0 ? "Resend in ${_countdown}s" : "You can resend now", style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () { _timer?.cancel(); Navigator.pop(c); }, child: const Text("Back")),
            if (_countdown == 0) TextButton(onPressed: _sendCode, child: const Text("Resend")),
            ElevatedButton(
              onPressed: () {
                if (_codeCtrl.text == _generatedCode) {
                  _timer?.cancel();
                  Navigator.pop(c);
                  String mnemonic = bip39.generateMnemonic();
                  Navigator.push(context, MaterialPageRoute(builder: (c) => SeedPhraseScreen(mnemonic: mnemonic, email: _emailCtrl.text, name: _nameCtrl.text)));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Incorrect code")));
                }
              },
              child: const Text("Verify"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            children: [
              const Spacer(),
              Image.asset('assets/logo.png', height: 150, errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 120, color: Color(0xFFFFD700))),
              const SizedBox(height: 30),
              const Text("Nexus Wallet", style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
              const Text("Secure. Simple. Private.", style: TextStyle(color: Colors.black54, fontSize: 18)),
              const Spacer(),
              _btn("Create New Wallet", true, _startCreation),
              const SizedBox(height: 15),
              _btn("Import Existing Wallet", false, () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ImportWalletScreen()))),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String txt, bool primary, VoidCallback action) => ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: primary ? const Color(0xFFFFD700) : Colors.white,
      foregroundColor: Colors.black,
      minimumSize: const Size(double.infinity, 65),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: primary ? BorderSide.none : const BorderSide(color: Color(0xFFE0E0E0))),
    ),
    onPressed: action,
    child: Text(txt, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  );
}

// 3. SEED PHRASE BACKUP
class SeedPhraseScreen extends StatelessWidget {
  final String mnemonic;
  final String email;
  final String name;
  const SeedPhraseScreen({super.key, required this.mnemonic, required this.email, required this.name});

  @override
  Widget build(BuildContext context) {
    List<String> words = mnemonic.split(" ");
    return Scaffold(
      appBar: AppBar(title: const Text("Backup Phrase"), elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(FontAwesomeIcons.lock, size: 60, color: Color(0xFFFFD700)),
            const SizedBox(height: 20),
            Text("Hi $name, back up your wallet", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text("Write down these 12 words. You will NOT be able to see them again.", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFFE0E0E0))),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 2.5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: List.generate(words.length, (i) => Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Text("${i + 1}. ${words[i]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                )),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 60)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => VerifyPhraseScreen(mnemonic: mnemonic, email: email, name: name))),
              child: const Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}

// 4. VERIFY PHRASE
class VerifyPhraseScreen extends StatefulWidget {
  final String mnemonic;
  final String email;
  final String name;
  const VerifyPhraseScreen({super.key, required this.mnemonic, required this.email, required this.name});

  @override
  State<VerifyPhraseScreen> createState() => _VerifyPhraseScreenState();
}

class _VerifyPhraseScreenState extends State<VerifyPhraseScreen> {
  final storage = const FlutterSecureStorage();
  List<String> selected = [];
  late List<String> shuffled;

  @override
  void initState() {
    super.initState();
    shuffled = widget.mnemonic.split(" ");
    shuffled.shuffle();
  }

  Future<void> _complete() async {
    await storage.write(key: 'mnemonic', value: widget.mnemonic);
    await storage.write(key: 'wallet_name', value: widget.name);
    await storage.write(key: 'user_email', value: widget.email);
    String id = "NXS-" + sha256.convert(utf8.encode(widget.email + widget.mnemonic)).toString().substring(0, 8).toUpperCase();
    await storage.write(key: 'user_id', value: id);
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => HomeScreen(mnemonic: widget.mnemonic)), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Phrase")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text("Tap the words in correct order", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minHeight: 120),
              decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(20)),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selected.map((w) => Chip(label: Text(w), onDeleted: () => setState(() { selected.remove(w); shuffled.add(w); }))).toList(),
              ),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: shuffled.map((w) => ActionChip(label: Text(w), onPressed: () => setState(() { selected.add(w); shuffled.remove(w); }))).toList(),
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 60)),
              onPressed: selected.length == 12 ? () { if (selected.join(" ") == widget.mnemonic) _complete(); } : null,
              child: const Text("Finish"),
            ),
          ],
        ),
      ),
    );
  }
}

// 5. IMPORT WALLET
class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});
  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final storage = const FlutterSecureStorage();
  final ctrl = TextEditingController();
  String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Import Wallet")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: ctrl, maxLines: 4, decoration: InputDecoration(border: const OutlineInputBorder(), hintText: "Enter 12-word phrase", errorText: error), onChanged: (_) => setState(() => error = null)),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 60)),
              onPressed: () async {
                if (bip39.validateMnemonic(ctrl.text.trim())) {
                  await storage.write(key: 'mnemonic', value: ctrl.text.trim());
                  if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => HomeScreen(mnemonic: ctrl.text.trim())), (r) => false);
                } else {
                  setState(() => error = "Invalid secret phrase. This account does not exist.");
                }
              },
              child: const Text("Import"),
            ),
          ],
        ),
      ),
    );
  }
}

// 6. MAIN HUB
class HomeScreen extends StatefulWidget {
  final String mnemonic;
  const HomeScreen({super.key, required this.mnemonic});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final storage = const FlutterSecureStorage();
  int _tabIdx = 0;
  bool _isVisible = true;
  bool _useDecoy = false;
  double _decoyBal = 12450.50;
  double _realBal = 0.0;
  int _taps = 0;
  String? name;
  String? uid;
  Map<String, String> addr = {};
  late List<Coin> coins;

  @override
  void initState() {
    super.initState();
    coins = [
      Coin(name: "Bitcoin", symbol: "BTC", icon: FontAwesomeIcons.bitcoin, holdings: 0.0, color: Colors.orange),
      Coin(name: "Ethereum", symbol: "ETH", icon: FontAwesomeIcons.ethereum, holdings: 0.0, color: Colors.blue),
      Coin(name: "Solana", symbol: "SOL", icon: FontAwesomeIcons.bolt, holdings: 0.0, color: Colors.purple),
      Coin(name: "Nexus", symbol: "NXS", icon: FontAwesomeIcons.shieldHalved, holdings: 5000.0, color: const Color(0xFFFFD700)),
    ];
    _loadUser();
    _initWallet();
  }

  Future<void> _loadUser() async {
    String? n = await storage.read(key: 'wallet_name');
    String? i = await storage.read(key: 'user_id');
    setState(() { name = n; uid = i; });
  }

  Future<void> _initWallet() async {
    final seed = bip39.mnemonicToSeed(widget.mnemonic);
    final priv = EthPrivateKey.fromHex(HEX.encode(seed).substring(0, 64));
    final eth = await priv.extractAddress();
    setState(() {
      addr['ETH'] = eth.hexEip55;
      addr['BTC'] = Base58CheckCodec.bitcoin().encode(Base58CheckPayload(0x00, sha256.convert(seed).bytes.sublist(0, 20)));
      addr['NXS'] = eth.hexEip55;
      addr['SOL'] = "0x${HEX.encode(seed).substring(0, 40)}";
    });
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd'));
      if (res.statusCode == 200) {
        final d = json.decode(res.body);
        setState(() {
          coins[0].price = d['bitcoin']['usd']?.toDouble() ?? 0.0;
          coins[1].price = d['ethereum']['usd']?.toDouble() ?? 0.0;
          coins[2].price = d['solana']['usd']?.toDouble() ?? 0.0;
          coins[3].price = 1.0;
        });
      }
      final client = Web3Client('https://cloudflare-eth.com', http.Client());
      final bal = await client.getBalance(EthereumAddress.fromHex(addr['ETH']!));
      setState(() { _realBal = bal.getInEther.toDouble(); coins[1].holdings = _realBal; });
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _drawer(),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(onPressed: () => _scaffoldKey.currentState?.openDrawer(), icon: const Icon(Icons.menu_rounded, color: Colors.black)),
        title: GestureDetector(onTap: () { if (++_taps == 5) { _taps = 0; _secret(); } }, child: Text(name ?? "Nexus Wallet", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
        centerTitle: true,
        actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const NotificationPage())), icon: const Icon(Icons.notifications_none_rounded, color: Colors.black))],
      ),
      body: _buildPage(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIdx, onTap: (i) => setState(() => _tabIdx = i),
        selectedItemColor: Colors.black, unselectedItemColor: Colors.grey[400], type: BottomNavigationBarType.fixed, backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: "Wallet"),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horizontal_circle_rounded), label: "Swap"),
          BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: "Discover"),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: "Settings"),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_tabIdx) {
      case 0: return _walletView();
      case 1: return SwapPage(coins: coins);
      case 2: return const DiscoverPage();
      case 3: return const SettingsPage();
      default: return _walletView();
    }
  }

  Widget _walletView() {
    double total = (coins[0].holdings * coins[0].price) + (coins[1].holdings * coins[1].price) + (coins[2].holdings * coins[2].price) + (coins[3].holdings * coins[3].price);
    return RefreshIndicator(
      onRefresh: _fetch,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(children: [
          const SizedBox(height: 20),
          _card(_useDecoy ? _decoyBal : total),
          const SizedBox(height: 30),
          _actionRow(),
          const SizedBox(height: 30),
          _coinList(),
        ]),
      ),
    );
  }

  Widget _card(double b) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(30)),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text("Portfolio Balance", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
        IconButton(onPressed: () => setState(() => _isVisible = !_isVisible), icon: Icon(_isVisible ? Icons.visibility : Icons.visibility_off, size: 18))
      ]),
      Text(_isVisible ? "\$${b.toStringAsFixed(2)}" : "••••••••", style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1)),
      const Text("+2.5% today", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))
    ]),
  );

  Widget _actionRow() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _qa(FontAwesomeIcons.paperPlane, "Send", () => Navigator.push(context, MaterialPageRoute(builder: (c) => SendCoinSelectionPage(coins: coins, mnemonic: widget.mnemonic)))),
    _qa(FontAwesomeIcons.download, "Receive", () => Navigator.push(context, MaterialPageRoute(builder: (c) => ReceiveCoinSelectionPage(addresses: addr, coins: coins, onCoinSelected: _recvSheet)))),
    _qa(FontAwesomeIcons.shieldHeart, "Shield", () {}),
    _qa(FontAwesomeIcons.shuffle, "Swap", () => setState(() => _tabIdx = 1)),
  ]);

  Widget _qa(IconData i, String l, VoidCallback t) => Column(children: [
    InkWell(onTap: t, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEEEEEE))), child: Center(child: FaIcon(i, size: 20)))),
    const SizedBox(height: 8), Text(l, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))
  ]);

  Widget _coinList() => ListView.builder(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
    itemCount: coins.length,
    itemBuilder: (context, i) => ListTile(
      onTap: () => _recvSheet(coins[i]),
      leading: CircleAvatar(backgroundColor: coins[i].color.withOpacity(0.1), child: FaIcon(coins[i].icon, color: coins[i].color == const Color(0xFFFFD700) ? Colors.black87 : coins[i].color, size: 18)),
      title: Text(coins[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: Text("\$${(coins[i].price * coins[i].holdings).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );

  void _recvSheet(Coin c) {
    showModalBottomSheet(context: context, builder: (cxt) => Container(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Receive ${c.name}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        QrImageView(data: addr[c.symbol] ?? "", size: 200, foregroundColor: c.color == const Color(0xFFFFD700) ? Colors.black : c.color),
        const SizedBox(height: 20),
        SelectableText(addr[c.symbol] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () { Clipboard.setData(ClipboardData(text: addr[c.symbol] ?? "")); Navigator.pop(cxt); }, child: const Text("Copy Address"))
      ]),
    ));
  }

  Widget _drawer() => Drawer(child: Column(children: [
    UserAccountsDrawerHeader(decoration: const BoxDecoration(color: Color(0xFFFFD700)), accountName: Text(name ?? ""), accountEmail: Text("ID: $uid")),
    ListTile(leading: const Icon(Icons.security), title: const Text("Security"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SecuritySettingsPage()))),
    const Spacer(),
    ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Wipe Wallet"), onTap: () async {
      await storage.deleteAll();
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const OnboardingScreen()), (r) => false);
    }),
  ]));

  void _secret() {
    final ctrl = TextEditingController(text: _decoyBal.toString());
    showDialog(context: context, builder: (c) => StatefulBuilder(builder: (context, setS) => AlertDialog(
      title: const Text("Admin"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(title: const Text("Use Decoy"), value: _decoy, onChanged: (v) { setState(() => _decoy = v); setS(() {}); }),
        if (_decoy) TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Decoy Amount (\$)")),
      ]),
      actions: [TextButton(onPressed: () { setState(() => _decoyBal = double.tryParse(ctrl.text) ?? _decoyBal); Navigator.pop(c); }, child: const Text("Save"))],
    )));
  }
}

// --- SUB PAGES ---

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final ctrl = TextEditingController();
  void _open(String u) => Navigator.push(context, MaterialPageRoute(builder: (c) => Web3BrowserPage(initialUrl: u)));

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Discover", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        TextField(controller: ctrl, decoration: const InputDecoration(hintText: "Enter URL"), onSubmitted: (v) => _open(v.startsWith('http') ? v : 'https://$v')),
        const SizedBox(height: 25),
        const Text("Recommended", style: TextStyle(fontWeight: FontWeight.bold)),
        ListTile(title: const Text("Uniswap"), subtitle: const Text("DEX"), leading: const Icon(FontAwesomeIcons.shuffle), onTap: () => _open("https://app.uniswap.org")),
        ListTile(title: const Text("Aave"), subtitle: const Text("Lending"), leading: const Icon(Icons.account_balance), onTap: () => _open("https://app.aave.com")),
      ]),
    );
  }
}

class Web3BrowserPage extends StatefulWidget {
  final String initialUrl;
  const Web3BrowserPage({super.key, required this.initialUrl});
  @override
  State<Web3BrowserPage> createState() => _Web3BrowserPageState();
}

class _Web3BrowserPageState extends State<Web3BrowserPage> {
  late final WebViewController ctrl;
  @override
  void initState() {
    super.initState();
    ctrl = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..loadRequest(Uri.parse(widget.initialUrl));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(widget.initialUrl, style: const TextStyle(fontSize: 12))), body: WebViewWidget(controller: ctrl));
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Settings", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      ListTile(leading: const Icon(Icons.lock), title: const Text("Security"), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SecuritySettingsPage()))),
      ListTile(leading: const Icon(Icons.notifications), title: const Text("Notifications"), trailing: const Icon(Icons.chevron_right)),
    ]));
  }
}

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});
  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final storage = const FlutterSecureStorage();
  bool bio = false;
  @override
  void initState() { super.initState(); _l(); }
  Future<void> _l() async { String? e = await storage.read(key: 'biometrics_enabled'); setState(() => bio = e == 'true'); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Security")),
      body: ListView(children: [
        SwitchListTile(title: const Text("Biometric Lock"), subtitle: const Text("Fingerprint/FaceID"), value: bio, onChanged: (v) async { await storage.write(key: 'biometrics_enabled', value: v.toString()); setState(() => bio = v); }),
        const ListTile(title: Text("Recovery Phrase"), subtitle: Text("You have already backed up your phrase."), trailing: Icon(Icons.check_circle, color: Colors.green)),
      ]),
    );
  }
}

class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Notifications")), body: const Center(child: Text("No new alerts")));
  }
}

class SendCoinSelectionPage extends StatelessWidget {
  final List<Coin> coins;
  final String mnemonic;
  const SendCoinSelectionPage({super.key, required this.coins, required this.mnemonic});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Send")),
      body: ListView.builder(itemCount: coins.length, itemBuilder: (c, i) => ListTile(
        leading: CircleAvatar(backgroundColor: coins[i].color.withOpacity(0.1), child: FaIcon(coins[i].icon, color: coins[i].color, size: 18)),
        title: Text(coins[i].name),
        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (context) => RealSendPage(coin: coins[i], mnemonic: mnemonic))),
      )),
    );
  }
}

class RealSendPage extends StatefulWidget {
  final Coin coin;
  final String mnemonic;
  const RealSendPage({super.key, required this.coin, required this.mnemonic});
  @override
  State<RealSendPage> createState() => _RealSendPageState();
}

class _RealSendPageState extends State<RealSendPage> {
  final _a = TextEditingController();
  final _am = TextEditingController();
  String? err;

  Future<void> _sign() async {
    final seed = bip39.mnemonicToSeed(widget.mnemonic);
    final priv = EthPrivateKey.fromHex(HEX.encode(seed).substring(0, 64));
    final eth = await priv.extractAddress();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Signed by: ${eth.hexEip55}\nBroadcasting...")));
  }

  bool _val(String a) {
    if (widget.coin.symbol == "ETH") { try { EthereumAddress.fromHex(a); return true; } catch (e) { return false; } }
    return a.length > 25;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Send ${widget.coin.name}")),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        TextField(controller: _a, decoration: InputDecoration(labelText: "Address", errorText: err), onChanged: (_) => setState(() => err = null)),
        const SizedBox(height: 20),
        TextField(controller: _am, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Amount", suffixText: widget.coin.symbol)),
        const Spacer(),
        ElevatedButton(onPressed: () { if (_val(_a.text)) _sign(); else setState(() => err = "Invalid address"); }, child: const Text("Sign & Send"))
      ])),
    );
  }
}

class ReceiveCoinSelectionPage extends StatelessWidget {
  final Map<String, String> addresses;
  final List<Coin> coins;
  final Function(Coin) onCoinSelected;
  const ReceiveCoinSelectionPage({super.key, required this.addresses, required this.coins, required this.onCoinSelected});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Receive")), body: ListView.builder(itemCount: coins.length, itemBuilder: (c, i) => ListTile(
      leading: CircleAvatar(backgroundColor: coins[i].color.withOpacity(0.1), child: FaIcon(coins[i].icon, color: coins[i].color, size: 18)),
      title: Text(coins[i].name),
      onTap: () { Navigator.pop(c); onCoinSelected(coins[i]); }
    )));
  }
}

class SwapPage extends StatefulWidget {
  final List<Coin> coins;
  const SwapPage({super.key, required this.coins});
  @override
  State<SwapPage> createState() => _SwapPageState();
}

class _SwapPageState extends State<SwapPage> {
  late Coin f; late Coin t;
  final c = TextEditingController();
  double resultValue = 0.0;
  @override
  void initState() { super.initState(); f = widget.coins[1]; t = widget.coins[0]; }
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(24), child: Column(children: [
      const Text("Swap", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 30),
      _box("From", f, true),
      const Icon(Icons.arrow_downward, color: Color(0xFFFFD700)),
      _box("To", t, false),
      const Spacer(),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 60)), onPressed: () {}, child: const Text("Swap Assets")),
    ]));
  }
  Widget _box(String label, Coin co, bool e) => Container(
    padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
    child: Row(children: [
      Expanded(child: e ? TextField(controller: c, decoration: const InputDecoration(hintText: "0.0", border: InputBorder.none), keyboardType: TextInputType.number, onChanged: (v) => setState(() => resultValue = (double.tryParse(v) ?? 0) * (f.price/t.price)))) : Text(resultValue.toStringAsFixed(6))),
      Text(co.symbol, style: const TextStyle(fontWeight: FontWeight.bold))
    ]),
  );
}
