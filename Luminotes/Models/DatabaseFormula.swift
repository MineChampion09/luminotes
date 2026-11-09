import Foundation

/// A small, safe expression evaluator for database formula properties.
///
/// Supported syntax:
/// - property references: `prop("Price")`, `prop(Price)`
/// - arithmetic: `+ - * / %`
/// - comparisons: `== != > < >= <=`
/// - boolean logic: `&& || !`, `and(...)`, `or(...)`, `not(...)`
/// - functions: `if`, `concat`, `round`, `floor`, `ceil`, `abs`, `min`,
///   `max`, `length`, `upper`, `lower`, `trim`, `contains`, `startsWith`,
///   `endsWith`, `empty`, `notEmpty`, `toNumber`, `toString`, `year`,
///   `month`, `day`, `dateFormat`, `today`, `now`
///
/// Formulas never throw to the caller; parse or evaluation failures render as
/// `#ERROR` so a broken formula cannot take down the database view.
enum DatabaseFormula {
    static func evaluate(
        property: DatabaseProperty,
        row: DatabaseRow,
        config: DatabaseConfig
    ) -> String {
        let source = property.formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }
        do {
            let evaluator = Evaluator(
                row: row,
                config: config,
                currentPropertyID: property.id,
                depth: 0
            )
            return try evaluator.run(source).displayString
        } catch {
            return "#ERROR"
        }
    }

    static func validate(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let evaluator = Evaluator(
                row: .placeholder,
                config: .defaultConfig(),
                currentPropertyID: nil,
                depth: 0
            )
            _ = try evaluator.run(trimmed)
            return nil
        } catch {
            return "Check the formula syntax."
        }
    }
}

// MARK: - Values

private enum FormulaValue: Equatable {
    case number(Double)
    case string(String)
    case boolean(Bool)
    case null

    var displayString: String {
        switch self {
        case .number(let value):
            return FormulaValue.formatNumber(value)
        case .string(let value):
            return value
        case .boolean(let value):
            return value ? "Yes" : "No"
        case .null:
            return ""
        }
    }

    var stringValue: String {
        switch self {
        case .number(let value):
            return FormulaValue.formatNumber(value)
        case .string(let value):
            return value
        case .boolean(let value):
            return value ? "true" : "false"
        case .null:
            return ""
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        case .boolean(let value):
            return value ? 1 : 0
        case .null:
            return 0
        }
    }

    var boolValue: Bool {
        switch self {
        case .number(let value):
            return value != 0
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if trimmed.caseInsensitiveCompare("false") == .orderedSame { return false }
            if trimmed == "0" { return false }
            return true
        case .boolean(let value):
            return value
        case .null:
            return false
        }
    }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var isText: Bool {
        if case .string = self { return true }
        return false
    }

    static func formatNumber(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}

private struct FormulaError: Error {}

// MARK: - Tokenizer

private enum FormulaToken: Equatable {
    case number(Double)
    case string(String)
    case identifier(String)
    case symbol(String)
}

private struct FormulaLexer {
    private let characters: [Character]
    private var index = 0

    init(_ source: String) {
        characters = Array(source)
    }

    mutating func tokenize() throws -> [FormulaToken] {
        var tokens: [FormulaToken] = []

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            if character.isNumber || (character == "." && isNextNumber) {
                tokens.append(.number(try readNumber()))
                continue
            }

            if character == "\"" || character == "'" {
                tokens.append(.string(try readString(quote: character)))
                continue
            }

            if character.isLetter || character == "_" {
                tokens.append(.identifier(readIdentifier()))
                continue
            }

            if let symbol = readSymbol() {
                tokens.append(.symbol(symbol))
                continue
            }

            throw FormulaError()
        }

        return tokens
    }

    private var isNextNumber: Bool {
        guard index + 1 < characters.count else { return false }
        return characters[index + 1].isNumber
    }

