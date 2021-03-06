import Foundation

enum Keyword: String {
  case On = "on", Fragment = "fragment", BoolTrue = "true", BoolFalse = "false", Null = "null", Implements = "implements"
  case Type = "type", Interface = "interface", Union = "union", Scalar, EnumType = "enum", Input = "input", Extend = "extend"
  case Query = "query", Mutation = "mutation", Subscription = "subscription"
}

enum ParserError: ErrorType {
  case UnexpectedToken(Token)
  case UnexpectedKeyword(Keyword, Token)
  case WrongTokenKind(TokenKind, TokenKind)
}

public class Parser {
  private let lexer: Lexer
  private var token: Token!

  init(source: String) {
    lexer = Lexer(source: source)
  }

  public func parse() throws -> Document {
    token = try lexer.next()
    return try parseDocument()
  }

}

extension Parser {

  private func parseDocument() throws -> Document {
    var definitions: [Definition] = []

    repeat {
      definitions.append(try parseDefinition())
    } while try !skip(.EOF)

    return Document(definitions: definitions)
  }

  private func parseDefinition() throws -> Definition {
    if peek(.BraceL) {
      return .Operation(try parseOperationDefinition())
    }

    guard peek(.Name), let value = token.value, keyword = Keyword(rawValue: value) else {
      throw ParserError.UnexpectedToken(token)
    }

    switch keyword {
    case .Query, .Mutation, .Subscription:
      return .Operation(try parseOperationDefinition())
    case .Fragment:
      return .Fragment(try parseFragmentDefinition())
    case .Type, .Interface, .Union, .Scalar, .EnumType, .Input:
      return .Type(try parseTypeDefinition())
    case .Extend:
      return .TypeExtension(try parseTypeExtensionDefinition())
    default:
      throw ParserError.UnexpectedToken(token)
    }
  }

}

extension Parser {

  private func parseOperationDefinition() throws -> OperationDefinition {
    if peek(.BraceL) {
      return OperationDefinition(
        type: .Query,
        name: nil,
        variableDefinitions: [],
        directives: [],
        selectionSet: try parseSelectionSet())
    }

    let operationToken = try expect(.Name)

    guard let typeString = operationToken.value, type = OperationType(rawValue: typeString) else {
      throw ParserError.UnexpectedToken(operationToken)
    }

    let name: Name? = peek(.Name) ? try parseName() : nil

    return OperationDefinition(
      type: type,
      name: name,
      variableDefinitions: try parseVariableDefinitions(),
      directives: try parseDirectives(),
      selectionSet: try parseSelectionSet())
  }

  private func parseVariableDefinitions() throws -> [VariableDefinition] {
    return peek(.ParenL) ? try many(openKind: .ParenL, parseFn: parseVariableDefinition, closeKind: .ParenR) : []
  }

  private func parseVariableDefinition() throws -> VariableDefinition {
    let variable = try parseVariable()
    try expect(.Colon)
    let type = try parseType()
    let defaultValue: Value? = try skip(.Equals) ? try parseValueLiteral(isConst: true) : nil
    return VariableDefinition(variable: variable, type: type, defaultValue: defaultValue)
  }

  private func parseVariable() throws -> Variable {
    try expect(.Dollar)
    return Variable(name: try parseName())
  }

  private func parseSelectionSet() throws -> SelectionSet {
    return SelectionSet(selections: try many(openKind: .BraceL, parseFn: parseSelection, closeKind: .BraceR))
  }

  private func parseSelection() throws -> Selection {
    return peek(.Spread) ? try parseFragment() : Selection.FieldSelection(try parseField())
  }

  private func parseField() throws -> Field {
    let nameOrAlias = try parseName()
    let alias: Name?
    let name: Name
    if try skip(.Colon) {
      alias = nameOrAlias
      name = try parseName()
    } else {
      alias = nil
      name = nameOrAlias
    }

    return Field(
      alias: alias,
      name: name,
      arguments: try parseArguments(),
      directives: try parseDirectives(),
      selectionSet: peek(.BraceL) ? try parseSelectionSet() : nil)
  }

  private func parseArguments() throws -> [Argument] {
    return peek(.ParenL) ? try many(openKind: .ParenL, parseFn: parseArgument, closeKind: .ParenR) : []
  }

  private func parseArgument() throws -> Argument {
    let name = try parseName()
    try expect(.Colon)
    let value = try parseValueLiteral(isConst: false)
    return Argument(name: name, value: value)
  }

  private func parseName() throws -> Name {
    let nameToken = try expect(.Name)
    return Name(value: nameToken.value)
  }

}

extension Parser {

