import Foundation
@testable import HarborCore
import XCTest

// MARK: - WIQL Value Tests

final class WIQLValueTests: XCTestCase {

    // MARK: - Field Value

    func testFieldValueEscaping() {
        let field = WIQLField.title
        XCTAssertEqual(field.escapedName, "[System.Title]")
    }

    func testFieldValueWIQLRepresentation() {
        let value: WIQLValue = .field(.title)
        XCTAssertEqual(value.wiqlRepresentation, "[System.Title]")
    }

    // MARK: - String Value

    func testStringValueEscaping() {
        let value: WIQLValue = .string("Test")
        XCTAssertEqual(value.wiqlRepresentation, "'Test'")
    }

    func testStringValueEscapingSingleQuote() {
        let value: WIQLValue = .string("Test's")
        XCTAssertEqual(value.wiqlRepresentation, "'Test''s'")
    }

    func testStringValueKeepsBackslashLiteral() {
        // WIQL escapes only quotes; area/iteration paths use single backslashes.
        let value: WIQLValue = .string("path\\to\\file")
        XCTAssertEqual(value.wiqlRepresentation, "'path\\to\\file'")
    }

    // MARK: - Number Value

    func testNumberValue() {
        let value: WIQLValue = .number(42)
        XCTAssertEqual(value.wiqlRepresentation, "42")
    }

    func testNegativeNumberValue() {
        let value: WIQLValue = .number(-10)
        XCTAssertEqual(value.wiqlRepresentation, "-10")
    }

    // MARK: - Double Value

    func testDoubleValue() {
        let value: WIQLValue = .double(3.14)
        XCTAssertEqual(value.wiqlRepresentation, "3.14")
    }

    // MARK: - Boolean Value

    func testBooleanTrueValue() {
        let value: WIQLValue = .boolean(true)
        XCTAssertEqual(value.wiqlRepresentation, "true")
    }

    func testBooleanFalseValue() {
        let value: WIQLValue = .boolean(false)
        XCTAssertEqual(value.wiqlRepresentation, "false")
    }

    // MARK: - Special Values

    func testMeSpecialValue() {
        let value: WIQLValue = .me
        XCTAssertEqual(value.wiqlRepresentation, "@Me")
    }

    func testTodaySpecialValue() {
        let value: WIQLValue = .today
        XCTAssertEqual(value.wiqlRepresentation, "@Today")
    }

    func testCurrentIterationSpecialValue() {
        let value: WIQLValue = .currentIteration
        XCTAssertEqual(value.wiqlRepresentation, "@CurrentIteration")
    }

    func testProjectSpecialValue() {
        let value: WIQLValue = .currentProject
        XCTAssertEqual(value.wiqlRepresentation, "@Project")
    }

    func testDaysAgoValue() {
        XCTAssertEqual(WIQLValue.daysAgo(7).wiqlRepresentation, "@Today - 7")
        XCTAssertEqual(WIQLValue.daysAgo(0).wiqlRepresentation, "@Today")
    }
}

// MARK: - WIQL Condition Tests

final class WIQLConditionTests: XCTestCase {

    func testFieldEqualsStringCondition() {
        let condition = WIQLCondition.field(.state, .equals, .string("Active"))
        XCTAssertEqual(condition.wiqlString, "[System.State] = 'Active'")
    }

    func testFieldContainsStringCondition() {
        let condition = WIQLCondition.field(.title, .contains, .string("bug"))
        XCTAssertEqual(condition.wiqlString, "[System.Title] CONTAINS 'bug'")
    }

    func testFieldNotEqualsCondition() {
        let condition = WIQLCondition.field(.state, .notEquals, .string("Closed"))
        XCTAssertEqual(condition.wiqlString, "[System.State] <> 'Closed'")
    }

    func testFieldGreaterThanCondition() {
        let condition = WIQLCondition.field(.id, .greaterThan, .number(100))
        XCTAssertEqual(condition.wiqlString, "[System.Id] > 100")
    }

    func testFieldLessThanCondition() {
        let condition = WIQLCondition.field(.priority, .lessThan, .number(3))
        XCTAssertEqual(condition.wiqlString, "[Microsoft.VSTS.Common.Priority] < 3")
    }

    func testFieldGreaterThanOrEqualsCondition() {
        let condition = WIQLCondition.field(.priority, .greaterThanOrEquals, .number(1))
        XCTAssertEqual(condition.wiqlString, "[Microsoft.VSTS.Common.Priority] >= 1")
    }

