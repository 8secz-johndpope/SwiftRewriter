import XCTest
import SwiftAST
import SwiftRewriterLib
import TestCommons

class IntentionSerializerTests: XCTestCase {
    
    func testIntentionCollectionSerializationRoundtrip() throws {
        
        let intentions = IntentionCollectionBuilder()
            .createFile(named: "A.swift") { file in
                file.addPreprocessorDirective("#preprocessor")
                    .createClass(withName: "Class") { type in
                        type.createConformance(protocolName: "Protocol")
                            .createConstructor()
                            .createInstanceVariable(named: "a", type: .int)
                            .createProperty(named: "b", type: .float)
                            .createMethod("method(_ a: Int, b: Float)") { method in
                                method
                                    .addHistory(tag: "Test", description: "A test history")
                                    .addSemantics(Semantics.collectionMutator)
                                    .addAttributes([KnownAttribute(name: "attr", parameters: nil)])
                                    .addAnnotations(["annotation"])
                                    .setBody([
                                    Statement.expression(
                                        Expression
                                            .identifier("hello")
                                            .dot("world").call()
                                    )
                                ])
                            }
                            .inherit(from: "BaseClass")
                    }
                    .beginNonnulContext()
                    .createProtocol(withName: "Protocol") { type in
                        type.createMethod(named: "test")
                            .createProperty(named: "property", type: .int)
                    }
                    .endNonnullContext()
            }
            .createFile(named: "B.swift") { file in
                file.createStruct(withName: "Struct")
                    .createTypealias(withName: "Typealias", type: .struct("NSInteger"))
                    .createEnum(withName: "Enum", rawValue: .int) { type in
                        type.createCase(name: "first")
                        type.createCase(name: "second",
                                        expression: .identifier("test"))
                    }
                    .createExtension(forClassNamed: "Class", categoryName: "Test") { type in
                        type.createSynthesize(propertyName: "b", variableName: "_b")
                    }
            }
            .createFile(named: "C.swift") { file in
                file.createGlobalFunction(withName: "test")
                    .createGlobalVariable(withName: "globalVar",
                                          type: .int,
                                          initialExpression: Expression.constant(0))
            }
            .build()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let data = try IntentionSerializer.encode(intentions: intentions, encoder: encoder)
        
        XCTAssertNoThrow(
            try IntentionSerializer.decodeIntentions(decoder: JSONDecoder(), data: data)
        )
    }
}
