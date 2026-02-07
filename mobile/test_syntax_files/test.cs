// C# 12+ Sample File - Modern .NET Patterns & Best Practices
// Comprehensive demonstration of modern C# features and enterprise patterns

#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Collections.Immutable;
using System.ComponentModel.DataAnnotations;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Linq;
using System.Linq.Expressions;
using System.Net.Http;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace ModernCSharpPatterns;

#region Custom Attributes

/// <summary>
/// Marks a class as an aggregate root in Domain-Driven Design.
/// </summary>
[AttributeUsage(AttributeTargets.Class, Inherited = false, AllowMultiple = false)]
public sealed class AggregateRootAttribute : Attribute
{
    public string? BoundedContext { get; init; }
    public string? Description { get; init; }
}

/// <summary>
/// Marks a method for auditing purposes.
/// </summary>
[AttributeUsage(AttributeTargets.Method, AllowMultiple = false)]
public sealed class AuditAttribute : Attribute
{
    public string Action { get; }
    public AuditLevel Level { get; init; } = AuditLevel.Info;
    public bool IncludeParameters { get; init; } = true;
    public bool IncludeReturnValue { get; init; } = false;

    public AuditAttribute(string action)
    {
        Action = action;
    }
}

public enum AuditLevel
{
    Debug,
    Info,
    Warning,
    Critical
}

/// <summary>
/// Marks a property for caching purposes.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Method)]
public sealed class CacheableAttribute : Attribute
{
    public TimeSpan Duration { get; }
    public string? CacheKey { get; init; }
    public CacheStrategy Strategy { get; init; } = CacheStrategy.SlidingExpiration;

    public CacheableAttribute(int durationSeconds)
    {
        Duration = TimeSpan.FromSeconds(durationSeconds);
    }
}

public enum CacheStrategy
{
    AbsoluteExpiration,
    SlidingExpiration,
    NeverExpire
}

/// <summary>
/// Marks a method to be retried on failure.
/// </summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class RetryOnFailureAttribute : Attribute
{
    public int MaxAttempts { get; init; } = 3;
    public int InitialDelayMs { get; init; } = 100;
    public double BackoffMultiplier { get; init; } = 2.0;
    public Type[]? RetryableExceptions { get; init; }
}

/// <summary>
/// Validates that a string property matches an email format.
/// </summary>
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter)]
public sealed class EmailValidationAttribute : ValidationAttribute
{
    private static readonly Regex EmailRegex = new(
        @"^[\w!#$%&'*+/=?^`{|}~-]+(?:\.[\w!#$%&'*+/=?^`{|}~-]+)*@(?:[\w](?:[\w-]*[\w])?\.)+[\w](?:[\w-]*[\w])?$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public override bool IsValid(object? value)
    {
        if (value is null) return true; // Let [Required] handle null
        return value is string email && EmailRegex.IsMatch(email);
    }

    public override string FormatErrorMessage(string name)
        => $"The {name} field must be a valid email address.";
}

#endregion

#region Result and Option Types

/// <summary>
/// Represents the result of an operation that can either succeed with a value or fail with an error.
/// </summary>
public abstract record Result<T>
{
    private Result() { }

    public sealed record Success(T Value) : Result<T>
    {
        public override string ToString() => $"Success({Value})";
    }

    public sealed record Failure(Error Error) : Result<T>
    {
        public override string ToString() => $"Failure({Error})";
    }

    public static Result<T> Ok(T value) => new Success(value);
    public static Result<T> Err(string message, string? code = null) => new Failure(new Error(message, code));
    public static Result<T> Err(Error error) => new Failure(error);
    public static Result<T> Err(Exception exception) => new Failure(Error.FromException(exception));

    public bool IsSuccess => this is Success;
    public bool IsFailure => this is Failure;

    public T? ValueOrDefault => this switch
    {
        Success s => s.Value,
        _ => default
    };

