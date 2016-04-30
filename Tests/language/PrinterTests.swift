import Foundation
import XCTest
@testable import GraphQL

class PrinterTests: XCTestCase {

  func testPrintsMinimalAst() {
    let ast = Field(alias: nil, name: Name(value: "foo"), arguments: [], directives: [], selectionSet: SelectionSet(selections: []))

    XCTAssertEqual(ast.prettyPrint(), "foo")
  }

  func testCorrectlyPrintsNonQueryOperationsWithoutName() {
    let ast = try! Parser(source: "query { id, name }").parse()

    let expected = "{\n" +
      "  id\n" +
      "  name\n" +
      "}\n"

    XCTAssertEqual(ast.prettyPrint(), expected)
  }

  func testCorrectlyPrintsMutationsWithName() {
    let ast = try! Parser(source: "mutation { id, name }").parse()

    let expected = "mutation {\n" +
      "  id\n" +
      "  name\n" +
      "}\n"

    XCTAssertEqual(ast.prettyPrint(), expected)
  }

  func testCorrectlyPrintsQueryWithArgumentAndDirective() {
    let ast = try! Parser(source: "query ($foo: TestType) @testDirective { id, name }").parse()

    let expected = "query ($foo: TestType) @testDirective {\n" +
      "  id\n" +
      "  name\n" +
      "}\n"

    XCTAssertEqual(ast.prettyPrint(), expected)
  }

  func testCorrectlyPrintsMutationWithArgumentAndDirective() {
    let ast = try! Parser(source: "mutation ($foo: TestType) @testDirective { id, name }").parse()

    let expected = "mutation ($foo: TestType) @testDirective {\n" +
      "  id\n" +
      "  name\n" +
      "}\n"

    XCTAssertEqual(ast.prettyPrint(), expected)
  }

  func testPrintsKitchenSink() {
    let ast = try! Parser(source: graphQlQuery("kitchen_sink")).parse()

    let expectedKitchenSink = "query queryName($foo: ComplexType, $site: Site = MOBILE) {\n" +
      "  whoever123is:  node (id: [123, 456]) {\n" +
      "    id\n" +
      "    ... on User @defer {\n" +
      "      field2 {\n" +
      "        id\n" +
      "        alias:  field1 (first: 10, after: $foo) @include(if: $foo) {\n" +
      "          id\n" +
      "          ...frag\n" +
      "        }\n" +
      "      }\n" +
      "    }\n" +
      "    ... @skip(unless: $foo) {\n" +
      "      id\n" +
      "    }\n" +
      "    ... {\n" +
      "      id\n" +
      "    }\n" +
      "  }\n" +
      "}\n" +
      "\n" +
      "mutation likeStory {\n" +
      "  like (story: 123) @defer {\n" +
      "    story {\n" +
      "      id\n" +
      "    }\n" +
      "  }\n" +
      "}\n" +
      "\n" +
      "subscription StoryLikeSubscription($input: StoryLikeSubscribeInput) {\n" +
      "  storyLikeSubscribe (input: $input) {\n" +
      "    story {\n" +
      "      likers {\n" +
      "        count\n" +
      "      }\n" +
      "      likeSentence {\n" +
      "        text\n" +
      "      }\n" +
      "    }\n" +
      "  }\n" +
      "}\n" +
      "\n" +
      "fragment frag on Friend {\n" +
      "  foo (size: $size, bar: $b, obj: {key: \"value\"})\n" +
      "}\n" +
      "\n" +
      "{\n" +
      "  unnamed (truthy: true, falsey: false)\n" +
      "  query\n" +
      "}\n"

    XCTAssertEqual(ast.prettyPrint(), expectedKitchenSink)
  }

}
