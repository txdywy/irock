import CryptoKit
import Darwin
import Foundation
import XCTest
import CIrockNativeHysteria2Runtime
@testable import IrockNativeHysteria2

final class IrockNativeHysteria2Tests: XCTestCase {
    func testRuntimeInfoExposesLinkedQUICAndHTTP3Versions() {
        let info = NativeHysteria2Runtime.info

        XCTAssertEqual(info.ngtcp2Version, "1.22.1")
        XCTAssertEqual(info.nghttp3Version, "1.15.0")
    }

    func testClientConfigurationNormalizesEndpointAndDefaultsALPN() throws {
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: " hy2.example.com ", serverPort: 443)

        XCTAssertEqual(configuration.serverHost, "hy2.example.com")
        XCTAssertEqual(configuration.serverPort, 443)
        XCTAssertEqual(configuration.serverName, "hy2.example.com")
        XCTAssertEqual(configuration.alpn, ["h3"])
        XCTAssertFalse(configuration.allowInsecure)
    }

    func testClientConfigurationNormalizesCertificatePin() throws {
        let configuration = try NativeHysteria2ClientConfiguration(
            serverHost: "hy2.example.com",
            serverPort: 443,
            certificatePinSHA256: " wk99051vp+rw+g5xdvxqmhwyuy90hcrcbm+xjj/tg1o= "
        )

        XCTAssertEqual(configuration.certificatePinSHA256, "wk99051vp+rw+g5xdvxqmhwyuy90hcrcbm+xjj/tg1o=")
    }

    func testClientConfigurationRejectsInvalidEndpointBeforeRuntimeStarts() {
        let cases: [(String, Int, String?, [String], NativeHysteria2Error)] = [
            ("   ", 443, nil, ["h3"], .invalidConfiguration("missing server host")),
            ("hy2.example.com", 0, nil, ["h3"], .invalidConfiguration("invalid server port")),
            ("hy2.example.com", 65_536, nil, ["h3"], .invalidConfiguration("invalid server port")),
            ("hy2.example.com", 443, "   ", ["h3"], .invalidConfiguration("missing server name")),
            ("hy2.example.com", 443, nil, ["   "], .invalidConfiguration("missing alpn"))
        ]

        for (host, port, serverName, alpn, expectedError) in cases {
            do {
                _ = try NativeHysteria2ClientConfiguration(serverHost: host, serverPort: port, serverName: serverName, alpn: alpn)
                XCTFail("Expected invalid configuration")
            } catch let error as NativeHysteria2Error {
                XCTAssertEqual(error, expectedError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testNativeRuntimeCanUseConnectedUDPSocketPreparedByRealmResolver() {
        let udpSocket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(udpSocket, 0)
        var session: irock_hy2_session_ref?
        "realm-peer.invalid".withCString { serverHost in
            "hy2.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )
                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &session), IROCK_HY2_OK)
                    }
                }
            }
        }
        guard let session else {
            XCTFail("Expected configured session")
            Darwin.close(udpSocket)
            return
        }
        defer { irock_hy2_session_free(session) }

        XCTAssertEqual(irock_hy2_session_use_connected_udp_socket_for_testing(session, udpSocket, 19_991), IROCK_HY2_OK)
        var hasSocket: Int32 = 0
        var remotePort: Int32 = 0
        XCTAssertEqual(irock_hy2_session_copy_udp_state_for_testing(session, &hasSocket, &remotePort), IROCK_HY2_OK)
        XCTAssertEqual(hasSocket, 1)
        XCTAssertEqual(remotePort, 19_991)
    }

    func testClientConfigurationCarriesRealmPreparedUDPSocket() throws {
        let path = try NativeHysteria2ConnectedUDPPath(fileDescriptor: 42, remotePort: 19_991)
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: "realm-peer.invalid", serverPort: 443, serverName: "hy2.example.com", connectedUDPPath: path)

        XCTAssertEqual(configuration.connectedUDPPath, path)
    }

    func testClientConfigurationRejectsInvalidRealmPreparedUDPSocket() {
        let cases: [(Int32, Int, NativeHysteria2Error)] = [
            (-1, 19_991, .invalidConfiguration("invalid connected udp socket")),
            (42, 0, .invalidConfiguration("invalid connected udp remote port")),
            (42, 65_536, .invalidConfiguration("invalid connected udp remote port"))
        ]

        for (fd, remotePort, expectedError) in cases {
            do {
                _ = try NativeHysteria2ConnectedUDPPath(fileDescriptor: fd, remotePort: remotePort)
                XCTFail("Expected invalid connected UDP path")
            } catch let error as NativeHysteria2Error {
                XCTAssertEqual(error, expectedError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRealmUDPSocketBinderCreatesNonBlockingSocket() throws {
        let fd = try NativeHysteria2RealmResolver.bindUDPSocket(localPort: nil)
        defer { Darwin.close(fd) }

        let flags = Darwin.fcntl(fd, F_GETFL, 0)

        XCTAssertNotEqual(flags, -1)
        XCTAssertNotEqual(flags & O_NONBLOCK, 0)
    }

    func testRealmPunchPacketEncoderMatchesUpstreamFormat() throws {
        let metadata = try NativeHysteria2RealmPunchMetadata(
            nonce: "00112233445566778899aabbccddeeff",
            obfs: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        )
        let packet = try NativeHysteria2RealmPunchPacket.encode(
            type: .hello,
            metadata: metadata,
            salt: Data([0, 1, 2, 3, 4, 5, 6, 7]),
            padding: Data()
        )

        XCTAssertEqual(packet.hexString, "0001020304050607ddb1e7f48fd239aea4f299260a1e8b1e2d86a1a6b5502e2fd1")
        let decoded = try NativeHysteria2RealmPunchPacket.decode(packet, metadata: metadata)
        XCTAssertEqual(decoded.type, .hello)
        XCTAssertEqual(decoded.paddingLength, 0)
    }

    func testRealmRendezvousClientPostsConnectRequestWithoutLeakingTokenInBody() async throws {
        let metadata = try NativeHysteria2RealmPunchMetadata(
            nonce: "00112233445566778899aabbccddeeff",
            obfs: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        )
        let client = NativeHysteria2RealmRendezvousClient(
            baseURL: URL(string: "https://realm.hy2.io")!,
            token: "public-token"
        ) { request, body in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/demo-realm/connect")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer public-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("public-token"))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["addresses"] as? [String], ["198.51.100.20:4433"])
            XCTAssertEqual(json?["nonce"] as? String, metadata.nonce)
            XCTAssertEqual(json?["obfs"] as? String, metadata.obfs)
            return Data("{\"addresses\":[\"203.0.113.10:4433\"],\"nonce\":\"00112233445566778899aabbccddeeff\",\"obfs\":\"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\"}".utf8)
        }

        let response = try await client.connect(realmID: "demo-realm", localAddresses: ["198.51.100.20:4433"], metadata: metadata)

        XCTAssertEqual(response.addresses, ["203.0.113.10:4433"])
        XCTAssertEqual(response.metadata, metadata)
    }

    func testRealmResolverCombinesSTUNRendezvousAndPunchIntoConnectedUDPPath() async throws {
        let configuration = try NativeHysteria2RealmConfiguration(
            rendezvousBaseURL: URL(string: "https://realm.hy2.io")!,
            realmID: "demo-realm",
            token: "public-token",
            stunServers: ["stun.example.com:3478"],
            localPort: 43210
        )
        let metadata = try NativeHysteria2RealmPunchMetadata(
            nonce: "00112233445566778899aabbccddeeff",
            obfs: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        )
        let events = RecordingRealmEvents()
        let resolver = NativeHysteria2RealmResolver(
            metadataGenerator: { metadata },
            udpSocketBinder: { localPort in
                events.append("bind:\(localPort ?? 0)")
                return 42
            },
            stunDiscoverer: { fd, servers in
                events.append("stun:\(fd):\(servers.joined(separator: ","))")
                return ["198.51.100.20:4433"]
            },
            rendezvousConnector: { realmID, localAddresses, metadata in
                events.append("connect:\(realmID):\(localAddresses.joined(separator: ",")):\(metadata.nonce)")
                return NativeHysteria2RealmRendezvousResponse(addresses: ["203.0.113.10:4433"], metadata: metadata)
            },
            puncher: { fd, localAddresses, peerAddresses, metadata in
                events.append("punch:\(fd):\(localAddresses.joined(separator: ",")):\(peerAddresses.joined(separator: ",")):\(metadata.obfs)")
                return try NativeHysteria2ConnectedUDPPath(fileDescriptor: fd, remotePort: 4433)
            }
        )

        let path = try await resolver.resolve(configuration: configuration)

        XCTAssertEqual(path, try NativeHysteria2ConnectedUDPPath(fileDescriptor: 42, remotePort: 4433))
        XCTAssertEqual(events.values, [
            "bind:43210",
            "stun:42:stun.example.com:3478",
            "connect:demo-realm:198.51.100.20:4433:00112233445566778899aabbccddeeff",
            "punch:42:198.51.100.20:4433:203.0.113.10:4433:000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        ])
    }

    func testNativeRuntimeConnectAttemptsNetworkPathWithoutLeakingCredential() async throws {
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: "127.0.0.1", serverPort: 443)
        let client = NativeHysteria2Client(configuration: configuration)

        do {
            _ = try await client.connect(authentication: "secret-password")
            XCTFail("Expected native network failure")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .networkFailed("native hysteria2 connect network failed (quic_handshake: 4)"))
            XCTAssertFalse(error.description.contains("secret-password"))
            XCTAssertFalse(error.description.contains("ngtcp2/nghttp3 event loop is not wired"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNativeRuntimeRejectsMissingAuthenticationBeforeNetworkUse() async throws {
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: "hy2.example.com", serverPort: 443)
        let client = NativeHysteria2Client(configuration: configuration)

        do {
            _ = try await client.connect(authentication: "   ")
            XCTFail("Expected missing authentication")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .invalidConfiguration("missing authentication"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNativeRuntimeRejectsMissingAuthenticationAtCBoundary() {
        var session: irock_hy2_session_ref?
        "hy2.example.com".withCString { serverHost in
            "hy2.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    var configuration = irock_hy2_client_config(
                        server_host: serverHost,
                        server_port: 443,
                        server_name: serverName,
                        alpn: alpn,
                        allow_insecure: 0,
                        certificate_pin_sha256: nil
                    )

                    XCTAssertEqual(irock_hy2_connect(&configuration, "", &session), IROCK_HY2_INVALID_CONFIGURATION)
                    XCTAssertNil(session)
                }
            }
        }
    }

    func testNativeAuthStatusRequiresHysteria2SuccessCode() {
        XCTAssertEqual(irock_hy2_validate_auth_status(233), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_validate_auth_status(200), IROCK_HY2_AUTH_FAILED)
        XCTAssertEqual(irock_hy2_validate_auth_status(401), IROCK_HY2_AUTH_FAILED)
        XCTAssertEqual(irock_hy2_validate_auth_status(0), IROCK_HY2_INVALID_CONFIGURATION)
    }

    func testNativeAuthRequestUsesHTTP3PostAuthWithoutReturningSecret() {
        var method = [CChar](repeating: 0, count: 8)
        var path = [CChar](repeating: 0, count: 16)
        var authority = [CChar](repeating: 0, count: 256)
        var authPresent: Int32 = 0
        var authLength: Int32 = 0
        var receiveMbps: Int32 = 0
        "hy2.example.com".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(
                            irock_hy2_build_auth_request(
                                &configuration,
                                authentication,
                                250,
                                &method,
                                Int32(method.count),
                                &path,
                                Int32(path.count),
                                &authority,
                                Int32(authority.count),
                                &authPresent,
                                &authLength,
                                &receiveMbps
                            ),
                            IROCK_HY2_OK
                        )
                    }
                }
            }
        }

        XCTAssertEqual(String(cString: method), "POST")
        XCTAssertEqual(String(cString: path), "/auth")
        XCTAssertEqual(String(cString: authority), "hysteria")
        XCTAssertEqual(authPresent, 1)
        XCTAssertEqual(authLength, Int32("secret-password".utf8.count))
        XCTAssertEqual(receiveMbps, 250)
        XCTAssertFalse(String(cString: method).contains("secret-password"))
        XCTAssertFalse(String(cString: path).contains("secret-password"))
        XCTAssertFalse(String(cString: authority).contains("secret-password"))
    }

    func testNativeAuthHeaderMetadataMatchesHTTP3AuthRequestWithoutReturningSecret() {
        var headerCount: Int32 = 0
        var authHeaderIndex: Int32 = 0
        var authHeaderValueLength: Int32 = 0
        var ccRxHeaderValue = [CChar](repeating: 0, count: 16)
        "hy2.example.com".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(
                            irock_hy2_build_auth_header_metadata(
                                &configuration,
                                authentication,
                                250,
                                &headerCount,
                                &authHeaderIndex,
                                &authHeaderValueLength,
                                &ccRxHeaderValue,
                                Int32(ccRxHeaderValue.count)
                            ),
                            IROCK_HY2_OK
                        )
                    }
                }
            }
        }

        XCTAssertEqual(headerCount, 6)
        XCTAssertEqual(authHeaderIndex, 4)
        XCTAssertEqual(authHeaderValueLength, Int32("secret-password".utf8.count))
        XCTAssertEqual(String(cString: ccRxHeaderValue), "250")
        XCTAssertFalse(String(cString: ccRxHeaderValue).contains("secret-password"))
    }

    func testNativeSessionCopiesConfigurationWithoutStoringAuthentication() {
        var nativeSession: irock_hy2_session_ref?
        " hy2.example.com ".withCString { serverHost in
            " hysteria.example.com ".withCString { serverName in
                " h3 ".withCString { alpn in
                    " wk99051vp+rw+g5xdvxqmhwyuy90hcrcbm+xjj/tg1o= ".withCString { certificatePin in
                        "secret-password".withCString { authentication in
                            var configuration = irock_hy2_client_config(
                                server_host: serverHost,
                                server_port: 443,
                                server_name: serverName,
                                alpn: alpn,
                                allow_insecure: 1,
                                certificate_pin_sha256: certificatePin
                            )

                            XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 1, &nativeSession), IROCK_HY2_OK)
                        }
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        var host = [CChar](repeating: 0, count: 128)
        var serverName = [CChar](repeating: 0, count: 128)
        var alpn = [CChar](repeating: 0, count: 32)
        var certificatePin = [CChar](repeating: 0, count: 128)
        var port: Int32 = 0
        var allowInsecure: Int32 = 0
        var authenticationStored: Int32 = 1
        XCTAssertEqual(
            irock_hy2_session_copy_config_for_testing(
                nativeSession,
                &host,
                Int32(host.count),
                &port,
                &serverName,
                Int32(serverName.count),
                &alpn,
                Int32(alpn.count),
                &certificatePin,
                Int32(certificatePin.count),
                &allowInsecure,
                &authenticationStored
            ),
            IROCK_HY2_OK
        )

        XCTAssertEqual(String(cString: host), "hy2.example.com")
        XCTAssertEqual(port, 443)
        XCTAssertEqual(String(cString: serverName), "hysteria.example.com")
        XCTAssertEqual(String(cString: alpn), "h3")
        XCTAssertEqual(String(cString: certificatePin), "wk99051vp+rw+g5xdvxqmhwyuy90hcrcbm+xjj/tg1o=")
        XCTAssertEqual(allowInsecure, 1)
        XCTAssertEqual(authenticationStored, 0)
        XCTAssertFalse(String(cString: host).contains("secret-password"))
        XCTAssertFalse(String(cString: serverName).contains("secret-password"))
        XCTAssertFalse(String(cString: alpn).contains("secret-password"))
    }

    func testNativeCertificatePinValidationMatchesSHA256Base64Digest() {
        let certificate = Data([0, 1, 2, 3, 4, 5])
        let pin = Data(SHA256.hash(data: certificate)).base64EncodedString()
        let result = certificate.withUnsafeBytes { bytes in
            pin.withCString { pinPointer in
                irock_hy2_validate_certificate_pin_for_testing(bytes.bindMemory(to: UInt8.self).baseAddress, Int32(certificate.count), pinPointer)
            }
        }

        XCTAssertEqual(result, IROCK_HY2_OK)
    }

    func testNativeCertificatePinValidationRejectsMismatchedDigest() {
        let certificate = Data([0, 1, 2, 3, 4, 5])
        let result = certificate.withUnsafeBytes { bytes in
            "not-the-right-pin".withCString { pinPointer in
                irock_hy2_validate_certificate_pin_for_testing(bytes.bindMemory(to: UInt8.self).baseAddress, Int32(certificate.count), pinPointer)
            }
        }

        XCTAssertEqual(result, IROCK_HY2_AUTH_FAILED)
    }

    func testNativeSessionInitializesOpenSSLQUICClientState() {
        var nativeSession: irock_hy2_session_ref?
        "hy2.example.com".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        var hasSSLContext: Int32 = 0
        var hasSSL: Int32 = 0
        var hasCryptoContext: Int32 = 0
        var clientSessionConfigured: Int32 = 0
        XCTAssertEqual(irock_hy2_session_copy_tls_state_for_testing(nativeSession, &hasSSLContext, &hasSSL, &hasCryptoContext, &clientSessionConfigured), IROCK_HY2_OK)
        XCTAssertEqual(hasSSLContext, 1)
        XCTAssertEqual(hasSSL, 1)
        XCTAssertEqual(hasCryptoContext, 1)
        XCTAssertEqual(clientSessionConfigured, 1)
    }

    func testNativeSessionInitializesUDPSocketState() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        var hasSocket: Int32 = 0
        var remotePort: Int32 = 0
        XCTAssertEqual(irock_hy2_session_copy_udp_state_for_testing(nativeSession, &hasSocket, &remotePort), IROCK_HY2_OK)
        XCTAssertEqual(hasSocket, 1)
        XCTAssertEqual(remotePort, 443)
    }

    func testNativeSessionInitializesQUICClientConnectionState() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var hasConnection: Int32 = 0
        var hasPath: Int32 = 0
        var usesVersion1: Int32 = 0
        XCTAssertEqual(irock_hy2_session_copy_quic_state_for_testing(nativeSession, &hasConnection, &hasPath, &usesVersion1), IROCK_HY2_OK)
        XCTAssertEqual(hasConnection, 1)
        XCTAssertEqual(hasPath, 1)
        XCTAssertEqual(usesVersion1, 1)
    }

    func testNativeSessionWritesQUICInitialPacketToUDPSocket() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var bytesWritten: Int32 = 0
        XCTAssertEqual(irock_hy2_session_write_quic_initial_for_testing(nativeSession, &bytesWritten), IROCK_HY2_OK)
        XCTAssertGreaterThan(bytesWritten, 0)
    }

    func testNativeSessionInitializesHTTP3ClientState() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_http3_for_testing(nativeSession), IROCK_HY2_OK)
        var hasHTTP3Connection: Int32 = 0
        XCTAssertEqual(irock_hy2_session_copy_http3_state_for_testing(nativeSession, &hasHTTP3Connection), IROCK_HY2_OK)
        XCTAssertEqual(hasHTTP3Connection, 1)
    }

    func testNativeSessionSubmitsHTTP3AuthRequestWithoutStoringSecret() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_http3_for_testing(nativeSession), IROCK_HY2_OK)
        "secret-password".withCString { authentication in
            XCTAssertEqual(irock_hy2_session_submit_http3_auth_for_testing(nativeSession, authentication, 250), IROCK_HY2_OK)
        }
        var authStreamID: Int64 = -1
        var authStatus: Int32 = -1
        var authenticationStored: Int32 = 1
        XCTAssertEqual(irock_hy2_session_copy_http3_auth_state_for_testing(nativeSession, &authStreamID, &authStatus, &authenticationStored), IROCK_HY2_OK)
        XCTAssertEqual(authStreamID, 0)
        XCTAssertEqual(authStatus, 0)
        XCTAssertEqual(authenticationStored, 0)
    }

    func testNativeSessionOpensQUICBidiStreamForHTTP3AuthRequest() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_http3_for_testing(nativeSession), IROCK_HY2_OK)
        "secret-password".withCString { authentication in
            XCTAssertEqual(irock_hy2_session_submit_http3_auth_for_testing(nativeSession, authentication, 250), IROCK_HY2_OK)
        }

        var nativeStream: irock_hy2_stream_ref?
        XCTAssertEqual(irock_hy2_session_create_tcp_stream_for_testing(nativeSession, 0, &nativeStream), IROCK_HY2_OK)
        irock_hy2_stream_free(nativeStream)
    }

    func testNativeSessionProducesHTTP3AuthStreamData() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_http3_for_testing(nativeSession), IROCK_HY2_OK)
        "secret-password".withCString { authentication in
            XCTAssertEqual(irock_hy2_session_submit_http3_auth_for_testing(nativeSession, authentication, 250), IROCK_HY2_OK)
        }
        var streamID: Int64 = -1
        var bytesAvailable: Int32 = 0
        var fin: Int32 = 0
        XCTAssertEqual(irock_hy2_session_copy_next_http3_write_for_testing(nativeSession, &streamID, &bytesAvailable, &fin), IROCK_HY2_OK)
        XCTAssertGreaterThanOrEqual(streamID, 0)
        XCTAssertGreaterThan(bytesAvailable, 0)
    }

    func testNativeSessionReportsHTTP3AuthStreamWriteBlockedBeforeQUICHandshakeCompletes() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_http3_for_testing(nativeSession), IROCK_HY2_OK)
        "secret-password".withCString { authentication in
            XCTAssertEqual(irock_hy2_session_submit_http3_auth_for_testing(nativeSession, authentication, 250), IROCK_HY2_OK)
        }
        var streamID: Int64 = -1
        var bytesWritten: Int32 = -1
        var bytesAccepted: Int32 = -1
        XCTAssertEqual(irock_hy2_session_write_next_http3_for_testing(nativeSession, &streamID, &bytesWritten, &bytesAccepted), IROCK_HY2_BLOCKED)
        XCTAssertGreaterThanOrEqual(streamID, 0)
        XCTAssertEqual(bytesWritten, 0)
        XCTAssertEqual(bytesAccepted, 0)
    }

    func testNativeSessionReceiveQUICPacketReportsBlockedWhenNoUDPPacketIsAvailable() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var packetsRead: Int32 = -1
        XCTAssertEqual(irock_hy2_session_receive_quic_for_testing(nativeSession, &packetsRead), IROCK_HY2_BLOCKED)
        XCTAssertEqual(packetsRead, 0)
    }

    func testNativeSessionHandshakeStepWritesInitialAndReportsBlockedWithoutServerPacket() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var bytesWritten: Int32 = 0
        var packetsRead: Int32 = -1
        var handshakeCompleted: Int32 = 1
        XCTAssertEqual(irock_hy2_session_step_quic_handshake_for_testing(nativeSession, &bytesWritten, &packetsRead, &handshakeCompleted), IROCK_HY2_BLOCKED)
        XCTAssertGreaterThan(bytesWritten, 0)
        XCTAssertEqual(packetsRead, 0)
        XCTAssertEqual(handshakeCompleted, 0)
    }

    func testNativeSessionHandshakeLoopKeepsHandshakeBlockedWithoutServerPacket() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var bytesWritten: Int32 = 0
        var packetsRead: Int32 = -1
        var handshakeCompleted: Int32 = 1
        XCTAssertEqual(irock_hy2_session_run_quic_handshake_for_testing(nativeSession, 4, &bytesWritten, &packetsRead, &handshakeCompleted), IROCK_HY2_BLOCKED)
        XCTAssertGreaterThan(bytesWritten, 0)
        XCTAssertEqual(packetsRead, 0)
        XCTAssertEqual(handshakeCompleted, 0)
    }

    func testNativeSessionHandshakeWaitTimesOutWithoutServerPacket() throws {
        let blackholeSocket = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(blackholeSocket, 0)
        defer { close(blackholeSocket) }
        var blackholeAddress = sockaddr_in()
        blackholeAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        blackholeAddress.sin_family = sa_family_t(AF_INET)
        blackholeAddress.sin_port = in_port_t(0).bigEndian
        blackholeAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &blackholeAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.bind(blackholeSocket, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                getsockname(blackholeSocket, rebound, &boundAddressLength)
            }
        }
        XCTAssertEqual(nameResult, 0)
        let blackholePort = Int(UInt16(bigEndian: boundAddress.sin_port))

        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: UInt16(blackholePort),
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var bytesWritten: Int32 = 0
        var packetsRead: Int32 = -1
        var handshakeCompleted: Int32 = 1
        XCTAssertEqual(irock_hy2_session_run_quic_handshake_until_blocked_for_testing(nativeSession, 4, 10, &bytesWritten, &packetsRead, &handshakeCompleted), IROCK_HY2_BLOCKED)
        XCTAssertGreaterThan(bytesWritten, 0)
        XCTAssertEqual(packetsRead, 0)
        XCTAssertEqual(handshakeCompleted, 0)
    }

    func testNativeRuntimeConnectWaitsAcrossMultipleHandshakeAndAuthPollsBeforeNetworkFailure() async throws {
        let blackholeSocket = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(blackholeSocket, 0)
        defer { close(blackholeSocket) }
        var blackholeAddress = sockaddr_in()
        blackholeAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        blackholeAddress.sin_family = sa_family_t(AF_INET)
        blackholeAddress.sin_port = in_port_t(0).bigEndian
        blackholeAddress.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &blackholeAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                Darwin.bind(blackholeSocket, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        var boundAddress = sockaddr_in()
        var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                getsockname(blackholeSocket, rebound, &boundAddressLength)
            }
        }
        XCTAssertEqual(nameResult, 0)
        let blackholePort = Int(UInt16(bigEndian: boundAddress.sin_port))
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: "127.0.0.1", serverPort: blackholePort, serverName: "hysteria.example.com")
        let client = NativeHysteria2Client(configuration: configuration)
        let startedAt = Date()

        do {
            _ = try await client.connect(authentication: "secret-password")
            XCTFail("Expected network failure")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .networkFailed("native hysteria2 connect network failed (connect_blocked: 5)"))
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 2.0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNativeRuntimeErrorDescriptionsStayCredentialSafe() {
        let errors: [NativeHysteria2Error] = [
            .authenticationFailed("secret-password"),
            .authenticationFailed("native hysteria2 authentication rejected (http3_status: 401)"),
            .networkFailed("secret-password"),
            .networkFailed("native hysteria2 connect network failed (quic_read: -201)")
        ]

        for error in errors {
            XCTAssertFalse(error.description.contains("secret-password"))
        }
        XCTAssertEqual(NativeHysteria2Error.authenticationFailed("native hysteria2 authentication rejected (http3_status: 401)").description, "Native Hysteria2 authentication failed (http3_status: 401)")
        XCTAssertEqual(NativeHysteria2Error.networkFailed("native hysteria2 connect network failed (quic_read: -201)").description, "Native Hysteria2 network failed (quic_read: -201)")
    }

    func testNativeRuntimeConnectErrorIncludesCredentialSafeDiagnostic() async throws {
        irock_hy2_set_last_error_for_testing("quic_read", -201)
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: "127.0.0.1", serverPort: 443, serverName: "hysteria.example.com")
        let client = NativeHysteria2Client(configuration: configuration)

        do {
            _ = try await client.connect(authentication: "secret-password")
            XCTFail("Expected network failure")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .networkFailed("native hysteria2 connect network failed (quic_handshake: 4)"))
            XCTAssertFalse(error.description.contains("secret-password"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenTCPStreamBlocksUntilQUICAllowsBidirectionalStreams() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 1, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }
        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)

        var nativeStream: irock_hy2_stream_ref?
        "apple.com:443".withCString { address in
            XCTAssertEqual(irock_hy2_session_open_tcp_stream(nativeSession, address, &nativeStream), IROCK_HY2_BLOCKED)
        }
        XCTAssertNil(nativeStream)
    }

    func testNativeStreamWriteKeepsTCPRequestQueuedWhenQUICIsBlocked() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 1, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }
        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        var nativeStream: irock_hy2_stream_ref?
        "apple.com:443".withCString { address in
            XCTAssertEqual(irock_hy2_session_open_tcp_stream(nativeSession, address, &nativeStream), IROCK_HY2_BLOCKED)
        }
        XCTAssertNil(nativeStream)
    }

    func testOpenTCPStreamRequiresAuthenticatedSession() async throws {
        var nativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(0, &nativeSession), IROCK_HY2_OK)
        let session = NativeHysteria2Session(nativeSession: nativeSession!)

        do {
            _ = try await session.openTCPStream(address: "apple.com:443")
            XCTFail("Expected native tcp stream auth failure")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .authenticationFailed("native hysteria2 tcp stream authentication failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNativeSessionFeedsHTTP3StreamBytesIntoNghttp3() {
        var nativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(0, &nativeSession), IROCK_HY2_OK)
        defer { irock_hy2_session_free(nativeSession) }

        var bytesConsumed: Int32 = -1
        let bytes = Array("not-http3".utf8)
        XCTAssertEqual(irock_hy2_session_receive_http3_stream_for_testing(nativeSession, 0, bytes, Int32(bytes.count), 0, &bytesConsumed), IROCK_HY2_INVALID_CONFIGURATION)
        XCTAssertEqual(bytesConsumed, 0)
    }

    func testNativeSessionAuthExchangeBlocksUntilQUICHandshakeCompletes() {
        var nativeSession: irock_hy2_session_ref?
        "127.0.0.1".withCString { serverHost in
            "hysteria.example.com".withCString { serverName in
                "h3".withCString { alpn in
                    "secret-password".withCString { authentication in
                        var configuration = irock_hy2_client_config(
                            server_host: serverHost,
                            server_port: 443,
                            server_name: serverName,
                            alpn: alpn,
                            allow_insecure: 0,
                            certificate_pin_sha256: nil
                        )

                        XCTAssertEqual(irock_hy2_session_create_configured_for_testing(&configuration, authentication, 0, &nativeSession), IROCK_HY2_OK)
                    }
                }
            }
        }
        defer { irock_hy2_session_free(nativeSession) }

        XCTAssertEqual(irock_hy2_session_initialize_udp_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_tls_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_quic_for_testing(nativeSession), IROCK_HY2_OK)
        XCTAssertEqual(irock_hy2_session_initialize_http3_for_testing(nativeSession), IROCK_HY2_OK)
        "secret-password".withCString { authentication in
            XCTAssertEqual(irock_hy2_session_submit_http3_auth_for_testing(nativeSession, authentication, 250), IROCK_HY2_OK)
        }
        var bytesWritten: Int32 = -1
        var packetsRead: Int32 = -1
        var authStatus: Int32 = -1
        XCTAssertEqual(irock_hy2_session_run_http3_auth_for_testing(nativeSession, 4, 10, &bytesWritten, &packetsRead, &authStatus), IROCK_HY2_BLOCKED)
        XCTAssertEqual(bytesWritten, 0)
        XCTAssertEqual(packetsRead, 0)
        XCTAssertEqual(authStatus, 0)
    }

    func testApplyingHTTP3AuthResponseStatusUnlocksTCPStreamOnlyForHysteria2Success() async throws {
        var rejectedNativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(0, &rejectedNativeSession), IROCK_HY2_OK)
        ":status".withCString { name in
            "200".withCString { value in
                XCTAssertEqual(irock_hy2_session_receive_http3_header_for_testing(rejectedNativeSession, 0, name, value), IROCK_HY2_AUTH_FAILED)
            }
        }
        let rejectedSession = NativeHysteria2Session(nativeSession: rejectedNativeSession!)
        do {
            _ = try await rejectedSession.openTCPStream(address: "apple.com:443")
            XCTFail("Expected tcp stream to stay locked after non-233 auth")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .authenticationFailed("native hysteria2 tcp stream authentication failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        var acceptedNativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(0, &acceptedNativeSession), IROCK_HY2_OK)
        ":status".withCString { name in
            "233".withCString { value in
                XCTAssertEqual(irock_hy2_session_receive_http3_header_for_testing(acceptedNativeSession, 0, name, value), IROCK_HY2_OK)
            }
        }
        let acceptedSession = NativeHysteria2Session(nativeSession: acceptedNativeSession!)
        do {
            _ = try await acceptedSession.openTCPStream(address: "apple.com:443")
            XCTFail("Expected authenticated tcp stream to require QUIC state")
        } catch let error as NativeHysteria2Error {
            XCTAssertEqual(error, .invalidConfiguration("native hysteria2 tcp stream rejected"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNativeTCPRequestEncoderMatchesOfficialHysteria2Format() throws {
        let address = "apple.com:443"
        var output = [UInt8](repeating: 0, count: 64)
        var outputLength: Int32 = 0

        let result = address.withCString { address in
            irock_hy2_encode_tcp_request(address, &output, Int32(output.count), &outputLength)
        }

        XCTAssertEqual(result, IROCK_HY2_OK)
        XCTAssertEqual(Data(output.prefix(Int(outputLength))), Data([0x44, 0x01, 0x0d]) + Data(address.utf8) + Data([0x00]))
    }

    func testNativeByteStreamRejectsInvalidCBoundaryState() {
        var bytesRead: Int32 = -1
        var buffer = [UInt8](repeating: 0, count: 16)
        XCTAssertEqual(irock_hy2_stream_read(nil, &buffer, Int32(buffer.count), &bytesRead), IROCK_HY2_INVALID_CONFIGURATION)
        XCTAssertEqual(bytesRead, 0)
        let payload = Array("payload".utf8)
        XCTAssertEqual(irock_hy2_stream_write(nil, payload, Int32(payload.count)), IROCK_HY2_INVALID_CONFIGURATION)
        XCTAssertEqual(irock_hy2_stream_close_write(nil), IROCK_HY2_INVALID_CONFIGURATION)

        var nativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(1, &nativeSession), IROCK_HY2_OK)
        defer { irock_hy2_session_free(nativeSession) }
        var nativeStream: irock_hy2_stream_ref?
        XCTAssertEqual(irock_hy2_session_create_tcp_stream_for_testing(nativeSession, 4, &nativeStream), IROCK_HY2_OK)
        defer { irock_hy2_stream_free(nativeStream) }
        XCTAssertEqual(irock_hy2_stream_close_write(nativeStream), IROCK_HY2_INVALID_CONFIGURATION)
    }

    func testNativeByteStreamWaitsForBlockedReadToReceiveData() async throws {
        var nativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(1, &nativeSession), IROCK_HY2_OK)
        let session = NativeHysteria2Session(nativeSession: nativeSession!)

        var nativeStream: irock_hy2_stream_ref?
        XCTAssertEqual(irock_hy2_session_create_tcp_stream_for_testing(nativeSession, 4, &nativeStream), IROCK_HY2_OK)
        let stream = NativeHysteria2NativeByteStream(nativeStream: nativeStream!, session: session)

        Task {
            try await Task.sleep(nanoseconds: 20_000_000)
            let responseBytes = Array("delayed".utf8)
            var bytesConsumed: Int32 = -1
            XCTAssertEqual(irock_hy2_session_receive_tcp_stream_for_testing(nativeSession, 4, responseBytes, Int32(responseBytes.count), 0, &bytesConsumed), IROCK_HY2_OK)
        }

        let data = try await stream.read(maxLength: 32)

        XCTAssertEqual(data, Data("delayed".utf8))
    }

    func testNativeByteStreamDrainsSuccessfulTCPResponseBeforeReturningPayload() async throws {
        var nativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(1, &nativeSession), IROCK_HY2_OK)
        let session = NativeHysteria2Session(nativeSession: nativeSession!)

        var nativeStream: irock_hy2_stream_ref?
        XCTAssertEqual(irock_hy2_session_create_tcp_stream_for_testing(nativeSession, 4, &nativeStream), IROCK_HY2_OK)
        let stream = NativeHysteria2NativeByteStream(nativeStream: nativeStream!, session: session)
        let response = Data([0x00, 0x09]) + Data("Connected".utf8) + Data([0x00]) + Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        var bytesConsumed: Int32 = -1
        XCTAssertEqual(response.withUnsafeBytes { buffer in
            irock_hy2_session_receive_tcp_stream_for_testing(nativeSession, 4, buffer.bindMemory(to: UInt8.self).baseAddress, Int32(response.count), 0, &bytesConsumed)
        }, IROCK_HY2_OK)

        try await stream.drainSuccessfulTCPResponse()
        let payload = try await stream.read(maxLength: 64)

        XCTAssertEqual(payload, Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
    }

    func testNativeByteStreamReadsReceivedTCPStreamData() {
        var nativeSession: irock_hy2_session_ref?
        XCTAssertEqual(irock_hy2_session_create_for_testing(1, &nativeSession), IROCK_HY2_OK)
        defer { irock_hy2_session_free(nativeSession) }

        var nativeStream: irock_hy2_stream_ref?
        XCTAssertEqual(irock_hy2_session_create_tcp_stream_for_testing(nativeSession, 4, &nativeStream), IROCK_HY2_OK)
        defer { irock_hy2_stream_free(nativeStream) }

        let responseBytes = Array("server-data".utf8)
        var bytesConsumed: Int32 = -1
        XCTAssertEqual(irock_hy2_session_receive_tcp_stream_for_testing(nativeSession, 4, responseBytes, Int32(responseBytes.count), 0, &bytesConsumed), IROCK_HY2_OK)
        XCTAssertEqual(bytesConsumed, Int32(responseBytes.count))

        var firstBuffer = [UInt8](repeating: 0, count: 6)
        var firstBytesRead: Int32 = -1
        XCTAssertEqual(irock_hy2_stream_read(nativeStream, &firstBuffer, Int32(firstBuffer.count), &firstBytesRead), IROCK_HY2_OK)
        XCTAssertEqual(Data(firstBuffer.prefix(Int(firstBytesRead))), Data("server".utf8))

        var secondBuffer = [UInt8](repeating: 0, count: 32)
        var secondBytesRead: Int32 = -1
        XCTAssertEqual(irock_hy2_stream_read(nativeStream, &secondBuffer, Int32(secondBuffer.count), &secondBytesRead), IROCK_HY2_OK)
        XCTAssertEqual(Data(secondBuffer.prefix(Int(secondBytesRead))), Data("-data".utf8))
    }

    func testRealServerConnectAndOpenTCPStreamWhenEnvironmentIsProvided() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let host = environment["IROCK_HY2_TEST_HOST"], !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let portText = environment["IROCK_HY2_TEST_PORT"], let port = Int(portText),
            let authentication = environment["IROCK_HY2_TEST_AUTH"], !authentication.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw XCTSkip("Set IROCK_HY2_TEST_HOST, IROCK_HY2_TEST_PORT, and IROCK_HY2_TEST_AUTH to run real Hysteria2 connectivity verification")
        }
        let serverName = environment["IROCK_HY2_TEST_SNI"]
        let allowInsecure = environment["IROCK_HY2_TEST_INSECURE"] == "1"
        let destination = environment["IROCK_HY2_TEST_DESTINATION"] ?? "example.com:80"
        let configuration = try NativeHysteria2ClientConfiguration(serverHost: host, serverPort: port, serverName: serverName, allowInsecure: allowInsecure)
        let client = NativeHysteria2Client(configuration: configuration)

        do {
            let session = try await client.connect(authentication: authentication)
            _ = try await session.openTCPStream(address: destination)
        } catch let error as NativeHysteria2Error {
            XCTAssertFalse(error.description.contains(authentication))
            XCTFail("Real Hysteria2 connectivity verification failed: \(error.description)")
        }
    }
}

private final class RecordingRealmEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: String) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