    func testFieldLessThanOrEqualsCondition() {
        let condition = WIQLCondition.field(.priority, .lessThanOrEquals, .number(2))
        XCTAssertEqual(condition.wiqlString, "[Microsoft.VSTS.Common.Priority] <= 2")
    }

    func testFieldInCondition() {
        let condition = WIQLCondition.field(.state, .in, .list(["Active", "New", "In Progress"]))
        XCTAssertEqual(condition.wiqlString, "[System.State] IN ('Active', 'New', 'In Progress')")
    }

    func testFieldNotInCondition() {
        let condition = WIQLCondition.field(.state, .notIn, .list(["Closed", "Done"]))
        XCTAssertEqual(condition.wiqlString, "[System.State] NOT IN ('Closed', 'Done')")
    }

    func testListValuesEscapeQuotes() {
        let condition = WIQLCondition.field(.title, .in, .list(["it's", "plain"]))
        XCTAssertEqual(condition.wiqlString, "[System.Title] IN ('it''s', 'plain')")
    }

    func testFieldUnderCondition() {
        let condition = WIQLCondition.field(.areaPath, .under, .string("Project\\Team"))
        XCTAssertEqual(condition.wiqlString, "[System.AreaPath] UNDER 'Project\\Team'")
    }

    func testCompareFieldsCondition() {
        let condition = WIQLCondition.compareFields(.priority, .lessThanOrEquals, .priority)
        XCTAssertEqual(condition.wiqlString, "[Microsoft.VSTS.Common.Priority] <= [Microsoft.VSTS.Common.Priority]")
    }

    func testFieldWithMeValue() {
        let condition = WIQLCondition.field(.assignedTo, .equals, .me)
        XCTAssertEqual(condition.wiqlString, "[System.AssignedTo] = @Me")
    }

    func testFieldWithTodayValue() {
        let condition = WIQLCondition.field(.changedDate, .greaterThanOrEquals, .today)
        XCTAssertEqual(condition.wiqlString, "[System.ChangedDate] >= @Today")
    }

    func testFieldWithBooleanValue() {
        let condition = WIQLCondition.field(.workItemType, .equals, .boolean(true))
        XCTAssertEqual(condition.wiqlString, "[System.WorkItemType] = true")
    }
}

// MARK: - WIQL Condition Group Tests

final class WIQLConditionGroupTests: XCTestCase {

    func testEmptyConditionGroup() {
        let group = WIQLConditionGroup()
        XCTAssertEqual(group.wiqlString, "")
    }

    func testSingleConditionGroup() {
        var group = WIQLConditionGroup()
        group.add(.field(.state, .equals, .string("Active")))
        XCTAssertEqual(group.wiqlString, "[System.State] = 'Active'")
    }

    func testMultipleConditionsWithAnd() {
        var group = WIQLConditionGroup()
        group.add(.field(.state, .equals, .string("Active")))
        group.add(.field(.assignedTo, .equals, .me))
        XCTAssertEqual(group.wiqlString, "[System.State] = 'Active' AND [System.AssignedTo] = @Me")
    }

    func testMultipleConditionsWithOr() {
        var group = WIQLConditionGroup(conditions: [], logicalOperator: .or)
        group.add(.field(.state, .equals, .string("Active")))
        group.add(.field(.state, .equals, .string("New")))
        XCTAssertEqual(group.wiqlString, "[System.State] = 'Active' OR [System.State] = 'New'")
    }

    func testAndMethod() {
        var group1 = WIQLConditionGroup()
        group1.add(.field(.state, .equals, .string("Active")))
        let combined = group1.and(.field(.assignedTo, .equals, .me))
        XCTAssertEqual(combined.wiqlString, "[System.State] = 'Active' AND [System.AssignedTo] = @Me")
    }

    func testOrMethod() {
        var group1 = WIQLConditionGroup()
        group1.add(.field(.state, .equals, .string("Active")))
        let combined = group1.or(.field(.state, .equals, .string("New")))
        XCTAssertEqual(combined.wiqlString, "[System.State] = 'Active' OR [System.State] = 'New'")
    }

    func testOrOnAnAndGroupKeepsTheAndTogether() {
        var group = WIQLConditionGroup()
        group.add(.field(.state, .equals, .string("Active")))
        group.add(.field(.assignedTo, .equals, .me))
        let combined = group.or(.field(.state, .equals, .string("New")))
        XCTAssertEqual(
            combined.wiqlString,
            "([System.State] = 'Active' AND [System.AssignedTo] = @Me) OR [System.State] = 'New'"
        )
    }
}

// MARK: - WIQL Order By Clause Tests

final class WIQLOrderByClauseTests: XCTestCase {

