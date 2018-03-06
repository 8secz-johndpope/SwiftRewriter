import SwiftAST

/// A function signature transformer allows changing the shape of a postfix function
/// call into equivalent calls with function name and parameters moved around,
/// labeled and transformed properly.
///
/// e.g:
///
/// ```
/// FunctionInvocationTransformer(
///     name: "CGPointMake",
///     swiftName: "CGPoint",
///     firstArgIsInstance: false,
///     arguments: [
///         .labeled("x", .asIs),
///         .labeled("y", .asIs)
///     ])
/// ```
///
/// Would allow matching and converting:
/// ```
/// CGPointMake(<x>, <y>)
/// // becomes
/// CGPoint(x: <x>, y: <y>)
/// ```
///
/// The method also allows taking in two arguments and merging them, as well as
/// moving arguments around:
/// ```
/// FunctionInvocationTransformer(
///     name: "CGPathMoveToPoint",
///     swiftName: "move",
///     firstArgIsInstance: true,
///     arguments: [
///         .labeled("to",
///                  .mergeArguments(arg0: 1, arg1: 2, { x, y in
///                                     Expression.identifier("CGPoint")
///                                     .call([.labeled("x", x), .labeled("y", y)])
///                                  }))
///     ])
/// ```
///
/// Would allow detecting and converting:
///
/// ```
/// CGPathMoveToPoint(<path>, <transform>, <x>, <y>)
/// // becomes
/// <path>.move(to: CGPoint(x: <x>, y: <y>))
/// ```
///
/// Note that the `<transform>` parameter from the original call was discarded:
/// it is not neccessary to map all arguments of the original call into the target
/// call.
public final class FunctionInvocationTransformer {
    public let name: String
    public let swiftName: String
    
    /// Strategy to apply to each argument in the call.
    public let arguments: [ArgumentStrategy]
    
    /// The number of arguments this function signature transformer needs, exactly,
    /// in order to be fulfilled.
    public let requiredArgumentCount: Int
    
    /// Whether to convert the first argument of the call into a target instance,
    /// such that the free function call becomes a method call.
    public let firstArgIsInstance: Bool
    
    public init(name: String, swiftName: String, firstArgIsInstance: Bool, arguments: [ArgumentStrategy]) {
        self.name = name
        self.swiftName = swiftName
        self.arguments = arguments
        self.firstArgIsInstance = firstArgIsInstance
        
        let offset = firstArgIsInstance ? 1 : 0
        
        var requiredArgs = arguments.reduce(0) { $0 + $1.argumentConsumeCount } + offset
        
        // Verify max arg count inferred from indexes of arguments
        if let max = arguments.map({ $0.maxArgumentReferenced + offset }).max(), max > requiredArgs {
            requiredArgs = max
        }
        
        requiredArgumentCount = requiredArgs
    }
    
    public func canApply(to postfix: PostfixExpression) -> Bool {
        guard postfix.exp.asIdentifier?.identifier == name else {
            return false
        }
        guard let functionCall = postfix.functionCall else {
            return false
        }
        
        if functionCall.arguments.count != requiredArgumentCount {
            return false
        }
        
        return true
    }
    
    public func attemptApply(on postfix: PostfixExpression) -> Expression? {
        guard postfix.exp.asIdentifier?.identifier == name else {
            return nil
        }
        guard let functionCall = postfix.functionCall else {
            return nil
        }
        guard self.arguments.count > 0, functionCall.arguments.count > 0 else {
            return nil
        }
        
        if functionCall.arguments.count != requiredArgumentCount {
            return nil
        }
        
        var arguments =
            firstArgIsInstance ? Array(functionCall.arguments.dropFirst()) : functionCall.arguments
        
        var result: [FunctionArgument] = []
        
        func handleArg(i: Int, argument: ArgumentStrategy) -> FunctionArgument? {
            switch argument {
            case .asIs:
                return arguments[i]
            case let .mergeArguments(arg0, arg1, merger):
                let arg =
                    FunctionArgument(
                        label: nil,
                        expression: merger(arguments[arg0].expression,
                                           arguments[arg1].expression)
                    )
                
                return arg
            
            case .fromArgIndex(let index):
                return arguments[index]
                
            case let .omitIf(matches: exp, strat):
                guard let result = handleArg(i: i, argument: strat) else {
                    return nil
                }
                
                if result.expression == exp {
                    return nil
                }
                
                return result
            case let .labeled(label, strat):
                if let arg = handleArg(i: i, argument: strat) {
                    return .labeled(label, arg.expression)
                }
                
                return nil
            }
        }
        
        var i = 0
        while i < self.arguments.count {
            let arg = self.arguments[i]
            if let res = handleArg(i: i, argument: arg) {
                result.append(res)
                
                if case .mergeArguments = arg {
                    i += 1
                }
            }
            
            i += 1
        }
        
        // Construct a new postfix operation with the result
        if firstArgIsInstance {
            let exp =
                functionCall
                    .arguments[0]
                    .expression
                    .dot(swiftName)
                    .call(result)
            exp.resolvedType = postfix.resolvedType
            
            return exp
        }
        
        let exp = Expression.identifier(swiftName).call(result)
        exp.resolvedType = postfix.resolvedType
        
        return exp
    }
    
    /// What to do with one or more arguments of a function call
    public enum ArgumentStrategy {
        /// Maps the target argument from the original argument at the nth index
        /// on the original call.
        case fromArgIndex(Int)
        
        /// Maps the current argument as-is, with no changes.
        case asIs
        
        /// Merges two argument indices into a single expression, using a given
        /// transformation closure.
        case mergeArguments(arg0: Int, arg1: Int, (Expression, Expression) -> Expression)
        
        /// Creates a rule that omits the argument in case it matches a given
        /// expression.
        indirect case omitIf(matches: Expression, ArgumentStrategy)
        
        /// Allows adding a label to the result of an argument strategy for the
        /// current parameter.
        indirect case labeled(String, ArgumentStrategy)
        
        /// Gets the number of arguments this argument strategy will consume when
        /// applied.
        var argumentConsumeCount: Int {
            switch self {
            case .asIs, .fromArgIndex:
                return 1
            case .mergeArguments:
                return 2
            case .labeled(_, let inner), .omitIf(_, let inner):
                return inner.argumentConsumeCount
            }
        }
        
        /// Gets the index of the maximal argument index referenced by this argument
        /// rule.
        /// Returns 0, for non-indexed arguments.
        var maxArgumentReferenced: Int {
            switch self {
            case .asIs:
                return 0
            case .fromArgIndex(let index):
                return index
            case let .mergeArguments(index1, index2, _):
                return max(index1, index2)
            case .labeled(_, let inner), .omitIf(_, let inner):
                return inner.maxArgumentReferenced
            }
        }
    }
}
