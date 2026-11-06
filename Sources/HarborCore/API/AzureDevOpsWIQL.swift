import Foundation

// MARK: - WIQL Field Names

/// Common Azure DevOps work item field names
public enum WIQLField: String, CaseIterable {
    case id = "System.Id"
    case title = "System.Title"
    case state = "System.State"
    case assignedTo = "System.AssignedTo"
    case createdBy = "System.CreatedBy"
    case workItemType = "System.WorkItemType"
    case createdDate = "System.CreatedDate"
    case changedDate = "System.ChangedDate"
    case priority = "Microsoft.VSTS.Common.Priority"
    case description = "System.Description"
    case areaPath = "System.AreaPath"
    case iterationPath = "System.IterationPath"
    case teamProject = "System.TeamProject"
    case tags = "System.Tags"
    case reason = "System.Reason"
    case resolvedBy = "Microsoft.VSTS.Common.ResolvedBy"
    case activatedBy = "Microsoft.VSTS.Common.ActivatedBy"

    public var escapedName: String {
        "[\(rawValue)]"
    }
}

// MARK: - WIQL Operators

/// Logical operators for combining conditions
public enum WIQLLogicalOperator: String {
    case and = "AND"
    case or = "OR"
}

/// Comparison operators for value comparisons
public enum WIQLComparisonOperator: String {
    case equals = "="
    case notEquals = "<>"
    case greaterThan = ">"
    case lessThan = "<"
    case greaterThanOrEquals = ">="
    case lessThanOrEquals = "<="
    case contains = "CONTAINS"
    case notContains = "NOT CONTAINS"
    case `in` = "IN"
    case notIn = "NOT IN"
    case under = "UNDER"
    case notUnder = "NOT UNDER"
    case wasEver = "WAS EVER"
}

// MARK: - WIQL Value

/// Represents a value in a WIQL query condition
public enum WIQLValue {
    case field(WIQLField)
    case string(String)
    /// A value list for IN / NOT IN: renders ('a', 'b', 'c').
    case list([String])
    case number(Int)
    case double(Double)
    case boolean(Bool)
    case me // @Me special value
    case today // @Today special value
    /// @Today - N: the start of the day N days ago (N <= 0 renders @Today).
    case daysAgo(Int)
    case currentIteration // @CurrentIteration special value
    case currentProject // @Project: the project the query runs in

    public var wiqlRepresentation: String {
        switch self {
        case .field(let field):
            return field.escapedName
        case .string(let value):
            return WIQLValue.escapeString(value)
        case let .list(values):
            return "(" + values.map(WIQLValue.escapeString).joined(separator: ", ") + ")"
        case .number(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .me:
            return "@Me"
        case .today:
            return "@Today"
        case .currentIteration:
            return "@CurrentIteration"
        case let .daysAgo(days):
            return days > 0 ? "@Today - \(days)" : "@Today"
        case .currentProject:
            return "@Project"
        }
    }

    /// WIQL string literals escape only the single quote (doubled). A backslash
    /// is literal: area and iteration paths like 'Project\Team' must stay as-is.
    private static func escapeString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}

// MARK: - WIQL Condition

/// Represents a single condition in a WIQL WHERE clause
public struct WIQLCondition {
    public let leftValue: WIQLValue
    public let op: WIQLComparisonOperator
    public let rightValue: WIQLValue

    public init(leftValue: WIQLValue, op: WIQLComparisonOperator, rightValue: WIQLValue) {
        self.leftValue = leftValue
        self.op = op
        self.rightValue = rightValue
    }

    /// Create a condition comparing a field to a value
    public static func field(_ field: WIQLField, _ op: WIQLComparisonOperator, _ value: WIQLValue) -> WIQLCondition {
        WIQLCondition(leftValue: .field(field), op: op, rightValue: value)
    }

