# Transport-only routing for the isolated preview. TLS still verifies the issuer
# hostname against the fixture CA. No application authentication code is replaced.
require "socket"
module LoopbackOidcSocket
  def tcp(host, port, ...)
    return super("127.0.0.1", 55494, ...) if host == "auth.harvj.com" && port.to_i == 443

    super
  end
end
module LoopbackOidcTcpSocket
  def open(host, port, ...)
    return super("127.0.0.1", 55494, ...) if host == "auth.harvj.com" && port.to_i == 443

    super
  end

  def new(host, port, ...)
    return super("127.0.0.1", 55494, ...) if host == "auth.harvj.com" && port.to_i == 443

    super
  end
end
Socket.singleton_class.prepend(LoopbackOidcSocket)
TCPSocket.singleton_class.prepend(LoopbackOidcTcpSocket)
