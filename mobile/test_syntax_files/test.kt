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

    companion object {
        fun <T> success(data: T): Result<T> = Success(data)
        fun <T> failure(error: String): Result<T> = Failure(error)
        fun <T> failure(exception: Throwable): Result<T> =
            Failure(exception.message ?: "Unknown error", exception)

        inline fun <T> runCatching(block: () -> T): Result<T> = try {
            Success(block())
        } catch (e: Exception) {
            Failure(e.message ?: "Unknown error", e)
        }
    }
}

// =============================================================================
// EXTENSION FUNCTIONS & PROPERTIES
// =============================================================================

fun String.toSlug(): String = this
    .lowercase()
    .replace(Regex("[^a-z0-9\\s-]"), "")
    .replace(Regex("\\s+"), "-")
    .trim('-')

fun String.truncate(maxLength: Int, suffix: String = "..."): String =
    if (length <= maxLength) this
    else take(maxLength - suffix.length) + suffix

val String.wordCount: Int get() = split(Regex("\\s+")).filter { it.isNotBlank() }.size

fun <T> List<T>.secondOrNull(): T? = if (size >= 2) this[1] else null

inline fun <T> List<T>.forEachIndexedReversed(action: (Int, T) -> Unit) {
    for (i in lastIndex downTo 0) {
        action(i, this[i])
    }
}

fun <T : Comparable<T>> List<T>.isSorted(): Boolean =
    zipWithNext().all { (a, b) -> a <= b }

fun <K, V> Map<K, V>.merge(other: Map<K, V>, resolver: (V, V) -> V): Map<K, V> {
    val result = this.toMutableMap()
    for ((key, value) in other) {
        result[key] = if (key in result) resolver(result[key]!!, value) else value
    }
    return result
}

// =============================================================================
// DATA CLASSES & SEALED INTERFACES
// =============================================================================

data class User(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val email: String,
    val role: UserRole = UserRole.USER,
    val permissions: Set<String> = emptySet(),
    val createdAt: LocalDateTime = LocalDateTime.now(),
    val metadata: Map<String, Any?> = emptyMap()
) {
    fun hasPermission(permission: String): Boolean =
        role == UserRole.ADMIN || permission in permissions

    fun withRole(newRole: UserRole): User = copy(role = newRole)
}

enum class UserRole(val level: Int) {
    GUEST(0),
    USER(1),
    MODERATOR(2),
    ADMIN(3);

    fun canAccess(requiredLevel: UserRole): Boolean = this.level >= requiredLevel.level

    companion object {
        fun fromString(value: String): UserRole =
            entries.find { it.name.equals(value, ignoreCase = true) }
                ?: throw IllegalArgumentException("Unknown role: $value")
    }
}

sealed interface Event {
    val timestamp: LocalDateTime
    val source: String
}

data class UserCreated(
    val user: User,
    override val timestamp: LocalDateTime = LocalDateTime.now(),
    override val source: String = "user-service"
) : Event

data class UserUpdated(
    val userId: String,
    val changes: Map<String, Any?>,
    override val timestamp: LocalDateTime = LocalDateTime.now(),
    override val source: String = "user-service"
) : Event

data class UserDeleted(
    val userId: String,
    val reason: String?,
    override val timestamp: LocalDateTime = LocalDateTime.now(),
    override val source: String = "user-service"
) : Event

// =============================================================================
// VALUE CLASSES & INLINE CLASSES
// =============================================================================

@JvmInline
value class Email(val value: String) {
    init {
        require(value.contains("@")) { "Invalid email: $value" }
    }

    val domain: String get() = value.substringAfter("@")
    val localPart: String get() = value.substringBefore("@")
}

@JvmInline
value class Password(private val value: String) {
    init {
        require(value.length >= 8) { "Password must be at least 8 characters" }
    }

    val strength: PasswordStrength get() = when {
        value.length >= 16 && value.any { it.isDigit() } && value.any { !it.isLetterOrDigit() } ->
            PasswordStrength.STRONG
        value.length >= 12 && value.any { it.isDigit() } ->
            PasswordStrength.MEDIUM
        else -> PasswordStrength.WEAK
    }
}

