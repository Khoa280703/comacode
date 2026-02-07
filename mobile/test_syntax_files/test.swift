// Swift 5.9+ Comprehensive Sample File
// Demonstrates modern Swift patterns and best practices
import Foundation
import Combine

// MARK: - Custom Operators

infix operator >>>: AdditionPrecedence
infix operator <<<: AdditionPrecedence
infix operator <|>: LogicalDisjunctionPrecedence
infix operator <&>: LogicalConjunctionPrecedence
infix operator |>: AdditionPrecedence
infix operator <~: AssignmentPrecedence

/// Pipe forward operator - applies a function to a value
func |> <A, B>(value: A, transform: (A) -> B) -> B {
    transform(value)
}

/// Forward composition operator - composes two functions left to right
func >>> <A, B, C>(lhs: @escaping (A) -> B, rhs: @escaping (B) -> C) -> (A) -> C {
    { a in rhs(lhs(a)) }
}

/// Backward composition operator - composes two functions right to left
func <<< <A, B, C>(lhs: @escaping (B) -> C, rhs: @escaping (A) -> B) -> (A) -> C {
    { a in lhs(rhs(a)) }
}

/// Alternative operator for Result types
func <|> <T, E: Error>(lhs: Result<T, E>, rhs: @autoclosure () -> T) -> T {
    switch lhs {
    case .success(let value): return value
    case .failure: return rhs()
    }
}

/// Applicative operator for Optional types
func <&> <A, B>(lhs: A?, rhs: (A) -> B) -> B? {
    lhs.map(rhs)
}

/// Bind operator for assigning to optional references
func <~ <T>(lhs: inout T?, rhs: T?) {
    if let value = rhs {
        lhs = value
    }
}

// MARK: - Error Types

/// Comprehensive application error type
enum AppError: Error, CustomStringConvertible, Equatable, LocalizedError {
    case notFound(String)
    case validationFailed([String])
    case networkError(String)
    case unauthorized
    case forbidden(String)
    case timeout(TimeInterval)
    case rateLimited(retryAfter: TimeInterval)
    case databaseError(String)
    case serializationError(String)
    case configurationError(String)
    case concurrencyError(String)
    case unknown(String)

    var description: String {
        switch self {
        case .notFound(let msg):
            return "Not found: \(msg)"
        case .validationFailed(let errors):
            return "Validation failed: \(errors.joined(separator: ", "))"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .unauthorized:
            return "Unauthorized access"
        case .forbidden(let resource):
            return "Access forbidden: \(resource)"
        case .timeout(let duration):
            return "Operation timed out after \(duration)s"
        case .rateLimited(let retryAfter):
            return "Rate limited. Retry after \(retryAfter)s"
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .serializationError(let msg):
            return "Serialization error: \(msg)"
        case .configurationError(let msg):
            return "Configuration error: \(msg)"
        case .concurrencyError(let msg):
            return "Concurrency error: \(msg)"
        case .unknown(let msg):
            return "Unknown error: \(msg)"
        }
    }

    var errorDescription: String? { description }

    var failureReason: String? {
        switch self {
        case .unauthorized: return "Authentication credentials are missing or invalid"
        case .forbidden: return "Insufficient permissions for this operation"
        case .timeout: return "The server did not respond in time"
        default: return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized: return "Please log in again"
        case .rateLimited(let retryAfter): return "Wait \(Int(retryAfter)) seconds before retrying"
        case .timeout: return "Check your network connection and try again"
        default: return nil
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .rateLimited: return true
        default: return false
        }
    }
}

/// Network-specific errors
enum NetworkError: Error, Equatable {
    case noConnection
    case invalidURL(String)
    case invalidResponse(statusCode: Int)
    case decodingFailed(String)
    case encodingFailed(String)
    case sslError(String)
    case dnsLookupFailed(String)
    case connectionRefused(String)
    case requestCancelled

    var statusCode: Int? {
        if case .invalidResponse(let code) = self {
            return code
        }
        return nil
    }
}

