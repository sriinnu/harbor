import Foundation
@testable import HarborCore
import Testing

struct RequestTallyTests {
    @Test
    func template_hidesOwnerRepoAndNumbers() {
        #expect(RequestTally.template(forPath: "/repos/octo/hello/pulls") == "/repos/{owner}/{repo}/pulls")
        #expect(RequestTally.template(forPath: "/repos/octo/hello/pulls/42/reviews") == "/repos/{owner}/{repo}/pulls/{n}/reviews")
        #expect(RequestTally.template(forPath: "/user/repos") == "/user/repos")
        #expect(RequestTally.template(forPath: "/users/octo/events") == "/users/{user}/events")
        #expect(RequestTally.template(forPath: "/orgs/acme/repos") == "/orgs/{org}/repos")
    }

    @Test
    func drain_returnsCountsAndResets() async {
        let tally = RequestTally()
        await tally.recordREST(path: "/repos/a/b/pulls")
        await tally.recordREST(path: "/repos/c/d/pulls")
        await tally.recordGraphQL(label: "RepoBatch")
        let drained = await tally.drain()
        #expect(drained == RequestTally.Snapshot(rest: ["/repos/{owner}/{repo}/pulls": 2], graphQL: ["RepoBatch": 1]))
        #expect(drained.restTotal == 2)
        #expect(drained.graphQLTotal == 1)
        #expect(await tally.snapshot() == RequestTally.Snapshot())
    }

    @Test
    func summary_isExact() {
        let snapshot = RequestTally.Snapshot(rest: ["/user": 1, "/repos/{owner}/{repo}/pulls": 3], graphQL: ["RepoBatch": 4])
        #expect(RequestTally.summary(snapshot) == "requests rest=4 graphql=4 | REST /repos/{owner}/{repo}/pulls=3 /user=1 | GQL RepoBatch=4")
    }
}
