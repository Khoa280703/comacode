// Java 21+ Comprehensive Sample File - Modern Java Patterns
// This file demonstrates modern Java features including records, sealed classes,
// pattern matching, virtual threads, and functional programming patterns.

import java.lang.annotation.*;
import java.lang.reflect.*;
import java.time.*;
import java.time.format.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.concurrent.locks.*;
import java.util.function.*;
import java.util.regex.*;
import java.util.stream.*;

// ============================================================================
// CUSTOM ANNOTATIONS
// ============================================================================

/**
 * Marks a field as validated during entity construction.
 * Validation rules are specified via the annotation parameters.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
@interface Validated {
    String message() default "Validation failed";
    boolean required() default true;
    int minLength() default 0;
    int maxLength() default Integer.MAX_VALUE;
    String pattern() default "";
}

/**
 * Marks a method as cacheable with TTL configuration.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
@interface Cacheable {
    String key() default "";
    long ttlSeconds() default 300;
    boolean refreshOnAccess() default false;
}

/**
 * Marks a method for async execution.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
@interface Async {
    int timeout() default 30000;
    boolean useVirtualThread() default true;
}

/**
 * Marks an entity for auditing.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
@interface Auditable {
    String createdByField() default "createdBy";
    String createdAtField() default "createdAt";
    String modifiedByField() default "modifiedBy";
    String modifiedAtField() default "modifiedAt";
}

/**
 * Marks a method as transactional.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
@interface Transactional {
    boolean readOnly() default false;
    int isolationLevel() default 2; // READ_COMMITTED
    Class<? extends Exception>[] rollbackFor() default {};
}

/**
 * Rate limiting annotation for methods.
 */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
@interface RateLimited {
    int maxRequests() default 100;
    int windowSeconds() default 60;
    String key() default "";
}

// ============================================================================
// CUSTOM EXCEPTIONS
// ============================================================================

/**
 * Base exception for all domain-specific exceptions.
 */
class DomainException extends RuntimeException {
    private final String errorCode;
    private final Map<String, Object> context;
    private final Instant timestamp;

    public DomainException(String message, String errorCode) {
        this(message, errorCode, Map.of(), null);
    }

    public DomainException(String message, String errorCode, Map<String, Object> context) {
        this(message, errorCode, context, null);
    }

    public DomainException(String message, String errorCode, Map<String, Object> context, Throwable cause) {
        super(message, cause);
        this.errorCode = Objects.requireNonNull(errorCode);
        this.context = Collections.unmodifiableMap(new HashMap<>(context));
        this.timestamp = Instant.now();
    }

    public String getErrorCode() { return errorCode; }
    public Map<String, Object> getContext() { return context; }
    public Instant getTimestamp() { return timestamp; }

    @Override
    public String toString() {
        return STR."DomainException[code=\{errorCode}, message=\{getMessage()}, context=\{context}]";
    }
}

/**
 * Exception for entity not found scenarios.
 */
class EntityNotFoundException extends DomainException {
    public EntityNotFoundException(String entityType, Object id) {
        super(
            STR."Entity '\{entityType}' with id '\{id}' not found",
            "ENTITY_NOT_FOUND",
            Map.of("entityType", entityType, "id", id)
        );
    }
}

/**
 * Exception for validation failures.
 */
class ValidationException extends DomainException {
    private final List<ValidationError> errors;

    public ValidationException(List<ValidationError> errors) {
        super(
            "Validation failed with " + errors.size() + " error(s)",
            "VALIDATION_FAILED",
            Map.of("errorCount", errors.size())
        );
        this.errors = List.copyOf(errors);
    }

    public List<ValidationError> getErrors() { return errors; }
}

/**
 * Exception for duplicate entity scenarios.
 */
class DuplicateEntityException extends DomainException {
    public DuplicateEntityException(String entityType, String field, Object value) {
        super(
            STR."Entity '\{entityType}' with \{field}='\{value}' already exists",
            "DUPLICATE_ENTITY",
            Map.of("entityType", entityType, "field", field, "value", value)
        );
    }
}

