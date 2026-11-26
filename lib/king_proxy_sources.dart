/// Shared public subscription inputs for Hysteria 2 and sing-box.
/// Third-party feeds are untrusted. Parse defensively, deduplicate, validate,
/// and verify real end-to-end traffic; HTTP 200 is not proof of a healthy node.
enum KingProxyProtocolFilter { all, hysteria, hysteria2 }
enum KingOfflineSourceKind { androidDocumentPicker, localFile, clipboardText, qrCode, manualShareLink, importedSingBoxJson, importedXrayJson, importedBase64Subscription }
class KingProxySource {
  const KingProxySource({required this.id, required this.url, this.protocols = KingProxyProtocolFilter.all});
  final String id;
  final String url;
  final KingProxyProtocolFilter protocols;
}
class KingProxySourceCatalog {
  static const List<KingProxySource> online = [
    KingProxySource(id: 'public_01', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/009.txt'),
    KingProxySource(id: 'public_02', url: 'https://raw.githubusercontent.com/Argh94/V2RayAutoConfig/refs/heads/main/configs/USA.txt'),
    KingProxySource(id: 'public_03', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/008.txt'),
    KingProxySource(id: 'public_04', url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/trojan.txt'),
    KingProxySource(id: 'public_05', url: 'https://raw.githubusercontent.com/kort0881/vpn-vless-configs-russia/main/data/githubmirror/clean/trojan.txt'),
    KingProxySource(id: 'public_06', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/normal/10ium-telegram-configs-collector-trojan'),
    KingProxySource(id: 'public_07', url: 'https://raw.githubusercontent.com/kort0881/vpn-vless-configs-russia/main/data/githubmirror/clean/ss.txt'),
    KingProxySource(id: 'public_08', url: 'https://raw.githubusercontent.com/Leon406/SubCrawler/master/sub/share/vless'),
    KingProxySource(id: 'public_09', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/base64/10ium-telegram-configs-collector-trojan'),
    KingProxySource(id: 'public_10', url: 'https://raw.githubusercontent.com/coldwater-10/V2ray-Config/main/Splitted-By-Protocol/trojan.txt'),
    KingProxySource(id: 'public_11', url: 'https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/HEAD/configs/trojan.txt'),
    KingProxySource(id: 'public_12', url: 'https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/HEAD/configs/trojan_sub.txt'),
    KingProxySource(id: 'public_13', url: 'https://raw.githubusercontent.com/pie-with-jam/5ubscrpt10n-Reborn/main/mini/m1n1-5ub-15.txt'),
    KingProxySource(id: 'public_14', url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/shadowsocks.txt'),
    KingProxySource(id: 'public_15', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/base64/split/protocols/trojan.txt'),
    KingProxySource(id: 'public_16', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/split/protocols/trojan.txt'),
    KingProxySource(id: 'public_17', url: 'https://raw.githubusercontent.com/pie-with-jam/5ubscrpt10n-Reborn/main/mini/m1n1-5ub-16.txt'),
    KingProxySource(id: 'public_18', url: 'https://raw.githubusercontent.com/mani-moh/pattn/master/subs/countries/cd.txt'),
    KingProxySource(id: 'public_19', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/007.txt'),
    KingProxySource(id: 'public_20', url: 'https://raw.githubusercontent.com/pie-with-jam/5ubscrpt10n-Reborn/main/mini/m1n1-5ub-8.txt'),
    KingProxySource(id: 'public_21', url: 'https://raw.githubusercontent.com/kort0881/vpn-vless-configs-russia/main/data/githubmirror/clean/vless.txt'),
    KingProxySource(id: 'public_22', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/020.txt'),
    KingProxySource(id: 'public_23', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/split/countries/US.txt'),
    KingProxySource(id: 'public_24', url: 'https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-78.txt'),
    KingProxySource(id: 'public_25', url: 'https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/trojan.txt'),
    KingProxySource(id: 'public_26', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/016.txt'),
    KingProxySource(id: 'public_27', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/027.txt'),
    KingProxySource(id: 'public_28', url: 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/subs/bundles/tls.txt'),
    KingProxySource(id: 'public_29', url: 'https://raw.githubusercontent.com/drmikecrypto/PulseConfigs/main/verified/configs_base64.txt'),
    KingProxySource(id: 'public_30', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/023.txt'),
    KingProxySource(id: 'public_31', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/base64/split/countries/US.txt'),
    KingProxySource(id: 'public_32', url: 'https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-35.txt'),
    KingProxySource(id: 'public_33', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/split/non-tls.txt'),
    KingProxySource(id: 'public_34', url: 'https://raw.githubusercontent.com/thealiiakbarii-ai/VCC/main/configs/lite.txt'),
    KingProxySource(id: 'public_35', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/005.txt'),
    KingProxySource(id: 'public_36', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/024.txt'),
    KingProxySource(id: 'public_37', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/036.txt'),
    KingProxySource(id: 'public_38', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/019.txt'),
    KingProxySource(id: 'public_39', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/031.txt'),
    KingProxySource(id: 'public_40', url: 'https://raw.githubusercontent.com/10Dream/sub-mod/main/sub/base64/split/non-tls.txt'),
    KingProxySource(id: 'public_41', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/029.txt'),
    KingProxySource(id: 'public_42', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/017.txt'),
    KingProxySource(id: 'public_43', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/033.txt'),
    KingProxySource(id: 'public_44', url: 'https://raw.githubusercontent.com/thealiiakbarii-ai/VCC/main/configs/vless.txt'),
    KingProxySource(id: 'public_45', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/021.txt'),
    KingProxySource(id: 'public_46', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/035.txt'),
    KingProxySource(id: 'public_47', url: 'https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/trojan.txt'),
    KingProxySource(id: 'public_48', url: 'https://raw.githubusercontent.com/elvisl8/sub-collector/main/out/merged-v2ray.txt'),
    KingProxySource(id: 'public_49', url: 'https://raw.githubusercontent.com/arg9244/V2R-Subs/HEAD/subs/1000/022.txt'),
    KingProxySource(id: 'public_50', url: 'https://raw.githubusercontent.com/q31r/Qode/main/nodes_curated.txt'),
  ];
  static const List<KingOfflineSourceKind> offline = KingOfflineSourceKind.values;
  static List<KingProxySource> forHysteria2() => online.map((s) => KingProxySource(id: s.id, url: s.url, protocols: KingProxyProtocolFilter.hysteria2)).toList(growable: false);
  static List<KingProxySource> forSingBox() => online;
}