    /// Create a condition comparing two fields
    public static func compareFields(_ leftField: WIQLField, _ op: WIQLComparisonOperator, _ rightField: WIQLField) -> WIQLCondition {
        WIQLCondition(leftValue: .field(leftField), op: op, rightValue: .field(rightField))
    }

    public var wiqlString: String {
        "\(leftValue.wiqlRepresentation) \(op.rawValue) \(rightValue.wiqlRepresentation)"
    }
}

// MARK: - WIQL Condition Group

/// A group of conditions that can be combined with logical operators
public struct WIQLConditionGroup {
    public var conditions: [WIQLCondition]
    public var logicalOperator: WIQLLogicalOperator

    public init(conditions: [WIQLCondition] = [], logicalOperator: WIQLLogicalOperator = .and) {
        self.conditions = conditions
        self.logicalOperator = logicalOperator
    }

    /// Add a condition to the group
    public mutating func add(_ condition: WIQLCondition) {
        conditions.append(condition)
    }

    /// This group, then AND the condition: `(group) AND condition` when the group is an OR.
    public func and(_ condition: WIQLCondition) -> WIQLExpression {
        WIQLExpression(self).combined(.and, condition)
    }

    /// This group, then OR the condition: `(group) OR condition` when the group is an AND.
    public func or(_ condition: WIQLCondition) -> WIQLExpression {
        WIQLExpression(self).combined(.or, condition)
    }

    public var wiqlString: String {
        if conditions.isEmpty {
            return ""
        }

        if conditions.count == 1 {
            return conditions[0].wiqlString
        }

        let operatorString = " \(logicalOperator.rawValue) "
        let conditionStrings = conditions.map { $0.wiqlString }
        return conditionStrings.joined(separator: operatorString)
    }
}

// MARK: - WIQL Expression

/// A WHERE expression. `and` / `or` combine everything so far with the new
/// condition, left to right: `where(A).and(B).or(C)` is `(A AND B) OR C`.
/// Mixed operators always render with explicit parentheses; WIQL's own
/// precedence never decides the meaning.
public indirect enum WIQLExpression {
    case condition(WIQLCondition)
    case group(WIQLLogicalOperator, [WIQLExpression])

    init(_ group: WIQLConditionGroup) {
        self = group.conditions.count == 1
            ? .condition(group.conditions[0])
            : .group(group.logicalOperator, group.conditions.map { .condition($0) })
    }

    public func combined(_ op: WIQLLogicalOperator, _ condition: WIQLCondition) -> WIQLExpression {
        if case let .group(existing, items) = self, existing == op || items.count < 2 {
            return .group(op, items + [.condition(condition)])
        }
        return .group(op, [self, .condition(condition)])
    }

    public var wiqlString: String {
        switch self {
        case let .condition(condition):
            return condition.wiqlString
        case let .group(op, items):
            return items.map { item in
                if case let .group(_, nested) = item, nested.count > 1 { return "(\(item.wiqlString))" }
                return item.wiqlString
            }.joined(separator: " \(op.rawValue) ")
        }
    }
}

// MARK: - WIQL Order Clause

/// Represents an ORDER BY clause
public struct WIQLOrderByClause {
    public var fields: [(field: WIQLField, ascending: Bool)]

    public init(fields: [(field: WIQLField, ascending: Bool)] = []) {
        self.fields = fields
    }

    /// Add an ordering field (default ascending)
    public func orderBy(_ field: WIQLField, ascending: Bool = false) -> WIQLOrderByClause {
        var result = self
        result.fields.append((field, ascending))
        return result
    }

    public var wiqlString: String {
        guard !fields.isEmpty else { return "" }

        let fieldStrings = fields.map { field, ascending in
            let direction = ascending ? "ASC" : "DESC"
            return "\(field.escapedName) \(direction)"
        }

        return "ORDER BY \(fieldStrings.joined(separator: ", "))"
    }
}

// MARK: - WIQL Query Builder

/// A type-safe builder for constructing WIQL queries with a fluent API
public final class WIQLQueryBuilder {
    private var selectedFields: [WIQLField] = []
    private var expression: WIQLExpression?
    private var orderByClause: WIQLOrderByClause?
    private var isDeleted = false

