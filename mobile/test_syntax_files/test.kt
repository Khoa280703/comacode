// Kotlin 1.9+ Comprehensive Sample File
// Demonstrates modern patterns, coroutines, Flow, DSL, and advanced features

@file:OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDateTime
import java.time.Duration
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.properties.Delegates
import kotlin.properties.ReadOnlyProperty
import kotlin.reflect.KProperty
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

// =============================================================================
// CUSTOM EXCEPTIONS
// =============================================================================

sealed class DomainException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    abstract val errorCode: String
    abstract val httpStatusCode: Int
}

class EntityNotFoundException(
    val entityType: String,
    val entityId: Any
) : DomainException("$entityType with id '$entityId' not found") {
    override val errorCode = "ENTITY_NOT_FOUND"
    override val httpStatusCode = 404
}

class ValidationException(
    val violations: List<ValidationViolation>
) : DomainException("Validation failed: ${violations.joinToString(", ") { it.message }}") {
    override val errorCode = "VALIDATION_ERROR"
    override val httpStatusCode = 400

    constructor(field: String, message: String) : this(listOf(ValidationViolation(field, message)))
}

data class ValidationViolation(
    val field: String,
    val message: String,
    val invalidValue: Any? = null
)

class AuthenticationException(
    message: String = "Authentication required"
) : DomainException(message) {
    override val errorCode = "AUTHENTICATION_REQUIRED"
    override val httpStatusCode = 401
}

class AuthorizationException(
    val requiredPermission: String,
    val userId: String
) : DomainException("User '$userId' lacks permission: $requiredPermission") {
    override val errorCode = "FORBIDDEN"
    override val httpStatusCode = 403
}

class ConflictException(
    val resourceType: String,
    val conflictingField: String,
    val conflictingValue: Any
) : DomainException("$resourceType with $conflictingField '$conflictingValue' already exists") {
    override val errorCode = "CONFLICT"
    override val httpStatusCode = 409
}

class RateLimitException(
    val retryAfterSeconds: Long
) : DomainException("Rate limit exceeded. Retry after $retryAfterSeconds seconds") {
    override val errorCode = "RATE_LIMITED"
    override val httpStatusCode = 429
}

class ServiceUnavailableException(
    val serviceName: String,
    cause: Throwable? = null
) : DomainException("Service '$serviceName' is temporarily unavailable", cause) {
    override val errorCode = "SERVICE_UNAVAILABLE"
    override val httpStatusCode = 503
}

// =============================================================================
// RESULT TYPE - Functional Error Handling
// =============================================================================

sealed class Result<out T> {
    data class Success<T>(val data: T) : Result<T>()
    data class Failure(val error: String, val exception: Throwable? = null) : Result<Nothing>()

    val isSuccess: Boolean get() = this is Success
    val isFailure: Boolean get() = this is Failure

    inline fun <R> map(transform: (T) -> R): Result<R> = when (this) {
        is Success -> Success(transform(data))
        is Failure -> this
    }

    inline fun <R> flatMap(transform: (T) -> Result<R>): Result<R> = when (this) {
        is Success -> transform(data)
        is Failure -> this
    }

    inline fun mapError(transform: (String) -> String): Result<T> = when (this) {
        is Success -> this
        is Failure -> Failure(transform(error), exception)
    }

    inline fun recover(transform: (String) -> T): Result<T> = when (this) {
        is Success -> this
        is Failure -> Success(transform(error))
    }

    inline fun recoverWith(transform: (String) -> Result<T>): Result<T> = when (this) {
        is Success -> this
        is Failure -> transform(error)
    }

    inline fun onSuccess(action: (T) -> Unit): Result<T> {
        if (this is Success) action(data)
        return this
    }

    inline fun onFailure(action: (String, Throwable?) -> Unit): Result<T> {
        if (this is Failure) action(error, exception)
        return this
    }

    fun getOrNull(): T? = (this as? Success)?.data

    fun getOrDefault(default: @UnsafeVariance T): T = when (this) {
        is Success -> data
        is Failure -> default
    }

    inline fun getOrElse(default: () -> @UnsafeVariance T): T = when (this) {
        is Success -> data
        is Failure -> default()
    }

    fun getOrThrow(): T = when (this) {
        is Success -> data
        is Failure -> throw exception ?: RuntimeException(error)
    }

