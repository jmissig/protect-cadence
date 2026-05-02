import ArgumentParser
import Foundation

// VERSION-SYNC-START
private let protectCadenceCLIVersion = "1.0.0"
// VERSION-SYNC-END

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
          protect-cadence annotations add --target-kind camera --target-id id:<camera-id> --body "Plain-English caveat"
          protect-cadence setup --controller-url https://protect.example --username agent
        """,
        version: protectCadenceCLIVersion,
        subcommands: [
            ProtectCadenceCLIIngestCommand.self,
            ProtectCadenceCLIQueryCommand.self,
            ProtectCadenceCLIModelCommand.self,
            ProtectCadenceCLIAnnotationsCommand.self,
            ProtectCadenceCLIAuthCommand.self,
            ProtectCadenceCLISetupCommand.self,
            ProtectCadenceCLIValidateCommand.self,
        ]
    )

    public init() {}
}
