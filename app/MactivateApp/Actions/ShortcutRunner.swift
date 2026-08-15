import Foundation

protocol ShortcutRunning {
    func run(name: String,
             completion: @escaping (Result<Void, Error>) -> Void)
    func list(completion: @escaping (Result<[String], Error>) -> Void)
}

final class SystemShortcutRunner: ShortcutRunning {
    private let queue = DispatchQueue(
        label: "com.mactivate.actions.shortcuts",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func run(name: String,
             completion: @escaping (Result<Void, Error>) -> Void) {
        execute(arguments: ["run", name]) { result in
            completion(result.map { _ in () })
        }
    }

    func list(completion: @escaping (Result<[String], Error>) -> Void) {
        execute(arguments: ["list"]) { result in
            completion(result.map { output in
                output.split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .filter { !$0.isEmpty }
                    .sorted()
            })
        }
    }

    private func execute(
        arguments: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        queue.async {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            do {
                try process.run()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(output))
                    } else {
                        let reason = output.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        completion(.failure(AppActionError.shortcutFailed(
                            reason.isEmpty ? "exit \(process.terminationStatus)" : reason
                        )))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
