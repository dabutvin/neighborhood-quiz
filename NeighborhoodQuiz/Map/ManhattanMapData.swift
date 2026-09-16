import Foundation

/// What a road is, which is all the drawing needs to know to pick a weight and a colour.
enum RoadKind {
    /// Runs the length of the island. Drawn heaviest, labelled first.
    case avenue
    /// A cross street with a name people use — Fourteenth, Forty-Second, a Hundred and Twenty-Fifth.
    case majorCrossStreet
    /// One of the two hundred others, drawn fine. Together they are the island's hatching.
    case crossStreet
    /// Downtown, where the grid gives out and the streets have names instead of numbers.
    case namedStreet
}

/// One line on the map: where it runs, what it is called, and when its name appears.
struct Road {
    var name: String
    var coordinates: [Coordinate]
    var kind: RoadKind
    /// Where the name is written. `nil` puts it at the middle of the longest stretch
    /// of the road that survives the shoreline.
    var labelAnchor: Coordinate?
    /// How far in the map has to be pulled before the name is written at all. 1 is
    /// the whole island on screen.
    var labelMinZoom: Double
}

/// Manhattan, assembled: the shoreline, the park, and every road the map draws.
enum ManhattanMapData {
    // MARK: - The island

    /// The shoreline, traced clockwise from the Battery up the Hudson, round Inwood and
    /// back down the Harlem and East Rivers. Two dozen-odd fixed points with the rest
    /// falling on the line between them — enough that the island is recognisably itself
    /// at a glance, which is all a drawing with a wobbling pen can hold anyway.
    static let shoreline: [Coordinate] = [
        // Up the Hudson.
        Coordinate(-74.0170, 40.7033),  // The Battery
        Coordinate(-74.0175, 40.7110),  // Battery Park City
        Coordinate(-74.0168, 40.7185),  // Tribeca
        Coordinate(-74.0110, 40.7262),  // Canal Street at West Street
        Coordinate(-74.0100, 40.7340),  // The Village piers
        Coordinate(-74.0095, 40.7420),  // Chelsea
        Coordinate(-74.0090, 40.7490),  // Twenty-Third Street
        Coordinate(-74.0070, 40.7570),  // The rail yards
        Coordinate(-74.0000, 40.7650),  // The Fifties
        Coordinate(-73.9925, 40.7720),  // Fifty-Ninth Street
        Coordinate(-73.9855, 40.7855),  // The Seventy-Ninth Street basin
        Coordinate(-73.9750, 40.8000),  // The Hundreds
        Coordinate(-73.9630, 40.8195),  // A Hundred and Twenty-Fifth Street
        Coordinate(-73.9545, 40.8350),  // A Hundred and Forty-Fifth Street
        Coordinate(-73.9475, 40.8517),  // The George Washington Bridge
        Coordinate(-73.9345, 40.8690),  // Dyckman Street
        Coordinate(-73.9270, 40.8760),  // The north-west corner, at Inwood Hill
        // Down the Harlem River.
        Coordinate(-73.9180, 40.8745),  // The ship canal
        Coordinate(-73.9230, 40.8620),
        Coordinate(-73.9290, 40.8480),  // High Bridge
        Coordinate(-73.9335, 40.8300),  // Macombs Dam Bridge
        Coordinate(-73.9320, 40.8155),
        Coordinate(-73.9295, 40.8040),  // The Willis Avenue Bridge
        // Down the East River.
        Coordinate(-73.9310, 40.7950),
        Coordinate(-73.9400, 40.7825),  // Ninety-Sixth Street
        Coordinate(-73.9440, 40.7742),  // Seventy-Ninth Street
        Coordinate(-73.9490, 40.7660),
        Coordinate(-73.9585, 40.7580),  // The Queensboro Bridge
        Coordinate(-73.9680, 40.7490),  // Forty-Second Street
        Coordinate(-73.9730, 40.7405),  // Twenty-Third Street
        Coordinate(-73.9730, 40.7310),  // Fourteenth Street
        Coordinate(-73.9745, 40.7188),  // Houston Street
        Coordinate(-73.9765, 40.7135),  // The Williamsburg Bridge
        Coordinate(-73.9880, 40.7095),  // The Manhattan Bridge
        Coordinate(-73.9985, 40.7075),  // The Brooklyn Bridge
        Coordinate(-74.0030, 40.7055),  // The Seaport
    ]

