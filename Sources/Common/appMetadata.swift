// Fork identity. Deliberately different from upstream AeroSpace so the two can coexist:
// this drives the bundle id, the socket path in commonUtil.swift, and the Accessibility grant
public let stableAeroSpaceAppId: String = "bogac.tessera"
#if DEBUG
    public let aeroSpaceAppId: String = "bogac.tessera.debug"
    public let aeroSpaceAppName: String = "Tessera-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "Tessera"
#endif