/**
 * Exception for authorization failures.
 */
class AuthorizationException extends DomainException {
    public AuthorizationException(String action, String resource) {
        super(
            STR."Not authorized to perform '\{action}' on '\{resource}'",
            "UNAUTHORIZED",
            Map.of("action", action, "resource", resource)
        );
    }
}

/**
 * Exception for concurrent modification conflicts.
 */
class ConcurrencyException extends DomainException {
    public ConcurrencyException(String entityType, Object id, long expectedVersion, long actualVersion) {
        super(
            STR."Concurrent modification detected for \{entityType} with id \{id}",
            "CONCURRENT_MODIFICATION",
            Map.of("entityType", entityType, "id", id,
                   "expectedVersion", expectedVersion, "actualVersion", actualVersion)
        );
    }
}

/**
 * Represents a single validation error.
 */
record ValidationError(String field, String message, Object rejectedValue) {}

// ============================================================================
// RESULT AND OPTION TYPES
// ============================================================================

/**
 * A Result type representing either a successful value or a failure.
 * Uses sealed interfaces and pattern matching for type-safe error handling.
 */
sealed interface Result<T> permits Success, Failure {

    /**
     * Returns the value if successful, throws otherwise.
     */
    default T getOrThrow() {
        return switch (this) {
            case Success<T> s -> s.value();
            case Failure<T> f -> throw new DomainException(f.error(), f.errorCode());
        };
    }

    /**
     * Returns the value if successful, or the provided default.
     */
    default T getOrElse(T defaultValue) {
        return switch (this) {
            case Success<T> s -> s.value();
            case Failure<T> f -> defaultValue;
        };
    }

    /**
     * Returns the value if successful, or computes a default.
     */
    default T getOrElseGet(Supplier<? extends T> supplier) {
        return switch (this) {
            case Success<T> s -> s.value();
            case Failure<T> f -> supplier.get();
        };
    }

    /**
     * Maps the successful value using the provided function.
     */
    default <U> Result<U> map(Function<? super T, ? extends U> mapper) {
        return switch (this) {
            case Success<T> s -> new Success<>(mapper.apply(s.value()));
            case Failure<T> f -> new Failure<>(f.error(), f.errorCode());
        };
    }

    /**
     * FlatMaps the successful value using the provided function.
     */
    default <U> Result<U> flatMap(Function<? super T, ? extends Result<U>> mapper) {
        return switch (this) {
            case Success<T> s -> mapper.apply(s.value());
            case Failure<T> f -> new Failure<>(f.error(), f.errorCode());
        };
    }

    /**
     * Applies a function if successful.
     */
    default Result<T> peek(Consumer<? super T> consumer) {
        if (this instanceof Success<T> s) {
            consumer.accept(s.value());
        }
        return this;
    }

    /**
     * Applies a function if failed.
     */
    default Result<T> peekError(Consumer<String> consumer) {
        if (this instanceof Failure<T> f) {
            consumer.accept(f.error());
        }
        return this;
    }

    /**
     * Recovers from a failure using the provided function.
     */
    default Result<T> recover(Function<String, ? extends T> recoveryFn) {
        return switch (this) {
            case Success<T> s -> s;
            case Failure<T> f -> new Success<>(recoveryFn.apply(f.error()));
        };
    }

    /**
     * Combines two Results into a tuple Result.
     */
    default <U> Result<Tuple2<T, U>> zip(Result<U> other) {
        return switch (this) {
            case Success<T> s1 -> switch (other) {
                case Success<U> s2 -> new Success<>(new Tuple2<>(s1.value(), s2.value()));
                case Failure<U> f -> new Failure<>(f.error(), f.errorCode());
            };
            case Failure<T> f -> new Failure<>(f.error(), f.errorCode());
        };
    }

    /**
     * Checks if the result is successful.
     */
    default boolean isSuccess() {
        return this instanceof Success<T>;
    }