/// Validation error with field information
struct ValidationError: Error, Equatable {
    let field: String
    let message: String
    let code: String

    static func required(_ field: String) -> ValidationError {
        ValidationError(field: field, message: "\(field) is required", code: "REQUIRED")
    }

    static func invalid(_ field: String, reason: String) -> ValidationError {
        ValidationError(field: field, message: "\(field) is invalid: \(reason)", code: "INVALID")
    }

    static func tooShort(_ field: String, minLength: Int) -> ValidationError {
        ValidationError(field: field, message: "\(field) must be at least \(minLength) characters", code: "TOO_SHORT")
    }

    static func tooLong(_ field: String, maxLength: Int) -> ValidationError {
        ValidationError(field: field, message: "\(field) must be at most \(maxLength) characters", code: "TOO_LONG")
    }
}

// MARK: - Result Type Extensions

extension Result {
    /// Map the success value
    func mapSuccess<NewSuccess>(_ transform: (Success) -> NewSuccess) -> Result<NewSuccess, Failure> {
        switch self {
        case .success(let value): return .success(transform(value))
        case .failure(let error): return .failure(error)
        }
    }

    /// Flat map the success value
    func flatMapSuccess<NewSuccess>(_ transform: (Success) -> Result<NewSuccess, Failure>) -> Result<NewSuccess, Failure> {
        switch self {
        case .success(let value): return transform(value)
        case .failure(let error): return .failure(error)
        }
    }

    /// Map the failure to a different error type
    func mapFailure<NewFailure: Error>(_ transform: (Failure) -> NewFailure) -> Result<Success, NewFailure> {
        switch self {
        case .success(let value): return .success(value)
        case .failure(let error): return .failure(transform(error))
        }
    }

    /// Get the success value or a default
    func getOrElse(_ defaultValue: @autoclosure () -> Success) -> Success {
        switch self {
        case .success(let value): return value
        case .failure: return defaultValue()
        }
    }

