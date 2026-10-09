import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct TickTickClientTests {
    private func makeClient(_ transport: StubTodoTransport) -> TickTickClient {
        TickTickClient(token: TickTickFixtures.token, transport: transport)
    }

    private func response(status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://api.ticktick.com/open/v1/project"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
    }

    // MARK: Requests

    @Test func listingProjectsSendsTheTokenToTheOpenAPI() async throws {
        let transport = StubTodoTransport { _, _ in
            .json(TickTickFixtures.list([TickTickFixtures.project(id: "p1", name: "Work")]))
        }

        let projects = try await makeClient(transport).projects()

        let request = try #require(transport.requests.first)
        #expect(request.route == "GET /open/v1/project")
        #expect(request.url?.host == "api.ticktick.com")
        #expect(request.url?.scheme == "https")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(TickTickFixtures.token)")
        #expect(request.httpBody == nil)
        #expect(projects == [TickTickProject(id: "p1", name: "Work", kind: "TASK")])
    }

    @Test func theInboxIsReadThroughItsOwnPath() async throws {
        let transport = StubTodoTransport { _, _ in
            .json(TickTickFixtures.projectData(tasks: [TickTickFixtures.task(id: "a", title: "Buy milk")]))
        }

        let data = try await makeClient(transport).projectData(id: TickTickClient.inboxID)

        #expect(transport.requests.map(\.route) == ["GET /open/v1/project/inbox/data"])
        #expect(data.project == nil)
        #expect(data.tasks.map(\.id) == ["a"])
        #expect(data.tasks.first?.projectID == TickTickFixtures.inboxRealID)
    }

    @Test func aNewTaskNamesItsListOnlyWhenOneIsGiven() async throws {
        let transport = StubTodoTransport { _, _ in .json(TickTickFixtures.task(id: "n", title: "Call mom")) }
        let client = makeClient(transport)

        let inList = try await client.createTask(title: "Call mom", projectID: "p1")
        _ = try await client.createTask(title: "Call mom", projectID: nil)

        #expect(inList?.id == "n")
        #expect(transport.requests.map(\.route) == ["POST /open/v1/task", "POST /open/v1/task"])
        #expect(transport.requests[0].jsonBody as? [String: String] == ["title": "Call mom", "projectId": "p1"])
        #expect(transport.requests[1].jsonBody as? [String: String] == ["title": "Call mom"])
        #expect(transport.requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func aTaskThatWasTakenButAnsweredOddlyIsNotAFailure() async throws {
        let transport = StubTodoTransport { _, _ in StubTodoResponse(status: 200, body: "") }

        let created = try await makeClient(transport).createTask(title: "Call mom", projectID: nil)

        #expect(created == nil)
    }

    @Test func completingATaskNamesItsListAndSendsNoBody() async throws {
        let transport = StubTodoTransport { _, _ in StubTodoResponse(status: 200, body: "") }

        try await makeClient(transport).completeTask(id: "t1", projectID: "p1")

        let request = try #require(transport.requests.first)
        #expect(request.route == "POST /open/v1/project/p1/task/t1/complete")
        #expect(request.httpBody == nil)
    }

    @Test func savingNotesSendsTheWholeTaskBackWithOneFieldChanged() async throws {
        let transport = StubTodoTransport { request, _ in
            request.httpMethod == "GET" ? .json(TickTickFixtures.storedTask(id: "t1", projectID: "p1")) : .json("{}")
        }

        try await makeClient(transport).setNotes("bring cash", taskID: "t1", projectID: "p1", field: .content)

        #expect(transport.requests.map(\.route) == ["GET /open/v1/project/p1/task/t1", "POST /open/v1/task/t1"])
        let sent = transport.requests[1].jsonBody
        #expect(sent["content"] as? String == "bring cash")
        // Everything else goes back as it came, which keeps TickTick from
        // dropping what an update leaves out.
        #expect(sent["id"] as? String == "t1")
        #expect(sent["projectId"] as? String == "p1")
        #expect(sent["title"] as? String == "Kept title")
        #expect(sent["desc"] as? String == "old desc")
        #expect(sent["dueDate"] as? String == "2026-10-10T17:00:00+0000")
        #expect(sent["repeatFlag"] as? String == "RRULE:FREQ=MONTHLY;INTERVAL=1")
        #expect(sent["tags"] as? [String] == ["work", "urgent"])
        #expect(sent["reminders"] as? [String] == ["TRIGGER:PT0S"])
        #expect((sent["sortOrder"] as? NSNumber)?.int64Value == Int64(-2_199_023_255_552))
        #expect(sent["priority"] as? Int == 5)
        #expect(sent.count == 13)
    }

    @Test func clearingAChecklistTasksNoteChangesOnlyDesc() async throws {
        let transport = StubTodoTransport { request, _ in
            request.httpMethod == "GET" ? .json(TickTickFixtures.storedTask(id: "t2", projectID: "p1")) : .json("{}")
        }

        try await makeClient(transport).setNotes("", taskID: "t2", projectID: "p1", field: .desc)

        let sent = transport.requests[1].jsonBody
        #expect(sent["desc"] as? String == "")
        #expect(sent["content"] as? String == "old note")
    }

    @Test func nothingIsWrittenWhenTheTaskCannotBeRead() async {
        let gone = StubTodoTransport { _, _ in StubTodoResponse(status: 404) }
        await #expect(throws: TickTickAPIError.notFound) {
            try await makeClient(gone).setNotes("x", taskID: "t1", projectID: "p1", field: .content)
        }
        #expect(gone.requests.map(\.route) == ["GET /open/v1/project/p1/task/t1"])

        // An answer that is some other task, or no task at all, is refused.
        for body in [TickTickFixtures.storedTask(id: "other"), "[]", "", "{\"title\":\"no id\"}"] {
            let odd = StubTodoTransport { _, _ in .json(body) }
            await #expect(throws: TickTickAPIError.invalidResponse) {
                try await makeClient(odd).setNotes("x", taskID: "t1", projectID: "p1", field: .content)
            }
            #expect(odd.requests.count == 1)
        }
    }

    @Test func anIDStaysInsideOnePathSegment() async throws {
        let transport = StubTodoTransport { _, _ in .json(TickTickFixtures.projectData(tasks: [])) }

        _ = try await makeClient(transport).projectData(id: "a/b?c")

        let url = try #require(transport.requests.first?.url)
        #expect(url.absoluteString == "https://api.ticktick.com/open/v1/project/a%2Fb%3Fc/data")
    }

    @Test func anEmptyIDIsRefusedBeforeAnythingIsSent() async {
        let transport = StubTodoTransport()

        await #expect(throws: TickTickAPIError.invalidResponse) {
            _ = try await makeClient(transport).projectData(id: "")
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Decoding

    @Test func oneBrokenTaskDoesNotLoseTheRest() async throws {
        let body = """
        {"project":{"id":"p1","name":"Work","permission":"read"},
         "tasks":[{"id":"a","title":"Good"},{"title":"No id"},"not an object",{"id":"b","title":"Also good","sortOrder":-2199023255552}]}
        """
        let transport = StubTodoTransport { _, _ in .json(body) }

        let data = try await makeClient(transport).projectData(id: "p1")

        #expect(data.tasks.map(\.id) == ["a", "b"])
        #expect(data.tasks.last?.sortOrder == Int64(-2_199_023_255_552))
        #expect(data.project?.isReadOnly == true)
    }

    @Test func aTaskWithOnlyAnIDStillDecodes() throws {
        let task = try TickTickFixtures.decodeTask("{\"id\":\"a\"}")

        #expect(task == TickTickTask(id: "a", title: ""))
        #expect(task.status == TickTickTask.statusOpen)
    }

    @Test func anAnswerThatIsNotAListOfProjectsIsInvalid() async {
        let transport = StubTodoTransport { _, _ in .json("{\"oops\":true}") }

        await #expect(throws: TickTickAPIError.invalidResponse) {
            _ = try await makeClient(transport).projects()
        }
    }

    @Test func aListTheUserOwnsOrMayWriteIsNotReadOnly() {
        #expect(TickTickProject(id: "a", name: "Mine").isReadOnly == false)
        #expect(TickTickProject(id: "a", name: "Shared", permission: "write").isReadOnly == false)
        #expect(TickTickProject(id: "a", name: "Shared", permission: "comment").isReadOnly == true)
        #expect(TickTickProject(id: "a", name: "Notes", kind: "NOTE").holdsTasks == false)
        #expect(TickTickProject(id: "a", name: "Tasks").holdsTasks == true)
    }

    // MARK: Failures

    @Test func statusCodesSortIntoTheCasesTheWidgetShows() throws {
        let empty = Data()
        #expect(TickTickClient.failure(status: 200, response: try response(status: 200), data: empty) == nil)
        #expect(TickTickClient.failure(status: 401, response: try response(status: 401), data: empty) == .unauthorized)
        #expect(TickTickClient.failure(status: 403, response: try response(status: 403), data: empty) == .forbidden)
        #expect(TickTickClient.failure(status: 404, response: try response(status: 404), data: empty) == .notFound)
        #expect(TickTickClient.failure(status: 400, response: try response(status: 400), data: empty) == .badRequest)
        #expect(TickTickClient.failure(status: 503, response: try response(status: 503), data: empty)
            == .server(status: 503))
    }

    @Test func aRateLimitCarriesTheWaitTheServerAskedFor() throws {
        let limited = try response(status: 429, headers: ["Retry-After": "30"])

        #expect(TickTickClient.failure(status: 429, response: limited, data: Data())
            == .rateLimited(retryAfter: TimeInterval(30)))
        #expect(TickTickClient.retryAfter(from: try response(status: 429, headers: ["Retry-After": "soon"])) == nil)
        #expect(TickTickClient.retryAfter(from: try response(status: 429, headers: ["Retry-After": "999999"]))
            == TickTickClient.maxRetryAfter)
    }

    @Test func anErrorCodeIsAFailureUnderAnyStatus() throws {
        let limited = Data("{\"errorCode\":\"exceed_query_limit\",\"errorMessage\":\"slow down\"}".utf8)
        let other = Data("{\"errorCode\":\"task_not_found\"}".utf8)

        #expect(TickTickClient.failure(status: 500, response: try response(status: 500), data: limited)
            == .rateLimited(retryAfter: nil))
        #expect(TickTickClient.failure(status: 200, response: try response(status: 200), data: limited)
            == .rateLimited(retryAfter: nil))
        // A 200 that carries an error is not a success.
        #expect(TickTickClient.failure(status: 200, response: try response(status: 200), data: other)
            == .invalidResponse)
        #expect(TickTickClient.failure(status: 404, response: try response(status: 404), data: other) == .notFound)
        // A task or a list of lists has no error code.
        let task = Data(TickTickFixtures.task(id: "a", title: "Fine").utf8)
        #expect(TickTickClient.failure(status: 200, response: try response(status: 200), data: task) == nil)
        #expect(TickTickClient.failure(status: 200, response: try response(status: 200), data: Data("[]".utf8)) == nil)
    }

    @Test func aRejectedTokenThrowsUnauthorized() async {
        let transport = StubTodoTransport { _, _ in
            .json("{\"error\":\"invalid_token\",\"error_description\":\"Invalid access token\"}", status: 401)
        }

        await #expect(throws: TickTickAPIError.unauthorized) {
            _ = try await makeClient(transport).projects()
        }
    }

    @Test func transportErrorsAreSorted() {
        #expect(TickTickClient.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(TickTickClient.classify(URLError(.timedOut)) == .offline)
        #expect(TickTickClient.classify(URLError(.cancelled)) == .cancelled)
        #expect(TickTickClient.classify(URLError(.badServerResponse)) == .invalidResponse)
        #expect(TickTickClient.classify(CancellationError()) == .cancelled)
        #expect(TickTickClient.classify(TickTickAPIError.forbidden) == .forbidden)
    }

    // MARK: Keychain item

    @Test func theTokenHasAKeychainItemOfItsOwn() {
        let tickTick = NookTodoKeychain.tickTick
        let notion = NookTodoKeychain.notion

        #expect(tickTick.service.hasSuffix(NookTodoKeychain.tickTickServiceSuffix))
        #expect(tickTick.service.count > NookTodoKeychain.tickTickServiceSuffix.count)
        #expect(tickTick.service != notion.service)
        #expect(tickTick.account == "api-token")
    }
}
