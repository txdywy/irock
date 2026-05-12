import Foundation
import IrockAppFeature

struct MacOSUserModeTunRouteCommands: Equatable {
    let endpoint: UserModeTunEndpoint
    let serviceName: String

    init(endpoint: UserModeTunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500), serviceName: String = "Wi-Fi") {
        self.endpoint = endpoint
        self.serviceName = serviceName
    }

    var configureInterface: [String] {
        ["/sbin/ifconfig", endpoint.interfaceName, "inet", endpoint.address, endpoint.gateway, "mtu", String(endpoint.mtu), "up"]
    }

    var addDefaultRoute: [String] {
        ["/sbin/route", "add", "-net", "0.0.0.0/1", "-interface", endpoint.interfaceName]
    }

    var addSecondaryDefaultRoute: [String] {
        ["/sbin/route", "add", "-net", "128.0.0.0/1", "-interface", endpoint.interfaceName]
    }

    var deleteDefaultRoute: [String] {
        ["/sbin/route", "delete", "-net", "0.0.0.0/1", "-interface", endpoint.interfaceName]
    }

    var deleteSecondaryDefaultRoute: [String] {
        ["/sbin/route", "delete", "-net", "128.0.0.0/1", "-interface", endpoint.interfaceName]
    }

    var getDNS: [String] {
        ["/usr/sbin/networksetup", "-getdnsservers", serviceName]
    }

    var enableDNS: [String] {
        setDNS(["1.1.1.1", "8.8.8.8"])
    }

    var disableDNS: [String] {
        setDNS(nil)
    }

    func setDNS(_ servers: [String]?) -> [String] {
        ["/usr/sbin/networksetup", "-setdnsservers", serviceName] + (servers ?? ["Empty"])
    }
}
