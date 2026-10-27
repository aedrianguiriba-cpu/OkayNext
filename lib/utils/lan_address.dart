/// A usable address of this PC on the local network.
class LanAddress {
  final String ip;

  /// Adapter name as the OS reports it, e.g. "Ethernet" or "Wi-Fi".
  final String interfaceName;
  const LanAddress(this.ip, this.interfaceName);

  @override
  bool operator ==(Object other) =>
      other is LanAddress &&
      other.ip == ip &&
      other.interfaceName == interfaceName;

  @override
  int get hashCode => Object.hash(ip, interfaceName);
}
