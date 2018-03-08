import GrammarModels
import Antlr4
import ObjcParserAntlr

public class TypeParsing {
    public let state: ObjcParserState
    
    public init(state: ObjcParserState) {
        self.state = state
    }
    
    // Helper for mapping Objective-C types from raw strings into a structured types
    public func parseObjcType(_ source: String) -> ObjcType? {
        let parser = ObjcParser(source: StringCodeSource(source: source), state: state)
        return try? parser.parseObjcType()
    }
    
    // Helper for mapping Objective-C types from type declarations into structured
    // types.
    public func parseObjcType(inDeclaration decl: ObjectiveCParser.FieldDeclarationContext) -> ObjcType? {
        guard let specQualifier = decl.specifierQualifierList() else {
            return nil
        }
        guard let baseTypeString = specQualifier.typeSpecifier(0)?.getText() else {
            return nil
        }
        guard let declarator = decl.fieldDeclaratorList()?.fieldDeclarator(0)?.declarator() else {
            return nil
        }
        
        let pointerDecl = declarator.pointer()
        
        var typeName = "\(baseTypeString) \(pointerDecl.map { $0.getText() } ?? "")"
        
        if specQualifier.arcBehaviourSpecifier().count > 0 {
            let arcSpecifiers =
                specQualifier.arcBehaviourSpecifier().map {
                    $0.getText()
            }
            
            typeName = "\(arcSpecifiers.joined(separator: " ")) \(typeName)"
        }
        
        guard let type = parseObjcType(typeName) else {
            return nil
        }
        
        return type
    }
    
    public func parseObjcType(inSpecifierQualifierList specQual: ObjectiveCParser.SpecifierQualifierListContext) -> ObjcType? {
        guard let typeName = VarDeclarationTypeExtractor.extract(from: specQual) else {
            return nil
        }
        
        return parseObjcType(typeName)
    }
    
    public func parseObjcType(inSpecifierQualifierList specifierQualifierList: ObjectiveCParser.SpecifierQualifierListContext,
                              declarator: ObjectiveCParser.DeclaratorContext) -> ObjcType? {
        guard let specifiersString = VarDeclarationTypeExtractor.extract(from: specifierQualifierList) else {
            return nil
        }
        
        let pointer = declarator.pointer()?.accept(VarDeclarationTypeExtractor())
        
        let typeString = "\(specifiersString) \(pointer ?? "")"
        
        guard let type = parseObjcType(typeString) else {
            return nil
        }
        
        // Block type
        if let blockType = manageBlock(baseType: type,
                                       qualifiers: TypeParsing.qualifiers(from: specifierQualifierList),
                                       declarator: declarator) {
            return blockType
        }
        
        return type
    }
    
    public func parseObjcType(inDeclarationSpecifiers declarationSpecifiers: ObjectiveCParser.DeclarationSpecifiersContext) -> ObjcType? {
        guard let specifiersString = VarDeclarationTypeExtractor.extract(from: declarationSpecifiers) else {
            return nil
        }
        
        return parseObjcType(specifiersString)
    }
    
    public func parseObjcType(inDeclarationSpecifiers declarationSpecifiers: ObjectiveCParser.DeclarationSpecifiersContext,
                                     declarator: ObjectiveCParser.DeclaratorContext) -> ObjcType? {
        guard let specifiersString = VarDeclarationTypeExtractor.extract(from: declarationSpecifiers) else {
            return nil
        }
        
        let pointer = declarator.pointer()
        
        let typeString = "\(specifiersString) \(pointer?.getText() ?? "")"
        
        guard let type = parseObjcType(typeString) else {
            return nil
        }
        
        // Block type
        if let blockType = manageBlock(baseType: type,
                                       qualifiers: TypeParsing.qualifiers(from: declarationSpecifiers),
                                       declarator: declarator) {
            return blockType
        }
        
        return type
    }
    
    private func manageBlock(baseType: ObjcType,
                             qualifiers: [ObjectiveCParser.TypeQualifierContext],
                             declarator: ObjectiveCParser.DeclaratorContext) -> ObjcType? {
        var type = baseType
        
        // Block type
        if let directDeclarator = declarator.directDeclarator(),
            let blockIdentifier = directDeclarator.identifier(),
            let blockParameters = directDeclarator.blockParameters() {
            
            let blockParameterTypes = parseObjcTypes(fromBlockParameters: blockParameters)
            
            type = .blockType(name: blockIdentifier.getText(),
                              returnType: type,
                              parameters: blockParameterTypes)
            
            // Verify qualifiers
            if qualifiers.count > 0 {
                let qualifiers = qualifiers.map { $0.getText() }
                type = .specified(specifiers: qualifiers, type)
            }
            // Verify nullability specifiers
            if let nullabillitySpecifier = directDeclarator.nullabilitySpecifier() {
                type = .qualified(type, qualifiers: [nullabillitySpecifier.getText()])
            }
            
            return type
        }
        
        return nil
    }
    