    /// Central Park, which the grid draws for us: Fifty-Ninth Street to a Hundred and
    /// Tenth, Fifth Avenue across to Eighth. It is left unlabelled on purpose — the
    /// quiz is about streets for now.
    static let centralPark: [Coordinate] = [
        ManhattanGrid.coordinate(street: 59, westOfFifth: 0),
        ManhattanGrid.coordinate(street: 110, westOfFifth: 0),
        ManhattanGrid.coordinate(street: 110, westOfFifth: 2520),
        ManhattanGrid.coordinate(street: 59, westOfFifth: 2520),
    ]

    // MARK: - The avenues

    /// An avenue as the grid holds it: how far west of Fifth it runs, between which two
    /// numbered streets, and where along itself its name is written.
    ///
    /// The distances are the block widths the grid was actually laid out at, which are
    /// not even: the long blocks either side of Fifth are more than twice the width of
    /// the ones between Third and Park.
    struct Avenue {
        var name: String
        var westOfFifth: Double
        var from: Double
        var to: Double
        var labelStreet: Double
        /// Thirteen names standing side by side in a phone's width is a wall of text,
        /// so they arrive in three waves as the map is pulled in: the four anybody
        /// could place blind, then the rest of the numbered ones, then the long names.
        var labelMinZoom: Double
    }

    static let avenues: [Avenue] = [
        Avenue(name: "York Avenue", westOfFifth: -3600, from: 59, to: 92, labelStreet: 76, labelMinZoom: 2.8),
        Avenue(name: "First Avenue", westOfFifth: -2950, from: 1, to: 125, labelStreet: 72, labelMinZoom: 1.8),
        Avenue(name: "Second Avenue", westOfFifth: -2300, from: 1, to: 127, labelStreet: 68, labelMinZoom: 2.8),
        Avenue(name: "Third Avenue", westOfFifth: -1650, from: 6, to: 129, labelStreet: 64, labelMinZoom: 1.8),
        Avenue(name: "Lexington Avenue", westOfFifth: -1245, from: 21, to: 131, labelStreet: 60, labelMinZoom: 1.8),
        Avenue(name: "Park Avenue", westOfFifth: -840, from: 17, to: 132, labelStreet: 56, labelMinZoom: 1.6),
        Avenue(name: "Madison Avenue", westOfFifth: -420, from: 23, to: 138, labelStreet: 52, labelMinZoom: 1.8),
        Avenue(name: "Fifth Avenue", westOfFifth: 0, from: 8, to: 142, labelStreet: 48, labelMinZoom: 1.6),
        Avenue(name: "Avenue of the Americas", westOfFifth: 920, from: 3, to: 59, labelStreet: 44, labelMinZoom: 2.8),
        Avenue(name: "Seventh Avenue", westOfFifth: 1720, from: 11, to: 59, labelStreet: 40, labelMinZoom: 1.8),
        Avenue(name: "Eighth Avenue", westOfFifth: 2520, from: 13, to: 59, labelStreet: 36, labelMinZoom: 1.8),
        Avenue(name: "Ninth Avenue", westOfFifth: 3320, from: 13, to: 59, labelStreet: 32, labelMinZoom: 2.8),
        Avenue(name: "Tenth Avenue", westOfFifth: 4120, from: 14, to: 59, labelStreet: 28, labelMinZoom: 2.8),
        Avenue(name: "Eleventh Avenue", westOfFifth: 4920, from: 14, to: 59, labelStreet: 24, labelMinZoom: 2.8),
        // Above the park the same ruled lines carry different names.
        Avenue(name: "Central Park West", westOfFifth: 2520, from: 59, to: 110, labelStreet: 88, labelMinZoom: 1.6),
        Avenue(name: "Columbus Avenue", westOfFifth: 3320, from: 59, to: 110, labelStreet: 84, labelMinZoom: 1.8),
        Avenue(name: "Amsterdam Avenue", westOfFifth: 4120, from: 59, to: 125, labelStreet: 80, labelMinZoom: 1.8),
        Avenue(name: "West End Avenue", westOfFifth: 4920, from: 59, to: 107, labelStreet: 76, labelMinZoom: 2.8),
        Avenue(name: "Riverside Drive", westOfFifth: 5650, from: 72, to: 125, labelStreet: 100, labelMinZoom: 1.8),
        Avenue(name: "Lenox Avenue", westOfFifth: 920, from: 110, to: 147, labelStreet: 128, labelMinZoom: 1.8),
        Avenue(name: "Adam Clayton Powell Jr. Boulevard", westOfFifth: 1720, from: 110, to: 155, labelStreet: 138, labelMinZoom: 2.8),
        Avenue(name: "Frederick Douglass Boulevard", westOfFifth: 2520, from: 110, to: 155, labelStreet: 146, labelMinZoom: 2.8),
    ]

