import ProtectCadenceCore

@main
enum ProtectCadenceCommandMain {
    static func main() async {
        await ProtectCadenceCLICommand.main()
    }
}