    /// Get the success value or throw the error
    func getOrThrow() throws -> Success {
        switch self {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    /// Check if the result is successful
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Check if the result is a failure
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    /// Get the success value as optional
    var successValue: Success? {
        if case .success(let value) = self { return value }
        return nil
    }

    /// Get the failure as optional
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

    /// Recover from failure with a fallback result
    func recover(_ fallback: (Failure) -> Result<Success, Failure>) -> Result<Success, Failure> {
        switch self {
        case .success: return self
        case .failure(let error): return fallback(error)
        }
    }

    /// Tap into success without modifying
    func onSuccess(_ action: (Success) -> Void) -> Result<Success, Failure> {
        if case .success(let value) = self { action(value) }
        return self
    }

    /// Tap into failure without modifying
    func onFailure(_ action: (Failure) -> Void) -> Result<Success, Failure> {
        if case .failure(let error) = self { action(error) }
        return self
    }
}

// MARK: - Role and Permission Models

/// User role enumeration with associated permissions
enum Role: String, Codable, CaseIterable, Comparable {
    case superAdmin = "super_admin"
    case admin
    case moderator
    case user
    case guest
    case suspended

    var permissions: Set<Permission> {
        switch self {
        case .superAdmin: return Set(Permission.allCases)
        case .admin: return [.read, .write, .delete, .manageUsers, .viewReports, .audit]
        case .moderator: return [.read, .write, .delete, .viewReports]
        case .user: return [.read, .write]
        case .guest: return [.read]
        case .suspended: return []
        }
    }

    var displayName: String {
        switch self {
        case .superAdmin: return "Super Administrator"
        case .admin: return "Administrator"
        case .moderator: return "Moderator"
        case .user: return "User"
        case .guest: return "Guest"
        case .suspended: return "Suspended"
        }
    }

    var priority: Int {
        switch self {
        case .superAdmin: return 100
        case .admin: return 80
        case .moderator: return 60
        case .user: return 40
        case .guest: return 20
        case .suspended: return 0
        }
    }

    static func < (lhs: Role, rhs: Role) -> Bool {
        lhs.priority < rhs.priority
    }

    func hasPermission(_ permission: Permission) -> Bool {
        permissions.contains(permission)
    }

    func hasAllPermissions(_ required: Set<Permission>) -> Bool {
        required.isSubset(of: permissions)
    }

    func hasAnyPermission(_ required: Set<Permission>) -> Bool {
        !permissions.isDisjoint(with: required)
    }
}

/// Permission enumeration
enum Permission: String, Codable, CaseIterable, Hashable {
    case read
    case write
    case delete
    case manageUsers
    case viewReports
    case audit
    case configure
    case deploy
    case billing

    var description: String {
        switch self {
        case .read: return "Read data"
        case .write: return "Write data"
        case .delete: return "Delete data"
        case .manageUsers: return "Manage users"
        case .viewReports: return "View reports"
        case .audit: return "Audit actions"
        case .configure: return "Configure settings"
        case .deploy: return "Deploy changes"
        case .billing: return "Manage billing"
        }
    }

    var category: PermissionCategory {
        switch self {
        case .read, .write, .delete: return .data
        case .manageUsers, .viewReports, .audit: return .administration
        case .configure, .deploy, .billing: return .system
        }
    }
}

/// Permission categories
enum PermissionCategory: String, CaseIterable {
    case data
    case administration
    case system

    var permissions: [Permission] {
        Permission.allCases.filter { $0.category == self }
    }
}

// MARK: - User Entity with Validation

/// Comprehensive user model with validation
struct User: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var email: String
    var role: Role
    var metadata: [String: String]
    let createdAt: Date
    var updatedAt: Date?
    var lastLoginAt: Date?
    var isActive: Bool
    var preferences: UserPreferences
    var profile: UserProfile?

    struct UserPreferences: Codable, Equatable, Hashable {
        var theme: Theme
        var language: String
        var notifications: NotificationSettings
        var timezone: String

        enum Theme: String, Codable, CaseIterable {
            case light, dark, system
        }

        struct NotificationSettings: Codable, Equatable, Hashable {
            var email: Bool
            var push: Bool
            var sms: Bool
            var frequency: Frequency

            enum Frequency: String, Codable, CaseIterable {
                case immediate, hourly, daily, weekly, never
            }

            static var `default`: NotificationSettings {
                NotificationSettings(email: true, push: true, sms: false, frequency: .immediate)
            }
        }

        static var `default`: UserPreferences {
            UserPreferences(
                theme: .system,
                language: "en",
                notifications: .default,
                timezone: TimeZone.current.identifier
            )
        }
    }

    struct UserProfile: Codable, Equatable, Hashable {
        var displayName: String?
        var bio: String?
        var avatarURL: URL?
        var location: String?
        var website: URL?
        var socialLinks: [SocialLink]

        struct SocialLink: Codable, Equatable, Hashable {
            let platform: Platform
            let url: URL

            enum Platform: String, Codable, CaseIterable {
                case twitter, github, linkedin, instagram, facebook, youtube
            }
        }
    }

    /// Failable initializer with validation
    init(
        id: UUID = UUID(),
        name: String,
        email: String,
        role: Role = .user,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastLoginAt: Date? = nil,
        isActive: Bool = true,
        preferences: UserPreferences = .default,
        profile: UserProfile? = nil
    ) throws {
        // Validate name
        guard name.count >= 2 else {
            throw AppError.validationFailed(["Name must be at least 2 characters"])
        }
        guard name.count <= 100 else {
            throw AppError.validationFailed(["Name must be at most 100 characters"])
        }

        // Validate email
        let emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        guard email.wholeMatch(of: emailRegex) != nil else {
            throw AppError.validationFailed(["Invalid email format"])
        }

        self.id = id
        self.name = name
        self.email = email.lowercased()
        self.role = role
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastLoginAt = lastLoginAt
        self.isActive = isActive
        self.preferences = preferences
        self.profile = profile
    }

    /// Validate the entire user entity
    func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        if name.isEmpty {
            errors.append(.required("name"))
        } else if name.count < 2 {
            errors.append(.tooShort("name", minLength: 2))
        } else if name.count > 100 {
            errors.append(.tooLong("name", maxLength: 100))
        }

        if email.isEmpty {
            errors.append(.required("email"))
        } else if !email.contains("@") {
            errors.append(.invalid("email", reason: "must contain @"))
        }

        return errors
    }