  private func parseFragment() throws -> Selection {
    try expect(.Spread)

    if peek(.Name) && token.value != Keyword.On.rawValue {
      return .FragmentSpreadSelection(FragmentSpread(
      name: try parseFragmentName(),
        directives: try parseDirectives()))
    }

    let typeCondition: Type?
    if token.value == Keyword.On.rawValue {
      try advance()
      typeCondition = try parseNamedType()
    } else {
      typeCondition = nil
    }

    return .InlineFragmentSelection(InlineFragment(
    typeCondition: typeCondition,
      directives: try parseDirectives(),
      selectionSet: try parseSelectionSet()))
  }

  private func parseFragmentDefinition() throws -> FragmentDefinition {
    try expectKeyword(.Fragment)
    let name = try parseFragmentName()
    try expectKeyword(.On)
    let typeCondition = try parseNamedType()
    return FragmentDefinition(
    name: name,
      typeCondition: typeCondition,
      directives: try parseDirectives(),
      selectionSet: try parseSelectionSet()
    )
  }

  private func parseFragmentName() throws -> Name {
    if token.value == Keyword.On.rawValue {
      throw ParserError.UnexpectedToken(token)
    }
    return try parseName()
  }

}

extension Parser {

  private func parseValueLiteral(isConst isConst: Bool) throws -> Value {
    switch token.kind {
    case .BracketL:
      return try parseList(isConst: isConst)
    case .BraceL:
      return try parseObject(isConst: isConst)
    case .Int:
      guard let value = token.value else {
        throw ParserError.UnexpectedToken(token)
      }
      try advance()
      return .IntValue(value)
    case .Float:
      guard let value = token.value else {
        throw ParserError.UnexpectedToken(token)
      }
      try advance()
      return .FloatValue(value)
    case .String:
      guard let value = token.value else {
        throw ParserError.UnexpectedToken(token)
      }
      try advance()
      return .StringValue(value)
    case .Name:
      if let value = token.value where (value == Keyword.BoolFalse.rawValue || value == Keyword.BoolTrue.rawValue) {
        try advance()
        return .BoolValue(value)
      } else if token.value != Keyword.Null.rawValue {
        guard let value = token.value else {
          throw ParserError.UnexpectedToken(token)
        }
        try advance()
        return .Enum(value)
      }
    case .Dollar:
      if !isConst {
        return .VariableValue(try parseVariable())
      }
    default:
      throw ParserError.UnexpectedToken(token)
    }
    throw ParserError.UnexpectedToken(token)
  }

  private func parseList(isConst isConst: Bool) throws -> Value {
    return .List(try any(openKind: .BracketL, parseFn: { return try self.parseValueLiteral(isConst: isConst) }, closeKind: .BracketR))
  }

  private func parseObject(isConst isConst: Bool) throws -> Value {
    try expect(.BraceL)
    var fields: [ObjectField] = []
    while try !skip(.BraceR) {
      fields.append(try parseObjectField(isConst: isConst))
    }
    return .Object(fields)
  }

  private func parseObjectField(isConst isConst: Bool) throws -> ObjectField {
    let name = try parseName()
    try expect(.Colon)
    let value = try parseValueLiteral(isConst: isConst)
    return ObjectField(name: name, value: value)
  }

}

extension Parser {

  private func parseDirectives() throws -> [Directive] {
    var directives: [Directive] = []
    while peek(.At) {
      directives.append(try parseDirective())
    }
    return directives
  }

  private func parseDirective() throws -> Directive {
    try expect(.At)
    return Directive(name: try parseName(), arguments: try parseArguments())
  }

}

extension Parser {

  private func parseType() throws -> Type {
    let type: Type
    if try skip(.BracketL) {
      let listType = try parseType()
      try expect(.BracketR)
      type = .List(listType)
    } else {
      type = try parseNamedType()
    }
    if try skip(.Bang) {
      return .NonNull(type)
    }
    return type
  }

  private func parseNamedType() throws -> Type {
    return .Named(try parseName())
  }

}

extension Parser {

  private func parseTypeDefinition() throws -> TypeDefinition {
    if !peek(.Name) {
      throw ParserError.UnexpectedToken(token)
    }

    guard let value = token.value, type = Keyword(rawValue: value) else {
      throw ParserError.UnexpectedToken(token)
    }

    switch type {
    case .Type:
      return .Object(try parseObjectTypeDefinition())
    case .Interface:
      return .Interface(try parseInterfaceTypeDefinition())
    case .Union:
      return .Union(try parseUnionTypeDefinition())
    case .Scalar:
      return .Scalar(try parseScalarTypeDefinition())
    case .EnumType:
      return .Enum(try parseEnumTypeDefinition())
    case .Input:
      return .InputObject(try parseInputObjectTypeDefinition())
    default:
      throw ParserError.UnexpectedToken(token)
    }
  }

