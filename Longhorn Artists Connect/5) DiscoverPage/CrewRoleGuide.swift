//
//  CrewRoleGuide.swift
//  Longhorn Artists Connect
//
//  Plain-language descriptions of film set positions, shown on the Apply / Audition
//  screen so someone answering a Cast & Crew Call knows what the job actually involves
//  before they put their name in.
//

import Foundation

/// What one crew position does and what the person filling it is expected to do.
struct CrewRoleDescription {
    /// The full job title ("Best Boy Electric" for the "BBE" credit).
    let title: String
    /// One short paragraph on what the role is.
    let summary: String
    /// The concrete things this person is expected to handle on the production.
    let expectations: [String]
    /// Other names the role goes by, lowercase, so a posting's own wording still matches.
    let aliases: [String]

    init(_ title: String, summary: String, expectations: [String], aliases: [String] = []) {
        self.title = title
        self.summary = summary
        self.expectations = expectations
        self.aliases = aliases
    }
}

enum CrewRoleGuide {
    /// What every performer on a student set is expected to do, regardless of the part.
    static let castExpectations: [String] = [
        "Attend callbacks and rehearsals as scheduled",
        "Be available for every shoot day listed on the project",
        "Learn your lines and arrive on set prepared and on time",
        "Keep continuity between takes: same look, wardrobe and energy",
        "Take direction and adjust your performance quickly"
    ]

    /// Finds the description for a posting's crew role. The posting's wording is
    /// matched against each role's title and aliases, loosely enough that "DP",
    /// "Cinematographer" and "Director of Photography" all land on the same entry.
    /// Returns `nil` for a custom role the guide doesn't know.
    static func description(for role: String) -> CrewRoleDescription? {
        let wanted = normalize(role)
        guard !wanted.isEmpty else { return nil }

        // Exact title or alias match first.
        if let exact = roles.first(where: { entry in
            normalize(entry.title) == wanted || entry.aliases.contains { normalize($0) == wanted }
        }) {
            return exact
        }

        // Otherwise the longest alias contained in the posting's wording wins, so
        // "Director of Photography" beats "Director" and "Art Director" beats both.
        // Matched on whole words, so "ad" doesn't fire on "shadow" or "ac" on "backup".
        let paddedWanted = " \(wanted) "
        var best: (entry: CrewRoleDescription, length: Int)?
        for entry in roles {
            for name in [entry.title] + entry.aliases {
                let normalized = normalize(name)
                guard !normalized.isEmpty, paddedWanted.contains(" \(normalized) ") else { continue }
                if normalized.count > (best?.length ?? 0) {
                    best = (entry, normalized.count)
                }
            }
        }
        return best?.entry
    }

    /// Lowercased, punctuation stripped, ordinals spelled the same way, single spaces.
    private static func normalize(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "first", with: "1st")
        s = s.replacingOccurrences(of: "second", with: "2nd")
        s = s.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
        return s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    // MARK: - The roles