    public Result<U> Map<U>(Func<T, U> mapper) => this switch
    {
        Success s => Result<U>.Ok(mapper(s.Value)),
        Failure f => Result<U>.Err(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public async Task<Result<U>> MapAsync<U>(Func<T, Task<U>> mapper) => this switch
    {
        Success s => Result<U>.Ok(await mapper(s.Value)),
        Failure f => Result<U>.Err(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public Result<U> FlatMap<U>(Func<T, Result<U>> mapper) => this switch
    {
        Success s => mapper(s.Value),
        Failure f => Result<U>.Err(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public async Task<Result<U>> FlatMapAsync<U>(Func<T, Task<Result<U>>> mapper) => this switch
    {
        Success s => await mapper(s.Value),
        Failure f => Result<U>.Err(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public T GetOrDefault(T defaultValue) => this switch
    {
        Success s => s.Value,
        _ => defaultValue
    };

    public T GetOrElse(Func<T> fallback) => this switch
    {
        Success s => s.Value,
        _ => fallback()
    };

    public T GetOrThrow() => this switch
    {
        Success s => s.Value,
        Failure f => throw new ResultException(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public Result<T> OnSuccess(Action<T> action)
    {
        if (this is Success s)
            action(s.Value);
        return this;
    }

    public Result<T> OnFailure(Action<Error> action)
    {
        if (this is Failure f)
            action(f.Error);
        return this;
    }

    public async Task<Result<T>> OnSuccessAsync(Func<T, Task> action)
    {
        if (this is Success s)
            await action(s.Value);
        return this;
    }

    public TResult Match<TResult>(Func<T, TResult> onSuccess, Func<Error, TResult> onFailure) => this switch
    {
        Success s => onSuccess(s.Value),
        Failure f => onFailure(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public async Task<TResult> MatchAsync<TResult>(
        Func<T, Task<TResult>> onSuccess,
        Func<Error, Task<TResult>> onFailure) => this switch
    {
        Success s => await onSuccess(s.Value),
        Failure f => await onFailure(f.Error),
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public Result<T> Ensure(Func<T, bool> predicate, string errorMessage) => this switch
    {
        Success s when predicate(s.Value) => this,
        Success => Err(errorMessage),
        Failure => this,
        _ => throw new InvalidOperationException("Invalid result state")
    };

    public Result<T> Tap(Action<T> action)
    {
        if (this is Success s)
            action(s.Value);
        return this;
    }

    public static implicit operator Result<T>(T value) => Ok(value);
    public static implicit operator Result<T>(Error error) => Err(error);
}

/// <summary>
/// Represents a structured error with code, message, and optional details.
/// </summary>
public record Error(
    string Message,
    string? Code = null,
    IReadOnlyDictionary<string, object>? Details = null)
{
    public static Error FromException(Exception ex) => new(
        ex.Message,
        ex.GetType().Name,
        new Dictionary<string, object>
        {
            ["ExceptionType"] = ex.GetType().FullName ?? ex.GetType().Name,
            ["StackTrace"] = ex.StackTrace ?? string.Empty
        });

    public Error WithDetail(string key, object value)
    {
        var newDetails = Details is null
            ? new Dictionary<string, object> { [key] = value }
            : new Dictionary<string, object>(Details) { [key] = value };
        return this with { Details = newDetails };
    }

    public static Error NotFound(string entity, object id) => new(
        $"{entity} with id '{id}' was not found.",
        "NOT_FOUND",
        new Dictionary<string, object> { ["Entity"] = entity, ["Id"] = id });

    public static Error Validation(string message, IDictionary<string, string[]>? errors = null) => new(
        message,
        "VALIDATION_ERROR",
        errors?.ToDictionary(x => x.Key, x => (object)x.Value));

    public static Error Conflict(string message) => new(message, "CONFLICT");
    public static Error Forbidden(string message = "Access denied.") => new(message, "FORBIDDEN");
    public static Error Unauthorized(string message = "Authentication required.") => new(message, "UNAUTHORIZED");
    public static Error Internal(string message = "An internal error occurred.") => new(message, "INTERNAL_ERROR");
}

/// <summary>
/// Represents an optional value that may or may not be present.
/// </summary>
public abstract record Option<T>
{
    private Option() { }

    public sealed record Some(T Value) : Option<T>
    {
        public override string ToString() => $"Some({Value})";
    }

    public sealed record None : Option<T>
    {
        public static readonly None Instance = new();
        public override string ToString() => "None";
    }

    public static Option<T> Of(T? value) => value is null ? None.Instance : new Some(value);
    public static Option<T> OfNullable(T? value) where T : struct
        => value.HasValue ? new Some(value.Value) : None.Instance;

    public bool IsSome => this is Some;
    public bool IsNone => this is None;

    public T? ValueOrDefault => this switch
    {
        Some s => s.Value,
        _ => default
    };

    public Option<U> Map<U>(Func<T, U> mapper) => this switch
    {
        Some s => new Option<U>.Some(mapper(s.Value)),
        None => Option<U>.None.Instance,
        _ => throw new InvalidOperationException()
    };

    public Option<U> FlatMap<U>(Func<T, Option<U>> mapper) => this switch
    {
        Some s => mapper(s.Value),
        None => Option<U>.None.Instance,
        _ => throw new InvalidOperationException()
    };

    public T GetOrDefault(T defaultValue) => this switch
    {
        Some s => s.Value,
        _ => defaultValue
    };

    public T GetOrElse(Func<T> fallback) => this switch
    {
        Some s => s.Value,
        _ => fallback()
    };

    public T GetOrThrow(string? errorMessage = null) => this switch
    {
        Some s => s.Value,
        _ => throw new InvalidOperationException(errorMessage ?? "Option is None")
    };

    public Option<T> Filter(Func<T, bool> predicate) => this switch
    {
        Some s when predicate(s.Value) => this,
        Some => None.Instance,
        _ => this
    };

    public TResult Match<TResult>(Func<T, TResult> onSome, Func<TResult> onNone) => this switch
    {
        Some s => onSome(s.Value),
        None => onNone(),
        _ => throw new InvalidOperationException()
    };

    public Result<T> ToResult(string errorMessage) => this switch
    {
        Some s => Result<T>.Ok(s.Value),
        None => Result<T>.Err(errorMessage),
        _ => throw new InvalidOperationException()
    };

    public Result<T> ToResult(Error error) => this switch
    {
        Some s => Result<T>.Ok(s.Value),
        None => Result<T>.Err(error),
        _ => throw new InvalidOperationException()
    };

    public IEnumerable<T> ToEnumerable() => this switch
    {
        Some s => [s.Value],
        _ => []
    };

    public static implicit operator Option<T>(T? value) => Of(value);
}

#endregion

#region Custom Exceptions

/// <summary>
/// Base exception for domain-specific errors.
/// </summary>
public abstract class DomainException : Exception
{
    public string Code { get; }
    public IReadOnlyDictionary<string, object>? Details { get; }

    protected DomainException(
        string message,
        string code,
        IReadOnlyDictionary<string, object>? details = null,
        Exception? innerException = null)
        : base(message, innerException)
    {
        Code = code;
        Details = details;
    }
}

/// <summary>
/// Exception thrown when a Result contains an error.
/// </summary>
public class ResultException : DomainException
{
    public Error Error { get; }

    public ResultException(Error error)
        : base(error.Message, error.Code ?? "RESULT_ERROR", error.Details)
    {
        Error = error;
    }
}

/// <summary>
/// Exception thrown when an entity is not found.
/// </summary>
public class EntityNotFoundException : DomainException
{
    public string EntityType { get; }
    public object EntityId { get; }

    public EntityNotFoundException(string entityType, object entityId)
        : base(
            $"{entityType} with id '{entityId}' was not found.",
            "ENTITY_NOT_FOUND",
            new Dictionary<string, object> { ["EntityType"] = entityType, ["EntityId"] = entityId })
    {
        EntityType = entityType;
        EntityId = entityId;
    }
}

/// <summary>
/// Exception thrown when a validation error occurs.
/// </summary>
public class ValidationException : DomainException
{
    public IReadOnlyDictionary<string, string[]> Errors { get; }

    public ValidationException(string message, IDictionary<string, string[]> errors)
        : base(message, "VALIDATION_ERROR", errors.ToDictionary(x => x.Key, x => (object)x.Value))
    {
        Errors = new Dictionary<string, string[]>(errors);
    }

    public ValidationException(string field, string error)
        : this($"Validation failed for {field}", new Dictionary<string, string[]> { [field] = [error] })
    {
    }
}

/// <summary>
/// Exception thrown when a concurrency conflict occurs.
/// </summary>
public class ConcurrencyException : DomainException
{
    public ConcurrencyException(string message, Exception? innerException = null)
        : base(message, "CONCURRENCY_CONFLICT", null, innerException)
    {
    }
}

/// <summary>
/// Exception thrown when an operation times out.
/// </summary>
public class OperationTimeoutException : DomainException
{
    public TimeSpan Timeout { get; }
    public string OperationName { get; }

    public OperationTimeoutException(string operationName, TimeSpan timeout)
        : base(
            $"Operation '{operationName}' timed out after {timeout.TotalSeconds:F1} seconds.",
            "OPERATION_TIMEOUT",
            new Dictionary<string, object>
            {
                ["OperationName"] = operationName,
                ["TimeoutSeconds"] = timeout.TotalSeconds
            })
    {
        OperationName = operationName;
        Timeout = timeout;
    }
}

#endregion

#region Domain Entities

/// <summary>
/// User roles in the system.
/// </summary>
[Flags]
public enum Role
{
    None = 0,
    Guest = 1,
    User = 2,
    Moderator = 4,
    Admin = 8,
    SuperAdmin = 16
}

/// <summary>
/// User status in the system.
/// </summary>
public enum UserStatus
{
    Pending,
    Active,
    Suspended,
    Deleted
}

/// <summary>
/// Value object representing an email address.
/// </summary>
public readonly record struct Email
{
    private static readonly Regex EmailRegex = new(
        @"^[\w!#$%&'*+/=?^`{|}~-]+(?:\.[\w!#$%&'*+/=?^`{|}~-]+)*@(?:[\w](?:[\w-]*[\w])?\.)+[\w](?:[\w-]*[\w])?$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public string Value { get; }

    private Email(string value) => Value = value;

    public static Result<Email> Create(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return Result<Email>.Err("Email cannot be empty.", "INVALID_EMAIL");

        if (!EmailRegex.IsMatch(value))
            return Result<Email>.Err("Email format is invalid.", "INVALID_EMAIL_FORMAT");

        return Result<Email>.Ok(new Email(value.ToLowerInvariant()));
    }

    public string Domain => Value.Split('@')[1];
    public string LocalPart => Value.Split('@')[0];

    public override string ToString() => Value;
    public static implicit operator string(Email email) => email.Value;
}

/// <summary>
/// Value object representing a strong user ID.
/// </summary>
public readonly record struct UserId(Guid Value)
{
    public static UserId New() => new(Guid.NewGuid());
    public static UserId Parse(string value) => new(Guid.Parse(value));
    public static Result<UserId> TryParse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return Result<UserId>.Err("UserId cannot be empty.");
        if (!Guid.TryParse(value, out var guid))
            return Result<UserId>.Err($"Invalid UserId format: {value}");
        return Result<UserId>.Ok(new UserId(guid));
    }

    public override string ToString() => Value.ToString();
    public static implicit operator Guid(UserId id) => id.Value;
    public static implicit operator UserId(Guid guid) => new(guid);
}

/// <summary>
/// Base class for domain entities with common properties.
/// </summary>
public abstract record Entity<TId> where TId : struct
{
    public TId Id { get; init; }
    public DateTime CreatedAt { get; init; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; protected set; }
    public int Version { get; protected set; } = 1;

    protected void IncrementVersion()
    {
        Version++;
        UpdatedAt = DateTime.UtcNow;
    }
}

/// <summary>
/// User entity with comprehensive validation and behavior.
/// </summary>
[AggregateRoot(BoundedContext = "Identity", Description = "User aggregate root for authentication and authorization")]
public record User : Entity<UserId>
{
    private readonly List<DomainEvent> _domainEvents = [];

    public required string Name { get; init; }
    public required Email Email { get; init; }
    public Role Roles { get; private set; } = Role.User;
    public UserStatus Status { get; private set; } = UserStatus.Pending;
    public string? AvatarUrl { get; init; }
    public DateTime? LastLoginAt { get; private set; }
    public int FailedLoginAttempts { get; private set; }
    public DateTime? LockedUntil { get; private set; }
    public IReadOnlyDictionary<string, string> Metadata { get; init; } = new Dictionary<string, string>();

    public IReadOnlyList<DomainEvent> DomainEvents => _domainEvents.AsReadOnly();

    public static Result<User> Create(string name, string email, Role? roles = null)
    {
        var validationErrors = new Dictionary<string, string[]>();

        if (string.IsNullOrWhiteSpace(name))
            validationErrors["Name"] = ["Name is required."];
        else if (name.Length < 2 || name.Length > 100)
            validationErrors["Name"] = ["Name must be between 2 and 100 characters."];

        var emailResult = Email.Create(email);
        if (emailResult.IsFailure && emailResult is Result<Email>.Failure f)
            validationErrors["Email"] = [f.Error.Message];

        if (validationErrors.Count > 0)
            return Result<User>.Err(Error.Validation("User validation failed.", validationErrors));

        var user = new User
        {
            Id = UserId.New(),
            Name = name.Trim(),
            Email = emailResult.GetOrThrow(),
            Roles = roles ?? Role.User
        };

        user._domainEvents.Add(new UserCreatedEvent(user.Id, user.Email.Value, DateTime.UtcNow));
        return Result<User>.Ok(user);
    }

    public Result<User> Activate()
    {
        if (Status == UserStatus.Deleted)
            return Result<User>.Err("Cannot activate a deleted user.", "INVALID_STATE");

        Status = UserStatus.Active;
        IncrementVersion();
        _domainEvents.Add(new UserActivatedEvent(Id, DateTime.UtcNow));
        return this;
    }

    public Result<User> Suspend(string reason)
    {
        if (Status == UserStatus.Deleted)
            return Result<User>.Err("Cannot suspend a deleted user.", "INVALID_STATE");

        Status = UserStatus.Suspended;
        IncrementVersion();
        _domainEvents.Add(new UserSuspendedEvent(Id, reason, DateTime.UtcNow));
        return this;
    }

    public Result<User> Delete()
    {
        Status = UserStatus.Deleted;
        IncrementVersion();
        _domainEvents.Add(new UserDeletedEvent(Id, DateTime.UtcNow));
        return this;
    }

    public Result<User> AddRole(Role role)
    {
        if (Status != UserStatus.Active)
            return Result<User>.Err("User must be active to modify roles.", "INVALID_STATE");

        Roles |= role;
        IncrementVersion();
        _domainEvents.Add(new UserRoleChangedEvent(Id, Roles, DateTime.UtcNow));
        return this;
    }

    public Result<User> RemoveRole(Role role)
    {
        if (Status != UserStatus.Active)
            return Result<User>.Err("User must be active to modify roles.", "INVALID_STATE");

        Roles &= ~role;
        IncrementVersion();
        _domainEvents.Add(new UserRoleChangedEvent(Id, Roles, DateTime.UtcNow));
        return this;
    }

    public bool HasRole(Role role) => (Roles & role) == role;
    public bool HasAnyRole(Role roles) => (Roles & roles) != 0;

    public Result<User> RecordLogin()
    {
        if (Status != UserStatus.Active)
            return Result<User>.Err("Only active users can login.", "INVALID_STATE");

        if (LockedUntil.HasValue && LockedUntil.Value > DateTime.UtcNow)
            return Result<User>.Err($"Account is locked until {LockedUntil.Value:u}", "ACCOUNT_LOCKED");

        LastLoginAt = DateTime.UtcNow;
        FailedLoginAttempts = 0;
        LockedUntil = null;
        IncrementVersion();
        return this;
    }

    public Result<User> RecordFailedLogin(int maxAttempts = 5, TimeSpan? lockDuration = null)
    {
        FailedLoginAttempts++;

        if (FailedLoginAttempts >= maxAttempts)
        {
            LockedUntil = DateTime.UtcNow.Add(lockDuration ?? TimeSpan.FromMinutes(15));
            _domainEvents.Add(new UserLockedOutEvent(Id, LockedUntil.Value, DateTime.UtcNow));
        }

        IncrementVersion();
        return this;
    }

    public void ClearDomainEvents() => _domainEvents.Clear();

    public User WithName(string name) => this with { Name = name };
    public User WithAvatar(string url) => this with { AvatarUrl = url };
    public User WithMetadata(IDictionary<string, string> metadata) => this with { Metadata = new Dictionary<string, string>(metadata) };
}

/// <summary>
/// Represents a user session.
/// </summary>
public record Session(
    Guid Id,
    UserId UserId,
    string IpAddress,
    string UserAgent,
    DateTime CreatedAt,
    DateTime ExpiresAt,
    DateTime? LastActivityAt = null,
    bool IsRevoked = false)
{
    public bool IsExpired => DateTime.UtcNow > ExpiresAt;
    public bool IsValid => !IsExpired && !IsRevoked;
    public TimeSpan TimeUntilExpiry => ExpiresAt - DateTime.UtcNow;

    public Session Touch() => this with
    {
        LastActivityAt = DateTime.UtcNow,
        ExpiresAt = DateTime.UtcNow.AddHours(24)
    };

    public Session Revoke() => this with { IsRevoked = true };
}

#endregion

#region Domain Events

/// <summary>
/// Base interface for domain events.
/// </summary>
public interface IDomainEvent
{
    Guid EventId { get; }
    DateTime OccurredAt { get; }
    string EventType { get; }
}

/// <summary>
/// Base record for domain events.
/// </summary>
public abstract record DomainEvent : IDomainEvent
{
    public Guid EventId { get; } = Guid.NewGuid();
    public DateTime OccurredAt { get; init; } = DateTime.UtcNow;
    public abstract string EventType { get; }
}

public record UserCreatedEvent(UserId UserId, string Email, DateTime OccurredAt) : DomainEvent
{
    public override string EventType => "user.created";
}

public record UserActivatedEvent(UserId UserId, DateTime OccurredAt) : DomainEvent
{
    public override string EventType => "user.activated";
}

public record UserSuspendedEvent(UserId UserId, string Reason, DateTime OccurredAt) : DomainEvent
{
    public override string EventType => "user.suspended";
}

public record UserDeletedEvent(UserId UserId, DateTime OccurredAt) : DomainEvent
{
    public override string EventType => "user.deleted";
}

public record UserRoleChangedEvent(UserId UserId, Role NewRoles, DateTime OccurredAt) : DomainEvent
{
    public override string EventType => "user.role_changed";
}

public record UserLockedOutEvent(UserId UserId, DateTime LockedUntil, DateTime OccurredAt) : DomainEvent
{
    public override string EventType => "user.locked_out";
}

#endregion

#region Repository Interfaces

/// <summary>
/// Specification pattern for building queries.
/// </summary>
public interface ISpecification<T>
{
    Expression<Func<T, bool>> Criteria { get; }
    List<Expression<Func<T, object>>> Includes { get; }
    List<string> IncludeStrings { get; }
    Expression<Func<T, object>>? OrderBy { get; }
    Expression<Func<T, object>>? OrderByDescending { get; }
    int Take { get; }
    int Skip { get; }
    bool IsPagingEnabled { get; }
}

/// <summary>
/// Base specification implementation.
/// </summary>
public abstract class Specification<T> : ISpecification<T>
{
    public Expression<Func<T, bool>> Criteria { get; private set; } = x => true;
    public List<Expression<Func<T, object>>> Includes { get; } = [];
    public List<string> IncludeStrings { get; } = [];
    public Expression<Func<T, object>>? OrderBy { get; private set; }
    public Expression<Func<T, object>>? OrderByDescending { get; private set; }
    public int Take { get; private set; }
    public int Skip { get; private set; }
    public bool IsPagingEnabled { get; private set; }

    protected void AddCriteria(Expression<Func<T, bool>> criteria) => Criteria = criteria;
    protected void AddInclude(Expression<Func<T, object>> include) => Includes.Add(include);
    protected void AddInclude(string include) => IncludeStrings.Add(include);
    protected void ApplyOrderBy(Expression<Func<T, object>> orderBy) => OrderBy = orderBy;
    protected void ApplyOrderByDescending(Expression<Func<T, object>> orderBy) => OrderByDescending = orderBy;

    protected void ApplyPaging(int skip, int take)
    {
        Skip = skip;
        Take = take;
        IsPagingEnabled = true;
    }
}

/// <summary>
/// Generic repository interface with comprehensive CRUD operations.
/// </summary>
public interface IRepository<T, TId>
    where T : Entity<TId>
    where TId : struct
{
    // Read operations
    Task<Option<T>> FindByIdAsync(TId id, CancellationToken ct = default);
    Task<IReadOnlyList<T>> FindAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<T>> FindAsync(ISpecification<T> spec, CancellationToken ct = default);
    Task<Option<T>> FindOneAsync(ISpecification<T> spec, CancellationToken ct = default);
    Task<int> CountAsync(ISpecification<T>? spec = null, CancellationToken ct = default);
    Task<bool> ExistsAsync(TId id, CancellationToken ct = default);
    Task<bool> AnyAsync(ISpecification<T> spec, CancellationToken ct = default);

    // Write operations
    Task<Result<T>> AddAsync(T entity, CancellationToken ct = default);
    Task<Result<T>> UpdateAsync(T entity, CancellationToken ct = default);
    Task<Result<bool>> DeleteAsync(TId id, CancellationToken ct = default);
    Task<Result<int>> AddRangeAsync(IEnumerable<T> entities, CancellationToken ct = default);
    Task<Result<int>> DeleteRangeAsync(IEnumerable<TId> ids, CancellationToken ct = default);
}

/// <summary>
/// User-specific repository interface with additional query methods.
/// </summary>
public interface IUserRepository : IRepository<User, UserId>
{
    Task<Option<User>> FindByEmailAsync(Email email, CancellationToken ct = default);
    Task<IReadOnlyList<User>> FindByRolesAsync(Role roles, CancellationToken ct = default);
    Task<IReadOnlyList<User>> FindByStatusAsync(UserStatus status, CancellationToken ct = default);
    Task<IReadOnlyList<User>> SearchAsync(string query, int limit = 10, CancellationToken ct = default);
    Task<PagedResult<User>> GetPagedAsync(int page, int pageSize, CancellationToken ct = default);
}

/// <summary>
/// Represents a paginated result set.
/// </summary>
public record PagedResult<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNextPage => Page < TotalPages;
    public bool HasPreviousPage => Page > 1;
    public bool IsEmpty => Items.Count == 0;

    public PagedResult<U> Map<U>(Func<T, U> mapper) => new(
        Items.Select(mapper).ToList(),
        Page,
        PageSize,
        TotalCount);
}

#endregion

#region In-Memory Repository Implementation

/// <summary>
/// Thread-safe in-memory repository implementation for users.
/// </summary>
public class InMemoryUserRepository : IUserRepository
{
    private readonly ConcurrentDictionary<UserId, User> _storage = new();
    private readonly ReaderWriterLockSlim _lock = new();

    public Task<Option<User>> FindByIdAsync(UserId id, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return Task.FromResult<Option<User>>(
            _storage.TryGetValue(id, out var user) ? user : Option<User>.None.Instance);
    }

    public Task<IReadOnlyList<User>> FindAllAsync(CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return Task.FromResult<IReadOnlyList<User>>(_storage.Values.ToList());
    }

    public Task<IReadOnlyList<User>> FindAsync(ISpecification<User> spec, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        var query = _storage.Values.AsQueryable().Where(spec.Criteria);

        if (spec.OrderBy is not null)
            query = query.OrderBy(spec.OrderBy);
        else if (spec.OrderByDescending is not null)
            query = query.OrderByDescending(spec.OrderByDescending);

        if (spec.IsPagingEnabled)
            query = query.Skip(spec.Skip).Take(spec.Take);

        return Task.FromResult<IReadOnlyList<User>>(query.ToList());
    }

    public Task<Option<User>> FindOneAsync(ISpecification<User> spec, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        var user = _storage.Values.AsQueryable().Where(spec.Criteria).FirstOrDefault();
        return Task.FromResult<Option<User>>(user is null ? Option<User>.None.Instance : user);
    }

    public Task<int> CountAsync(ISpecification<User>? spec = null, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return Task.FromResult(spec is null
            ? _storage.Count
            : _storage.Values.AsQueryable().Count(spec.Criteria));
    }

    public Task<bool> ExistsAsync(UserId id, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return Task.FromResult(_storage.ContainsKey(id));
