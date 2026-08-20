import Foundation

/// Reads and writes GPS coordinates in an XMP sidecar.
///
/// Proprietary RAW is the reason this exists. A CR3 or an ARW cannot be
/// rewritten safely — the format is closed and ImageIO will not write it — so
/// every tool that edits RAW metadata puts it in a `.xmp` file beside the
/// original instead. The naming follows Adobe's convention, which replaces the
/// extension rather than appending to it: `DSC0001.ARW` pairs with
/// `DSC0001.xmp`. A RAW+JPEG pair sharing a stem therefore shares one sidecar,
/// which is correct — it is one photograph.
enum LocationSidecar {
    private static let exifNamespace = "http://ns.adobe.com/exif/1.0/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    static func url(for photoURL: URL) -> URL {
        photoURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    static func read(for photoURL: URL) -> PhotoLocation? {
        let sidecarURL = url(for: photoURL)
        guard
            let data = try? Data(contentsOf: sidecarURL),
            let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace])
        else {
            return nil
        }

        guard
            let latitude = GPSCoordinateFormat.value(fromXMP: property("GPSLatitude", in: document) ?? ""),
            let longitude = GPSCoordinateFormat.value(fromXMP: property("GPSLongitude", in: document) ?? "")
        else {
            return nil
        }

        return PhotoLocation(latitude: latitude, longitude: longitude)
    }

    /// Writes the coordinates into the sidecar, creating it when absent.
    ///
    /// An existing sidecar is edited in place rather than replaced. It may hold
    /// develop settings, keywords, or crops written by Lightroom or Capture
    /// One, and overwriting those to store two numbers would destroy work this
    /// app never made.
    static func write(_ location: PhotoLocation, for photoURL: URL) throws {
        let sidecarURL = url(for: photoURL)
        let document = existingDocument(at: sidecarURL) ?? emptyDocument()

        guard let description = descriptionElement(in: document) else {
            throw LocationWriteError.malformedSidecar(sidecarURL.lastPathComponent)
        }

        if description.namespace(forPrefix: "exif") == nil {
            let namespace = XMLNode.namespace(withName: "exif", stringValue: exifNamespace)
            if let namespace = namespace as? XMLNode {
                description.addNamespace(namespace)
            }
        }

        // A property spelled as a child element would win over the attribute
        // form written below, so any stale one has to go.
        for name in ["exif:GPSLatitude", "exif:GPSLongitude", "exif:GPSVersionID"] {
            for child in description.elements(forName: name) {
                description.removeChild(at: child.index)
            }
        }

        set("exif:GPSLatitude", GPSCoordinateFormat.xmp(location.latitude, isLatitude: true), on: description)
        set("exif:GPSLongitude", GPSCoordinateFormat.xmp(location.longitude, isLatitude: false), on: description)
        set("exif:GPSVersionID", "2.2.0.0", on: description)

        // The root element, not the whole document: serialising the document
        // would emit an <?xml?> declaration, and the xpacket instruction that
        // has to come first would then sit ahead of it. That is malformed XML,
        // and the sidecar would not parse back — including by Lightroom.
        guard let root = document.rootElement() else {
            throw LocationWriteError.malformedSidecar(sidecarURL.lastPathComponent)
        }

        let packet = "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n"
            + root.xmlString(options: [.nodePrettyPrint])
            + "\n<?xpacket end=\"w\"?>\n"

        try Data(packet.utf8).write(to: sidecarURL, options: .atomic)
    }

    // MARK: - Document plumbing

    private static func existingDocument(at sidecarURL: URL) -> XMLDocument? {
        guard let data = try? Data(contentsOf: sidecarURL) else { return nil }
        return try? XMLDocument(data: data, options: [.nodePreserveWhitespace])
    }

    private static func emptyDocument() -> XMLDocument {
        let xml = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Pickroom">
          <rdf:RDF xmlns:rdf="\(rdfNamespace)">
            <rdf:Description rdf:about="" xmlns:exif="\(exifNamespace)"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        // The literal above is the one input this function has, and it parses.
        return (try? XMLDocument(xmlString: xml, options: [.nodePreserveWhitespace]))
            ?? XMLDocument()
    }

    private static func descriptionElement(in document: XMLDocument) -> XMLElement? {
        guard let root = document.rootElement() else { return nil }
        let rdf = root.elements(forName: "rdf:RDF").first
            ?? root.elements(forName: "RDF").first
        guard let rdf else { return nil }

        let descriptions = rdf.elements(forName: "rdf:Description")
            + rdf.elements(forName: "Description")

        // Prefer one that already speaks exif, so coordinates land beside any
        // other exif properties rather than in a second block.
        return descriptions.first { $0.namespace(forPrefix: "exif") != nil }
            ?? descriptions.first
    }

    private static func set(_ name: String, _ value: String, on element: XMLElement) {
        if let existing = element.attribute(forName: name) {
            existing.stringValue = value
            return
        }
        let attribute = XMLNode.attribute(withName: name, stringValue: value)
        if let attribute = attribute as? XMLNode {
            element.addAttribute(attribute)
        }
    }

    private static func property(_ name: String, in document: XMLDocument) -> String? {
        guard let description = descriptionElement(in: document) else { return nil }

        if let attribute = description.attribute(forName: "exif:\(name)")?.stringValue {
            return attribute
        }
        return description.elements(forName: "exif:\(name)").first?.stringValue
    }
}
