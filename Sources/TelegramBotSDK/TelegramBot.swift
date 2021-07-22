//
// TelegramBot.swift
//
// This source file is part of the Telegram Bot SDK for Swift (unofficial).
//

import Foundation
import Dispatch

public class TelegramBot {
    internal typealias DataTaskCompletion = (_ result: Decodable?, _ error: DataTaskError?)->()

    public typealias RequestParameters = [String: Encodable?]
	
    /// Telegram server URL.
    public var url = "https://api.telegram.org"
    
    /// Unique authentication token obtained from BotFather.
    public var token: String
	
    /// Default request parameters
    public var defaultParameters = [String: RequestParameters]()
	
    /// In case of network errors or server problems,
    /// do not report the errors and try to reconnect
    /// automatically.
    public var autoReconnect: Bool = true

    /// Offset for long polling.
    public var nextOffset: Int64?

    /// Number of updates to fetch by default.
    public var defaultUpdatesLimit: Int = 100

    /// Default getUpdates timeout in seconds.
    public var defaultUpdatesTimeout: Int = 60
    
    // Should probably be a LinkedList, but it won't be longer than
    // 100 elements anyway.
    var unprocessedUpdates: [Update]
    
    /// Queue for callbacks in asynchronous versions of requests.
    public var queue = DispatchQueue.main
    
    /// Last error for use with synchronous requests.
    public var lastError: DataTaskError?
    
    /// Logging function. Defaults to `print`.
    public var logger: (_ text: String) -> () = { print($0) }
    
    /// Defines reconnect delay in seconds when requesting updates. Can be overridden.
    ///
    /// - Parameter retryCount: Number of reconnect retries associated with `request`.
    /// - Returns: Seconds to wait before next reconnect attempt. Return `0.0` for instant reconnect.
    public var reconnectDelay: (_ retryCount: Int) -> Double = { retryCount in
        switch retryCount {
            case 0: return 0.0
            case 1: return 1.0
            case 2: return 2.0
            case 3: return 5.0
            case 4: return 10.0
            case 5: return 20.0
            default: break
        }
        return 30.0
    }
    
    /// Equivalent of calling `getMe()`
    ///
    /// This function will block until the request is finished.
    public lazy var user: User = {
        guard let me = self.getMeSync() else {
            print("Unable to fetch bot information: \(self.lastError.unwrapOptional)")
            exit(1)
        }
        return me
    }()
    
    /// Equivalent of calling `user.username` and unwrapping it
    ///
    /// This function will block until the request is finished.
    public lazy var username: String = {
        guard let username = self.user.username else {
            fatalError("Unable to fetch bot username")
        }
        return username
    }()
    
    /// Equivalent of calling `BotName(username: username)`
    ///
    /// This function will block until the request is finished.
    public lazy var name: BotName = BotName(username: self.username)

    /// URLSession with cache policy set to
    /// `.reloadIgnoringLocalAndRemoteCacheData`
    private lazy var urlSession: URLSession = {
        var config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        return session
    }()
    
    /// Creates an instance of Telegram Bot.
    /// - Parameter token: A unique authentication token.
    /// - Parameter fetchBotInfo: If true, issue a blocking `getMe()` call and cache the bot information. Otherwise it will be lazy-loaded when needed. Defaults to true.
    /// - Parameter session: `NSURLSession` instance, a session with `ephemeralSessionConfiguration` is used by default.
    public init(token: String, fetchBotInfo: Bool = true) {
        self.token = token
        self.unprocessedUpdates = []
        if fetchBotInfo {
            _ = user // Load the lazy user variable
        }
    }
    
    deinit {
        //print("Deinit")
    }
    
    /// Returns next update for this bot.
    ///
    /// Blocks while fetching updates from the server.
    ///
    /// - Parameter mineOnly: Ignore commands not addressed to me, i.e. `/command@another_bot`.
    /// - Returns: `Update`. `Nil` on error, in which case details
    ///   can be obtained from `lastError` property.
    public func nextUpdateSync(onlyMine: Bool = true) -> Update? {
        while let update = nextUpdateSync() {
            if onlyMine {
                if let message = update.message, !message.addressed(to: self) {
                    continue
                }
            }
            return update
        }
        return nil
    }
    
