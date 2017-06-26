import Foundation

extension SQL {
    /// A result in a SQL query.
    internal enum ResultType {
        case expression(AnyExpression)
        case wildcard(Table)
        
        var sql: SQL {
            switch self {
            case let .expression(expression):
                return expression.sql
            case let .wildcard(table):
                return SQL("\"\(table.name)\".*")
            }
        }
        
        var tables: Set<Table> {
            switch self {
            case let .expression(expression):
                return expression.tables
            case let .wildcard(table):
                return [table]
            }
        }
    }
}

extension SQL.ResultType: Hashable {
    var hashValue: Int {
        switch self {
        case let .expression(expression):
            return expression.hashValue
        case let .wildcard(table):
            return table.hashValue
        }
    }
    
    static func == (lhs: SQL.ResultType, rhs: SQL.ResultType) -> Bool {
        switch (lhs, rhs) {
        case let (.expression(lhs), .expression(rhs)):
            return lhs == rhs
        case let (.wildcard(lhs), .wildcard(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

extension SQL {
    /// Something that can be used as a result in a SQL query.
    public struct Result: Hashable {
        private let result: ResultType
        
        public static func wildcard(_ table: Table) -> Result {
            return Result(.wildcard(table))
        }
        
        private init(_ result: ResultType) {
            self.result = result
        }
        
        public init<Value>(_ expression: Expression<Value>) {
            self.init(.expression(expression.expression))
        }
        
        var sql: SQL {
            return result.sql
        }
        
        var tables: Set<Table> {
            return result.tables
        }
        
        public var hashValue: Int {
            return result.hashValue
        }
        
        public static func == (lhs: Result, rhs: Result) -> Bool {
            return lhs.result == rhs.result
        }
    }
}

extension SQL {
    /// A SQL query.
    public struct Query {
        public var results: [Result]
        public var predicates: [Expression<Bool>] = []
        public var order: [SortDescriptor] = []
    }
}

extension SQL.Query {
    /// Create a new query by selecting results.
    public static func select(_ results: [SQL.Result]) -> SQL.Query {
        return SQL.Query(results: results)
    }
    
    private init(results: [SQL.Result]) {
        self.results = results
    }
    
    /// Filter the query by adding a predicate that limits results.
    public func `where`(_ predicate: SQL.Expression<Bool>) -> SQL.Query {
        var query = self
        query.predicates.append(predicate)
        return query
    }
    
    /// Sort the results of the query.
    ///
    /// The first sort descriptor in the list will be the primary sort. This
    /// supercedes previous sorting.
    public func sorted(by descriptors: [SQL.SortDescriptor]) -> SQL.Query {
        var query = self
        query.order = descriptors + query.order
        return query
    }
    
    /// Sort the results of the query.
    ///
    /// The first sort descriptor in the list will be the primary sort. This
    /// supercedes previous sorting.
    public func sorted(by descriptors: SQL.SortDescriptor...) -> SQL.Query {
        return sorted(by: descriptors)
    }
    
    /// The tables that are a part of this query.
    private var tables: Set<SQL.Table> {
        let results = self.results.map { $0.tables }
        let predicates = self.predicates.map { $0.tables }
        return (results + predicates).reduce(Set()) { $0.union($1) }
    }
    
    /// The SQL for this query.
    public var sql: SQL {
        let results = self.results.map { $0.sql }.joined(separator: ", ")
        let tables = self.tables.map { "\"\($0.name)\"" }.joined(separator: ", ")
        
        let whereSQL: SQL
        if predicates.isEmpty {
            whereSQL = SQL()
        } else {
            whereSQL = " WHERE " + predicates.map { $0.sql }.joined(separator: " AND ")
        }
        
        let orderBySQL: SQL
        if order.isEmpty {
            orderBySQL = SQL()
        } else {
            orderBySQL = " ORDER BY " + order.map { $0.sql }.joined(separator: ",")
        }
        
        return "SELECT " + results
            + " FROM " + tables
            + whereSQL
            + orderBySQL
    }
    
    /// An expression that tests whether `self` has any results.
    public var exists: SQL.Expression<Bool> {
        return SQL.Expression(.exists(self))
    }
}

extension SQL.Query: Hashable {
    public var hashValue: Int {
        return results.reduce(0) { $0 ^ $1.hashValue }
            + predicates.reduce(0) { $0 ^ $1.hashValue }
    }
    
    public static func == (lhs: SQL.Query, rhs: SQL.Query) -> Bool {
        return lhs.results == rhs.results
            && lhs.predicates == rhs.predicates
            && lhs.order == rhs.order
    }
}