    /**
     * Checks if the result is a failure.
     */
    default boolean isFailure() {
        return this instanceof Failure<T>;
    }

    /**
     * Converts to Optional.
     */
    default Optional<T> toOptional() {
        return switch (this) {
            case Success<T> s -> Optional.of(s.value());
            case Failure<T> f -> Optional.empty();
        };
    }

    /**
     * Converts to Option.
     */
    default Option<T> toOption() {
        return switch (this) {
            case Success<T> s -> new Some<>(s.value());
            case Failure<T> f -> new None<>();
        };
    }

    /**
     * Creates a successful Result.
     */
    static <T> Result<T> success(T value) {
        return new Success<>(value);
    }

    /**
     * Creates a failed Result.
     */
    static <T> Result<T> failure(String error) {
        return new Failure<>(error, "GENERIC_ERROR");
    }

    /**
     * Creates a failed Result with error code.
     */
    static <T> Result<T> failure(String error, String errorCode) {
        return new Failure<>(error, errorCode);
    }

    /**
     * Wraps a potentially throwing operation in a Result.
     */
    static <T> Result<T> of(ThrowingSupplier<T> supplier) {
        try {
            return new Success<>(supplier.get());
        } catch (Exception e) {
            return new Failure<>(e.getMessage(), "EXCEPTION");
        }
    }

    /**
     * Collects multiple Results into a single Result of List.
     */
    static <T> Result<List<T>> sequence(List<Result<T>> results) {
        List<T> values = new ArrayList<>();
        for (var result : results) {
            switch (result) {
                case Success<T> s -> values.add(s.value());
                case Failure<T> f -> { return new Failure<>(f.error(), f.errorCode()); }
            }
        }
        return new Success<>(List.copyOf(values));
    }
}

record Success<T>(T value) implements Result<T> {
    public Success {
        Objects.requireNonNull(value, "Success value cannot be null");
    }
}

record Failure<T>(String error, String errorCode) implements Result<T> {
    public Failure {
        Objects.requireNonNull(error, "Error message cannot be null");
        if (errorCode == null) {
            errorCode = "GENERIC_ERROR";
        }
    }

    public Failure(String error) {
        this(error, "GENERIC_ERROR");
    }
}

/**
 * A functional interface for suppliers that can throw exceptions.
 */
@FunctionalInterface
interface ThrowingSupplier<T> {
    T get() throws Exception;
}

/**
 * An Option type representing presence or absence of a value.
 */
sealed interface Option<T> permits Some, None {

    default T getOrElse(T defaultValue) {
        return switch (this) {
            case Some<T> s -> s.value();
            case None<T> n -> defaultValue;
        };
    }

    default T getOrElseGet(Supplier<? extends T> supplier) {
        return switch (this) {
            case Some<T> s -> s.value();
            case None<T> n -> supplier.get();
        };
    }

    default <U> Option<U> map(Function<? super T, ? extends U> mapper) {
        return switch (this) {
            case Some<T> s -> new Some<>(mapper.apply(s.value()));
            case None<T> n -> new None<>();
        };
    }

    default <U> Option<U> flatMap(Function<? super T, ? extends Option<U>> mapper) {
        return switch (this) {
            case Some<T> s -> mapper.apply(s.value());
            case None<T> n -> new None<>();
        };
    }

    default Option<T> filter(Predicate<? super T> predicate) {
        return switch (this) {
            case Some<T> s -> predicate.test(s.value()) ? s : new None<>();
            case None<T> n -> n;
        };
    }

    default void ifPresent(Consumer<? super T> consumer) {
        if (this instanceof Some<T> s) {
            consumer.accept(s.value());
        }
    }

    default void ifPresentOrElse(Consumer<? super T> consumer, Runnable emptyAction) {
        switch (this) {
            case Some<T> s -> consumer.accept(s.value());
            case None<T> n -> emptyAction.run();
        }
    }