    fun exceptionOrNull(): Throwable? = (this as? Failure)?.exception

    companion object {
        inline fun <T> catch(block: () -> T): Result<T> = try {
            Success(block())
        } catch (e: Exception) {
            Failure(e.message ?: "Unknown error", e)
        }

        fun <T> fromNullable(value: T?, errorMessage: String = "Value is null"): Result<T> =
            value?.let { Success(it) } ?: Failure(errorMessage)

        suspend fun <T> catchSuspend(block: suspend () -> T): Result<T> = try {
            Success(block())
        } catch (e: Exception) {
            Failure(e.message ?: "Unknown error", e)
        }
    }
}

// Result extension functions
inline fun <T, R> Result<T>.fold(
    onSuccess: (T) -> R,
    onFailure: (String, Throwable?) -> R
): R = when (this) {
    is Result.Success -> onSuccess(data)
    is Result.Failure -> onFailure(error, exception)
}

fun <T> Result<Result<T>>.flatten(): Result<T> = when (this) {
    is Result.Success -> data
    is Result.Failure -> this
}

fun <T> List<Result<T>>.sequence(): Result<List<T>> {
    val results = mutableListOf<T>()
    for (result in this) {
        when (result) {
            is Result.Success -> results.add(result.data)
            is Result.Failure -> return result
        }
    }
    return Result.Success(results)
}

suspend fun <T> List<Result<T>>.sequenceAsync(): Result<List<T>> = coroutineScope {
    val deferred = map { result ->
        async { result }
    }
    deferred.awaitAll().sequence()
}

// =============================================================================
// ENTITY DEFINITIONS - Data Classes with Validation
// =============================================================================

enum class Role(val permissions: Set<Permission>) {
    SUPER_ADMIN(Permission.values().toSet()),
    ADMIN(setOf(Permission.READ, Permission.WRITE, Permission.DELETE, Permission.MANAGE_USERS)),
    MODERATOR(setOf(Permission.READ, Permission.WRITE, Permission.MODERATE)),
    USER(setOf(Permission.READ, Permission.WRITE)),
    GUEST(setOf(Permission.READ));

    fun hasPermission(permission: Permission): Boolean = permission in permissions
}

enum class Permission {
    READ, WRITE, DELETE, MODERATE, MANAGE_USERS, MANAGE_SYSTEM
}

enum class UserStatus {
    ACTIVE, INACTIVE, SUSPENDED, PENDING_VERIFICATION, DELETED
}

@JvmInline
value class UserId(val value: String) {
    init {
        require(value.isNotBlank()) { "UserId cannot be blank" }
    }

    companion object {
        fun generate(): UserId = UserId(UUID.randomUUID().toString())
    }
}

@JvmInline
value class Email(val value: String) {
    init {
        require(value.matches(EMAIL_REGEX)) { "Invalid email format: $value" }
    }

    companion object {
        private val EMAIL_REGEX = Regex("^[\\w.-]+@[\\w.-]+\\.\\w{2,}$")
    }

    val domain: String get() = value.substringAfter("@")
    val localPart: String get() = value.substringBefore("@")
}

@JvmInline
value class PhoneNumber(val value: String) {
    init {
        require(value.matches(PHONE_REGEX)) { "Invalid phone number format: $value" }
    }

    companion object {
        private val PHONE_REGEX = Regex("^\\+?[1-9]\\d{1,14}$")
    }

    val formatted: String
        get() = when {
            value.length == 10 -> "(${value.substring(0, 3)}) ${value.substring(3, 6)}-${value.substring(6)}"
            value.startsWith("+") -> value
            else -> "+$value"
        }
}

data class Address(
    val street: String,
    val city: String,
    val state: String,
    val postalCode: String,
    val country: String
) {
    init {
        require(street.isNotBlank()) { "Street cannot be blank" }
        require(city.isNotBlank()) { "City cannot be blank" }
        require(country.isNotBlank()) { "Country cannot be blank" }
    }

    val formatted: String
        get() = "$street, $city, $state $postalCode, $country"
}

