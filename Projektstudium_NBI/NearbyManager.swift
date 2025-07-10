import Foundation
import MultipeerConnectivity
import NearbyInteraction
import os
import Combine

class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "nbi-demo"
    public let myPeerID = MCPeerID(displayName: "Benutzer-\(UUID().uuidString.prefix(5))")

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private var niSession: NISession!
    private var peerDiscoveryToken: NIDiscoveryToken?


    @Published var receivedPeerName: String = "Noch nichts empfangen"
    @Published var isConnected: Bool = false
    @Published var distance: Float?
    

    private var stableTimer: Timer?
    private var isInTargetRange = false
    private var hasSentPeerID = false
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()

        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()

        niSession = NISession()
        niSession.delegate = self

        // 📡 Distance-Überwachung
        $distance
            .receive(on: RunLoop.main)
            .sink { [weak self] optionalValue in
                guard let self = self, let value = optionalValue else {
                    self?.cancelStableTimer()
                    return
                }

                if value < 0.05 {
                    if !self.isInTargetRange {
                        self.isInTargetRange = true
                        self.startStableTimer()
                    }
                } else {
                    self.isInTargetRange = false
                    self.cancelStableTimer()
                }
            }
            .store(in: &cancellables)
    }

    
    private func triggerAction() {
        guard !hasSentPeerID else { return } // Nur ausführen, wenn noch nicht gesendet
        hasSentPeerID = true

        print("Abstand 2 Sekunden im Zielbereich → Peer-ID wird gesendet")
        sendOwnPeerID()
    }


    func sendOwnPeerID() {
        guard !session.connectedPeers.isEmpty else { return }
        let name = myPeerID.displayName
        if let data = name.data(using: .utf8) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }
    
    
    private func startStableTimer() {
        stableTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isInTargetRange else { return }
            self.triggerAction()
        }
    }

    private func cancelStableTimer() {
        stableTimer?.invalidate()
        stableTimer = nil
    }

    

    private func sendDiscoveryToken() {
        guard let token = niSession.discoveryToken else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Fehler beim Senden des DiscoveryTokens: \(error)")
        }
    }

    private func setupNearbyInteraction(with token: NIDiscoveryToken) {
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession.run(config)
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.isConnected = state == .connected
            if self.isConnected {
                self.sendDiscoveryToken()
                self.hasSentPeerID = false
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle name
        if let name = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.receivedPeerName = name
            }
            return
        }

        // Handle discovery token
        do {
            if let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) {
                DispatchQueue.main.async {
                    self.peerDiscoveryToken = token
                    self.setupNearbyInteraction(with: token)
                }
            }
        } catch {
            print("Fehler beim Empfangen des DiscoveryTokens: \(error)")
        }
    }

    func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {}
    func session(_: MCSession, didStartReceivingResourceWithName _: String, fromPeer _: MCPeerID, with _: Progress) {}
    func session(_: MCSession, didFinishReceivingResourceWithName _: String, fromPeer _: MCPeerID, at _: URL?, withError _: Error?) {}
}

// MARK: - MCNearbyService Delegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_: MCNearbyServiceBrowser, lostPeer _: MCPeerID) {}
    func advertiser(_: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
    func browser(_: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}

// MARK: - NISessionDelegate
extension MultipeerManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else { return }
        DispatchQueue.main.async {
            self.distance = nearbyObject.distance
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("NI Session invalidiert: \(error.localizedDescription)")
    }

    func sessionWasSuspended(_ session: NISession) {
        print("NI Session wurde pausiert.")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let token = peerDiscoveryToken {
            setupNearbyInteraction(with: token)
        }
    }
}