    default boolean isPresent() {
        return this instanceof Some<T>;
    }

    default boolean isEmpty() {
        return this instanceof None<T>;
    }

    default Optional<T> toOptional() {
        return switch (this) {
            case Some<T> s -> Optional.of(s.value());
            case None<T> n -> Optional.empty();
        };
    }

    default Stream<T> stream() {
        return switch (this) {
            case Some<T> s -> Stream.of(s.value());
            case None<T> n -> Stream.empty();
        };
    }

    static <T> Option<T> of(T value) {
        return value != null ? new Some<>(value) : new None<>();
    }

    static <T> Option<T> ofNullable(T value) {
        return value != null ? new Some<>(value) : new None<>();
    }

    static <T> Option<T> none() {
        return new None<>();
    }

    static <T> Option<T> fromOptional(Optional<T> optional) {
        return optional.map(Some::new).orElseGet(None::new);
    }
}

record Some<T>(T value) implements Option<T> {
    public Some {
        Objects.requireNonNull(value, "Some value cannot be null");
    }
}

record None<T>() implements Option<T> {}

// ============================================================================
// TUPLE TYPES
// ============================================================================

/**
 * A tuple of two elements.
 */
record Tuple2<A, B>(A first, B second) {
    public <C> Tuple2<C, B> mapFirst(Function<? super A, ? extends C> mapper) {
        return new Tuple2<>(mapper.apply(first), second);
    }

    public <C> Tuple2<A, C> mapSecond(Function<? super B, ? extends C> mapper) {
        return new Tuple2<>(first, mapper.apply(second));
    }

    public <C, D> Tuple2<C, D> bimap(
        Function<? super A, ? extends C> firstMapper,
        Function<? super B, ? extends D> secondMapper
    ) {
        return new Tuple2<>(firstMapper.apply(first), secondMapper.apply(second));
    }

    public Tuple2<B, A> swap() {
        return new Tuple2<>(second, first);
    }
}

/**
 * A tuple of three elements.
 */
record Tuple3<A, B, C>(A first, B second, C third) {
    public <D> Tuple3<D, B, C> mapFirst(Function<? super A, ? extends D> mapper) {
        return new Tuple3<>(mapper.apply(first), second, third);
    }

    public <D> Tuple3<A, D, C> mapSecond(Function<? super B, ? extends D> mapper) {
        return new Tuple3<>(first, mapper.apply(second), third);
    }

    public <D> Tuple3<A, B, D> mapThird(Function<? super C, ? extends D> mapper) {
        return new Tuple3<>(first, second, mapper.apply(third));
    }
}

// ============================================================================
// EITHER TYPE
// ============================================================================

/**
 * An Either type representing one of two possible values.
 */
sealed interface Either<L, R> permits Left, Right {

    default boolean isLeft() {
        return this instanceof Left<L, R>;
    }

    default boolean isRight() {
        return this instanceof Right<L, R>;
    }

    default Option<L> getLeft() {
        return switch (this) {
            case Left<L, R> l -> new Some<>(l.value());
            case Right<L, R> r -> new None<>();
        };
    }

    default Option<R> getRight() {
        return switch (this) {
            case Left<L, R> l -> new None<>();
            case Right<L, R> r -> new Some<>(r.value());
        };
    }

    default <T> Either<L, T> map(Function<? super R, ? extends T> mapper) {
        return switch (this) {
            case Left<L, R> l -> new Left<>(l.value());
            case Right<L, R> r -> new Right<>(mapper.apply(r.value()));
        };
    }

    default <T> Either<T, R> mapLeft(Function<? super L, ? extends T> mapper) {
        return switch (this) {
            case Left<L, R> l -> new Left<>(mapper.apply(l.value()));
            case Right<L, R> r -> new Right<>(r.value());
        };
    }

    default <T> Either<L, T> flatMap(Function<? super R, ? extends Either<L, T>> mapper) {
        return switch (this) {
            case Left<L, R> l -> new Left<>(l.value());
            case Right<L, R> r -> mapper.apply(r.value());
        };
    }