    /// Check if user is valid
    var isValid: Bool {
        validate().isEmpty
    }
}

// MARK: - User Builder Pattern

/// Builder for creating User instances
final class UserBuilder {
    private var id: UUID = UUID()
    private var name: String = ""
    private var email: String = ""
    private var role: Role = .user
    private var metadata: [String: String] = [:]
    private var createdAt: Date = Date()
    private var updatedAt: Date?
    private var lastLoginAt: Date?
    private var isActive: Bool = true
    private var preferences: User.UserPreferences = .default
    private var profile: User.UserProfile?

    func withId(_ id: UUID) -> UserBuilder {
        self.id = id
        return self
    }

    func withName(_ name: String) -> UserBuilder {
        self.name = name
        return self
    }

    func withEmail(_ email: String) -> UserBuilder {
        self.email = email
        return self
    }

    func withRole(_ role: Role) -> UserBuilder {
        self.role = role
        return self
    }

    func withMetadata(_ metadata: [String: String]) -> UserBuilder {
        self.metadata = metadata
        return self
    }

    func addMetadata(key: String, value: String) -> UserBuilder {
        self.metadata[key] = value
        return self
    }

    func withPreferences(_ preferences: User.UserPreferences) -> UserBuilder {
        self.preferences = preferences
        return self
    }

    func withProfile(_ profile: User.UserProfile) -> UserBuilder {
        self.profile = profile
        return self
    }

    func asActive(_ isActive: Bool) -> UserBuilder {
        self.isActive = isActive
        return self
    }

    func build() throws -> User {
        try User(
            id: id,
            name: name,
            email: email,
            role: role,
            metadata: metadata,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastLoginAt: lastLoginAt,
            isActive: isActive,
            preferences: preferences,
            profile: profile
        )
    }