enum class PasswordStrength { WEAK, MEDIUM, STRONG }

@JvmInline
value class Percentage(val value: Double) {
    init {
        require(value in 0.0..100.0) { "Percentage must be 0-100, got: $value" }
    }

    operator fun plus(other: Percentage): Percentage =
        Percentage((value + other.value).coerceIn(0.0, 100.0))

    operator fun times(factor: Double): Percentage =
        Percentage((value * factor).coerceIn(0.0, 100.0))

    override fun toString(): String = "${value}%"
}

// =============================================================================
// DELEGATION PATTERN
// =============================================================================

interface Logger {
    fun log(level: LogLevel, message: String)
    fun debug(message: String) = log(LogLevel.DEBUG, message)
    fun info(message: String) = log(LogLevel.INFO, message)
    fun warn(message: String) = log(LogLevel.WARN, message)
    fun error(message: String) = log(LogLevel.ERROR, message)
}

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

class ConsoleLogger(private val tag: String) : Logger {
    override fun log(level: LogLevel, message: String) {
        val timestamp = LocalDateTime.now()
        println("[$timestamp] [$level] [$tag] $message")
    }
}

class LoggerWithPrefix(
    private val prefix: String,
    private val delegate: Logger
) : Logger by delegate {
    override fun log(level: LogLevel, message: String) {
        delegate.log(level, "$prefix $message")
    }
}

// Delegated properties
class ObservableProperty<T>(initialValue: T) {
    private val listeners = mutableListOf<(T, T) -> Unit>()

    var value: T = initialValue
        set(new) {
            val old = field
            field = new
            listeners.forEach { it(old, new) }
        }

    fun onChange(listener: (T, T) -> Unit) {
        listeners.add(listener)
    }
}

class UserPreferences {
    var theme: String by Delegates.observable("light") { _, old, new ->
        println("Theme changed: $old -> $new")
    }

    var fontSize: Int by Delegates.vetoable(14) { _, _, new ->
        new in 8..72
    }

    val computedProperty: String by lazy {
        println("Computing expensive property...")
        "Computed at ${LocalDateTime.now()}"
    }
}

// =============================================================================
// COROUTINES & FLOW
// =============================================================================

class UserRepository(private val logger: Logger) {
    private val users = ConcurrentHashMap<String, User>()
    private val mutex = Mutex()
    private val _events = MutableSharedFlow<Event>(
        replay = 0,
        extraBufferCapacity = 64
    )
    val events: SharedFlow<Event> = _events.asSharedFlow()

    suspend fun create(user: User): Result<User> = mutex.withLock {
        if (users.containsKey(user.id)) {
            return@withLock Result.failure("User already exists: ${user.id}")
        }
        users[user.id] = user
        logger.info("Created user: ${user.name}")
        _events.emit(UserCreated(user))
        Result.success(user)
    }

    suspend fun findById(id: String): Result<User> = withContext(Dispatchers.IO) {
        val user = users[id]
        if (user != null) Result.success(user)
        else Result.failure("User not found: $id")
    }

    suspend fun findAll(): List<User> = withContext(Dispatchers.IO) {
        users.values.toList()
    }

    fun searchByName(query: String): Flow<User> = flow {
        users.values
            .filter { it.name.contains(query, ignoreCase = true) }
            .forEach { emit(it) }
    }.flowOn(Dispatchers.IO)

    suspend fun update(id: String, transform: (User) -> User): Result<User> = mutex.withLock {
        val existing = users[id] ?: return@withLock Result.failure("User not found: $id")
        val updated = transform(existing)
        users[id] = updated
        logger.info("Updated user: ${updated.name}")
        _events.emit(UserUpdated(id, mapOf("user" to updated)))
        Result.success(updated)
    }