    private mutating func readNumber() throws -> Double {
        var text = ""
        var hasDot = false
        var hasExponent = false

        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                text.append(character)
                index += 1
            } else if character == ".", !hasDot, !hasExponent {
                hasDot = true
                text.append(character)
                index += 1
            } else if (character == "e" || character == "E"), !hasExponent {
                hasExponent = true
                text.append(character)
                index += 1
                if index < characters.count,
                   characters[index] == "+" || characters[index] == "-" {
                    text.append(characters[index])
                    index += 1
                }
            } else {
                break
            }
        }

        guard let value = Double(text) else { throw FormulaError() }
        return value
    }

    private mutating func readString(quote: Character) throws -> String {
        index += 1
        var text = ""

        while index < characters.count {
            let character = characters[index]
            if character == quote {
                index += 1
                return text
            }
            if character == "\\", index + 1 < characters.count {
                index += 1
                let escaped = characters[index]
                switch escaped {
                case "n": text.append("\n")
                case "t": text.append("\t")
                case "\\": text.append("\\")
                case "\"": text.append("\"")
                case "'": text.append("'")
                default: text.append(escaped)
                }
                index += 1
                continue
            }
            text.append(character)
            index += 1
        }

        throw FormulaError()
    }

    private mutating func readIdentifier() -> String {
        var text = ""
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" {
                text.append(character)
                index += 1
            } else {
                break
            }
        }
        return text
    }

    private mutating func readSymbol() -> String? {
        let character = characters[index]
        let twoCharacter = index + 1 < characters.count
            ? String(characters[index...(index + 1)])
            : nil

        if let twoCharacter,
           ["==", "!=", ">=", "<=", "&&", "||"].contains(twoCharacter) {
            index += 2
            return twoCharacter
        }

        if "+-*/%(),<>!".contains(character) {
            index += 1
            return String(character)
        }

        return nil
    }
}

// MARK: - Evaluator

private struct Evaluator {
    let row: DatabaseRow
    let config: DatabaseConfig
    let currentPropertyID: String?
    let depth: Int

    func run(_ source: String) throws -> FormulaValue {
        var lexer = FormulaLexer(source)
        let tokens = try lexer.tokenize()
        guard !tokens.isEmpty else { return .null }
        var parser = Parser(tokens: tokens, evaluator: self)
        return try parser.parse()
    }

    func propertyValue(named name: String) -> FormulaValue {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let property = config.properties.first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame || $0.id == trimmed
        }) else {
            return .null
        }

        if property.type == .formula {
            guard property.id != currentPropertyID,
                  depth < 8,
                  !property.formula.isEmpty else {
                return .null
            }
            do {
                let nested = Evaluator(
                    row: row,
                    config: config,
                    currentPropertyID: property.id,
                    depth: depth + 1
                )
                return try nested.run(property.formula)
            } catch {
                return .null
            }
        }

        let raw = row.rawValue(for: property)
        if raw.isEmpty { return .null }

        switch property.type {
        case .number:
            return Double(raw).map(FormulaValue.number) ?? .string(raw)
        case .checkbox:
            return .boolean(raw == "true")
        default:
            return .string(raw)
        }
    }
}

private struct Parser {
    let tokens: [FormulaToken]
    let evaluator: Evaluator
    var index = 0

    mutating func parse() throws -> FormulaValue {
        let value = try expression()
        guard index == tokens.count else { throw FormulaError() }
        return value
    }

    private var current: FormulaToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func advance() -> FormulaToken? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    private mutating func match(_ symbol: String) -> Bool {
        guard case .symbol(let value)? = current, value == symbol else {
            return false
        }
        index += 1
        return true
    }

    private mutating func matchWord(_ word: String) -> Bool {
        guard case .identifier(let value)? = current,
              value.caseInsensitiveCompare(word) == .orderedSame else {
            return false
        }
        index += 1
        return true
    }

    private mutating func expect(_ symbol: String) throws {
        guard match(symbol) else { throw FormulaError() }
    }

    private mutating func expression() throws -> FormulaValue {
        try orExpression()
    }

    private mutating func orExpression() throws -> FormulaValue {
        var value = try andExpression()
        while match("||") || matchWord("or") {
            let right = try andExpression()
            value = .boolean(value.boolValue || right.boolValue)
        }
        return value
    }

    private mutating func andExpression() throws -> FormulaValue {
        var value = try equalityExpression()
        while match("&&") || matchWord("and") {
            let right = try equalityExpression()
            value = .boolean(value.boolValue && right.boolValue)
        }
        return value
    }

