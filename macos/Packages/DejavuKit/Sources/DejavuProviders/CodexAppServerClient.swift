import Darwin
import Foundation
import DejavuDomain

public struct CodexAppServerConfiguration: Sendable {
    public let clientName: String
    public let clientTitle: String
    public let clientVersion: String
    public let requestTimeout: Duration
    public let shutdownGracePeriod: Duration
    public let maximumLineBytes: Int

    public init(
        clientName: String = "dejavu",
        clientTitle: String = "Dejavu",
        clientVersion: String = "0.1.0",
        requestTimeout: Duration = .seconds(15),
        shutdownGracePeriod: Duration = .seconds(1),
        maximumLineBytes: Int = 1_048_576
    ) {
        self.clientName = clientName
        self.clientTitle = clientTitle
        self.clientVersion = clientVersion
        self.requestTimeout = requestTimeout
        self.shutdownGracePeriod = shutdownGracePeriod
        self.maximumLineBytes = min(8_388_608, max(1_024, maximumLineBytes))
    }
}

public enum CodexAppServerTransportError: Error, Equatable, Sendable {
    case alreadyStarted
    case launchFailed
    case notRunning
    case writeFailed
    case endOfFile
    case lineTooLarge
}

public enum CodexAppServerError: Error, Equatable, Sendable {
    case requestInProgress
    case shutDown
    case launchFailed
    case serverExited
    case transportFailure
    case responseTooLarge
    case malformedResponse
    case initializationRejected
    case accountReadRejected
    case invalidAccountResponse
    case loginRequired
    case rateLimitsRejected
    case invalidRateLimitsResponse
    case timedOut
}

/// An injectable message transport keeps protocol and cancellation tests from
/// needing a real Codex account. Implementations must never log message bytes,
/// and `stop` must unblock an outstanding `receiveLine` call.
public protocol CodexAppServerTransport: AnyObject, Sendable {
    func start() async throws
    func sendMessage(_ data: Data) async throws
    func receiveLine(maximumBytes: Int) async throws -> Data
    func stop(gracePeriod: Duration) async
}

public typealias CodexAppServerTransportFactory = @Sendable (
    _ executableURL: URL
) -> any CodexAppServerTransport

