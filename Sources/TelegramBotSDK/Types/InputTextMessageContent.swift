// Telegram Bot SDK for Swift (unofficial).
// This file is autogenerated by API/generate_wrappers.rb script.

import Foundation
import SwiftyJSON

/// Represents the content of a text message to be sent as the result of an inline query.
///
/// - SeeAlso: <https://core.telegram.org/bots/api#inputtextmessagecontent>

public struct InputTextMessageContent: JsonConvertible {
    /// Original JSON for fields not yet added to Swift structures.
    public var json: JSON

    /// Text of the message to be sent, 1-4096 characters
    public var message_text: String {
        get { return json["message_text"].stringValue }
        set { json["message_text"].stringValue = newValue }
    }

    /// Optional. Send Markdown or HTML, if you want Telegram apps to show bold, italic, fixed-width text or inline URLs in your bot's message.
    public var parse_mode: String? {
        get { return json["parse_mode"].string }
        set { json["parse_mode"].string = newValue }
    }

    /// Optional. Disables link previews for links in the sent message
    public var disable_web_page_preview: Bool? {
        get { return json["disable_web_page_preview"].bool }
        set { json["disable_web_page_preview"].bool = newValue }
    }

    public init(json: JSON = [:]) {
        self.json = json
    }
}