import Foundation

extension SQL {
    internal enum UnaryOperator: String {
        case not = "NOT"
    }

    internal enum BinaryOperator: String {
        case and = "AND"
        case equal = "=="
        case greaterThan = ">"
        case `is` = "IS"
        case isNot = "IS NOT"
        case lessThan = "<"
        case notEqual = "!="
        case or = "OR"
    }

    internal enum Function: String {
        case max = "MAX"
        case min = "MIN"
    }

    /// A SQL expression.
    internal indirect enum Expression {
        case binary(BinaryOperator, Expression, Expression)
        case column(Column)
        case exists(Query)
        case function(Function, [Expression])
        case inList(Expression, [Value])
        case join(Column, Column, Expression)
        case unary(UnaryOperator, Expression)
        case value(Value)
    }
}

extension SQL.Expression {
    var sql: SQL {
        switch self {
        case let .binary(op, lhs, rhs):
            return (lhs.sql + " " + SQL(op.rawValue) + " " + rhs.sql).parenthesized
        case let .column(column):
            return column.sql
        case let .exists(query):
            return "EXISTS" + query.sql.parenthesized
        case let .function(function, arguments):
            let args = arguments.map { $0.sql }.joined(separator: ",")
            return SQL(function.rawValue) + args.parenthesized
        case let .inList(expr, values):
            let vs = values.map { $0.sql }.joined(separator: ",")
            return "(" + expr.sql + " IN (" + vs + "))"
        case let .join(_, _, expr):
            return expr.sql
        case let .unary(op, expr):
            return (SQL(op.rawValue) + " " + expr.sql).parenthesized
        case let .value(value):
            return value.sql
        }
    }
    
    private var expressions: Set<SQL.Expression> {
        switch self {
        case let .binary(_, lhs, rhs):
            return lhs.expressions
                .union(rhs.expressions)
                .union([self])
        case .column,
             .exists,
             .value:
            return [self]
        case let .function(_, exprs):
            return exprs.reduce([self]) { $0.union($1.expressions) }
        case let .inList(expr, _),
             let .unary(_, expr),
             let .join(_, _, expr):
            return expr.expressions.union([self])
        }
    }
    
    var joins: Set<SQL.Expression> {
        var result: Set<SQL.Expression> = []
        for case let .join(a, b, _) in expressions {
            result.insert(.binary(.equal, .column(a), .column(b)))
        }
        return result
    }
    
    var tables: Set<SQL.Table> {
        var result: Set<SQL.Table> = []
        for expr in expressions {
            switch expr {
            case let .column(column):
                result.insert(column.table)
            case let .join(a, b, _):
                result.insert(a.table)
                result.insert(b.table)
            case .binary, .exists, .function, .inList, .unary, .value:
                break
            }
        }
        return result
    }
}

extension SQL.Expression: Hashable {
    var hashValue: Int {
        switch self {
        case let .binary(op, lhs, rhs):
            return op.hashValue ^ lhs.hashValue ^ rhs.hashValue
        case let .column(column):
            return column.hashValue
        case let .exists(query):
            return query.hashValue
        case let .function(function, arguments):
            return function.hashValue + arguments.reduce(0) { $0 ^ $1.hashValue }
        case let .inList(expr, values):
            return expr.hashValue ^ values.reduce(0) { $0 ^ $1.hashValue }
        case let .join(left, right, expr):
            return left.hashValue ^ right.hashValue ^ expr.hashValue
        case let .unary(op, expr):
            return op.hashValue ^ expr.hashValue
        case let .value(value):
            return value.hashValue
        }
    }
    
    static func == (lhs: SQL.Expression, rhs: SQL.Expression) -> Bool {
        switch (lhs, rhs) {
        case let (.binary(op1, lhs1, rhs1), .binary(op2, lhs2, rhs2)):
            return op1 == op2 && lhs1 == lhs2 && rhs1 == rhs2
        case let (.column(lhs), .column(rhs)):
            return lhs == rhs
        case let (.exists(query1), .exists(query2)):
            return query1 == query2
        case let (.function(function1, args1), .function(function2, args2)):
            return function1 == function2 && args1 == args2
        case let (.inList(expr1, values1), .inList(expr2, values2)):
            return expr1 == expr2 && values1 == values2
        case let (.join(left1, right1, expr1), .join(left2, right2, expr2)):
            return left1 == left2 && right1 == right2 && expr1 == expr2
        case let (.unary(op1, expr1), .unary(op2, expr2)):
            return op1 == op2 && expr1 == expr2
        case let (.value(value1), .value(value2)):
            return value1 == value2
        default:
            return false
        }
    }
}

extension SQL.Expression: InsertValueConvertible {
    internal var insertValue: SQL.Insert.Value {
        return SQL.Insert.Value(self)
    }
}

extension SQL.Expression {
    /// An ascending ordering.
    internal var ascending: SQL.Ordering {
        return SQL.Ordering(self, .ascending)
    }
    
    /// A descending ordering.
    internal var descending: SQL.Ordering {
        return SQL.Ordering(self, .descending)
    }
}

// MARK: - Operators

internal func == (lhs: SQL.Expression, rhs: SQL.Expression) -> SQL.Expression {
    if lhs == .value(.null) {
        return .binary(.is, rhs, lhs)
    } else if rhs == .value(.null) {
        return .binary(.is, lhs, rhs)
    } else {
        return .binary(.equal, lhs, rhs)
    }
}

internal func != (lhs: SQL.Expression, rhs: SQL.Expression) -> SQL.Expression {
    if lhs == .value(.null) {
        return .binary(.isNot, rhs, lhs)
    } else if rhs == .value(.null) {
        return .binary(.isNot, lhs, rhs)
    } else {
        return .binary(.notEqual, lhs, rhs)
    }
}

internal func && (lhs: SQL.Expression, rhs: SQL.Expression) -> SQL.Expression {
    return .binary(.and, lhs, rhs)
}

internal func || (lhs: SQL.Expression, rhs: SQL.Expression) -> SQL.Expression {
    return .binary(.or, lhs, rhs)
}

internal prefix func ! (expression: SQL.Expression) -> SQL.Expression {
    return .unary(.not, expression)
}

internal func < (lhs: SQL.Expression, rhs: SQL.Expression) -> SQL.Expression {
    return .binary(.lessThan, lhs, rhs)
}

internal func > (lhs: SQL.Expression, rhs: SQL.Expression) -> SQL.Expression {
    return .binary(.greaterThan, lhs, rhs)
}

// MARK: - Aggregates

internal func max(_ expressions: [SQL.Expression]) -> SQL.Expression {
    return .function(.max, expressions)
}

internal func max(_ expressions: SQL.Expression...) -> SQL.Expression {
    return max(expressions)
}

internal func min(_ expressions: [SQL.Expression]) -> SQL.Expression {
    return .function(.min, expressions)
}

internal func min(_ expressions: SQL.Expression...) -> SQL.Expression {
    return min(expressions)
}

// MARK: - Collections

extension Collection where Iterator.Element == String {
    /// An expression that tests whether the list contains the value of an
    /// expression.
    internal func contains(_ expression: SQL.Expression) -> SQL.Expression {
        return .inList(expression, map(SQL.Value.text))
    }
}