    public func parseObjcTypes(fromBlockParameters blockParameters: ObjectiveCParser.BlockParametersContext) -> [ObjcType] {
        let typeVariableDeclaratorOrNames = blockParameters.typeVariableDeclaratorOrName()
        
        var paramTypes: [ObjcType] = []
        
        for typeVariableDeclaratorOrName in typeVariableDeclaratorOrNames {
            guard let paramType = parseObjcType(fromTypeVariableDeclaratorOrTypeName: typeVariableDeclaratorOrName) else {
                continue
            }
            
            paramTypes.append(paramType)
        }
        
        return paramTypes
    }
    
    public func parseObjcType(fromTypeVariableDeclaratorOrTypeName typeContext: ObjectiveCParser.TypeVariableDeclaratorOrNameContext) -> ObjcType? {
        if let typeName = typeContext.typeName(),
            let type = parseObjcType(fromTypeName: typeName) {
            return type
        } else if let typeVariableDecl = typeContext.typeVariableDeclarator() {
            if typeVariableDecl.declarator()?.directDeclarator()?.blockParameters() != nil {
                return parseObjcType(fromTypeVariableDeclarator: typeVariableDecl)
            }
            
            if let type = parseObjcType(fromTypeVariableDeclarator: typeVariableDecl) {
                return type
            } else {
                return nil
            }
        }
        
        guard let typeString = VarDeclarationTypeExtractor.extract(from: typeContext) else {
            return nil
        }
        
        return parseObjcType(typeString)
    }
    
    public func parseObjcType(fromTypeVariableDeclarator typeVariableDecl: ObjectiveCParser.TypeVariableDeclaratorContext) -> ObjcType? {
        if let blockParameters = typeVariableDecl.declarator()?.directDeclarator()?.blockParameters() {
            guard let declarationSpecifiers = typeVariableDecl.declarationSpecifiers() else {
                return nil
            }
            
            let parameters = parseObjcTypes(fromBlockParameters: blockParameters)
            
            guard let returnTypeName = VarDeclarationTypeExtractor.extract(from: declarationSpecifiers) else { return nil }
            guard let returnType = parseObjcType(returnTypeName) else { return nil }
            
            let identifier = VarDeclarationIdentifierNameExtractor.extract(from: typeVariableDecl)
            
            var type: ObjcType = .blockType(name: identifier ?? "",
                                            returnType: returnType,
                                            parameters: parameters)
            
            if let nullability = typeVariableDecl.declarator()?.directDeclarator()?.nullabilitySpecifier() {
                type = .qualified(type, qualifiers: [nullability.getText()])
            }
            
            return type
        }
        
        guard let typeString = VarDeclarationTypeExtractor.extract(from: typeVariableDecl) else {
            return nil
        }
        guard let type = parseObjcType(typeString) else {
            return nil
        }
        
        return type
    }
    
    public func parseObjcType(fromTypeSpecifier typeSpecifier: ObjectiveCParser.TypeSpecifierContext) -> ObjcType? {
        guard let typeString = VarDeclarationTypeExtractor.extract(from: typeSpecifier) else {
            return nil
        }
        guard let type = parseObjcType(typeString) else {
            return nil
        }
        
        return type
    }
    
    public func parseObjcType(fromBlockType blockType: ObjectiveCParser.BlockTypeContext) -> ObjcType? {
        guard let returnTypeSpecifier = blockType.typeSpecifier(0) else {
            return nil
        }
        guard let returnType = parseObjcType(fromTypeSpecifier: returnTypeSpecifier) else {
            return nil
        }
        
        var parameterTypes: [ObjcType] = []
        
        if let blockParameters = blockType.blockParameters() {
            for param in blockParameters.typeVariableDeclaratorOrName() {
                guard let paramType = parseObjcType(fromTypeVariableDeclaratorOrTypeName: param) else {
                    continue
                }
                
                parameterTypes.append(paramType)
            }
        }
        
        var type = ObjcType.blockType(name: "", returnType: returnType, parameters: parameterTypes)
        
        if let nullability = blockType.nullabilitySpecifier().last {
            type = .qualified(type, qualifiers: [nullability.getText()])
        }
        
        return type
    }
    
    public func parseObjcType(fromTypeName typeName: ObjectiveCParser.TypeNameContext) -> ObjcType? {
        // Block type
        if let blockType = typeName.blockType() {
            return parseObjcType(fromBlockType: blockType)
        }
        
        guard let typeString = VarDeclarationTypeExtractor.extract(from: typeName) else {
            return nil
        }
        guard let type = parseObjcType(typeString) else {
            return nil
        }
        
        return type
    }
}

extension TypeParsing {
    static func qualifiers(from spec: ObjectiveCParser.SpecifierQualifierListContext) -> [ObjectiveCParser.TypeQualifierContext] {
        return spec.typeQualifier()
    }
    
    static func qualifiers(from spec: ObjectiveCParser.DeclarationSpecifiersContext) -> [ObjectiveCParser.TypeQualifierContext] {
        return spec.typeQualifier()
    }
}