    func testEmptyOrderByClause() {
        let clause = WIQLOrderByClause()
        XCTAssertEqual(clause.wiqlString, "")
    }

    func testSingleFieldOrderBy() {
        let clause = WIQLOrderByClause().orderBy(.changedDate)
        XCTAssertEqual(clause.wiqlString, "ORDER BY [System.ChangedDate] DESC")
    }

    func testSingleFieldOrderByAscending() {
        let clause = WIQLOrderByClause().orderBy(.changedDate, ascending: true)
        XCTAssertEqual(clause.wiqlString, "ORDER BY [System.ChangedDate] ASC")
    }

    func testMultipleFieldsOrderBy() {
        let clause = WIQLOrderByClause()
            .orderBy(.priority)
            .orderBy(.changedDate)
        XCTAssertEqual(clause.wiqlString, "ORDER BY [Microsoft.VSTS.Common.Priority] DESC, [System.ChangedDate] DESC")
    }

    func testMultipleFieldsOrderByMixed() {
        let clause = WIQLOrderByClause()
            .orderBy(.priority)
            .orderBy(.changedDate, ascending: true)
        XCTAssertEqual(clause.wiqlString, "ORDER BY [Microsoft.VSTS.Common.Priority] DESC, [System.ChangedDate] ASC")
    }
}

// MARK: - WIQL Query Builder Tests

final class WIQLQueryBuilderTests: XCTestCase {

    func testEmptyQuery() {
        let builder = WIQLQueryBuilder()
        let query = builder.build()
        XCTAssertTrue(query.contains("SELECT"))
        XCTAssertTrue(query.contains("FROM WorkItems"))
    }

    func testSelectSingleField() {
        let builder = WIQLQueryBuilder().select(.id)
        let query = builder.build()
        XCTAssertTrue(query.contains("[System.Id]"))
    }

    func testSelectMultipleFields() {
        let builder = WIQLQueryBuilder().select(.id, .title, .state)
        let query = builder.build()
        XCTAssertTrue(query.contains("[System.Id]"))
        XCTAssertTrue(query.contains("[System.Title]"))
        XCTAssertTrue(query.contains("[System.State]"))
    }

    func testSelectAll() {
        let builder = WIQLQueryBuilder().selectAll()
        let query = builder.build()
        XCTAssertTrue(query.contains("[System.Id]"))
        XCTAssertTrue(query.contains("[System.Title]"))
        XCTAssertTrue(query.contains("[System.State]"))
    }

    func testWhereSingleCondition() {
        let builder = WIQLQueryBuilder()
            .where(.field(.state, .equals, .string("Active")))
        let query = builder.build()
        XCTAssertTrue(query.contains("WHERE"))
        XCTAssertTrue(query.contains("[System.State] = 'Active'"))
    }

    func testWhereMultipleConditionsWithAnd() {
        let builder = WIQLQueryBuilder()
            .where(.field(.state, .equals, .string("Active")))
            .and(.field(.assignedTo, .equals, .me))
        let query = builder.build()
        XCTAssertTrue(query.contains("WHERE"))
        XCTAssertTrue(query.contains("AND"))
    }

    func testWhereMultipleConditionsWithOr() {
        let builder = WIQLQueryBuilder()
            .where(.field(.state, .equals, .string("Active")))
            .or(.field(.state, .equals, .string("New")))
        XCTAssertEqual(Self.whereClause(builder), "[System.State] = 'Active' OR [System.State] = 'New'")
    }

    // Used to render "A AND B OR C" by flipping every connector to OR.
    func testAndThenOrGroupsLeftToRight() {
        let builder = WIQLQueryBuilder()
            .where(.field(.state, .equals, .string("Active")))
            .and(.field(.assignedTo, .equals, .me))
            .or(.field(.state, .equals, .string("New")))
        XCTAssertEqual(
            Self.whereClause(builder),
            "([System.State] = 'Active' AND [System.AssignedTo] = @Me) OR [System.State] = 'New'"
        )
    }

    func testOrThenAndGroupsLeftToRight() {
        let builder = WIQLTemplates.byTags(["bug", "p1"])
            .and(.field(.teamProject, .equals, .string("MyProject")))
        XCTAssertEqual(
            Self.whereClause(builder),
            "([System.Tags] CONTAINS 'bug' OR [System.Tags] CONTAINS 'p1') AND [System.TeamProject] = 'MyProject'"
        )
    }

    func testSameOperatorStaysFlat() {
        let builder = WIQLQueryBuilder()
            .where(.field(.state, .equals, .string("A")))
            .or(.field(.state, .equals, .string("B")))
            .or(.field(.state, .equals, .string("C")))
        XCTAssertEqual(
            Self.whereClause(builder),
            "[System.State] = 'A' OR [System.State] = 'B' OR [System.State] = 'C'"
        )
    }