    // MARK: - Initialization

    /// Create a new empty query builder
    public init() {}

    // MARK: - Select

    /// Specify fields to select in the query
    public func select(_ fields: WIQLField...) -> WIQLQueryBuilder {
        let builder = copy()
        builder.selectedFields = fields
        return builder
    }

    /// Select all default fields
    public func selectAll() -> WIQLQueryBuilder {
        select(.id, .title, .state, .assignedTo, .changedDate)
    }

    // MARK: - Where

    /// Start or modify the WHERE clause with a condition
    public func `where`(_ condition: WIQLCondition) -> WIQLQueryBuilder {
        // A second where() narrows the query: AND.
        self.and(condition)
    }

    /// Everything so far AND the condition.
    public func and(_ condition: WIQLCondition) -> WIQLQueryBuilder {
        self.combined(.and, condition)
    }

    /// Everything so far OR the condition: `where(A).and(B).or(C)` is `(A AND B) OR C`.
    public func or(_ condition: WIQLCondition) -> WIQLQueryBuilder {
        self.combined(.or, condition)
    }

    private func combined(_ op: WIQLLogicalOperator, _ condition: WIQLCondition) -> WIQLQueryBuilder {
        let builder = copy()
        // On an empty query this is the first condition (it used to be dropped).
        builder.expression = builder.expression.map { $0.combined(op, condition) } ?? .condition(condition)
        return builder
    }

    // MARK: - Order By

    /// Add ORDER BY clause
    public func orderBy(_ field: WIQLField, ascending: Bool = false) -> WIQLQueryBuilder {
        let builder = copy()
        if builder.orderByClause == nil {
            builder.orderByClause = WIQLOrderByClause()
        }
        builder.orderByClause = builder.orderByClause?.orderBy(field, ascending: ascending)
        return builder
    }

    // MARK: - Build

    /// Build the WIQL query string
    public func build() -> String {
        var query = "SELECT "

        if selectedFields.isEmpty {
            query += "[System.Id], [System.Title], [System.State], [System.AssignedTo], [System.ChangedDate]"
        } else {
            query += selectedFields.map { $0.escapedName }.joined(separator: ", ")
        }

        query += "\nFROM WorkItems"

        if let expression {
            query += "\nWHERE \(expression.wiqlString)"
        }

        if let orderBy = orderByClause, !orderBy.fields.isEmpty {
            query += "\n\(orderBy.wiqlString)"
        }

        return query
    }

    /// Build the query and encode for URL (for Azure DevOps API)
    public func buildEncoded() -> String {
        build().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? build()
    }

    // MARK: - Private

    private func copy() -> WIQLQueryBuilder {
        let builder = WIQLQueryBuilder()
        builder.selectedFields = selectedFields
        builder.expression = expression
        builder.orderByClause = orderByClause
        return builder
    }
}

// MARK: - WIQL Query Templates

/// Pre-built query templates for common Azure DevOps queries
public struct WIQLTemplates {

