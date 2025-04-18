import Foundation

extension sockaddr_in {
    var size: Int {
        return MemoryLayout.size(ofValue: self)
    }

    init?(_ host: String, port: Int) {
        self.init()
        self.sin_family = sa_family_t(AF_INET)
        self.sin_port = CFSwapInt16BigToHost(UInt16(port))
        guard inet_pton(AF_INET, host, &self.sin_addr) == 1 else {
            return nil
        }
        guard let hostent = gethostbyname(host), hostent.pointee.h_addrtype == AF_INET else {
            return nil
        }
        self.sin_addr = UnsafeRawPointer(hostent.pointee.h_addr_list[0]!).assumingMemoryBound(to: in_addr.self).pointee
    }

    mutating func makeSockaddr() -> sockaddr {
        var address = sockaddr()
        memcpy(&address, &self, size)
        return address
    }
}
