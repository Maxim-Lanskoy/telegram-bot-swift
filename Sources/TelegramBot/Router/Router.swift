// Telegram Bot SDK for Swift (unofficial).
// (c) 2015 - 2016 Andrey Fidrya. MIT license. See LICENSE for more information.

import Foundation

public class Router {
	public typealias Handler = (context: Context) throws -> Bool
	public typealias Path = (contentType: ContentType, handler: Handler)
	
    public var caseSensitive: Bool = false
    public var charactersToBeSkipped: NSCharacterSet? = NSCharacterSet.whitespacesAndNewlines()

	public var bot: TelegramBot

	public lazy var partialMatch: Handler? = { context in
		context.respondAsync("❗ Part of your input was ignored: \(context.args.scanRestOfString())")
		return true
	}
	
	public lazy var unknownCommand: Handler? = { context in
		context.respondAsync("Unrecognized command: \(context.args.command). Type /help for help.")
		return true
	}

	public lazy var unsupportedContentType: Handler? = { context in
		context.respondAsync("Unsupported content type.")
		return true
	}

	public init(bot: TelegramBot) {
		self.bot = bot
    }
	
	public func add(_ contentType: ContentType, _ handler: (Context) throws -> Bool) {
		paths.append(Path(contentType, handler))
	}
	
	public func add(_ contentType: ContentType, _ handler: (Context) throws->()) {
		add(contentType) { (context: Context) -> Bool in
			try handler(context)
			return true
		}
	}
	
	public func add(_ contentType: ContentType, _ handler: () throws->(Bool)) {
		add(contentType) {  (_: Context) -> Bool in
			return try handler()
		}
	}
	
	public func add(_ contentType: ContentType, _ handler: () throws->()) {
		add(contentType) {  (context: Context) -> Bool in
			try handler()
			return true
		}
	}
	
	public func add(_ command: Command, _ handler: (Context) throws -> Bool) {
		paths.append(Path(.command(command), handler))
	}

	public func add(_ command: Command, _ handler: (Context) throws->()) {
		add(command) { (context: Context) -> Bool in
			try handler(context)
			return true
		}
	}

    public func add(_ command: Command, _ handler: () throws->(Bool)) {
		add(command) {  (_: Context) -> Bool in
			return try handler()
		}
    }

	public func add(_ command: Command, _ handler: () throws->()) {
		add(command) {  (context: Context) -> Bool in
			try handler()
			return true
		}
    }
	
    public func process(message: Message) throws -> Bool {
		let string = message.extractCommand(for: bot) ?? ""
        let scanner = NSScanner(string: string)
        scanner.caseSensitive = caseSensitive
        scanner.charactersToBeSkipped = charactersToBeSkipped
		let originalScanLocation = scanner.scanLocation
		
		for path in paths {
			var command = ""
			if !match(contentType: path.contentType, message: message, commandScanner: scanner, userCommand: &command) {
				scanner.scanLocation = originalScanLocation
				continue;
			}
			
			let context = Context(bot: bot, message: message, scanner: scanner, command: command)
			let handler = path.handler

			if try handler(context: context) {
				return try checkPartialMatch(context: context)
			}

			scanner.scanLocation = originalScanLocation
		}

		if !string.isEmpty {
			if let unknownCommand = unknownCommand {
				let whitespaceAndNewline = NSCharacterSet.whitespacesAndNewlines()
				let command = scanner.scanUpToCharactersFromSet(whitespaceAndNewline)
				let context = Context(bot: bot, message: message, scanner: scanner, command: command ?? "")
				if try !unknownCommand(context: context) {
					return try checkPartialMatch(context: context)
				}
				return true
			}
		} else {
			if let unsupportedContentType = unsupportedContentType {
				let context = Context(bot: bot, message: message, scanner: scanner, command: "")
				return try !unsupportedContentType(context: context)
			}
		}
		
		return false
    }
	
	func match(contentType: ContentType, message: Message, commandScanner: NSScanner, userCommand: inout String) -> Bool {
		switch contentType {
		case .command(let command):
			guard let command = command.fetchFrom(commandScanner) else {
				return false // Does not match path command
			}
			userCommand = command
			return true
		case .audio: return message.audio != nil
		case .document: return message.document != nil
		case .photo: return !message.photo.isEmpty
		case .sticker: return message.sticker != nil
		case .video: return message.video != nil
		//case .voice: return message.voice != nil
		case .contact: return message.contact != nil
		case .location: return message.location != nil
		//case .venue: return message.venue != nil
		case .newChatMember: return message.new_chat_member != nil
		case .leftChatMember: return message.left_chat_member != nil
		case .newChatTitle: return message.new_chat_title != nil
		//case .newChatPhoto: return message.new_chat_photo != nil
		//case .deleteChatPhoto: return message.delete_chat_photo != nil
		//case .groupChatCreated: return message.group_chat_created != nil
		//case .supergroupChatCreated: return message.supergroup_chat_created != nil
		//case .channelChatCreated: return message.channel_chat_created != nil
		//case .migrateToChatId: return message.migrate_to_chat_id != nil
		//case .migrateFromChatId: return message.migrate_from_chat_id != nil
		//case .pinnedMessage: return message.pinned_message != nil
		default: break
		}
		return false
	}
	
	// After processing the command, check that no unprocessed text is left
	func checkPartialMatch(context: Context) throws -> Bool {

		// Note that scanner.atEnd automatically ignores charactersToBeSkipped
		if !context.args.isAtEnd {
			// Partial match
			if let handler = partialMatch {
				return try handler(context: context)
			}
		}
		
		return true
	}
	
	var paths = [Path]()
}