    static let roles: [CrewRoleDescription] = [
        CrewRoleDescription(
            "Director",
            summary: "Leads the creative vision of the film. The director interprets the script, guides the actors' performances, and makes the final call on how every scene looks and feels.",
            expectations: [
                "Break down the script and plan the shots with the DP",
                "Run rehearsals and direct performances on set",
                "Make decisions quickly to keep the day on schedule",
                "Work with the editor through post-production"
            ]
        ),
        CrewRoleDescription(
            "Producer",
            summary: "Runs the production from start to finish: budget, schedule, locations, permits, crew, and making sure the shoot actually happens.",
            expectations: [
                "Build and manage the budget and shooting schedule",
                "Secure locations, permits, insurance and equipment",
                "Bring on and coordinate the cast and crew",
                "Solve problems on set so the director can focus on directing"
            ],
            aliases: ["executive producer", "co-producer", "associate producer"]
        ),
        CrewRoleDescription(
            "Line Producer",
            summary: "Manages the budget and day-to-day logistics of the shoot: schedule, crew deals, equipment and locations.",
            expectations: [
                "Track spending against the budget",
                "Coordinate equipment, vehicles and locations for each day",
                "Keep the schedule realistic and the crew informed"
            ],
            aliases: ["unit production manager", "upm", "production manager"]
        ),
        CrewRoleDescription(
            "Writer",
            summary: "Writes and revises the screenplay, from outline to shooting draft.",
            expectations: [
                "Deliver drafts on the production's timeline",
                "Take notes from the director and producer and revise",
                "Be available for on-set rewrites if a scene changes"
            ],
            aliases: ["screenwriter"]
        ),
        CrewRoleDescription(
            "1st Assistant Director",
            summary: "Runs the set. The 1st AD builds the shooting schedule and keeps the day on time, calling the roll and watching out for safety.",
            expectations: [
                "Break down the script and create the schedule and call sheets",
                "Call roll and run the set during the shoot",
                "Keep every department informed and on schedule",
                "Lead the safety meeting at the top of each day"
            ],
            aliases: ["assistant director", "1st ad", "ad"]
        ),
        CrewRoleDescription(
            "2nd Assistant Director",
            summary: "Supports the 1st AD. The 2nd AD handles call sheets, actor paperwork and getting the cast through hair, makeup and wardrobe to set on time.",
            expectations: [
                "Prepare and send call sheets",
                "Track where the cast is and get them to set when needed",
                "Wrangle background actors and keep paperwork in order"
            ],
            aliases: ["2nd ad"]
        ),
        CrewRoleDescription(
            "Script Supervisor",
            summary: "Tracks continuity, dialogue and coverage during the shoot and keeps the notes the editor relies on.",
            expectations: [
                "Log every take with notes for the editor",
                "Watch for continuity errors in action, props and wardrobe",
                "Time scenes and track any script changes"
            ],
            aliases: ["scripty", "continuity"]
        ),
        CrewRoleDescription(
            "Editor",
            summary: "Assembles the footage into the finished film, shaping pacing, performance and story in post.",
            expectations: [
                "Organize and sync footage after each shoot day",
                "Cut an assembly, then refine it with the director's notes",
                "Deliver picture lock for sound and color"
            ],
            aliases: ["assistant editor", "picture editor"]
        ),
        CrewRoleDescription(
            "Director of Photography",
            summary: "Heads the camera and lighting departments. The DP designs the look of the film and is responsible for every frame's exposure, composition and movement.",
            expectations: [
                "Plan the shot list and lighting with the director",
                "Choose the camera, lenses and lighting package",
                "Lead the camera, grip and electric crews on set",
                "Operate the camera on most student sets"
            ],
            aliases: ["dp", "dop", "cinematographer", "cinematography"]
        ),
        CrewRoleDescription(
            "Camera Operator",
            summary: "Operates the camera under the DP, executing the framing and movement of each shot.",
            expectations: [
                "Rehearse camera moves with the actors' blocking",
                "Hold framing and movement consistently take to take",
                "Work closely with the 1st AC and dolly grip"
            ],
            aliases: ["cam op", "operator"]
        ),
        CrewRoleDescription(
            "1st Assistant Camera",
            summary: "The focus puller. The 1st AC keeps every shot sharp and is responsible for the camera body, lenses and accessories.",
            expectations: [
                "Build, test and maintain the camera package",
                "Pull focus during takes and set marks for the actors",
                "Change lenses and filters quickly between setups",
                "Keep camera reports and track media with the 2nd AC"
            ],
            aliases: ["1st ac", "ac", "assistant camera", "focus puller"]
        ),
        CrewRoleDescription(
            "2nd Assistant Camera",
            summary: "Supports the 1st AC and runs the slate. The 2nd AC manages media, batteries and the camera paperwork.",
            expectations: [
                "Slate every take and keep the camera log",
                "Swap, label and track cards and batteries",
                "Stage lenses and gear so changes are fast",
                "Help the 1st AC set focus marks"
            ],
            aliases: ["2nd ac", "clapper loader", "loader"]
        ),
        CrewRoleDescription(
            "Digital Imaging Technician",
            summary: "Backs up and manages the footage on set, checks exposure and color, and prepares dailies for the editor.",
            expectations: [
                "Offload and verify every card, with a backup copy",
                "Check exposure, focus and color on a calibrated monitor",
                "Hand organized footage to the editor"
            ],
            aliases: ["dit", "data wrangler", "media manager"]
        ),
        CrewRoleDescription(
            "Gaffer",
            summary: "Head of the electric department. The gaffer executes the DP's lighting plan and is responsible for power and electrical safety on set.",
            expectations: [
                "Set up and adjust lights to the DP's design",
                "Plan power distribution and run cable safely",
                "Lead the electric crew (best boy and electrics)",
                "Load and unload the lighting package"
            ]
        ),
        CrewRoleDescription(
            "Best Boy Electric",
            summary: "The gaffer's second in command. The BBE manages the electric crew, the lighting inventory and power on set.",
            expectations: [
                "Run power distribution and cable",
                "Track the lighting inventory and expendables",
                "Coordinate the electrics so setups are ready on time",
                "Step in for the gaffer when needed"
            ],
            aliases: ["bbe", "best boy"]
        ),
        CrewRoleDescription(
            "Electric",
            summary: "Works under the gaffer to set, power and adjust the lights.",
            expectations: [
                "Carry, set and strike lighting equipment",
                "Run cable and power safely",
                "Adjust lights as the gaffer and DP call for it"
            ],
            aliases: ["electrician", "lighting technician", "lighting tech", "lighting", "swing"]
        ),
        CrewRoleDescription(
            "Key Grip",
            summary: "Head of the grip department. The key grip handles everything that supports, shapes or moves the camera and lights: stands, flags, dollies and rigging.",
            expectations: [
                "Rig and secure lights, flags and diffusion",
                "Set up the dolly, slider or other camera support",
                "Keep the set safe: sandbags, cable runs, overhead rigs",
                "Lead the grip crew and manage the grip truck"
            ]
        ),
        CrewRoleDescription(
            "Grip",
            summary: "Works under the key grip to set up stands, flags, diffusion and camera support.",
            expectations: [
                "Carry, set and strike grip equipment",
                "Sandbag and secure every stand",
                "Help build dolly track and camera rigs",
                "Keep the grip truck and staging area organized"
            ],
            aliases: ["dolly grip", "best boy grip"]
        ),
        CrewRoleDescription(
            "On-Set Mixer",
            summary: "Records production sound. The on-set mixer captures clean dialogue and manages the mics, levels and recorder during the shoot.",
            expectations: [
                "Set up the recorder, boom and wireless lavs",
                "Monitor and mix levels during every take",
                "Capture room tone and wild lines",
                "Keep sound reports and hand files to post"
            ],
            aliases: ["production sound mixer", "production sound", "sound recordist", "location sound", "sound"]
        ),
        CrewRoleDescription(
            "Boom Operator",
            summary: "Holds the boom mic over the actors, keeping it close to the dialogue and out of the frame.",
            expectations: [
                "Learn the blocking and dialogue for each scene",
                "Follow the actors without entering the shot or casting shadows",
                "Help the mixer place lav mics",
                "Wrap and care for the sound gear"
            ],
            aliases: ["boom op", "boom"]
        ),
        CrewRoleDescription(
            "Sound Mixer",
            summary: "Mixes the final soundtrack in post: dialogue, music and effects balanced for the finished film.",
            expectations: [
                "Clean up and balance the dialogue",
                "Mix music and effects to picture",
                "Deliver the final mix and stems"
            ],
            aliases: ["re-recording mixer", "post sound mixer"]
        ),
        CrewRoleDescription(
            "Sound Effects Designer",
            summary: "Creates and edits the sound effects, foley and ambiences that bring the picture to life in post.",
            expectations: [
                "Spot the film for sound effects needs",
                "Record or source and edit effects and foley",
                "Deliver organized tracks to the final mix"
            ],
            aliases: ["sfx designer", "sfx", "sound designer", "sound design", "foley"]
        ),
        CrewRoleDescription(
            "Composer",
            summary: "Writes the original music for the film in post-production.",
            expectations: [
                "Spot the film with the director to decide where music goes",
                "Write, record and mix cues to picture",
                "Deliver stems to the sound mixer on schedule"
            ],
            aliases: ["music", "score"]
        ),
        CrewRoleDescription(
            "Production Designer",
            summary: "Heads the art department and designs the physical world of the film: sets, locations, props, color and texture.",
            expectations: [
                "Create the look of sets and locations with the director and DP",
                "Source, build and dress sets within budget",
                "Manage the art crew: set dressers and props",
                "Keep continuity across shoot days"
            ],
            aliases: ["production design"]
        ),
        CrewRoleDescription(
            "Art Director",
            summary: "Works under the production designer to execute the art department's plan and manage its crew.",
            expectations: [
                "Turn the production designer's plans into built, dressed sets",
                "Run the art department's schedule and budget",
                "Coordinate props, set dressing and construction"
            ],
            aliases: ["art department", "art"]
        ),
        CrewRoleDescription(
            "Props",
            summary: "Sources, builds and manages every hand prop the actors use, keeping continuity from take to take.",
            expectations: [
                "Break down the script for every prop",
                "Source or build props and have them ready on set",
                "Track continuity and keep props secure between takes"
            ],
            aliases: ["prop master", "property master", "props master"]
        ),
        CrewRoleDescription(
            "Set Dresser",
            summary: "Places and maintains the furniture, props and details that dress each set.",
            expectations: [
                "Dress sets to the production designer's plan",
                "Keep continuity between setups",
                "Strike and return set dressing after the shoot"
            ],
            aliases: ["set dressing", "set decorator"]
        ),
        CrewRoleDescription(
            "Wardrobe",
            summary: "Designs, sources and maintains every costume, keeping continuity from take to take.",
            expectations: [
                "Plan costumes with the director and production designer",
                "Fit the actors and source or alter clothing",
                "Track continuity with photos each scene",
                "Launder, repair and return wardrobe after the shoot"
            ],
            aliases: ["costume designer", "costumes", "costume"]
        ),
        CrewRoleDescription(
            "Hair and Makeup",
            summary: "Designs and applies hair and makeup for the cast, from natural looks to special effects.",
            expectations: [
                "Design looks with the director and wardrobe",
                "Apply looks before call and touch up between takes",
                "Track continuity with photos",
                "Keep a clean, sanitary kit"
            ],
            aliases: ["hair makeup", "hmu", "mua", "makeup", "make up", "makeup artist", "hair"]
        ),
        CrewRoleDescription(
            "Stunt Coordinator",
            summary: "Designs and supervises any stunts or physical action so they're performed safely.",
            expectations: [
                "Plan each stunt with the director",
                "Rehearse the action with actors and performers",
                "Have the final say on safety during action takes"
            ],
            aliases: ["stunts", "fight choreographer"]
        ),
        CrewRoleDescription(
            "Colorist",
            summary: "Grades the finished picture in post, balancing shots and crafting the film's final look.",
            expectations: [
                "Balance and match shots across the film",
                "Develop the look with the director and DP",
                "Deliver the final graded masters"
            ],
            aliases: ["color", "color grading", "colour"]
        ),
        CrewRoleDescription(
            "VFX Artist",
            summary: "Creates the visual effects: compositing, cleanup, and anything that can't be captured in camera.",
            expectations: [
                "Advise on set so shots are captured with effects in mind",
                "Composite and finish effects shots to the editor's cut",
                "Deliver finished shots for color"
            ],
            aliases: ["vfx", "visual effects", "compositor", "motion graphics"]
        ),
        CrewRoleDescription(
            "Location Manager",
            summary: "Finds and secures the shooting locations, handling permits, parking, neighbors and leaving each place as it was found.",
            expectations: [
                "Scout and lock locations that fit the script",
                "Arrange permits, access and parking",
                "Be the point of contact with the location during the shoot"
            ],
            aliases: ["locations", "location scout", "location"]
        ),
        CrewRoleDescription(
            "Casting Director",
            summary: "Runs the auditions and helps the director find the right cast for every role.",
            expectations: [
                "Put out the casting call and schedule auditions",
                "Run audition sessions and callbacks",
                "Keep the cast informed through booking"
            ],
            aliases: ["casting"]
        ),
        CrewRoleDescription(
            "Storyboard Artist",
            summary: "Draws the shots in advance so the director and DP can plan coverage and camera movement.",
            expectations: [
                "Translate the shot list into clear frames",
                "Revise boards as the director's plan changes"
            ],
            aliases: ["storyboard", "storyboards"]
        ),
        CrewRoleDescription(
            "Still Photographer",
            summary: "Shoots production stills and behind-the-scenes photos or video for the film's promotion.",
            expectations: [
                "Capture stills during rehearsals and between takes without disrupting the set",
                "Document behind the scenes for socials and press",
                "Deliver edited selects to the producer"
            ],
            aliases: ["bts", "behind the scenes", "stills", "unit photographer", "photographer", "social media"]
        ),
        CrewRoleDescription(
            "Production Assistant",
            summary: "The all-purpose support role on set. PAs help every department and keep the day moving.",
            expectations: [
                "Arrive early to help set up and stay to help wrap",
                "Lock down the set and manage background during takes",
                "Run errands, handle crafty and support any department that needs it",
                "Be reliable, positive and ready to learn"
            ],
            aliases: ["pa", "set pa", "production assistants"]
        )
    ]
}