data class UserProfile(
    val firstName: String,
    val lastName: String,
    val avatarUrl: String? = null,
    val bio: String? = null,
    val dateOfBirth: LocalDateTime? = null,
    val phone: PhoneNumber? = null,
    val address: Address? = null,
    val preferences: UserPreferences = UserPreferences()
) {
    init {
        require(firstName.length in 1..50) { "First name must be 1-50 characters" }
        require(lastName.length in 1..50) { "Last name must be 1-50 characters" }
        bio?.let { require(it.length <= 500) { "Bio must be at most 500 characters" } }
    }

    val fullName: String get() = "$firstName $lastName"
    val initials: String get() = "${firstName.first()}${lastName.first()}".uppercase()
}

data class UserPreferences(
    val theme: Theme = Theme.SYSTEM,
    val language: String = "en",
    val timezone: String = "UTC",
    val emailNotifications: Boolean = true,
    val pushNotifications: Boolean = true,
    val twoFactorEnabled: Boolean = false
)

enum class Theme { LIGHT, DARK, SYSTEM }

data class User(
    val id: UserId,
    val email: Email,
    val profile: UserProfile,
    val role: Role = Role.USER,
    val status: UserStatus = UserStatus.PENDING_VERIFICATION,
    val metadata: Map<String, String> = emptyMap(),
    val createdAt: LocalDateTime = LocalDateTime.now(),
    val updatedAt: LocalDateTime = LocalDateTime.now(),
    val lastLoginAt: LocalDateTime? = null,
    val version: Long = 0
) {
    fun validate(): List<ValidationViolation> {
        val violations = mutableListOf<ValidationViolation>()

        if (profile.firstName.isBlank()) {
            violations.add(ValidationViolation("profile.firstName", "First name is required"))
        }
        if (profile.lastName.isBlank()) {
            violations.add(ValidationViolation("profile.lastName", "Last name is required"))
        }

        return violations
    }

    fun hasPermission(permission: Permission): Boolean = role.hasPermission(permission)

    fun isActive(): Boolean = status == UserStatus.ACTIVE

    fun withUpdatedProfile(block: UserProfile.() -> UserProfile): User =
        copy(profile = profile.block(), updatedAt = LocalDateTime.now(), version = version + 1)
}

// User builder DSL
class UserBuilder {
    var id: UserId = UserId.generate()
    var email: String = ""
    var firstName: String = ""
    var lastName: String = ""
    var role: Role = Role.USER
    var status: UserStatus = UserStatus.PENDING_VERIFICATION
    private var profile: UserProfile? = null
    private val metadata = mutableMapOf<String, String>()

    fun profile(block: UserProfileBuilder.() -> Unit) {
        profile = UserProfileBuilder().apply(block).build()
    }

    fun metadata(key: String, value: String) {
        metadata[key] = value
    }

    fun build(): User {
        require(email.isNotBlank()) { "Email is required" }
        require(firstName.isNotBlank()) { "First name is required" }
        require(lastName.isNotBlank()) { "Last name is required" }

        return User(
            id = id,
            email = Email(email),
            profile = profile ?: UserProfile(firstName, lastName),
            role = role,
            status = status,
            metadata = metadata.toMap()
        )
    }
}

class UserProfileBuilder {
    var firstName: String = ""
    var lastName: String = ""
    var avatarUrl: String? = null
    var bio: String? = null
    var phone: String? = null
    private var address: Address? = null
    private var preferences: UserPreferences = UserPreferences()

    fun address(block: AddressBuilder.() -> Unit) {
        address = AddressBuilder().apply(block).build()
    }

    fun preferences(block: PreferencesBuilder.() -> Unit) {
        preferences = PreferencesBuilder().apply(block).build()
    }

    fun build(): UserProfile = UserProfile(
        firstName = firstName,
        lastName = lastName,
        avatarUrl = avatarUrl,
        bio = bio,
        phone = phone?.let { PhoneNumber(it) },
        address = address,
        preferences = preferences
    )
}

class AddressBuilder {
    var street: String = ""
    var city: String = ""
    var state: String = ""
    var postalCode: String = ""
    var country: String = ""

    fun build(): Address = Address(street, city, state, postalCode, country)
}

class PreferencesBuilder {
    var theme: Theme = Theme.SYSTEM
    var language: String = "en"
    var timezone: String = "UTC"
    var emailNotifications: Boolean = true
    var pushNotifications: Boolean = true
    var twoFactorEnabled: Boolean = false

