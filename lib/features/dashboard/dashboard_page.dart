import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  final String leagueId;
  const DashboardPage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    final items = <_HomeItem>[
      _HomeItem("ECCEDENZE", Icons.inventory_2_outlined, const Color(0xFFEF6C00),
              (ctx) => EccedenzePage(leagueId: leagueId)),
      _HomeItem("MOVIMENTAZIONE", Icons.swap_horiz_rounded, const Color(0xFF00897B),
              (ctx) => MovimentazionePage(leagueId: leagueId)),
      _HomeItem("ARRIVI", Icons.south_west_rounded, const Color(0xFF1E88E5),
              (ctx) => ArriviPage(leagueId: leagueId)),
      _HomeItem("PARTENZE", Icons.north_east_rounded, const Color(0xFF7CB342),
              (ctx) => PartenzePage(leagueId: leagueId)),
      _HomeItem("AMMINISTRAZIONE", Icons.account_balance_outlined, const Color(0xFF5E35B1),
              (ctx) => AmministrazionePage(leagueId: leagueId)),
      _HomeItem("COMMERCIALE", Icons.local_offer_outlined, const Color(0xFF3949AB),
              (ctx) => CommerciamePage(leagueId: leagueId)),
      _HomeItem("AUTOMEZZI", Icons.local_shipping_outlined, const Color(0xFF546E7A),
              (ctx) => AutomezziPage(leagueId: leagueId)),
    ];

    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final crossAxisCount = w >= 1000 ? 4 : w >= 700 ? 3 : 2;

          return GridView.builder(
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 160, // ✅ altezza fissa della card (aumenta se vuoi)
            ),
            itemBuilder: (context, i) => _HomeCard(item: items[i]),
          );

        },
      ),
    );
  }
}

class _HomeItem {
  final String title;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;

  const _HomeItem(this.title, this.icon, this.color, this.builder);
}

class _HomeCard extends StatelessWidget {
  final _HomeItem item;
  const _HomeCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: item.builder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.color, size: 26),
              ),
              const Spacer(),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Apri sezione",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================
// Pagine placeholder (le puoi spostare in altri file quando vuoi)
// =======================

class EccedenzePage extends StatelessWidget {
  final String leagueId;
  const EccedenzePage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Eccedenze", leagueId: leagueId);
}

class MovimentazionePage extends StatelessWidget {
  final String leagueId;
  const MovimentazionePage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Movimentazione", leagueId: leagueId);
}

class ArriviPage extends StatelessWidget {
  final String leagueId;
  const ArriviPage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Arrivi", leagueId: leagueId);
}

class PartenzePage extends StatelessWidget {
  final String leagueId;
  const PartenzePage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Partenze", leagueId: leagueId);
}

class AmministrazionePage extends StatelessWidget {
  final String leagueId;
  const AmministrazionePage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Amministrazione", leagueId: leagueId);
}

class CommerciamePage extends StatelessWidget {
  final String leagueId;
  const CommerciamePage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Commerciale", leagueId: leagueId);
}

class AutomezziPage extends StatelessWidget {
  final String leagueId;
  const AutomezziPage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) => _BasePage(title: "Automezzi", leagueId: leagueId);
}

class _BasePage extends StatelessWidget {
  final String title;
  final String leagueId;
  const _BasePage({required this.title, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("$title • $leagueId")),
      body: Center(
        child: Text(
          "Pagina: $title\nleagueId: $leagueId",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