    // MARK: - The cross streets

    /// The numbered streets the map draws. The grid proper starts at Fourteenth; below
    /// it only the East Side keeps to the ruling, so those streets are cut short.
    ///
    /// It carries on past a Hundred and Fifty-Fifth, where the Commissioners' plan
    /// stopped and Washington Heights was laid out later on its own reckoning. The
    /// ruling drifts from the real streets up there by a block or so — but a bare
    /// third of the island reads as an error and a drifting one does not, and every
    /// street above the Heights line is drawn fine and left unnamed.
    static let crossStreetNumbers = Array(1...190)

    /// The cross streets drawn a shade heavier than their neighbours and given their
    /// full name — the ones that carry a bus, cross a bridge, or end a park.
    static let majorCrossStreets: Set<Int> = [
        14, 23, 34, 42, 50, 57, 59, 66, 72, 79, 86, 96, 103, 110, 116, 125, 135, 145, 155,
        168, 181,
    ]

    /// The handful whose names are written with the whole island on screen. The rest of
    /// the majors wait until the map has been pulled in a little.
    static let headlineCrossStreets: Set<Int> = [
        14, 23, 34, 42, 57, 72, 86, 96, 110, 125,
    ]

    /// How far a numbered street runs, west of Fifth Avenue, before the shoreline takes
    /// over. The spans deliberately overshoot into both rivers: the clip against the
    /// island decides where each one actually stops, so nothing here has to know how
    /// wide Manhattan is at a given latitude.
    static func spans(forStreet number: Int) -> [(from: Double, to: Double)] {
        switch number {
        case ..<14:
            // Below Fourteenth the ruling only holds east of the Bowery.
            return [(from: -5500, to: -1500)]
        case 60...109:
            // Central Park is in the way, so these run as two halves.
            return [(from: -6500, to: 0), (from: 2520, to: 10000)]
        default:
            return [(from: -6500, to: 10000)]
        }
    }

    // MARK: - Downtown

    /// Broadway, which was a footpath before there was a grid and still refuses it —
    /// the one road that crosses the avenues instead of running beside them, cutting
    /// the squares out of the sheet as it goes.
    static let broadway: [Coordinate] = [
        Coordinate(-74.0136, 40.7048),  // Bowling Green
        Coordinate(-74.0060, 40.7127),  // City Hall
        Coordinate(-74.0021, 40.7202),  // Canal Street
        Coordinate(-73.9968, 40.7255),  // Houston Street
        Coordinate(-73.9906, 40.7350),  // Union Square
        Coordinate(-73.9890, 40.7414),  // Madison Square
        Coordinate(-73.9877, 40.7497),  // Herald Square
        Coordinate(-73.9855, 40.7580),  // Times Square
        Coordinate(-73.9819, 40.7681),  // Columbus Circle
        Coordinate(-73.9820, 40.7780),  // Seventy-Second Street
        Coordinate(-73.9760, 40.7880),  // Eighty-Sixth Street
        Coordinate(-73.9721, 40.7947),  // Ninety-Sixth Street
        Coordinate(-73.9670, 40.8030),  // A Hundred and Tenth Street
        Coordinate(-73.9600, 40.8140),  // A Hundred and Twenty-Fifth Street
        Coordinate(-73.9500, 40.8265),  // A Hundred and Forty-Fifth Street
        Coordinate(-73.9410, 40.8405),  // A Hundred and Sixty-Eighth Street
        Coordinate(-73.9337, 40.8487),  // A Hundred and Eighty-First Street
        Coordinate(-73.9270, 40.8660),  // Dyckman Street
        Coordinate(-73.9155, 40.8730),  // Two Hundred and Eighteenth Street
    ]