    default R getOrElse(R defaultValue) {
        return switch (this) {
            case Left<L, R> l -> defaultValue;
            case Right<L, R> r -> r.value();
        };
    }

    default <T> T fold(Function<? super L, ? extends T> leftMapper, Function<? super R, ? extends T> rightMapper) {
        return switch (this) {
            case Left<L, R> l -> leftMapper.apply(l.value());
            case Right<L, R> r -> rightMapper.apply(r.value());
        };
    }

    default Either<R, L> swap() {
        return switch (this) {
            case Left<L, R> l -> new Right<>(l.value());
            case Right<L, R> r -> new Left<>(r.value());
        };
    }

    static <L, R> Either<L, R> left(L value) {
        return new Left<>(value);
    }

    static <L, R> Either<L, R> right(R value) {
        return new Right<>(value);
    }
}

record Left<L, R>(L value) implements Either<L, R> {}
record Right<L, R>(R value) implements Either<L, R> {}

// ============================================================================
// DOMAIN ENTITIES
// ============================================================================

/**
 * Role enumeration with permissions.
 */
enum Role {
    SUPER_ADMIN(Set.of(Permission.values())),
    ADMIN(Set.of(Permission.CREATE, Permission.READ, Permission.UPDATE, Permission.DELETE, Permission.MANAGE_USERS)),
    MANAGER(Set.of(Permission.CREATE, Permission.READ, Permission.UPDATE, Permission.MANAGE_TEAM)),
    USER(Set.of(Permission.CREATE, Permission.READ, Permission.UPDATE_OWN)),
    GUEST(Set.of(Permission.READ));

    private final Set<Permission> permissions;

    Role(Set<Permission> permissions) {
        this.permissions = Collections.unmodifiableSet(EnumSet.copyOf(permissions));
    }

    public Set<Permission> getPermissions() { return permissions; }

    public boolean hasPermission(Permission permission) {
        return permissions.contains(permission);
    }

    public boolean canModify() {
        return hasPermission(Permission.UPDATE) || hasPermission(Permission.UPDATE_OWN);
    }

    public boolean canDelete() {
        return hasPermission(Permission.DELETE);
    }

    public boolean canManageUsers() {
        return hasPermission(Permission.MANAGE_USERS);
    }
}

/**
 * Permission enumeration.
 */
enum Permission {
    CREATE,
    READ,
    UPDATE,
    UPDATE_OWN,
    DELETE,
    MANAGE_USERS,
    MANAGE_TEAM,
    MANAGE_SETTINGS,
    VIEW_REPORTS,
    EXPORT_DATA
}

/**
 * User status enumeration.
 */
enum UserStatus {
    PENDING_VERIFICATION,
    ACTIVE,
    SUSPENDED,
    LOCKED,
    DEACTIVATED;

    public boolean canLogin() {
        return this == ACTIVE;
    }

    public boolean isEditable() {
        return this != DEACTIVATED;
    }
}

/**
 * Email value object with validation.
 */
record Email(String value) {
    private static final Pattern EMAIL_PATTERN =
        Pattern.compile("^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$");

    public Email {
        Objects.requireNonNull(value, "Email cannot be null");
        value = value.toLowerCase().trim();
        if (!EMAIL_PATTERN.matcher(value).matches()) {
            throw new ValidationException(List.of(
                new ValidationError("email", "Invalid email format", value)
            ));
        }
    }

    public String getDomain() {
        return value.substring(value.indexOf('@') + 1);
    }

    public String getLocalPart() {
        return value.substring(0, value.indexOf('@'));
    }
}

/**
 * Phone number value object.
 */
record PhoneNumber(String countryCode, String number) {
    private static final Pattern PHONE_PATTERN = Pattern.compile("^\\d{7,15}$");