/// Short-lived client for the stable stdio JSONL app-server surface.
/// Each fetch owns exactly one child transport and always tears it down.
public actor CodexAppServerClient {
    private let executableURL: URL
    private let configuration: CodexAppServerConfiguration
    private let transportFactory: CodexAppServerTransportFactory
    private let parser = CodexRateLimitsParser()

    private var activeTransport: (any CodexAppServerTransport)?
    private var isShutDown = false

    public init(
        executableURL: URL,
        configuration: CodexAppServerConfiguration = CodexAppServerConfiguration()
    ) {
        self.executableURL = executableURL
        self.configuration = configuration
        transportFactory = { ProcessCodexAppServerTransport(executableURL: $0) }
    }

    public init(
        executableURL: URL,
        configuration: CodexAppServerConfiguration = CodexAppServerConfiguration(),
        transportFactory: @escaping CodexAppServerTransportFactory
    ) {
        self.executableURL = executableURL
        self.configuration = configuration
        self.transportFactory = transportFactory
    }

    public func fetchUsage() async throws -> CodexUsageSnapshot {
        guard !isShutDown else { throw CodexAppServerError.shutDown }
        guard activeTransport == nil else { throw CodexAppServerError.requestInProgress }

        let transport = transportFactory(executableURL)
        activeTransport = transport

        do {
            try await transport.start()
            try Task.checkCancellation()

            let deadline = ContinuousClock.now.advanced(by: configuration.requestTimeout)
            try await sendInitialize(to: transport)
            _ = try await readResponse(
                id: 1,
                kind: .initialize,
                deadline: deadline,
                transport: transport
            )
            try await transport.sendMessage(try encode(InitializedNotification()))
            try await transport.sendMessage(try encode(AccountReadRequest()))

            let accountResponse = try await readResponse(
                id: 2,
                kind: .account,
                deadline: deadline,
                transport: transport
            )
            let account: AccountReadResponse
            do {
                account = try JSONDecoder().decode(AccountReadResponse.self, from: accountResponse)
            } catch {
                throw CodexAppServerError.invalidAccountResponse
            }
            if !account.result.hasAccount, account.result.requiresOpenaiAuth {
                throw CodexAppServerError.loginRequired
            }

            try await transport.sendMessage(try encode(RateLimitsRequest()))

            let response = try await readResponse(
                id: 3,
                kind: .rateLimits,
                deadline: deadline,
                transport: transport
            )
            let snapshot: CodexUsageSnapshot
            do {
                snapshot = try parser.parseResponse(response)
            } catch {
                throw CodexAppServerError.invalidRateLimitsResponse
            }

            try Task.checkCancellation()
            await finish(transport)
            guard !isShutDown else { throw CancellationError() }
            return snapshot
        } catch is CancellationError {
            await finish(transport)
            throw CancellationError()
        } catch let error as CodexAppServerError {
            await finish(transport)
            guard !isShutDown else { throw CancellationError() }
            throw error
        } catch let error as CodexAppServerTransportError {
            await finish(transport)
            guard !isShutDown else { throw CancellationError() }
            switch error {
            case .lineTooLarge:
                throw CodexAppServerError.responseTooLarge
            case .launchFailed:
                throw CodexAppServerError.launchFailed
            case .endOfFile, .notRunning:
                throw CodexAppServerError.serverExited
            case .alreadyStarted, .writeFailed:
                throw CodexAppServerError.transportFailure
            }
        } catch {
            await finish(transport)
            guard !isShutDown else { throw CancellationError() }
            throw CodexAppServerError.transportFailure
        }
    }

    /// Permanently prevents new requests and waits for the owned child to exit.
    public func shutdown() async {
        isShutDown = true
        guard let activeTransport else { return }
        await finish(activeTransport)
    }

    private enum ResponseKind {
        case initialize
        case account
        case rateLimits
    }

    private func sendInitialize(to transport: any CodexAppServerTransport) async throws {
        let request = InitializeRequest(
            params: InitializeParameters(
                clientInfo: ClientInfo(
                    name: configuration.clientName,
                    title: configuration.clientTitle,
                    version: configuration.clientVersion
                )
            )
        )
        try await transport.sendMessage(try encode(request))
    }

    private func readResponse(
        id: Int,
        kind: ResponseKind,
        deadline: ContinuousClock.Instant,
        transport: any CodexAppServerTransport
    ) async throws -> Data {
        while true {
            try Task.checkCancellation()
            let line = try await receiveLine(
                deadline: deadline,
                transport: transport
            )
            guard line.count <= configuration.maximumLineBytes else {
                throw CodexAppServerError.responseTooLarge
            }

            let metadata: ResponseMetadata
            do {
                metadata = try JSONDecoder().decode(ResponseMetadata.self, from: line)
            } catch {
                throw CodexAppServerError.malformedResponse
            }

            guard metadata.id == id else { continue }
            if metadata.hasError {
                switch kind {
                case .initialize:
                    throw CodexAppServerError.initializationRejected
                case .account:
                    throw CodexAppServerError.accountReadRejected
                case .rateLimits:
                    throw CodexAppServerError.rateLimitsRejected
                }
            }
            guard metadata.hasResult else {
                throw CodexAppServerError.malformedResponse
            }
            return line
        }
    }

    private func receiveLine(
        deadline: ContinuousClock.Instant,
        transport: any CodexAppServerTransport
    ) async throws -> Data {
        let now = ContinuousClock.now
        guard now < deadline else { throw CodexAppServerError.timedOut }
        let remaining = now.duration(to: deadline)

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [maximumLineBytes = configuration.maximumLineBytes] in
                try await transport.receiveLine(maximumBytes: maximumLineBytes)
            }
            group.addTask {
                try await Task.sleep(for: remaining)
                throw CodexAppServerError.timedOut
            }

            do {
                guard let first = try await group.next() else {
                    throw CodexAppServerError.transportFailure
                }
                group.cancelAll()
                return first
            } catch {
                group.cancelAll()
                // Closing the owned process unblocks a pipe read before the
                // structured task group waits for its cancelled child.
                await transport.stop(gracePeriod: configuration.shutdownGracePeriod)
                throw error
            }
        }
    }

    private func finish(_ transport: any CodexAppServerTransport) async {
        await transport.stop(gracePeriod: configuration.shutdownGracePeriod)
        if let activeTransport, activeTransport === transport {
            self.activeTransport = nil
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw CodexAppServerError.transportFailure
        }
    }
}

