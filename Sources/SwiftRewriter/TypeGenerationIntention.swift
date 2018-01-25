import GrammarModels

/// An intention to generate a class, struct or enumeration in swift.
public class TypeGenerationIntention: Intention {
    public var typeName: String
    public var scope: Scope
    
    public var properties: [PropertyGenerationIntention] = []
    public var methods: [MethodGenerationIntention] = []
    
    public var source: ASTNode?
    
    public init(typeName: String, scope: Scope = .internal, source: ASTNode? = nil) {
        self.typeName = typeName
        self.scope = scope
        self.source = source
    }
}

/// An intention to generate a property or method on a type
public class MemberGenerationIntention: Intention {
    public var source: ASTNode?
    public var scope: Scope
    
    public init(scope: Scope, source: ASTNode?) {
        self.scope = scope
        self.source = source
    }
}

/// An intention to generate a property, either static/instance, computed/stored
/// for a type definition.
public class PropertyGenerationIntention: MemberGenerationIntention {
    public var typedSource: PropertyDefinition? {
        return source as? PropertyDefinition
    }
    
    public var name: String
    public var type: ObjcType
    
    public init(name: String, type: ObjcType, scope: Scope = .internal, source: ASTNode? = nil) {
        self.name = name
        self.type = type
        super.init(scope: scope, source: source)
    }
}

/// An intention to generate a static/instance function for a type.
public class MethodGenerationIntention: MemberGenerationIntention {
    public var typedSource: MethodDefinition? {
        return source as? MethodDefinition
    }
    
    public var signature: Signature
    
    public var name: String {
        return signature.name
    }
    public var returnType: ObjcType {
        return signature.returnType
    }
    public var parameters: [Parameter] {
        return signature.parameters
    }
    
    public init(name: String, returnType: ObjcType, parameters: [Parameter], scope: Scope = .internal, source: ASTNode? = nil) {
        self.signature = Signature(name: name, returnType: returnType, parameters: parameters)
        super.init(scope: scope, source: source)
    }
    
    public init(signature: Signature, scope: Scope = .internal, source: ASTNode? = nil) {
        self.signature = signature
        super.init(scope: scope, source: source)
    }
    
    public struct Signature {
        public var name: String
        public var returnType: ObjcType
        public var parameters: [Parameter]
    }
    
    public struct Parameter {
        public var selector: String
        public var name: String
        public var type: ObjcType
    }
}

/// Scope for a member
public enum Scope {
    case `private`
    case `fileprivate`
    case `internal`
    case `public`
}