    public PhoneNumber {
        Objects.requireNonNull(countryCode, "Country code cannot be null");
        Objects.requireNonNull(number, "Number cannot be null");
        countryCode = countryCode.startsWith("+") ? countryCode : "+" + countryCode;
        number = number.replaceAll("[^0-9]", "");
        if (!PHONE_PATTERN.matcher(number).matches()) {
            throw new ValidationException(List.of(
                new ValidationError("phoneNumber", "Invalid phone number", number)
            ));
        }
    }

    public String getFormatted() {
        return STR."\{countryCode} \{number}";
    }

    public String getE164() {
        return countryCode + number;
    }
}

/**
 * Address value object.
 */
record Address(
    String street,
    String city,
    String state,
    String postalCode,
    String country
) {
    public Address {
        Objects.requireNonNull(street, "Street cannot be null");
        Objects.requireNonNull(city, "City cannot be null");
        Objects.requireNonNull(country, "Country cannot be null");
        street = street.trim();
        city = city.trim();
        state = state != null ? state.trim() : "";
        postalCode = postalCode != null ? postalCode.trim() : "";
        country = country.trim();
    }

    public String getFormatted() {
        var parts = new ArrayList<String>();
        parts.add(street);
        parts.add(city);
        if (!state.isEmpty()) parts.add(state);
        if (!postalCode.isEmpty()) parts.add(postalCode);
        parts.add(country);
        return String.join(", ", parts);
    }

    public boolean isComplete() {
        return !street.isEmpty() && !city.isEmpty() &&
               !postalCode.isEmpty() && !country.isEmpty();
    }
}

/**
 * Money value object for currency handling.
 */
record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount, "Amount cannot be null");
        Objects.requireNonNull(currency, "Currency cannot be null");
        amount = amount.setScale(currency.getDefaultFractionDigits(), RoundingMode.HALF_UP);
    }

    public static Money of(double amount, String currencyCode) {
        return new Money(
            BigDecimal.valueOf(amount),
            Currency.getInstance(currencyCode)
        );
    }

    public static Money zero(String currencyCode) {
        return new Money(BigDecimal.ZERO, Currency.getInstance(currencyCode));
    }

    public Money add(Money other) {
        ensureSameCurrency(other);
        return new Money(amount.add(other.amount), currency);
    }

    public Money subtract(Money other) {
        ensureSameCurrency(other);
        return new Money(amount.subtract(other.amount), currency);
    }

    public Money multiply(BigDecimal factor) {
        return new Money(amount.multiply(factor), currency);
    }

    public Money multiply(double factor) {
        return multiply(BigDecimal.valueOf(factor));
    }

    public boolean isPositive() {
        return amount.compareTo(BigDecimal.ZERO) > 0;
    }

    public boolean isNegative() {
        return amount.compareTo(BigDecimal.ZERO) < 0;
    }

    public boolean isZero() {
        return amount.compareTo(BigDecimal.ZERO) == 0;
    }

    private void ensureSameCurrency(Money other) {
        if (!currency.equals(other.currency)) {
            throw new IllegalArgumentException(
                STR."Cannot operate on different currencies: \{currency} and \{other.currency}"
            );
        }
    }

    public String getFormatted() {
        return STR."\{currency.getSymbol()} \{amount}";
    }
}

/**
 * User ID value object.
 */
record UserId(UUID value) {
    public UserId {
        Objects.requireNonNull(value, "User ID cannot be null");
    }

    public static UserId generate() {
        return new UserId(UUID.randomUUID());
    }

    public static UserId of(String value) {
        return new UserId(UUID.fromString(value));
    }

    @Override
    public String toString() {
        return value.toString();
    }
}

/**
 * User profile containing personal information.
 */