    /// Create a query for bugs assigned to the current user
    public static func myBugs(state: String? = nil) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.workItemType, .equals, .string("Bug")))
            .and(.field(.assignedTo, .equals, .me))

        if let state = state {
            query = query.and(.field(.state, .equals, .string(state)))
        }

        return query.orderBy(.changedDate, ascending: false)
    }

    /// Create a query for work items assigned to the current user
    public static func myIssues(types: [String]? = nil) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.assignedTo, .equals, .me))

        if let types = types, !types.isEmpty {
            let typeCondition = WIQLCondition(
                leftValue: .field(.workItemType),
                op: .in,
                rightValue: .list(types)
            )
            query = query.and(typeCondition)
        }

        return query.orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items updated in the last N days
    public static func recentlyUpdated(days: Int = 7) -> WIQLQueryBuilder {
        let condition = WIQLCondition(
            leftValue: .field(.changedDate),
            op: .greaterThanOrEquals,
            rightValue: .daysAgo(days)
        )

        return WIQLQueryBuilder()
            .where(condition)
            .orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items updated in the last N days, assigned to current user
    public static func myRecentlyUpdated(days: Int = 7) -> WIQLQueryBuilder {
        let dateCondition = WIQLCondition(
            leftValue: .field(.changedDate),
            op: .greaterThanOrEquals,
            rightValue: .daysAgo(days)
        )

        let userCondition = WIQLCondition(
            leftValue: .field(.assignedTo),
            op: .equals,
            rightValue: .me
        )

        return WIQLQueryBuilder()
            .where(dateCondition)
            .and(userCondition)
            .orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items in a specific project
    public static func byProject(_ project: String) -> WIQLQueryBuilder {
        let condition = WIQLCondition(
            leftValue: .field(.teamProject),
            op: .equals,
            rightValue: .string(project)
        )

        return WIQLQueryBuilder()
            .where(condition)
            .orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items in a specific state
    public static func byState(_ state: String, project: String? = nil) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.state, .equals, .string(state)))

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.and(projectCondition)
        }

        return query.orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items of a specific type
    public static func byType(_ type: String, project: String? = nil) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.workItemType, .equals, .string(type)))

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.and(projectCondition)
        }

        return query.orderBy(.changedDate, ascending: false)
    }

    /// Create a query for all open work items
    public static func allOpen(project: String? = nil) -> WIQLQueryBuilder {
        let openStates = ["Active", "New", "In Progress", "In Review", "Resolved"]

        var query = WIQLQueryBuilder()

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.where(projectCondition)
        }

        // Add condition for open states
        let stateCondition = WIQLCondition(
            leftValue: .field(.state),
            op: .in,
            rightValue: .list(openStates)
        )
        query = query.where(stateCondition)

        return query.orderBy(.priority).orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items created by the current user
    public static func myCreatedItems(days: Int? = nil) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.createdBy, .equals, .me))

        if let days = days {
            let dateCondition = WIQLCondition(
                leftValue: .field(.createdDate),
                op: .greaterThanOrEquals,
                rightValue: .daysAgo(days)
            )
            query = query.and(dateCondition)
        }

        return query.orderBy(.createdDate, ascending: false)
    }

    /// Create a query for high priority items
    public static func highPriority(project: String? = nil, maxPriority: Int = 2) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.priority, .lessThanOrEquals, .number(maxPriority)))

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.and(projectCondition)
        }

        return query.orderBy(.priority).orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items by iteration
    public static func byIteration(_ iterationPath: String, project: String? = nil) -> WIQLQueryBuilder {
        var query = WIQLQueryBuilder()
            .where(.field(.iterationPath, .equals, .string(iterationPath)))

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.and(projectCondition)
        }

        return query.orderBy(.priority)
    }

    /// Create a query for items in an area path
    public static func byAreaPath(_ areaPath: String, includeSubAreas: Bool = true) -> WIQLQueryBuilder {
        let condition: WIQLCondition
        if includeSubAreas {
            condition = WIQLCondition(
                leftValue: .field(.areaPath),
                op: .under,
                rightValue: .string(areaPath)
            )
        } else {
            condition = WIQLCondition(
                leftValue: .field(.areaPath),
                op: .equals,
                rightValue: .string(areaPath)
            )
        }

        return WIQLQueryBuilder()
            .where(condition)
            .orderBy(.changedDate, ascending: false)
    }

    /// Create a query for completed items
    public static func completed(project: String? = nil, completedAfter: Date? = nil) -> WIQLQueryBuilder {
        let closedStates = ["Closed", "Done", "Completed"]

        let stateCondition = WIQLCondition(
            leftValue: .field(.state),
            op: .in,
            rightValue: .list(closedStates)
        )

        var query = WIQLQueryBuilder().where(stateCondition)

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.and(projectCondition)
        }

        return query.orderBy(.changedDate, ascending: false)
    }

    /// Create a query for items with specific tags
    public static func byTags(_ tags: [String], matchAll: Bool = false) -> WIQLQueryBuilder {
        let query = WIQLQueryBuilder()

        if matchAll {
            // All tags must be present
            return tags.reduce(query) { builder, tag in
                builder.and(.field(.tags, .contains, .string(tag)))
            }
        } else {
            // Any of the tags. System.Tags is a ';'-separated text field, so IN
            // never matches a multi-tag item; OR the CONTAINS checks instead.
            guard let first = tags.first else { return query }
            return tags.dropFirst().reduce(query.where(.field(.tags, .contains, .string(first)))) { builder, tag in
                builder.or(.field(.tags, .contains, .string(tag)))
            }
        }
    }

    /// Create a query for items linked to a specific work item
    public static func linkedItems(workItemId: Int, linkTypes: [String]? = nil) -> WIQLQueryBuilder {
        let query = WIQLQueryBuilder()
            .select(.id, .title, .workItemType, .state)
            .where(.field(.id, .equals, .number(workItemId)))

        return query
    }

    /// Create a query for stale items (not updated in N days)
    public static func staleItems(days: Int = 30, project: String? = nil) -> WIQLQueryBuilder {
        let condition = WIQLCondition(
            leftValue: .field(.changedDate),
            op: .lessThan,
            rightValue: .daysAgo(days)
        )

        var query = WIQLQueryBuilder().where(condition)

        if let project = project {
            let projectCondition = WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            )
            query = query.and(projectCondition)
        }

        return query.orderBy(.changedDate)
    }
}