    private static func whereClause(_ builder: WIQLQueryBuilder) -> String? {
        builder.build().components(separatedBy: "\n").first { $0.hasPrefix("WHERE ") }.map { String($0.dropFirst(6)) }
    }

    func testOrderBy() {
        let builder = WIQLQueryBuilder()
            .orderBy(.changedDate)
        let query = builder.build()
        XCTAssertTrue(query.contains("ORDER BY"))
    }

    func testCompleteQuery() {
        let builder = WIQLQueryBuilder()
            .select(.id, .title, .state)
            .where(.field(.state, .equals, .string("Active")))
            .and(.field(.assignedTo, .equals, .me))
            .orderBy(.changedDate)
        let query = builder.build()
        XCTAssertTrue(query.contains("SELECT"))
        XCTAssertTrue(query.contains("FROM WorkItems"))
        XCTAssertTrue(query.contains("WHERE"))
        XCTAssertTrue(query.contains("ORDER BY"))
    }

    func testBuildEncoded() {
        let builder = WIQLQueryBuilder()
            .where(.field(.title, .contains, .string("test query")))
        let encoded = builder.buildEncoded()
        XCTAssertNotNil(encoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))
    }
}

// MARK: - WIQL Templates Tests

final class WIQLTemplatesTests: XCTestCase {