record UserProfile(
    String firstName,
    String lastName,
    Option<String> middleName,
    Option<PhoneNumber> phoneNumber,
    Option<Address> address,
    Option<LocalDate> dateOfBirth,
    Option<String> avatarUrl,
    String timezone,
    String locale
) {
    public UserProfile {
        Objects.requireNonNull(firstName, "First name cannot be null");
        Objects.requireNonNull(lastName, "Last name cannot be null");
        firstName = firstName.trim();
        lastName = lastName.trim();
        if (firstName.length() < 1) {
            throw new ValidationException(List.of(
                new ValidationError("firstName", "First name is required", firstName)
            ));
        }
        if (lastName.length() < 1) {
            throw new ValidationException(List.of(
                new ValidationError("lastName", "Last name is required", lastName)
            ));
        }
        if (middleName == null) middleName = new None<>();
        if (phoneNumber == null) phoneNumber = new None<>();
        if (address == null) address = new None<>();
        if (dateOfBirth == null) dateOfBirth = new None<>();
        if (avatarUrl == null) avatarUrl = new None<>();
        if (timezone == null || timezone.isEmpty()) timezone = "UTC";
        if (locale == null || locale.isEmpty()) locale = "en-US";
    }

    public String getFullName() {
        return middleName
            .map(m -> STR."\{firstName} \{m} \{lastName}")
            .getOrElse(STR."\{firstName} \{lastName}");
    }

    public String getDisplayName() {
        return STR."\{firstName} \{lastName.substring(0, 1)}.";
    }

    public Option<Integer> getAge() {
        return dateOfBirth.map(dob -> Period.between(dob, LocalDate.now()).getYears());
    }

    public UserProfile withAddress(Address newAddress) {
        return new UserProfile(
            firstName, lastName, middleName, phoneNumber,
            new Some<>(newAddress), dateOfBirth, avatarUrl, timezone, locale
        );
    }

    public UserProfile withPhone(PhoneNumber newPhone) {
        return new UserProfile(
            firstName, lastName, middleName, new Some<>(newPhone),
            address, dateOfBirth, avatarUrl, timezone, locale
        );
    }
}

/**
 * User entity with comprehensive validation and behavior.
 */
@Auditable
record User(
    UserId id,
    Email email,
    String passwordHash,
    UserProfile profile,
    Role role,
    UserStatus status,
    Set<String> tags,
    Map<String, Object> metadata,
    LocalDateTime createdAt,
    LocalDateTime updatedAt,
    Option<LocalDateTime> lastLoginAt,
    long version
) {
    public User {
        Objects.requireNonNull(id, "User ID cannot be null");
        Objects.requireNonNull(email, "Email cannot be null");
        Objects.requireNonNull(passwordHash, "Password hash cannot be null");
        Objects.requireNonNull(profile, "Profile cannot be null");
        if (role == null) role = Role.USER;
        if (status == null) status = UserStatus.PENDING_VERIFICATION;
        if (tags == null) tags = Set.of();
        else tags = Set.copyOf(tags);
        if (metadata == null) metadata = Map.of();
        else metadata = Map.copyOf(metadata);
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (updatedAt == null) updatedAt = createdAt;
        if (lastLoginAt == null) lastLoginAt = new None<>();
        if (version < 0) version = 0;
    }

    /**
     * Builder pattern for User.
     */
    public static UserBuilder builder() {
        return new UserBuilder();
    }

    public boolean canPerform(Permission permission) {
        return status.canLogin() && role.hasPermission(permission);
    }

    public boolean isAdmin() {
        return role == Role.ADMIN || role == Role.SUPER_ADMIN;
    }

    public User activate() {
        return new User(id, email, passwordHash, profile, role, UserStatus.ACTIVE,
            tags, metadata, createdAt, LocalDateTime.now(), lastLoginAt, version + 1);
    }

    public User suspend(String reason) {
        var newMetadata = new HashMap<>(metadata);
        newMetadata.put("suspensionReason", reason);
        newMetadata.put("suspendedAt", LocalDateTime.now().toString());
        return new User(id, email, passwordHash, profile, role, UserStatus.SUSPENDED,
            tags, newMetadata, createdAt, LocalDateTime.now(), lastLoginAt, version + 1);
    }

    public User recordLogin() {
