import 'package:flutter/material.dart';
import 'transport_capabilities.dart';

/// Read-only inventory of available and externally-integrated network engines.
/// A catalog entry never enables packet manipulation by itself.
class KingCapabilityCatalogPage extends StatefulWidget {
  const KingCapabilityCatalogPage({super.key});

  @override
  State<KingCapabilityCatalogPage> createState() =>
      _KingCapabilityCatalogPageState();
}

class _KingCapabilityCatalogPageState extends State<KingCapabilityCatalogPage> {
  KingAddressFamily _family = KingAddressFamily.ipv4;
  String _category = 'all';

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      'all',
      ...kingTransportCapabilities.map((item) => item.category),
    }.toList(growable: false);
    final items = kingCapabilitiesForFamily(_family)
        .where((item) => _category == 'all' || item.category == _category)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('موتورها و روش‌های اتصال')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<KingAddressFamily>(
                    initialValue: _family,
                    decoration: const InputDecoration(labelText: 'خانواده IP'),
                    items: const [
                      DropdownMenuItem(
                        value: KingAddressFamily.ipv4,
                        child: Text('IPv4'),
                      ),
                      DropdownMenuItem(
                        value: KingAddressFamily.ipv6,
                        child: Text('IPv6'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _family = value ?? _family),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'گروه'),
                    items: [
                      for (final value in categories)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value == 'all' ? 'همه گروه‌ها' : value),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _category = value ?? 'all'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'نمایش ${items.length} قابلیت. گزینه‌های نیازمند موتور خارجی تا زمان نصب و آزمون وابستگی، اجرا نمی‌شوند.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final ready = item.executableWithCurrentCore;
                final verified = item.isVerifiedFor(_family);
                return ListTile(
                  dense: true,
                  title: Text(item.title),
                  subtitle: Text(
                    '${item.integration} · ${_family == KingAddressFamily.ipv4 ? 'IPv4' : 'IPv6'} · آزمون واقعی: ${verified ? 'موفق' : 'ثبت‌نشده'}',
                  ),
                  trailing: Chip(
                    label: Text(
                      verified ? 'تست‌شده' : ready ? 'پیکربندی موجود؛ تست‌نشده' : 'نیازمند موتور',
                      style: const TextStyle(fontSize: 10),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
