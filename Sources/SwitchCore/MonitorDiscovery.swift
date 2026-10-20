import Foundation
import IOKit
import CoreGraphics
import CDDC

/// Finds every external display with a DDC service and pairs it with its identity (FR1, D4).
///
/// On Apple silicon each external display has an `AppleCLCD2` node under `dispextN@…` carrying
/// `DisplayAttributes.ProductAttributes`, and a `DCPAVServiceProxy` (Location = External) whose
/// parent endpoint is named `dispextN:dcpav-service-epic:0`. The shared `dispextN` prefix is the
/// pairing key; registry order is the fallback when a name does not parse.
public enum MonitorDiscovery {
    struct ServiceNode { let service: io_service_t; let key: String?; let order: Int }
    struct DisplayNode { let identity: MonitorIdentity; let key: String?; let order: Int }

    public static func discover() -> [Monitor] {
        let (services, displays) = scan()
        var monitors: [Monitor] = []
        var usedDisplays = Set<Int>()
        for svc in services {
            var match: DisplayNode?
            if let k = svc.key { match = displays.first { $0.key == k && !usedDisplays.contains($0.order) } }
            if match == nil { match = displays.filter { $0.order < svc.order && !usedDisplays.contains($0.order) }.max { $0.order < $1.order } }
            guard let disp = match else { IOObjectRelease(svc.service); continue }
            usedDisplays.insert(disp.order)
            guard let av = IOAVServiceCreateWithService(kCFAllocatorDefault, svc.service)?.takeRetainedValue() else { IOObjectRelease(svc.service); continue }
            IOObjectRelease(svc.service)
            let link = DDCMonitorLink(channel: DeadlineChannel(IOAVServiceChannel(service: av)), label: disp.key ?? "\(disp.order)")
            monitors.append(Monitor(identity: disp.identity, link: link))
        }
        for d in displays where !usedDisplays.contains(d.order) { _ = d }  // displays without DDC are not listed (FR1)
        return monitors.sorted { ($0.identity.displayID ?? 0) < ($1.identity.displayID ?? 0) }
    }

    static func scan() -> ([ServiceNode], [DisplayNode]) {
        var services: [ServiceNode] = []
        var displays: [DisplayNode] = []
        var order = 0
        var iter: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else { return ([], []) }
        defer { IOObjectRelease(iter) }
        while case let entry = IOIteratorNext(iter), entry != 0 {
            order += 1
            let cls = className(entry)
            if cls == "DCPAVServiceProxy" {
                if property(entry, "Location") as? String == "External" {
                    services.append(ServiceNode(service: entry, key: displayKey(fromParentOf: entry), order: order))
                    continue  // keep the reference; released in discover()
                }
            } else if cls == "AppleCLCD2" {
                if let id = identity(from: entry) {
                    displays.append(DisplayNode(identity: id, key: displayKey(fromParentOf: entry), order: order))
                }
            }
            IOObjectRelease(entry)
        }
        return (services, displays)
    }

    static func className(_ e: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        return IOObjectGetClass(e, &buf) == KERN_SUCCESS ? String(cString: buf) : ""
    }

    static func entryName(_ e: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        return IORegistryEntryGetName(e, &buf) == KERN_SUCCESS ? String(cString: buf) : ""
    }

    /// "dispext0:dcpav-service-epic:0" or "dispext0@88000000" → "dispext0"
    static func displayKey(fromParentOf e: io_registry_entry_t) -> String? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(e, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        return displayKey(fromName: entryName(parent))
    }

    static func displayKey(fromName name: String) -> String? {
        guard name.hasPrefix("disp") else { return nil }
        let end = name.firstIndex { $0 == ":" || $0 == "@" } ?? name.endIndex
        let key = String(name[..<end])
        return key.isEmpty ? nil : key
    }

    static func property(_ e: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(e, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func identity(from e: io_registry_entry_t) -> MonitorIdentity? {
        guard let attrs = property(e, "DisplayAttributes") as? [String: Any],
              let prod = attrs["ProductAttributes"] as? [String: Any] else { return nil }
        let name = prod["ProductName"] as? String ?? "Display"
        let vendor = (prod["LegacyManufacturerID"] as? NSNumber)?.uint32Value ?? 0
        let model = (prod["ProductID"] as? NSNumber)?.uint32Value ?? 0
        let serial = (prod["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
        let alnum = prod["AlphanumericSerialNumber"] as? String
        var id = MonitorIdentity(name: name, vendor: vendor, model: model, serial: serial, alphanumericSerial: alnum)
        id.displayID = matchDisplayID(vendor: vendor, model: model, serial: serial)
        return id
    }

    /// Pairs IORegistry identity with CoreGraphics by vendor, model and serial.
    static func matchDisplayID(vendor: UInt32, model: UInt32, serial: UInt32) -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return nil }
        let online = ids.prefix(Int(n)).filter { CGDisplayIsBuiltin($0) == 0 }
        if let exact = online.first(where: { CGDisplayVendorNumber($0) == vendor && CGDisplayModelNumber($0) == model && CGDisplaySerialNumber($0) == serial }) { return exact }
        // Serial mismatch (some monitors report 0 to CoreGraphics): accept the model only when it is the one of its kind.
        let sameModel = online.filter { CGDisplayVendorNumber($0) == vendor && CGDisplayModelNumber($0) == model }
        return sameModel.count == 1 ? sameModel[0] : nil
    }
}