    func testMyBugsTemplate() {
        let query = WIQLTemplates.myBugs()
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.WorkItemType] = 'Bug'"))
        XCTAssertTrue(wiql.contains("[System.AssignedTo] = @Me"))
        XCTAssertTrue(wiql.contains("ORDER BY"))
    }

    func testMyBugsWithStateTemplate() {
        let query = WIQLTemplates.myBugs(state: "Active")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.WorkItemType] = 'Bug'"))
        XCTAssertTrue(wiql.contains("[System.AssignedTo] = @Me"))
        XCTAssertTrue(wiql.contains("[System.State] = 'Active'"))
    }

    func testMyIssuesTemplate() {
        let query = WIQLTemplates.myIssues()
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.AssignedTo] = @Me"))
    }

    func testMyIssuesWithTypesTemplate() {
        let query = WIQLTemplates.myIssues(types: ["Bug", "Task"])
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.AssignedTo] = @Me"))
        XCTAssertTrue(wiql.contains("IN"))
    }

    func testRecentlyUpdatedTemplate() {
        let query = WIQLTemplates.recentlyUpdated(days: 7)
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.ChangedDate] >= @Today - 7"))
        XCTAssertTrue(wiql.contains("ORDER BY"))
    }

    func testMyRecentlyUpdatedTemplate() {
        let query = WIQLTemplates.myRecentlyUpdated(days: 3)
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.ChangedDate] >= @Today - 3"))
        XCTAssertTrue(wiql.contains("[System.AssignedTo] = @Me"))
    }

    func testByProjectTemplate() {
        let query = WIQLTemplates.byProject("MyProject")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.TeamProject] = 'MyProject'"))
        XCTAssertFalse(wiql.contains("@Project"))
        XCTAssertTrue(wiql.contains("[System.Id]"))
    }

    func testByStateTemplate() {
        let query = WIQLTemplates.byState("Closed")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.State] = 'Closed'"))
    }

    func testByStateWithProjectTemplate() {
        let query = WIQLTemplates.byState("Closed", project: "MyProject")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.State] = 'Closed'"))
        XCTAssertTrue(wiql.contains("[System.TeamProject] = 'MyProject'"))
        XCTAssertFalse(wiql.contains("@Project"))
    }

    func testByTypeTemplate() {
        let query = WIQLTemplates.byType("Bug")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.WorkItemType] = 'Bug'"))
    }

    func testAllOpenTemplate() {
        let query = WIQLTemplates.allOpen()
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("IN"))
        XCTAssertTrue(wiql.contains("Active") || wiql.contains("New"))
    }

    func testAllOpenWithProjectTemplate() {
        let query = WIQLTemplates.allOpen(project: "MyProject")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.TeamProject] = 'MyProject'"))
        XCTAssertFalse(wiql.contains("@Project"))
        XCTAssertTrue(wiql.contains("IN"))
    }

    func testMyCreatedItemsTemplate() {
        let query = WIQLTemplates.myCreatedItems()
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.CreatedBy] = @Me"))
    }

    func testMyCreatedItemsWithDaysTemplate() {
        let query = WIQLTemplates.myCreatedItems(days: 30)
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.CreatedBy] = @Me"))
        XCTAssertTrue(wiql.contains("[System.CreatedDate] >= @Today - 30"))
    }

    func testHighPriorityTemplate() {
        let query = WIQLTemplates.highPriority()
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[Microsoft.VSTS.Common.Priority] <= 2"))
    }

    func testHighPriorityWithProjectTemplate() {
        let query = WIQLTemplates.highPriority(project: "MyProject")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[Microsoft.VSTS.Common.Priority] <= 2"))
        XCTAssertTrue(wiql.contains("[System.TeamProject] = 'MyProject'"))
        XCTAssertFalse(wiql.contains("@Project"))
    }

    func testByIterationTemplate() {
        let query = WIQLTemplates.byIteration("Sprint 1")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.IterationPath] = 'Sprint 1'"))
    }

    func testByIterationWithProjectTemplate() {
        let query = WIQLTemplates.byIteration("Sprint 1", project: "MyProject")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.IterationPath] = 'Sprint 1'"))
        XCTAssertTrue(wiql.contains("[System.TeamProject] = 'MyProject'"))
        XCTAssertFalse(wiql.contains("@Project"))
    }

    func testByAreaPathTemplate() {
        let query = WIQLTemplates.byAreaPath("Project\\Team")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.AreaPath] UNDER 'Project\\Team'"))
    }

    func testByAreaPathNoSubAreasTemplate() {
        let query = WIQLTemplates.byAreaPath("Project\\Team", includeSubAreas: false)
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.AreaPath] = 'Project\\Team'"))
    }

    func testCompletedTemplate() {
        let query = WIQLTemplates.completed()
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.State] IN ('Closed', 'Done', 'Completed')"))
    }

    func testByTagsTemplate() {
        let query = WIQLTemplates.byTags(["bug", "urgent"])
        let wiql = query.build()
        // Tags is a ';'-separated text field: any-of is an OR of CONTAINS, never IN.
        XCTAssertTrue(wiql.contains("[System.Tags] CONTAINS 'bug' OR [System.Tags] CONTAINS 'urgent'"))
    }

    func testByTagsMatchAllTemplate() {
        let query = WIQLTemplates.byTags(["bug", "urgent"], matchAll: true)
        let wiql = query.build()
        // The first and() on an empty query used to be dropped, leaving no WHERE at all.
        XCTAssertTrue(wiql.contains("[System.Tags] CONTAINS 'bug' AND [System.Tags] CONTAINS 'urgent'"))
    }

    func testLinkedItemsTemplate() {
        let query = WIQLTemplates.linkedItems(workItemId: 123)
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.Id] = 123"))
    }

    func testStaleItemsTemplate() {
        let query = WIQLTemplates.staleItems(days: 30)
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.ChangedDate] < @Today - 30"))
    }

    func testStaleItemsWithProjectTemplate() {
        let query = WIQLTemplates.staleItems(days: 30, project: "MyProject")
        let wiql = query.build()
        XCTAssertTrue(wiql.contains("[System.ChangedDate] < @Today - 30"))
        XCTAssertTrue(wiql.contains("[System.TeamProject] = 'MyProject'"))
        XCTAssertFalse(wiql.contains("@Project"))
    }
}

// MARK: - WIQL Field Tests

final class WIQLFieldTests: XCTestCase {

    func testAllFieldsContainsExpectedFields() {
        let allFields = WIQLField.all
        XCTAssertTrue(allFields.contains(.id))
        XCTAssertTrue(allFields.contains(.title))
        XCTAssertTrue(allFields.contains(.state))
        XCTAssertTrue(allFields.contains(.assignedTo))
        XCTAssertTrue(allFields.contains(.workItemType))
        XCTAssertTrue(allFields.contains(.priority))
    }

    func testFieldRawValues() {
        XCTAssertEqual(WIQLField.id.rawValue, "System.Id")
        XCTAssertEqual(WIQLField.title.rawValue, "System.Title")
        XCTAssertEqual(WIQLField.state.rawValue, "System.State")
        XCTAssertEqual(WIQLField.priority.rawValue, "Microsoft.VSTS.Common.Priority")
    }
}

// MARK: - WIQL Value Extension Tests

final class WIQLValueExtensionTests: XCTestCase {

    func testStringValue() {
        let value = WIQLValue.string("test")
        XCTAssertEqual(value.wiqlRepresentation, "'test'")
    }

    func testNumberValue() {
        let value = WIQLValue.number(42)
        XCTAssertEqual(value.wiqlRepresentation, "42")
    }
}