    private mutating func equalityExpression() throws -> FormulaValue {
        var value = try comparisonExpression()
        while true {
            if match("==") {
                let right = try comparisonExpression()
                value = .boolean(equal(value, right))
            } else if match("!=") {
                let right = try comparisonExpression()
                value = .boolean(!equal(value, right))
            } else {
                return value
            }
        }
    }

    private mutating func comparisonExpression() throws -> FormulaValue {
        var value = try additiveExpression()
        while true {
            if match(">=") {
                let right = try additiveExpression()
                value = .boolean(compare(value, right) != .orderedAscending)
            } else if match("<=") {
                let right = try additiveExpression()
                value = .boolean(compare(value, right) != .orderedDescending)
            } else if match(">") {
                let right = try additiveExpression()
                value = .boolean(compare(value, right) == .orderedDescending)
            } else if match("<") {
                let right = try additiveExpression()
                value = .boolean(compare(value, right) == .orderedAscending)
            } else {
                return value
            }
        }
    }

    private mutating func additiveExpression() throws -> FormulaValue {
        var value = try multiplicativeExpression()
        while true {
            if match("+") {
                let right = try multiplicativeExpression()
                if value.isText || right.isText {
                    value = .string(value.stringValue + right.stringValue)
                } else {
                    value = .number((value.numberValue ?? 0) + (right.numberValue ?? 0))
                }
            } else if match("-") {
                let right = try multiplicativeExpression()
                value = .number((value.numberValue ?? 0) - (right.numberValue ?? 0))
            } else {
                return value
            }
        }
    }

    private mutating func multiplicativeExpression() throws -> FormulaValue {
        var value = try unaryExpression()
        while true {
            if match("*") {
                let right = try unaryExpression()
                value = .number((value.numberValue ?? 0) * (right.numberValue ?? 0))
            } else if match("/") {
                let right = try unaryExpression()
                let divisor = right.numberValue ?? 0
                value = divisor == 0 ? .null : .number((value.numberValue ?? 0) / divisor)
            } else if match("%") {
                let right = try unaryExpression()
                let divisor = right.numberValue ?? 0
                value = divisor == 0
                    ? .null
                    : .number((value.numberValue ?? 0).truncatingRemainder(dividingBy: divisor))
            } else {
                return value
            }
        }
    }

    private mutating func unaryExpression() throws -> FormulaValue {
        if match("!") || matchWord("not") {
            return .boolean(!(try unaryExpression()).boolValue)
        }
        if match("-") {
            return .number(-((try unaryExpression()).numberValue ?? 0))
        }
        return try primaryExpression()
    }

