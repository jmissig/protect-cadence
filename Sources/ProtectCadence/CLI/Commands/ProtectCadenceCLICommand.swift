import ArgumentParser
import Foundation

public struct ProtectCadenceCLICommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "protect-cadence",
        abstract: "Turn UniFi Protect detections into a small local event store.",
        discussion: """
        Treat cameras as sensors, not as a dashboard surface.

        Examples:
          protect-cadence ingest --last-hours 6
          protect-cadence query events --last-hours 2 --camera Driveway
          protect-cadence query compare --last-hours 1 --vs-prior-window
          protect-cadence model rebuild
          protect-cadence model findings --finding-type unexpected_presence
          protect-cadence model findings --finding-type unexpected_transition
        """,
        subcommands: [
            ProtectCadenceCLIIngestCommand.self,
            ProtectCadenceCLIQueryCommand.self,
            ProtectCadenceCLIModelCommand.self,
            ProtectCadenceCLIAuthCommand.self,
            ProtectCadenceCLIValidateCommand.self,
        ]
    )

    public init() {}
}