// MARK: - WIQL Field Extensions

extension WIQLField {
    /// All common fields for selection
    public static var all: [WIQLField] {
        [
            .id, .title, .state, .assignedTo, .createdBy,
            .workItemType, .createdDate, .changedDate, .priority,
            .areaPath, .iterationPath, .tags, .reason
        ]
    }
}

// MARK: - WIQLValue to Condition Extensions

extension WIQLValue {
    /// Shortcut for creating an equality condition
    public static func == (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .equals, rhs)
    }

    /// Shortcut for creating an inequality condition
    public static func != (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .notEquals, rhs)
    }

    /// Shortcut for creating a greater-than condition
    public static func > (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .greaterThan, rhs)
    }

    /// Shortcut for creating a less-than condition
    public static func < (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .lessThan, rhs)
    }

    /// Shortcut for creating a greater-than-or-equal condition
    public static func >= (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .greaterThanOrEquals, rhs)
    }

    /// Shortcut for creating a less-than-or-equal condition
    public static func <= (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .lessThanOrEquals, rhs)
    }

    /// Shortcut for creating a contains condition
    public static func ~= (lhs: WIQLField, rhs: WIQLValue) -> WIQLCondition {
        WIQLCondition.field(lhs, .contains, rhs)
    }
}

// MARK: - Query Examples

extension WIQLQueryBuilder {
    /// Example: Query for all active bugs
    public static func exampleActiveBugs() -> String {
        WIQLQueryBuilder()
            .select(.id, .title, .state, .assignedTo, .priority)
            .where(.field(.workItemType, .equals, .string("Bug")))
            .and(.field(.state, .equals, .string("Active")))
            .orderBy(.priority)
            .build()
    }

    /// Example: Query for items assigned to me that were updated recently
    public static func exampleMyRecentItems() -> String {
        WIQLTemplates.myRecentlyUpdated(days: 7).build()
    }

    /// Example: Query for all work items in a project by state
    public static func exampleProjectItemsByState(project: String) -> String {
        WIQLQueryBuilder()
            .select(.id, .title, .state, .workItemType)
            .where(WIQLCondition(
                leftValue: .field(.teamProject),
                op: .equals,
                rightValue: .string(project)
            ))
            .orderBy(.state)
            .build()
    }
}
