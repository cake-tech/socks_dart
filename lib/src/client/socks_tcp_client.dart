import 'dart:io';

import '../../enums/socks_connection_type.dart';
import '../shared/proxy_settings.dart';
import 'socket_connection_task.dart';
import 'socks_client.dart';

class _ProxyOverrides extends HttpOverrides {
  final Function(HttpClient)? onCreate;
  List<ProxySettings> proxies;

  _ProxyOverrides({required this.proxies, this.onCreate});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    HttpClient httpClient = HttpClient(context: context);
    SocksTCPClient.assignToHttpClientWithSecureOptions(httpClient, proxies);

    if (onCreate != null) onCreate!(httpClient);
    return httpClient;
  }
}

class SocksTCPClient extends SocksSocket {
  SocksTCPClient._internal(Socket socket)
      : super.protected(socket, SocksConnectionType.connect);

  /// Assign http client connection factory to proxy connection.
  static void assignToHttpClient(
    HttpClient httpClient,
    List<ProxySettings> proxies,
  ) =>
      assignToHttpClientWithSecureOptions(httpClient, proxies);

  /// Assign http client connection factory to proxy connection.
  ///
  /// Applies [host], [context], [onBadCertificate],
  /// [keyLog] and [supportedProtocols] to [SecureSocket] if
  /// connection is tls-over-http
  static void assignToHttpClientWithSecureOptions(
    HttpClient httpClient,
    List<ProxySettings> proxies, {
    dynamic host,
    SecurityContext? context,
    bool Function(X509Certificate certificate)? onBadCertificate,
    void Function(String line)? keyLog,
    List<String>? supportedProtocols,
  }) {
    httpClient.connectionFactory = (uri, proxyHost, proxyPort) async {
      // Returns instance of SocksSocket which implements Socket
      final client = SocksTCPClient.connect(
        proxies,
        InternetAddress(uri.host, type: InternetAddressType.unix),
        uri.port,
      );

      // Secure connection after establishing Socks connection
      if (uri.scheme == 'https')
        return SocketConnectionTask(
          (await client).secure(
            uri.host,
            context: context,
            onBadCertificate: onBadCertificate,
            keyLog: keyLog,
            supportedProtocols: supportedProtocols,
          ),
        );

      // SocketConnectionTask implements ConnectionTask<Socket>
      return SocketConnectionTask(client);
    };
  }

  static void setProxy({
    required List<ProxySettings>? proxies,
    Function(HttpClient)? onCreate,
  }) {
    if (proxies == null) {
      HttpOverrides.global = null;
      return;
    }

    final overrides = HttpOverrides.current;
    if (overrides is _ProxyOverrides) {
      overrides.proxies = proxies;
    } else {
      HttpOverrides.global = _ProxyOverrides(
        proxies: proxies,
        onCreate: onCreate,
      );
    }
  }

  /// Connects proxy client to given [proxies] with exit point of [host]\:[port].
  static Future<SocksSocket> connect(
    List<ProxySettings> proxies,
    InternetAddress host,
    int port,
  ) async {
    final InternetAddress address;
    if (host.type == InternetAddressType.unix)
      address = (await InternetAddress.lookup(host.address))[0];
    else
      address = host;

    final client = await SocksSocket.initialize(
        proxies, address, port, SocksConnectionType.connect);
    return client.socket;
  }
}