    fun build(): UserPreferences = UserPreferences(
        theme, language, timezone, emailNotifications, pushNotifications, twoFactorEnabled
    )
}

fun user(block: UserBuilder.() -> Unit): User = UserBuilder().apply(block).build()

// =============================================================================
// REPOSITORY PATTERN - Interfaces and Implementations
// =============================================================================

interface Repository<T, ID> {
    suspend fun findById(id: ID): T?
    suspend fun findAll(): List<T>
    suspend fun findAll(page: Int, size: Int): Page<T>
    suspend fun save(entity: T): T
    suspend fun saveAll(entities: List<T>): List<T>
    suspend fun delete(id: ID): Boolean
    suspend fun deleteAll(ids: List<ID>): Int
    suspend fun exists(id: ID): Boolean
    suspend fun count(): Long
}

data class Page<T>(
    val content: List<T>,
    val pageNumber: Int,
    val pageSize: Int,
    val totalElements: Long,
    val totalPages: Int
) {
    val hasNext: Boolean get() = pageNumber < totalPages - 1
    val hasPrevious: Boolean get() = pageNumber > 0
    val isFirst: Boolean get() = pageNumber == 0
    val isLast: Boolean get() = pageNumber >= totalPages - 1

    fun <R> map(transform: (T) -> R): Page<R> = Page(
        content = content.map(transform),
        pageNumber = pageNumber,
        pageSize = pageSize,
        totalElements = totalElements,
        totalPages = totalPages
    )
}

interface UserRepository : Repository<User, UserId> {
    suspend fun findByEmail(email: Email): User?
    suspend fun findByRole(role: Role): List<User>
    suspend fun findByStatus(status: UserStatus): List<User>
    suspend fun findActiveUsers(): List<User>
    suspend fun searchByName(query: String): List<User>
    suspend fun updateStatus(id: UserId, status: UserStatus): Boolean
    suspend fun updateLastLogin(id: UserId, timestamp: LocalDateTime): Boolean
}

class InMemoryUserRepository : UserRepository {
    private val storage = ConcurrentHashMap<UserId, User>()
    private val mutex = Mutex()
    private val idCounter = AtomicLong(0)

    override suspend fun findById(id: UserId): User? = storage[id]

    override suspend fun findAll(): List<User> = storage.values.toList()

    override suspend fun findAll(page: Int, size: Int): Page<User> {
        val allUsers = storage.values.toList()
        val totalElements = allUsers.size.toLong()
        val totalPages = ((totalElements + size - 1) / size).toInt()
        val startIndex = page * size
        val endIndex = minOf(startIndex + size, allUsers.size)

        val content = if (startIndex < allUsers.size) {
            allUsers.subList(startIndex, endIndex)
        } else {
            emptyList()
        }

        return Page(content, page, size, totalElements, totalPages)
    }

    override suspend fun save(entity: User): User = mutex.withLock {
        val updated = entity.copy(updatedAt = LocalDateTime.now())
        storage[entity.id] = updated
        updated
    }

    override suspend fun saveAll(entities: List<User>): List<User> = mutex.withLock {
        entities.map { entity ->
            val updated = entity.copy(updatedAt = LocalDateTime.now())
            storage[entity.id] = updated
            updated
        }
    }

    override suspend fun delete(id: UserId): Boolean = mutex.withLock {
        storage.remove(id) != null
    }

    override suspend fun deleteAll(ids: List<UserId>): Int = mutex.withLock {
        ids.count { storage.remove(it) != null }
    }

    override suspend fun exists(id: UserId): Boolean = storage.containsKey(id)

    override suspend fun count(): Long = storage.size.toLong()

    override suspend fun findByEmail(email: Email): User? =
        storage.values.find { it.email == email }

    override suspend fun findByRole(role: Role): List<User> =
        storage.values.filter { it.role == role }

    override suspend fun findByStatus(status: UserStatus): List<User> =
        storage.values.filter { it.status == status }

    override suspend fun findActiveUsers(): List<User> =
        storage.values.filter { it.isActive() }

    override suspend fun searchByName(query: String): List<User> {
        val lowerQuery = query.lowercase()
        return storage.values.filter {
            it.profile.fullName.lowercase().contains(lowerQuery)
        }
    }