    suspend fun delete(id: String, reason: String? = null): Result<Unit> = mutex.withLock {
        users.remove(id) ?: return@withLock Result.failure("User not found: $id")
        logger.info("Deleted user: $id")
        _events.emit(UserDeleted(id, reason))
        Result.success(Unit)
    }
}

// =============================================================================
// DSL BUILDER
// =============================================================================

@DslMarker
annotation class HtmlDsl

@HtmlDsl
class HtmlBuilder {
    private val elements = mutableListOf<String>()

    fun head(block: HeadBuilder.() -> Unit) {
        elements.add(HeadBuilder().apply(block).build())
    }

    fun body(block: BodyBuilder.() -> Unit) {
        elements.add(BodyBuilder().apply(block).build())
    }

    fun build(): String = buildString {
        appendLine("<!DOCTYPE html>")
        appendLine("<html>")
        elements.forEach { appendLine(it) }
        appendLine("</html>")
    }
}

@HtmlDsl
class HeadBuilder {
    private val elements = mutableListOf<String>()

    fun title(text: String) { elements.add("  <title>$text</title>") }
    fun meta(name: String, content: String) {
        elements.add("  <meta name=\"$name\" content=\"$content\">")
    }
    fun link(rel: String, href: String) {
        elements.add("  <link rel=\"$rel\" href=\"$href\">")
    }

    fun build(): String = buildString {
        appendLine("<head>")
        elements.forEach { appendLine(it) }
        appendLine("</head>")
    }
}

@HtmlDsl
class BodyBuilder {
    private val elements = mutableListOf<String>()

    fun h1(text: String) { elements.add("  <h1>$text</h1>") }
    fun h2(text: String) { elements.add("  <h2>$text</h2>") }
    fun p(text: String) { elements.add("  <p>$text</p>") }
    fun div(className: String? = null, block: BodyBuilder.() -> Unit) {
        val cls = className?.let { " class=\"$it\"" } ?: ""
        val inner = BodyBuilder().apply(block).build()
        elements.add("  <div$cls>\n$inner\n  </div>")
    }
    fun ul(block: ListBuilder.() -> Unit) {
        elements.add(ListBuilder().apply(block).build())
    }

    fun build(): String = buildString {
        appendLine("<body>")
        elements.forEach { appendLine(it) }
        appendLine("</body>")
    }
}

@HtmlDsl
class ListBuilder {
    private val items = mutableListOf<String>()
    fun li(text: String) { items.add("    <li>$text</li>") }
    fun build(): String = buildString {
        appendLine("  <ul>")
        items.forEach { appendLine(it) }
        appendLine("  </ul>")
    }
}

fun html(block: HtmlBuilder.() -> Unit): String = HtmlBuilder().apply(block).build()

// =============================================================================
// SCOPE FUNCTIONS & IDIOMATIC KOTLIN
// =============================================================================

fun scopeFunctionsDemo() {
    // let - null-safe transformation
    val name: String? = "Kotlin"
    val length = name?.let { it.length } ?: 0

    // run - object configuration and computation
    val hexString = StringBuilder().run {
        for (i in 0..15) {
            append(i.toString(16))
        }
        toString()
    }

    // with - grouping function calls
    val numbers = mutableListOf(1, 2, 3, 4, 5)
    val summary = with(numbers) {
        "Sum: ${sum()}, Size: $size, Max: ${maxOrNull()}"
    }

    // apply - object configuration
    val user = User(name = "Alice", email = "alice@example.com").apply {
        println("Created user: $name with email: $email")
    }

    // also - additional actions
    val sortedList = numbers
        .also { println("Before sort: $it") }
        .sorted()
        .also { println("After sort: $it") }

    // takeIf / takeUnless
    val positiveNumber = (-5).takeIf { it > 0 }  // null
    val nonEmptyString = "hello".takeUnless { it.isBlank() }  // "hello"

    // Destructuring
    val (id, userName, email) = User(name = "Bob", email = "bob@example.com")
    println("$id: $userName ($email)")

    // when expression with multiple conditions
    val statusMessage = when {
        numbers.isEmpty() -> "Empty list"
        numbers.size == 1 -> "Single element: ${numbers.first()}"
        numbers.all { it > 0 } -> "All positive"
        numbers.any { it < 0 } -> "Contains negative"
        else -> "Mixed values"
    }
}