    /// The named streets below Fourteenth, traced by hand because no ruling would find
    /// them. A handful, not the whole tangle: the ones a New Yorker would use to say
    /// where something is.
    static let namedStreets: [(name: String, coordinates: [Coordinate])] = [
        ("Houston Street", [
            Coordinate(-74.0095, 40.7290),
            Coordinate(-74.0030, 40.7274),
            Coordinate(-73.9950, 40.7250),
            Coordinate(-73.9870, 40.7225),
            Coordinate(-73.9790, 40.7203),
            Coordinate(-73.9757, 40.7192),
        ]),
        ("Canal Street", [
            Coordinate(-74.0103, 40.7262),
            Coordinate(-74.0048, 40.7227),
            Coordinate(-74.0000, 40.7196),
            Coordinate(-73.9955, 40.7167),
        ]),
        ("Delancey Street", [
            Coordinate(-73.9930, 40.7185),
            Coordinate(-73.9870, 40.7174),
            Coordinate(-73.9800, 40.7163),
            Coordinate(-73.9762, 40.7156),
        ]),
        ("The Bowery", [
            Coordinate(-73.9982, 40.7136),
            Coordinate(-73.9958, 40.7175),
            Coordinate(-73.9935, 40.7220),
            Coordinate(-73.9912, 40.7263),
            Coordinate(-73.9905, 40.7290),
        ]),
        ("Chambers Street", [
            Coordinate(-74.0138, 40.7166),
            Coordinate(-74.0090, 40.7152),
            Coordinate(-74.0040, 40.7145),
            Coordinate(-74.0005, 40.7140),
        ]),
        ("Wall Street", [
            Coordinate(-74.0118, 40.7075),
            Coordinate(-74.0095, 40.7064),
            Coordinate(-74.0072, 40.7053),
        ]),
    ]

    // MARK: - Everything, in one list

    /// Every road the map draws, avenues first so the fine hatching of the cross
    /// streets is laid under them rather than over.
    static var roads: [Road] {
        var roads: [Road] = []

        for avenue in avenues {
            roads.append(Road(
                name: avenue.name,
                coordinates: [
                    ManhattanGrid.coordinate(street: avenue.from, westOfFifth: avenue.westOfFifth),
                    ManhattanGrid.coordinate(street: avenue.to, westOfFifth: avenue.westOfFifth),
                ],
                kind: .avenue,
                labelAnchor: ManhattanGrid.coordinate(
                    street: avenue.labelStreet,
                    westOfFifth: avenue.westOfFifth
                ),
                labelMinZoom: avenue.labelMinZoom
            ))
        }

        // The one avenue named on the opening map, and it is named down in SoHo rather
        // than up at Seventy-Second: the whole midtown column is spoken for by the cross
        // street names, and below Fourteenth there is clear paper at that zoom.
        roads.append(Road(
            name: "Broadway",
            coordinates: broadway,
            kind: .avenue,
            labelAnchor: Coordinate(-73.9968, 40.7255),
            labelMinZoom: 1
        ))

        for number in crossStreetNumbers {
            let major = majorCrossStreets.contains(number)
            let minZoom: Double
            if headlineCrossStreets.contains(number) {
                minZoom = 1
            } else if major {
                minZoom = 2
            } else {
                minZoom = 3.6
            }
            for span in spans(forStreet: number) {
                roads.append(Road(
                    name: major ? "\(ordinal(number)) Street" : ordinal(number),
                    coordinates: [
                        ManhattanGrid.coordinate(street: Double(number), westOfFifth: span.from),
                        ManhattanGrid.coordinate(street: Double(number), westOfFifth: span.to),
                    ],
                    kind: major ? .majorCrossStreet : .crossStreet,
                    labelAnchor: nil,
                    labelMinZoom: minZoom
                ))
            }
        }

        for street in namedStreets {
            roads.append(Road(
                name: street.name,
                coordinates: street.coordinates,
                kind: .namedStreet,
                labelAnchor: nil,
                labelMinZoom: 1.5
            ))
        }

        return roads
    }

    /// "1st", "2nd", "3rd", "11th", "42nd", "111th" — the suffixes English uses for
    /// street numbers, teens included.
    static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 100, number % 10) {
        case (11, _), (12, _), (13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}