    /// Waits for specified number of seconds. Message loop won't be blocked.
    ///
    /// - Parameter wait: Seconds to wait.
    public func wait(seconds: Double) {
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            sem.signal()
        }
        RunLoop.current.waitForSemaphore(sem)
    }
    
    /// Initiates a request to the server. Used for implementing
    /// specific requests (getMe, getStatus etc).
    internal func startDataTaskForEndpoint<T: Decodable>(_ endpoint: String, resultType: T.Type, completion: @escaping DataTaskCompletion) {
        startDataTaskForEndpoint(endpoint, parameters: [:], resultType: resultType, completion: completion)
    }
    
    /// Initiates a request to the server. Used for implementing
    /// specific requests.
    internal func startDataTaskForEndpoint<T: Decodable>(_ endpoint: String, parameters: [String: Encodable?], resultType: T.Type, completion: @escaping DataTaskCompletion) {
        let endpointUrl = urlForEndpoint(endpoint)
        var request = URLRequest(url: endpointUrl)

        // If parameters contain values of type InputFile, use  multipart/form-data for sending them.
        var hasAttachments = false
        for valueOrNil in parameters.values {
            guard let value = valueOrNil else { continue }
            guard value as? [LabeledPrice] == nil else { continue }
            if value is InputFile {
                hasAttachments = true
                break
            }
            if let inputFileOrString = value as? InputFileOrString {
                if case .inputFile = inputFileOrString {
                    hasAttachments = true
                    break
                }
            }
        }
        
        let contentType: String
        var requestDataOrNil: Data?
        if hasAttachments {
            let boundary = HTTPUtils.generateBoundaryString()
            contentType = "multipart/form-data; boundary=\(boundary)"
            requestDataOrNil = HTTPUtils.createMultipartFormDataBody(with: parameters, boundary: boundary)
            logger("endpoint: \(endpoint), sending parameters as multipart/form-data")
        } else {
            contentType = "application/x-www-form-urlencoded"
            if let encoded = HTTPUtils.formUrlencode(parameters) {
                logger("endpoint: \(endpoint), data: \(encoded)")
                requestDataOrNil = encoded.data(using: .utf8)
            }
        }

        guard let requestData = requestDataOrNil else {
            completion(nil, .invalidRequest)
            return
        }

        // Use post to send http body
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = requestData

        let dataTask = urlSession.dataTask(with: request) { data, response, error in
            let data = data ?? Data()
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .secondsSince1970

            guard let response = response as? HTTPURLResponse else {
                completion(nil, .noDataReceived)
                return
            }
            let httpCode = response.statusCode

            var telegramResponse: Response<T>?
            do {
                telegramResponse = try decoder.decode(Response<T>.self, from: data)
            } catch {
                print(error.localizedDescription)
                completion(nil, .decodeError(data: data))
                return
            }
            guard let safeTelegramResponse = telegramResponse else {
                completion(nil, .decodeError(data: data))
                return
            }
            guard httpCode == 200 else {
                completion(nil,
                           .invalidStatusCode(
                            statusCode: httpCode,
                            telegramDescription: safeTelegramResponse.description!,
                            telegramErrorCode: safeTelegramResponse.errorCode!,
                            data: data)
                )
                return
            }
            guard !data.isEmpty else {
                completion(nil, .noDataReceived)
                return
            }
            if !safeTelegramResponse.ok {
                completion(nil, .serverError(data: data))
                return
            }
            completion(safeTelegramResponse.result!, nil)
        }

        dataTask.resume()
    }
    
    private func urlForEndpoint(_ endpoint: String) -> URL {
        let tokenUrlencoded = token.urlQueryEncode()
        let endpointUrlencoded = endpoint.urlQueryEncode()
        let urlString = "\(url)/bot\(tokenUrlencoded)/\(endpointUrlencoded)"
        guard let result = URL(string: urlString) else {
            fatalError("Invalid URL: \(urlString)")
        }
        return result
    }
}
