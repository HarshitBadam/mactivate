import Foundation

func runIdentify(_ arguments: Arguments) throws {
    let environment = EnvironmentProbe.collect()
    if arguments.has("--json") {
        print(try jsonString(environment))
    } else {
        print(EnvironmentProbe.humanDescription(environment))
    }
}