    func buildResult() -> Result<User, AppError> {
        do {
            return .success(try build())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}

// MARK: - Repository Protocol with Associated Types

/// Generic repository protocol
protocol Repository<Entity, ID> {
    associatedtype Entity
    associatedtype ID: Hashable

    func findById(_ id: ID) async throws -> Entity?
    func findAll() async throws -> [Entity]
    func findAll(limit: Int, offset: Int) async throws -> [Entity]
    func count() async throws -> Int
    func exists(_ id: ID) async throws -> Bool
    func save(_ entity: Entity) async throws -> Entity
    func saveAll(_ entities: [Entity]) async throws -> [Entity]
    func delete(_ id: ID) async throws -> Bool
    func deleteAll(_ ids: [ID]) async throws -> Int
}

/// Extension with default implementations
extension Repository {
    func exists(_ id: ID) async throws -> Bool {
        try await findById(id) != nil
    }

    func saveAll(_ entities: [Entity]) async throws -> [Entity] {
        var saved: [Entity] = []
        for entity in entities {
            saved.append(try await save(entity))
        }
        return saved
    }

    func deleteAll(_ ids: [ID]) async throws -> Int {
        var count = 0
        for id in ids {
            if try await delete(id) {
                count += 1
            }
        }
        return count
    }
}

/// Queryable repository with filtering and sorting
protocol QueryableRepository<Entity, ID>: Repository {
    associatedtype Query

    func find(query: Query) async throws -> [Entity]
    func findOne(query: Query) async throws -> Entity?
    func count(query: Query) async throws -> Int
}

/// Transactional repository
protocol TransactionalRepository {
    func beginTransaction() async throws
    func commit() async throws
    func rollback() async throws
    func transaction<T>(_ operation: () async throws -> T) async throws -> T
}

// MARK: - User Query Types

/// Query object for user searches
struct UserQuery: Equatable {
    var ids: [UUID]?
    var roles: [Role]?
    var isActive: Bool?
    var searchTerm: String?
    var createdAfter: Date?
    var createdBefore: Date?
    var sortBy: SortField?
    var sortOrder: SortOrder
    var limit: Int?
    var offset: Int?

    enum SortField: String, CaseIterable {
        case name, email, createdAt, updatedAt, lastLoginAt
    }

    enum SortOrder: String, CaseIterable {
        case ascending, descending
    }

    init(
        ids: [UUID]? = nil,
        roles: [Role]? = nil,
        isActive: Bool? = nil,
        searchTerm: String? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        sortBy: SortField? = nil,
        sortOrder: SortOrder = .ascending,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.ids = ids
        self.roles = roles
        self.isActive = isActive
        self.searchTerm = searchTerm
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.limit = limit
        self.offset = offset
    }

    static var all: UserQuery { UserQuery() }

    static func byRole(_ role: Role) -> UserQuery {
        UserQuery(roles: [role])
    }

    static func active() -> UserQuery {
        UserQuery(isActive: true)
    }

    static func search(_ term: String) -> UserQuery {
        UserQuery(searchTerm: term)
    }
}

// MARK: - In-Memory Repository Implementation

/// Thread-safe in-memory user repository using actor
actor InMemoryUserRepository: Repository, QueryableRepository {
    typealias Entity = User
    typealias ID = UUID
    typealias Query = UserQuery

    private var storage: [UUID: User] = [:]
    private var versionMap: [UUID: Int] = [:]

    func findById(_ id: UUID) async throws -> User? {
        storage[id]
    }

    func findAll() async throws -> [User] {
        Array(storage.values)
    }

    func findAll(limit: Int, offset: Int) async throws -> [User] {
        let all = Array(storage.values)
        let start = min(offset, all.count)
        let end = min(start + limit, all.count)
        return Array(all[start..<end])
    }

    func count() async throws -> Int {
        storage.count
    }

    func save(_ user: User) async throws -> User {
        var updated = user
        updated.updatedAt = Date()
        storage[user.id] = updated
        versionMap[user.id] = (versionMap[user.id] ?? 0) + 1
        return updated
    }

    func delete(_ id: UUID) async throws -> Bool {
        let removed = storage.removeValue(forKey: id) != nil
        if removed {
            versionMap.removeValue(forKey: id)
        }
        return removed
    }

    func find(query: UserQuery) async throws -> [User] {
        var results = Array(storage.values)

        // Filter by IDs
        if let ids = query.ids, !ids.isEmpty {
            results = results.filter { ids.contains($0.id) }
        }

        // Filter by roles
        if let roles = query.roles, !roles.isEmpty {
            results = results.filter { roles.contains($0.role) }
        }

        // Filter by active status
        if let isActive = query.isActive {
            results = results.filter { $0.isActive == isActive }
        }

        // Filter by search term
        if let searchTerm = query.searchTerm, !searchTerm.isEmpty {
            let term = searchTerm.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(term) ||
                $0.email.lowercased().contains(term)
            }
        }

        // Filter by created date
        if let createdAfter = query.createdAfter {
            results = results.filter { $0.createdAt >= createdAfter }
        }
        if let createdBefore = query.createdBefore {
            results = results.filter { $0.createdAt <= createdBefore }
        }

        // Sort
        if let sortBy = query.sortBy {
            results = results.sorted { lhs, rhs in
                let ascending = query.sortOrder == .ascending
                switch sortBy {
                case .name:
                    return ascending ? lhs.name < rhs.name : lhs.name > rhs.name
                case .email:
                    return ascending ? lhs.email < rhs.email : lhs.email > rhs.email
                case .createdAt:
                    return ascending ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
                case .updatedAt:
                    let lhsDate = lhs.updatedAt ?? lhs.createdAt
                    let rhsDate = rhs.updatedAt ?? rhs.createdAt
                    return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
                case .lastLoginAt:
                    let lhsDate = lhs.lastLoginAt ?? .distantPast
                    let rhsDate = rhs.lastLoginAt ?? .distantPast
                    return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
                }
            }
        }

        // Pagination
        if let offset = query.offset {
            results = Array(results.dropFirst(offset))
        }
        if let limit = query.limit {
            results = Array(results.prefix(limit))
        }

        return results
    }

    func findOne(query: UserQuery) async throws -> User? {
        var limitedQuery = query
        limitedQuery.limit = 1
        return try await find(query: limitedQuery).first
    }

    func count(query: UserQuery) async throws -> Int {
        try await find(query: query).count
    }

    // Additional helper methods
    func findByEmail(_ email: String) async throws -> User? {
        storage.values.first { $0.email.lowercased() == email.lowercased() }
    }

    func findByRole(_ role: Role) async throws -> [User] {
        storage.values.filter { $0.role == role }
    }

    func getVersion(_ id: UUID) async -> Int? {
        versionMap[id]
    }

    func clear() async {
        storage.removeAll()
        versionMap.removeAll()
    }
}

// MARK: - Event System with Combine

/// Domain events
enum DomainEvent: Equatable {
    case userCreated(User)
    case userUpdated(old: User, new: User)
    case userDeleted(UUID)
    case userActivated(UUID)
    case userDeactivated(UUID)
    case userRoleChanged(userId: UUID, from: Role, to: Role)
    case userLoggedIn(UUID)
    case userLoggedOut(UUID)
    case passwordChanged(UUID)
    case profileUpdated(UUID)