    private mutating func primaryExpression() throws -> FormulaValue {
        guard let token = advance() else { throw FormulaError() }

        switch token {
        case .number(let value):
            return .number(value)
        case .string(let value):
            return .string(value)
        case .identifier(let name):
            if case .symbol("(")? = current {
                return try functionCall(name: name)
            }
            switch name.lowercased() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            case "null", "empty": return .null
            default: return evaluator.propertyValue(named: name)
            }
        case .symbol("("):
            let value = try expression()
            try expect(")")
            return value
        default:
            throw FormulaError()
        }
    }

    private mutating func functionCall(name: String) throws -> FormulaValue {
        try expect("(")

        if name.caseInsensitiveCompare("prop") == .orderedSame {
            let propertyName = try propertyNameArgument()
            try expect(")")
            return evaluator.propertyValue(named: propertyName)
        }

        var arguments: [FormulaValue] = []
        if !match(")") {
            repeat {
                arguments.append(try expression())
            } while match(",")
            try expect(")")
        }

        return try apply(function: name, arguments: arguments)
    }

    private mutating func propertyNameArgument() throws -> String {
        guard let token = advance() else { throw FormulaError() }
        switch token {
        case .string(let value):
            return value
        case .identifier(let value):
            return value
        default:
            throw FormulaError()
        }
    }

    private func apply(function: String, arguments: [FormulaValue]) throws -> FormulaValue {
        let name = function.lowercased()
        let first = arguments.first ?? .null

        switch name {
        case "if":
            guard arguments.count >= 2 else { throw FormulaError() }
            if first.boolValue {
                return arguments[1]
            }
            return arguments.count > 2 ? arguments[2] : .null

        case "and":
            return .boolean(arguments.allSatisfy(\.boolValue))

        case "or":
            return .boolean(arguments.contains(where: \.boolValue))

        case "not":
            return .boolean(!first.boolValue)

        case "concat":
            return .string(arguments.map(\.stringValue).joined())

        case "round":
            let value = first.numberValue ?? 0
            let digits = Int(arguments.count > 1 ? (arguments[1].numberValue ?? 0) : 0)
            let factor = pow(10, Double(max(-6, min(6, digits))))
            return .number((value * factor).rounded() / factor)

        case "floor":
            return .number(floor(first.numberValue ?? 0))

        case "ceil":
            return .number(ceil(first.numberValue ?? 0))

        case "abs":
            return .number(abs(first.numberValue ?? 0))

        case "min":
            let values = arguments.compactMap(\.numberValue)
            return values.min().map(FormulaValue.number) ?? .null

        case "max":
            let values = arguments.compactMap(\.numberValue)
            return values.max().map(FormulaValue.number) ?? .null

        case "length":
            return .number(Double(first.stringValue.count))

        case "upper":
            return .string(first.stringValue.uppercased())

        case "lower":
            return .string(first.stringValue.lowercased())

        case "trim":
            return .string(first.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))

        case "contains":
            guard arguments.count >= 2 else { return .boolean(false) }
            return .boolean(
                first.stringValue.localizedCaseInsensitiveContains(arguments[1].stringValue)
            )

        case "startswith":
            guard arguments.count >= 2 else { return .boolean(false) }
            return .boolean(
                first.stringValue.lowercased().hasPrefix(arguments[1].stringValue.lowercased())
            )

        case "endswith":
            guard arguments.count >= 2 else { return .boolean(false) }
            return .boolean(
                first.stringValue.lowercased().hasSuffix(arguments[1].stringValue.lowercased())
            )

        case "empty":
            return .boolean(first.isNull || first.stringValue.isEmpty)

        case "notempty":
            return .boolean(!(first.isNull || first.stringValue.isEmpty))

        case "tonumber":
            return first.numberValue.map(FormulaValue.number) ?? .null

        case "tostring":
            return .string(first.stringValue)

        case "year", "month", "day":
            guard let date = Self.parseDate(first.stringValue) else { return .null }
            let component: Calendar.Component = name == "year"
                ? .year
                : (name == "month" ? .month : .day)
            let value = Calendar.current.component(component, from: date)
            return .number(Double(value))

        case "dateformat":
            guard let date = Self.parseDate(first.stringValue) else { return .null }
            let format = arguments.count > 1 && !arguments[1].stringValue.isEmpty
                ? arguments[1].stringValue
                : "yyyy-MM-dd"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return .string(formatter.string(from: date))

        case "today":
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return .string(formatter.string(from: Date()))

        case "now":
            return .string(DatabaseRow.isoFormatter.string(from: Date()))

        default:
            throw FormulaError()
        }
    }

    private func equal(_ left: FormulaValue, _ right: FormulaValue) -> Bool {
        if let leftNumber = left.numberValue,
           let rightNumber = right.numberValue,
           (left.isText == false || Double(left.stringValue) != nil),
           (right.isText == false || Double(right.stringValue) != nil) {
            return leftNumber == rightNumber
        }
        return left.stringValue.localizedCaseInsensitiveCompare(right.stringValue) == .orderedSame
    }

    private func compare(_ left: FormulaValue, _ right: FormulaValue) -> ComparisonResult {
        if let leftNumber = left.numberValue,
           let rightNumber = right.numberValue,
           (left.isText == false || Double(left.stringValue) != nil),
           (right.isText == false || Double(right.stringValue) != nil) {
            if leftNumber == rightNumber { return .orderedSame }
            return leftNumber < rightNumber ? .orderedAscending : .orderedDescending
        }
        return left.stringValue.localizedStandardCompare(right.stringValue)
    }

    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = DatabaseRow.isoFormatter.date(from: trimmed) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }
}

private extension DatabaseRow {
    static var placeholder: DatabaseRow {
        DatabaseRow(
            id: "",
            url: URL(fileURLWithPath: "/"),
            relativePath: "",
            title: "Untitled",
            fileExtension: "md",
            isMarkdown: true,
            createdAt: Date(),
            modifiedAt: Date(),
            values: [:]
        )
    }
}