private actor ProcessCodexAppServerTransport: CodexAppServerTransport {
    private static let forcedExitGracePeriod: Duration = .seconds(1)

    private let executableURL: URL
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var readBuffer = Data()
    private var didStop = false

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func start() throws {
        guard process == nil, !didStop else {
            throw CodexAppServerTransportError.alreadyStarted
        }

        let child = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        child.executableURL = executableURL
        child.arguments = ["app-server"]
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice

        let writer = inputPipe.fileHandleForWriting
        let reader = outputPipe.fileHandleForReading
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)

        do {
            try child.run()
        } catch {
            try? writer.close()
            try? reader.close()
            throw CodexAppServerTransportError.launchFailed
        }

        // Close the parent's copies of the child-side pipe endpoints.
        try? inputPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForWriting.close()
        process = child
        inputHandle = writer
        outputHandle = reader
    }

    func sendMessage(_ data: Data) throws {
        guard let process, process.isRunning, let inputHandle else {
            throw CodexAppServerTransportError.notRunning
        }

        var framed = data
        framed.append(0x0A)
        do {
            try inputHandle.write(contentsOf: framed)
        } catch {
            throw CodexAppServerTransportError.writeFailed
        }
    }

    func receiveLine(maximumBytes: Int) async throws -> Data {
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let lineLength = readBuffer.distance(from: readBuffer.startIndex, to: newline)
                guard lineLength <= maximumBytes else {
                    throw CodexAppServerTransportError.lineTooLarge
                }

                var line = Data(readBuffer[..<newline])
                readBuffer.removeSubrange(readBuffer.startIndex...newline)
                if line.last == 0x0D { line.removeLast() }
                return line
            }

            guard readBuffer.count <= maximumBytes else {
                throw CodexAppServerTransportError.lineTooLarge
            }
            guard let outputHandle else {
                throw CodexAppServerTransportError.endOfFile
            }

            // `availableData` returns as soon as a pipe has bytes. In contrast,
            // FileHandle's exact-count read can wait for the requested buffer
            // size on a live JSONL stream even after a complete line arrived.
            let chunk = await Task.detached(priority: .utility) {
                outputHandle.availableData
            }.value

            guard !chunk.isEmpty else {
                throw CodexAppServerTransportError.endOfFile
            }
            readBuffer.append(chunk)
        }
    }

    func stop(gracePeriod: Duration) async {
        guard !didStop else { return }
        didStop = true

        try? inputHandle?.close()
        inputHandle = nil

        if let process {
            await waitForExit(process, duration: gracePeriod)
            if process.isRunning {
                process.terminate()
                await waitForExit(process, duration: Self.forcedExitGracePeriod)
            }
            if process.isRunning {
                // This PID belongs to the Process instance created above. No
                // name lookup or global process termination is ever used.
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                await waitForExit(process, duration: Self.forcedExitGracePeriod)
            }
        }

        try? outputHandle?.close()
        outputHandle = nil
        process = nil
        readBuffer.removeAll(keepingCapacity: false)
    }

    private func waitForExit(_ process: Process, duration: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: duration)
        while process.isRunning, ContinuousClock.now < deadline {
            await Task.detached(priority: .utility) {
                try? await Task.sleep(for: .milliseconds(20))
            }.value
        }
    }
}

private struct InitializeRequest: Encodable {
    let method = "initialize"
    let id = 1
    let params: InitializeParameters
}

private struct InitializeParameters: Encodable {
    let clientInfo: ClientInfo
}

private struct ClientInfo: Encodable {
    let name: String
    let title: String
    let version: String
}

private struct InitializedNotification: Encodable {
    let method = "initialized"
    let params = EmptyParameters()
}

private struct AccountReadRequest: Encodable {
    let method = "account/read"
    let id = 2
    let params = AccountReadParameters()
}

private struct AccountReadParameters: Encodable {
    let refreshToken = false
}

private struct RateLimitsRequest: Encodable {
    let method = "account/rateLimits/read"
    let id = 3
}

private struct EmptyParameters: Encodable {}

private struct AccountReadResponse: Decodable {
    let result: AccountReadResult
}

private struct AccountReadResult: Decodable {
    let hasAccount: Bool
    let requiresOpenaiAuth: Bool

    private enum CodingKeys: String, CodingKey {
        case account
        case requiresOpenaiAuth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.account) {
            hasAccount = try !container.decodeNil(forKey: .account)
        } else {
            hasAccount = false
        }
        requiresOpenaiAuth = try container.decode(Bool.self, forKey: .requiresOpenaiAuth)
    }
}

private struct ResponseMetadata: Decodable {
    let id: Int?
    let hasResult: Bool
    let hasError: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        if container.contains(.result) {
            hasResult = !(try container.decodeNil(forKey: .result))
        } else {
            hasResult = false
        }
        if container.contains(.error) {
            hasError = !(try container.decodeNil(forKey: .error))
        } else {
            hasError = false
        }
    }
}