    var eventType: String {
        switch self {
        case .userCreated: return "user.created"
        case .userUpdated: return "user.updated"
        case .userDeleted: return "user.deleted"
        case .userActivated: return "user.activated"
        case .userDeactivated: return "user.deactivated"
        case .userRoleChanged: return "user.role_changed"
        case .userLoggedIn: return "user.logged_in"
        case .userLoggedOut: return "user.logged_out"
        case .passwordChanged: return "user.password_changed"
        case .profileUpdated: return "user.profile_updated"
        }
    }

    var userId: UUID? {
        switch self {
        case .userCreated(let user): return user.id
        case .userUpdated(_, let user): return user.id
        case .userDeleted(let id): return id
        case .userActivated(let id): return id
        case .userDeactivated(let id): return id
        case .userRoleChanged(let id, _, _): return id
        case .userLoggedIn(let id): return id
        case .userLoggedOut(let id): return id
        case .passwordChanged(let id): return id
        case .profileUpdated(let id): return id
        }
    }
}

/// Event envelope with metadata
struct EventEnvelope<E>: Identifiable {
    let id: UUID
    let event: E
    let timestamp: Date
    let correlationId: UUID?
    let causationId: UUID?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        event: E,
        timestamp: Date = Date(),
        correlationId: UUID? = nil,
        causationId: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.event = event
        self.timestamp = timestamp
        self.correlationId = correlationId
        self.causationId = causationId
        self.metadata = metadata
    }
}

/// Event publisher protocol
protocol EventPublisher {
    func publish(_ event: DomainEvent) async
    func publishWithEnvelope(_ envelope: EventEnvelope<DomainEvent>) async
}

/// Event subscriber protocol
protocol EventSubscriber: AnyObject {
    func handleEvent(_ event: DomainEvent) async
    func handleEnvelope(_ envelope: EventEnvelope<DomainEvent>) async
}

extension EventSubscriber {
    func handleEnvelope(_ envelope: EventEnvelope<DomainEvent>) async {
        await handleEvent(envelope.event)
    }
}