// =============================================================================
// GENERICS & VARIANCE
// =============================================================================

interface Repository<T : Any> {
    suspend fun findById(id: String): T?
    suspend fun findAll(): List<T>
    suspend fun save(entity: T): T
    suspend fun delete(id: String): Boolean
}

class InMemoryRepository<T : Any>(
    private val idExtractor: (T) -> String
) : Repository<T> {
    private val store = ConcurrentHashMap<String, T>()

    override suspend fun findById(id: String): T? = store[id]
    override suspend fun findAll(): List<T> = store.values.toList()
    override suspend fun save(entity: T): T {
        store[idExtractor(entity)] = entity
        return entity
    }
    override suspend fun delete(id: String): Boolean = store.remove(id) != null
}

// Variance annotations
interface Producer<out T> {
    fun produce(): T
}

interface Consumer<in T> {
    fun consume(item: T)
}

interface Transformer<in I, out O> {
    fun transform(input: I): O
}

class StringToIntTransformer : Transformer<String, Int> {
    override fun transform(input: String): Int = input.toIntOrNull() ?: 0
}

// Type-safe builders with generics
class TypeSafeBuilder<T> {
    private val properties = mutableMapOf<String, Any?>()

    operator fun String.invoke(value: Any?) {
        properties[this] = value
    }

    fun build(): Map<String, Any?> = properties.toMap()
}

fun <T> buildConfig(block: TypeSafeBuilder<T>.() -> Unit): Map<String, Any?> =
    TypeSafeBuilder<T>().apply(block).build()

// =============================================================================
// COROUTINE PATTERNS
// =============================================================================

class RateLimiter(
    private val maxRequests: Int,
    private val windowDuration: kotlin.time.Duration
) {
    private val requests = AtomicLong(0)
    private val windowStart = AtomicLong(System.currentTimeMillis())

    suspend fun <T> execute(block: suspend () -> T): T {
        while (true) {
            val now = System.currentTimeMillis()
            val start = windowStart.get()
            if (now - start > windowDuration.inWholeMilliseconds) {
                windowStart.compareAndSet(start, now)
                requests.set(0)
            }
            if (requests.incrementAndGet() <= maxRequests) {
                return block()
            }
            requests.decrementAndGet()
            delay(100.milliseconds)
        }
    }
}

suspend fun <T> retryWithBackoff(
    maxAttempts: Int = 3,
    initialDelay: kotlin.time.Duration = 100.milliseconds,
    maxDelay: kotlin.time.Duration = 10.seconds,
    factor: Double = 2.0,
    block: suspend (attempt: Int) -> T
): T {
    var currentDelay = initialDelay
    var lastException: Exception? = null

    repeat(maxAttempts) { attempt ->
        try {
            return block(attempt + 1)
        } catch (e: Exception) {
            lastException = e
            if (attempt < maxAttempts - 1) {
                delay(currentDelay)
                currentDelay = (currentDelay * factor).coerceAtMost(maxDelay)
            }
        }
    }
    throw lastException ?: IllegalStateException("All retry attempts failed")
}

// Flow operators
fun <T> Flow<T>.chunked(size: Int): Flow<List<T>> = flow {
    val buffer = mutableListOf<T>()
    collect { value ->
        buffer.add(value)
        if (buffer.size >= size) {
            emit(buffer.toList())
            buffer.clear()
        }
    }
    if (buffer.isNotEmpty()) {
        emit(buffer.toList())
    }
}

fun <T> Flow<T>.throttleFirst(windowDuration: kotlin.time.Duration): Flow<T> = flow {
    var lastEmitTime = 0L
    collect { value ->
        val now = System.currentTimeMillis()
        if (now - lastEmitTime >= windowDuration.inWholeMilliseconds) {
            lastEmitTime = now
            emit(value)
        }
    }
}