    override suspend fun updateStatus(id: UserId, status: UserStatus): Boolean = mutex.withLock {
        storage[id]?.let { user ->
            storage[id] = user.copy(status = status, updatedAt = LocalDateTime.now())
            true
        } ?: false
    }

    override suspend fun updateLastLogin(id: UserId, timestamp: LocalDateTime): Boolean = mutex.withLock {
        storage[id]?.let { user ->
            storage[id] = user.copy(lastLoginAt = timestamp, updatedAt = LocalDateTime.now())
            true
        } ?: false
    }
}

// =============================================================================
// EVENT SYSTEM - Domain Events with Flow
// =============================================================================

sealed interface DomainEvent {
    val eventId: String
    val timestamp: LocalDateTime
    val metadata: Map<String, String>
}

sealed class UserEvent : DomainEvent {
    override val eventId: String = UUID.randomUUID().toString()
    override val timestamp: LocalDateTime = LocalDateTime.now()
    override val metadata: Map<String, String> = emptyMap()

    data class Created(
        val user: User,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class Updated(
        val userId: UserId,
        val oldUser: User,
        val newUser: User,
        val changedFields: Set<String>,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class Deleted(
        val userId: UserId,
        val deletedBy: UserId? = null,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class StatusChanged(
        val userId: UserId,
        val oldStatus: UserStatus,
        val newStatus: UserStatus,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class RoleChanged(
        val userId: UserId,
        val oldRole: Role,
        val newRole: Role,
        val changedBy: UserId,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class LoggedIn(
        val userId: UserId,
        val ipAddress: String? = null,
        val userAgent: String? = null,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class LoggedOut(
        val userId: UserId,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class PasswordChanged(
        val userId: UserId,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()

    data class EmailVerified(
        val userId: UserId,
        val email: Email,
        override val metadata: Map<String, String> = emptyMap()
    ) : UserEvent()
}

sealed class SystemEvent : DomainEvent {
    override val eventId: String = UUID.randomUUID().toString()
    override val timestamp: LocalDateTime = LocalDateTime.now()
    override val metadata: Map<String, String> = emptyMap()

    data class Started(
        val version: String,
        override val metadata: Map<String, String> = emptyMap()
    ) : SystemEvent()

    data class Shutdown(
        val reason: String,
        override val metadata: Map<String, String> = emptyMap()
    ) : SystemEvent()

    data class HealthCheck(
        val status: HealthStatus,
        val details: Map<String, HealthStatus>,
        override val metadata: Map<String, String> = emptyMap()
    ) : SystemEvent()
}

enum class HealthStatus { HEALTHY, DEGRADED, UNHEALTHY }

interface EventHandler<E : DomainEvent> {
    suspend fun handle(event: E)
}

class EventBus {
    private val _events = MutableSharedFlow<DomainEvent>(
        replay = 0,
        extraBufferCapacity = 100,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val events: SharedFlow<DomainEvent> = _events.asSharedFlow()

    private val handlers = ConcurrentHashMap<Class<*>, MutableList<EventHandler<*>>>()

    suspend fun publish(event: DomainEvent) {
        _events.emit(event)
        dispatchToHandlers(event)
    }

    suspend fun publishAll(events: List<DomainEvent>) {
        events.forEach { publish(it) }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun dispatchToHandlers(event: DomainEvent) {
        handlers[event::class.java]?.forEach { handler ->
            try {
                (handler as EventHandler<DomainEvent>).handle(event)
            } catch (e: Exception) {
                println("Error handling event ${event::class.simpleName}: ${e.message}")
            }
        }
    }

    fun <E : DomainEvent> register(eventClass: Class<E>, handler: EventHandler<E>) {
        handlers.getOrPut(eventClass) { mutableListOf() }.add(handler)
    }

    inline fun <reified E : DomainEvent> register(handler: EventHandler<E>) {
        register(E::class.java, handler)
    }

    fun subscribe(scope: CoroutineScope): Job = scope.launch {
        events.collect { event ->
            println("[EventBus] Event received: ${event::class.simpleName}")
        }
    }

    inline fun <reified E : DomainEvent> subscribeToType(
        scope: CoroutineScope,
        crossinline handler: suspend (E) -> Unit
    ): Job = scope.launch {
        events.filterIsInstance<E>().collect { event ->
            try {
                handler(event)
            } catch (e: Exception) {
                println("Error handling ${E::class.simpleName}: ${e.message}")
            }
        }
    }
}

// Event sourcing support
data class EventEnvelope<E : DomainEvent>(
    val event: E,
    val sequenceNumber: Long,
    val aggregateId: String,
    val aggregateType: String
)

interface EventStore {
    suspend fun append(aggregateId: String, events: List<DomainEvent>): Long
    suspend fun load(aggregateId: String): List<EventEnvelope<*>>
    suspend fun loadFrom(aggregateId: String, fromSequence: Long): List<EventEnvelope<*>>
}

class InMemoryEventStore : EventStore {
    private val store = ConcurrentHashMap<String, MutableList<EventEnvelope<*>>>()
    private val sequenceCounter = AtomicLong(0)

    override suspend fun append(aggregateId: String, events: List<DomainEvent>): Long {
        val envelopes = events.map { event ->
            EventEnvelope(
                event = event,
                sequenceNumber = sequenceCounter.incrementAndGet(),
                aggregateId = aggregateId,
                aggregateType = event::class.java.simpleName
            )
        }
        store.getOrPut(aggregateId) { mutableListOf() }.addAll(envelopes)
        return envelopes.lastOrNull()?.sequenceNumber ?: 0
    }

    override suspend fun load(aggregateId: String): List<EventEnvelope<*>> =
        store[aggregateId]?.toList() ?: emptyList()

    override suspend fun loadFrom(aggregateId: String, fromSequence: Long): List<EventEnvelope<*>> =
        store[aggregateId]?.filter { it.sequenceNumber > fromSequence } ?: emptyList()
}

// =============================================================================
// SERVICE LAYER - Business Logic with Caching
// =============================================================================

interface Cache<K, V> {
    suspend fun get(key: K): V?
    suspend fun put(key: K, value: V, ttlSeconds: Long = 300)
    suspend fun remove(key: K): V?
    suspend fun clear()
    suspend fun size(): Int
}

class LRUCache<K, V>(private val maxSize: Int = 100) : Cache<K, V> {
    private data class CacheEntry<V>(
        val value: V,
        val expiresAt: LocalDateTime
    )

    private val storage = LinkedHashMap<K, CacheEntry<V>>(maxSize, 0.75f, true)
    private val mutex = Mutex()

    override suspend fun get(key: K): V? = mutex.withLock {
        storage[key]?.let { entry ->
            if (LocalDateTime.now().isBefore(entry.expiresAt)) {
                entry.value
            } else {
                storage.remove(key)
                null
            }
        }
    }

    override suspend fun put(key: K, value: V, ttlSeconds: Long) = mutex.withLock {
        if (storage.size >= maxSize) {
            val oldest = storage.keys.firstOrNull()
            oldest?.let { storage.remove(it) }
        }
        storage[key] = CacheEntry(value, LocalDateTime.now().plusSeconds(ttlSeconds))
    }

    override suspend fun remove(key: K): V? = mutex.withLock {
        storage.remove(key)?.value
    }

    override suspend fun clear() = mutex.withLock {
        storage.clear()
    }

    override suspend fun size(): Int = storage.size
}

class UserService(
    private val repository: UserRepository,
    private val eventBus: EventBus,
    private val cache: Cache<UserId, User> = LRUCache(1000)
) {
    suspend fun findById(id: UserId): Result<User> {
        cache.get(id)?.let { return Result.Success(it) }

        return repository.findById(id)?.let { user ->
            cache.put(id, user)
            Result.Success(user)
        } ?: Result.Failure("User not found: ${id.value}")
    }

    suspend fun findByEmail(email: Email): Result<User> {
        return repository.findByEmail(email)?.let { Result.Success(it) }
            ?: Result.Failure("User not found with email: ${email.value}")
    }

    suspend fun findAll(page: Int = 0, size: Int = 20): Page<User> =
        repository.findAll(page, size)

    suspend fun searchUsers(query: String): List<User> =
        repository.searchByName(query)

    suspend fun createUser(user: User): Result<User> {
        val violations = user.validate()
        if (violations.isNotEmpty()) {
            return Result.Failure(
                violations.joinToString(", ") { it.message },
                ValidationException(violations)
            )
        }

        repository.findByEmail(user.email)?.let {
            return Result.Failure(
                "Email already exists: ${user.email.value}",
                ConflictException("User", "email", user.email.value)
            )
        }

        val saved = repository.save(user)
        cache.put(saved.id, saved)
        eventBus.publish(UserEvent.Created(saved))

        return Result.Success(saved)
    }

    suspend fun updateUser(id: UserId, update: (User) -> User): Result<User> {
        val existing = repository.findById(id)
            ?: return Result.Failure("User not found: ${id.value}")

        val updated = update(existing).copy(
            updatedAt = LocalDateTime.now(),
            version = existing.version + 1
        )

        val violations = updated.validate()
        if (violations.isNotEmpty()) {
            return Result.Failure(violations.joinToString(", ") { it.message })
        }

        val saved = repository.save(updated)
        cache.put(saved.id, saved)

        val changedFields = detectChangedFields(existing, saved)
        eventBus.publish(UserEvent.Updated(id, existing, saved, changedFields))

        return Result.Success(saved)
    }

    private fun detectChangedFields(old: User, new: User): Set<String> {
        val changes = mutableSetOf<String>()
        if (old.email != new.email) changes.add("email")
        if (old.profile != new.profile) changes.add("profile")
        if (old.role != new.role) changes.add("role")
        if (old.status != new.status) changes.add("status")
        return changes
    }

    suspend fun changeStatus(id: UserId, newStatus: UserStatus): Result<User> {
        val existing = repository.findById(id)
            ?: return Result.Failure("User not found: ${id.value}")

        val oldStatus = existing.status
        repository.updateStatus(id, newStatus)

        val updated = existing.copy(status = newStatus, updatedAt = LocalDateTime.now())
        cache.put(id, updated)
        eventBus.publish(UserEvent.StatusChanged(id, oldStatus, newStatus))

        return Result.Success(updated)
    }

    suspend fun changeRole(id: UserId, newRole: Role, changedBy: UserId): Result<User> {
        val existing = repository.findById(id)
            ?: return Result.Failure("User not found: ${id.value}")

        val oldRole = existing.role
        val updated = repository.save(existing.copy(role = newRole, updatedAt = LocalDateTime.now()))

        cache.put(id, updated)
        eventBus.publish(UserEvent.RoleChanged(id, oldRole, newRole, changedBy))

        return Result.Success(updated)
    }

    suspend fun deleteUser(id: UserId, deletedBy: UserId? = null): Result<Boolean> {
        if (!repository.exists(id)) {
            return Result.Failure("User not found: ${id.value}")
        }

        val deleted = repository.delete(id)
        if (deleted) {
            cache.remove(id)
            eventBus.publish(UserEvent.Deleted(id, deletedBy))
        }

        return Result.Success(deleted)
    }

    suspend fun recordLogin(id: UserId, ipAddress: String? = null, userAgent: String? = null): Result<User> {
        val now = LocalDateTime.now()
        repository.updateLastLogin(id, now)

        val user = repository.findById(id)
            ?: return Result.Failure("User not found: ${id.value}")

        cache.put(id, user)
        eventBus.publish(UserEvent.LoggedIn(id, ipAddress, userAgent))

        return Result.Success(user)
    }

    fun clearCache() {
        runBlocking { cache.clear() }
    }
}

// =============================================================================
// COROUTINES PATTERNS - Advanced Flow and Channel Operations
// =============================================================================

// Retry with exponential backoff
suspend fun <T> retryWithBackoff(
    times: Int = 3,
    initialDelayMs: Long = 100,
    maxDelayMs: Long = 5000,
    factor: Double = 2.0,
    shouldRetry: (Throwable) -> Boolean = { true },
    block: suspend () -> T
): T {
    var currentDelay = initialDelayMs
    repeat(times - 1) { attempt ->
        try {
            return block()
        } catch (e: Exception) {
            if (!shouldRetry(e)) throw e
            println("Attempt ${attempt + 1} failed: ${e.message}. Retrying in ${currentDelay}ms")
            delay(currentDelay)
            currentDelay = (currentDelay * factor).toLong().coerceAtMost(maxDelayMs)
        }
    }
    return block()
}

// Timeout with fallback
suspend fun <T> withTimeoutOrDefault(
    timeoutMs: Long,