/// Event bus using actors and Combine
actor EventBus: EventPublisher {
    private var subscribers: [ObjectIdentifier: WeakSubscriber] = [:]
    private let subject = PassthroughSubject<EventEnvelope<DomainEvent>, Never>()
    private var eventHistory: [EventEnvelope<DomainEvent>] = []
    private let maxHistorySize: Int

    struct WeakSubscriber {
        weak var subscriber: EventSubscriber?
        let filter: ((DomainEvent) -> Bool)?
    }

    var publisher: AnyPublisher<EventEnvelope<DomainEvent>, Never> {
        subject.eraseToAnyPublisher()
    }

    init(maxHistorySize: Int = 1000) {
        self.maxHistorySize = maxHistorySize
    }

    func subscribe(_ subscriber: EventSubscriber, filter: ((DomainEvent) -> Bool)? = nil) {
        let id = ObjectIdentifier(subscriber)
        subscribers[id] = WeakSubscriber(subscriber: subscriber, filter: filter)
    }

    func unsubscribe(_ subscriber: EventSubscriber) {
        let id = ObjectIdentifier(subscriber)
        subscribers.removeValue(forKey: id)
    }

    func publish(_ event: DomainEvent) async {
        let envelope = EventEnvelope(event: event)
        await publishWithEnvelope(envelope)
    }

    func publishWithEnvelope(_ envelope: EventEnvelope<DomainEvent>) async {
        // Store in history
        eventHistory.append(envelope)
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst()
        }

        // Publish to Combine
        subject.send(envelope)

        // Clean up nil references and notify subscribers
        subscribers = subscribers.filter { $0.value.subscriber != nil }

        for (_, weak) in subscribers {
            guard let subscriber = weak.subscriber else { continue }
            if let filter = weak.filter, !filter(envelope.event) { continue }
            await subscriber.handleEnvelope(envelope)
        }
    }

    func getHistory(limit: Int? = nil) -> [EventEnvelope<DomainEvent>] {
        if let limit = limit {
            return Array(eventHistory.suffix(limit))
        }
        return eventHistory
    }

    func getHistoryForUser(_ userId: UUID) -> [EventEnvelope<DomainEvent>] {
        eventHistory.filter { $0.event.userId == userId }
    }

    func clearHistory() {
        eventHistory.removeAll()
    }
}

// MARK: - Cache Implementation

/// Cache entry with expiration
struct CacheEntry<T> {
    let value: T
    let expiresAt: Date
    let createdAt: Date
    var hitCount: Int

    var isExpired: Bool {
        Date() > expiresAt
    }

    init(value: T, ttl: TimeInterval) {
        self.value = value
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(ttl)
        self.hitCount = 0
    }
}

/// Cache statistics
struct CacheStats {
    var hits: Int = 0
    var misses: Int = 0
    var evictions: Int = 0
    var size: Int = 0

    var hitRate: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0
    }
}

/// Thread-safe LRU cache using actors
actor LRUCache<Key: Hashable, Value> {
    private var storage: [Key: CacheEntry<Value>] = [:]
    private var accessOrder: [Key] = []
    private let maxSize: Int
    private let defaultTTL: TimeInterval
    private var stats = CacheStats()

    init(maxSize: Int = 100, defaultTTL: TimeInterval = 300) {
        self.maxSize = maxSize
        self.defaultTTL = defaultTTL
    }

    func get(_ key: Key) async -> Value? {
        guard let entry = storage[key] else {
            stats.misses += 1
            return nil
        }

        if entry.isExpired {
            storage.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            stats.misses += 1
            stats.evictions += 1
            return nil
        }

        // Update access order
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)

        // Update hit count
        var updated = entry
        updated.hitCount += 1
        storage[key] = updated

        stats.hits += 1
        return entry.value
    }

    func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) async {
        let entry = CacheEntry(value: value, ttl: ttl ?? defaultTTL)

        // Evict if at capacity
        if storage.count >= maxSize && storage[key] == nil {
            evictLRU()
        }

        storage[key] = entry
        accessOrder.removeAll { $0 == key }