// =============================================================================
// COMPANION OBJECT & FACTORY PATTERNS
// =============================================================================

data class HttpResponse(
    val statusCode: Int,
    val body: String,
    val headers: Map<String, String> = emptyMap()
) {
    val isSuccess: Boolean get() = statusCode in 200..299
    val isClientError: Boolean get() = statusCode in 400..499
    val isServerError: Boolean get() = statusCode in 500..599

    companion object {
        fun ok(body: String = "") = HttpResponse(200, body)
        fun created(body: String = "") = HttpResponse(201, body)
        fun noContent() = HttpResponse(204, "")
        fun badRequest(body: String = "Bad Request") = HttpResponse(400, body)
        fun unauthorized(body: String = "Unauthorized") = HttpResponse(401, body)
        fun forbidden(body: String = "Forbidden") = HttpResponse(403, body)
        fun notFound(body: String = "Not Found") = HttpResponse(404, body)
        fun serverError(body: String = "Internal Server Error") = HttpResponse(500, body)
    }
}

// =============================================================================
// MAIN FUNCTION
// =============================================================================

fun main() = runBlocking {
    println("=== Kotlin Syntax Highlighting Test ===\n")

    // Result type
    val result = Result.runCatching { 42 / 2 }
    result.onSuccess { println("Result: $it") }
          .onFailure { msg, _ -> println("Error: $msg") }

    // Extension functions
    println("hello-world".toSlug())
    println("A very long string that should be truncated".truncate(20))
    println("Hello World Kotlin".wordCount)

    // Value classes
    val email = Email("alice@example.com")
    println("Email domain: ${email.domain}")

    // User & scope functions
    scopeFunctionsDemo()

    // Repository
    val logger = ConsoleLogger("main")
    val repo = UserRepository(logger)

    val user = User(name = "Alice", email = "alice@example.com", role = UserRole.ADMIN)
    repo.create(user)

    repo.findById(user.id).onSuccess { println("Found: ${it.name}") }

    // Flow
    repo.searchByName("Ali")
        .collect { println("Search result: ${it.name}") }

    // Event processing
    launch {
        repo.events
            .take(3)
            .collect { event ->
                when (event) {
                    is UserCreated -> println("Event: User created: ${event.user.name}")
                    is UserUpdated -> println("Event: User updated: ${event.userId}")
                    is UserDeleted -> println("Event: User deleted: ${event.userId}")
                }
            }
    }

    // DSL
    val page = html {
        head {
            title("Kotlin DSL Demo")
            meta("viewport", "width=device-width, initial-scale=1")
        }
        body {
            h1("Welcome to Kotlin!")
            p("This page was generated using a type-safe DSL builder.")
            div("container") {
                h2("Features")
                ul {
                    li("Coroutines & Flow")
                    li("Sealed classes & interfaces")
                    li("Extension functions")
                    li("Type-safe builders")
                }
            }
        }
    }
    println(page)

    // Rate limiter
    val limiter = RateLimiter(maxRequests = 5, windowDuration = 1.seconds)
    repeat(3) { i ->
        limiter.execute {
            println("Request $i executed")
        }
    }

    // Retry with backoff
    try {
        val value = retryWithBackoff(maxAttempts = 3) { attempt ->
            println("Attempt $attempt")
            if (attempt < 3) throw RuntimeException("Simulated failure")
            "Success on attempt $attempt"
        }
        println(value)
    } catch (e: Exception) {
        println("All retries failed: ${e.message}")
    }

    // HttpResponse factory
    val response = HttpResponse.ok("""{"status": "healthy"}""")
    println("Response: ${response.statusCode} - ${response.body}")

    // Generic config builder
    val config = buildConfig<Any> {
        "host"("localhost")
        "port"(8080)
        "debug"(true)
    }
    println("Config: $config")

    println("\n=== Done ===")
}