  private func parseObjectTypeDefinition() throws -> ObjectTypeDefinition {
    try expectKeyword(.Type)
    return ObjectTypeDefinition(
      name: try parseName(),
      interfaces: try parseImplementsInterfaces(),
      fields: try any(openKind: .BraceL, parseFn: parseFieldDefinition, closeKind: .BraceR))
  }

  private func parseImplementsInterfaces() throws -> [Type] {
    if token.value == Keyword.Implements.rawValue {
      try advance()
      var types: [Type] = []
      repeat {
        types.append(try parseNamedType())
      } while !peek(.BraceL)
      return types
    }
    return []
  }

  private func parseFieldDefinition() throws -> FieldDefinition {
    let name = try parseName()
    let arguments = try parseArgumentDefinitions()
    try expect(.Colon)
    let type = try parseType()
    return FieldDefinition(name: name, arguments: arguments, type: type)
  }

  private func parseArgumentDefinitions() throws -> [InputValueDefinition] {
    if peek(.ParenL) {
      return try many(openKind: .ParenL, parseFn: parseInputValueDefinition, closeKind: .ParenR)
    }
    return []
  }

  private func parseInputValueDefinition() throws -> InputValueDefinition {
    let name = try parseName()
    try expect(.Colon)
    let type = try parseType()
    let defaultValue: Value? = try skip(.Equals) ? try parseValueLiteral(isConst: true) : nil
    return InputValueDefinition(name: name, type: type, defaultValue: defaultValue)
  }

  private func parseInterfaceTypeDefinition() throws -> InterfaceTypeDefinition {
    try expectKeyword(.Interface)
    return InterfaceTypeDefinition(
      name: try parseName(),
      fields: try any(openKind: .BraceL, parseFn: parseFieldDefinition, closeKind: .BraceR))
  }

  private func parseUnionTypeDefinition() throws -> UnionTypeDefinition {
    try expectKeyword(.Union)
    let name = try parseName()
    try expect(.Equals)
    let types = try parseUnionMembers()
    return UnionTypeDefinition(name: name, types: types)
  }

  private func parseUnionMembers() throws -> [Type] {
    var members: [Type] = []
    repeat {
      members.append(try parseNamedType())
    } while try skip(.Pipe)
    return members
  }

  private func parseScalarTypeDefinition() throws -> ScalarTypeDefinition {
    try expectKeyword(.Scalar)
    return ScalarTypeDefinition(name: try parseName())
  }

  private func parseEnumTypeDefinition() throws -> EnumTypeDefinition {
    try expectKeyword(.EnumType)
    return EnumTypeDefinition(
      name: try parseName(),
      values: try many(openKind: .BraceL, parseFn: parseEnumValueDefinition, closeKind: .BraceR))
  }

  private func parseEnumValueDefinition() throws -> EnumValueDefinition {
    return EnumValueDefinition(name: try parseName())
  }

  private func parseInputObjectTypeDefinition() throws -> InputObjectTypeDefinition {
    try expectKeyword(.Input)
    return InputObjectTypeDefinition(
      name: try parseName(),
      fields: try any(openKind: .BraceL, parseFn: parseInputValueDefinition, closeKind: .BraceR))
  }

  private func parseTypeExtensionDefinition() throws -> TypeExtensionDefinition {
    try expectKeyword(.Extend)
    return TypeExtensionDefinition(definition: try parseObjectTypeDefinition())
  }

}

extension Parser {

  private func advance() throws {
    token = try lexer.next()
  }

  private func skip(kind: TokenKind) throws -> Bool {
    let match = token.kind == kind
    if match {
      try advance()
    }
    return match
  }

  private func peek(kind: TokenKind) -> Bool {
    return token.kind == kind
  }

  private func expect(kind: TokenKind) throws -> Token {
    let currentToken = token
    if currentToken.kind == kind {
      try advance()
      return currentToken
    }
    throw ParserError.WrongTokenKind(kind, currentToken.kind)
  }

  private func expectKeyword(keyword: Keyword) throws -> Token {
    let currentToken = token
    if token.kind == .Name && token.value == keyword.rawValue {
      try advance()
      return currentToken
    }
    throw ParserError.UnexpectedKeyword(keyword, currentToken)
  }

  private func any<T>(openKind openKind: TokenKind, parseFn: () throws -> T, closeKind: TokenKind) throws -> [T] {
    try expect(openKind)
    var nodes: [T] = []
    while try !skip(closeKind) {
      nodes.append(try parseFn())
    }
    return nodes
  }

  private func many<T>(openKind openKind: TokenKind, parseFn: () throws -> T, closeKind: TokenKind) throws -> [T] {
    try expect(openKind)
    var nodes = [try parseFn()]
    while try !skip(closeKind) {
      nodes.append(try parseFn())
    }
    return nodes
  }

}

extension Parser {

  private func syntaxError(token: Token) throws {
    throw ParserError.UnexpectedToken(token)
  }

}
