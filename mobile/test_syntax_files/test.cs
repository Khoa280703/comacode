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

    public Result<TNew> Map<TNew>(Func<T, TNew> mapper) => this switch
    {
        Success s => Result<TNew>.Ok(mapper(s.Value)),
        Failure f => Result<TNew>.Err(f.Error),
        _ => throw new InvalidOperationException()
    };

    public async Task<Result<TNew>> MapAsync<TNew>(Func<T, Task<TNew>> mapper) => this switch
    {
        Success s => Result<TNew>.Ok(await mapper(s.Value)),
        Failure f => Result<TNew>.Err(f.Error),
        _ => throw new InvalidOperationException()
    };

    public Result<TNew> Bind<TNew>(Func<T, Result<TNew>> binder) => this switch
    {
        Success s => binder(s.Value),
        Failure f => Result<TNew>.Err(f.Error),
        _ => throw new InvalidOperationException()
    };

    public T GetValueOrThrow() => this switch
    {
        Success s => s.Value,
        Failure f => throw new InvalidOperationException($"Result is failure: {f.Error}"),
        _ => throw new InvalidOperationException()
    };

    public Result<T> Tap(Action<T> action)
    {
        if (this is Success s) action(s.Value);
        return this;
    }

    public Result<T> TapError(Action<Error> action)
    {
        if (this is Failure f) action(f.Error);
        return this;
    }
}

public sealed record Error(string Message, string? Code = null)
{
    public static Error FromException(Exception ex)
        => new(ex.Message, ex.GetType().Name);

    public override string ToString()
        => Code is not null ? $"[{Code}] {Message}" : Message;
}

#endregion

#region Domain Models with Records

[AggregateRoot(BoundedContext = "Identity", Description = "User aggregate")]
public record User
{
    public required Guid Id { get; init; }

    [Required, StringLength(100, MinimumLength = 2)]
    public required string Name { get; init; }

    [EmailValidation(ErrorMessage = "Invalid email format")]
    public required string Email { get; init; }

    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? LastLoginAt { get; init; }
    public UserRole Role { get; init; } = UserRole.User;
    public ImmutableList<string> Permissions { get; init; } = ImmutableList<string>.Empty;

    public bool HasPermission(string permission) =>
        Role == UserRole.Admin || Permissions.Contains(permission);
}

public enum UserRole
{
    Guest = 0,
    User = 1,
    Moderator = 2,
    Admin = 3,
    SuperAdmin = 4
}

public record Address(
    string Street,
    string City,
    string State,
    string PostalCode,
    string Country = "US"
)
{
    public string FullAddress => $"{Street}, {City}, {State} {PostalCode}, {Country}";
}

public record Product
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required decimal Price { get; init; }
    public string? Description { get; init; }
    public int StockQuantity { get; init; }
    public ProductCategory Category { get; init; }
    public ImmutableDictionary<string, string> Metadata { get; init; }
        = ImmutableDictionary<string, string>.Empty;

    public bool IsAvailable => StockQuantity > 0;
    public decimal PriceWithTax(decimal taxRate = 0.08m) => Price * (1 + taxRate);
}

public enum ProductCategory
{
    Electronics,
    Clothing,
    Books,
    Food,
    Home,
    Sports
}

#endregion

#region Pattern Matching

public static class PatternMatchingExamples
{
    public static string Classify(object obj) => obj switch
    {
        null => "null",
        int i when i < 0 => $"negative int: {i}",
        int i when i == 0 => "zero",
        int i => $"positive int: {i}",
        double d when double.IsNaN(d) => "NaN",
        double d when double.IsInfinity(d) => "Infinity",
        double d => $"double: {d:F2}",
        string { Length: 0 } => "empty string",
        string { Length: > 100 } s => $"long string ({s.Length} chars)",
        string s => $"string: {s}",
        IEnumerable<int> { } list => $"int collection ({list.Count()} items)",
        User { Role: UserRole.Admin } u => $"admin: {u.Name}",
        User u => $"user: {u.Name} ({u.Role})",
        _ => $"unknown: {obj.GetType().Name}"
    };

    public static decimal CalculateDiscount(Product product, User user) =>
        (product, user) switch
        {
            ({ Category: ProductCategory.Electronics }, { Role: UserRole.Admin }) => 0.25m,
            ({ Category: ProductCategory.Electronics }, _) => 0.10m,
            ({ Price: > 100m }, { Role: UserRole.Admin or UserRole.Moderator }) => 0.15m,
            ({ Price: > 100m }, _) => 0.05m,
            ({ StockQuantity: < 5 }, _) => 0m,
            _ => 0.02m
        };

    public static string DescribeShape(object shape) => shape switch
    {
        Circle { Radius: 0 } => "point (degenerate circle)",
        Circle { Radius: var r } when r < 0 => "invalid circle",
        Circle { Radius: var r } => $"circle with radius {r:F2}",
        Rectangle { Width: var w, Height: var h } when w == h => $"square with side {w:F2}",
        Rectangle { Width: var w, Height: var h } => $"rectangle {w:F2} x {h:F2}",
        Triangle { A: var a, B: var b, C: var c } when a == b && b == c => "equilateral triangle",
        Triangle { A: var a, B: var b, C: var c } when a == b || b == c || a == c => "isosceles triangle",
        Triangle => "scalene triangle",
        _ => "unknown shape"
    };
}

public record Circle(double Radius);
public record Rectangle(double Width, double Height);
public record Triangle(double A, double B, double C);

#endregion

#region LINQ and Extension Methods

public static class LinqExamples
{
    public static IEnumerable<TResult> FullOuterJoin<TLeft, TRight, TKey, TResult>(
        this IEnumerable<TLeft> left,
        IEnumerable<TRight> right,
        Func<TLeft, TKey> leftKeySelector,
        Func<TRight, TKey> rightKeySelector,
        Func<TLeft?, TRight?, TResult> resultSelector)
        where TKey : notnull
    {
        var rightLookup = right.ToLookup(rightKeySelector);
        var usedKeys = new HashSet<TKey>();

        foreach (var leftItem in left)
        {
            var key = leftKeySelector(leftItem);
            usedKeys.Add(key);

            var rightItems = rightLookup[key];
            if (rightItems.Any())
            {
                foreach (var rightItem in rightItems)
                    yield return resultSelector(leftItem, rightItem);
            }
            else
            {
                yield return resultSelector(leftItem, default);
            }
        }

        foreach (var rightGroup in rightLookup)
        {
            if (!usedKeys.Contains(rightGroup.Key))
            {
                foreach (var rightItem in rightGroup)
                    yield return resultSelector(default, rightItem);
            }
        }
    }

    public static async IAsyncEnumerable<T> WhereAsync<T>(
        this IAsyncEnumerable<T> source,
        Func<T, Task<bool>> predicate,
        [EnumeratorCancellation] CancellationToken ct = default)
    {
        await foreach (var item in source.WithCancellation(ct))
        {
            if (await predicate(item))
                yield return item;
        }
    }

    public static IEnumerable<IReadOnlyList<T>> Batch<T>(
        this IEnumerable<T> source, int batchSize)
    {
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(batchSize, 0);

        var batch = new List<T>(batchSize);
        foreach (var item in source)
        {
            batch.Add(item);
            if (batch.Count >= batchSize)
            {
                yield return batch.AsReadOnly();
                batch = new List<T>(batchSize);
            }
        }
        if (batch.Count > 0)
            yield return batch.AsReadOnly();
    }

    public static void QueryDemo()
    {
        var products = new List<Product>();
        var users = new List<User>();

        // Complex LINQ query
        var report = products
            .Where(p => p.IsAvailable)
            .GroupBy(p => p.Category)
            .Select(g => new
            {
                Category = g.Key,
                Count = g.Count(),
                AveragePrice = g.Average(p => p.Price),
                MaxPrice = g.Max(p => p.Price),
                MinPrice = g.Min(p => p.Price),
                TotalValue = g.Sum(p => p.Price * p.StockQuantity),
                TopProducts = g.OrderByDescending(p => p.Price)
                               .Take(3)
                               .Select(p => p.Name)
                               .ToList()
            })
            .OrderByDescending(x => x.TotalValue)
            .ToList();

        // Query syntax
        var expensive = from p in products
                        where p.Price > 50m
                        orderby p.Category, p.Price descending
                        group p by p.Category into g
                        select new { Category = g.Key, Products = g.ToList() };

        // Batched processing
        var batches = Enumerable.Range(0, 1000).Batch(100);
        foreach (var batch in batches)
        {
            Console.WriteLine($"Processing batch of {batch.Count} items");
        }
    }
}

#endregion

#region Async Patterns and Channels

public sealed class AsyncEventBus : IAsyncDisposable
{
    private readonly ConcurrentDictionary<Type, List<Delegate>> _handlers = new();
    private readonly Channel<(Type EventType, object Event)> _channel;
    private readonly CancellationTokenSource _cts = new();
    private readonly Task _processingTask;

    public AsyncEventBus(int capacity = 1000)
    {
        _channel = Channel.CreateBounded<(Type, object)>(
            new BoundedChannelOptions(capacity)
            {
                FullMode = BoundedChannelFullMode.Wait,
                SingleReader = true,
                SingleWriter = false
            });

        _processingTask = ProcessEventsAsync(_cts.Token);
    }

    public void Subscribe<TEvent>(Func<TEvent, CancellationToken, Task> handler)
    {
        var handlers = _handlers.GetOrAdd(typeof(TEvent), _ => new List<Delegate>());
        lock (handlers)
        {
            handlers.Add(handler);
        }
    }

    public async ValueTask PublishAsync<TEvent>(TEvent @event, CancellationToken ct = default)
        where TEvent : notnull
    {
        await _channel.Writer.WriteAsync((typeof(TEvent), @event), ct);
    }

    private async Task ProcessEventsAsync(CancellationToken ct)
    {
        await foreach (var (eventType, @event) in _channel.Reader.ReadAllAsync(ct))
        {
            if (_handlers.TryGetValue(eventType, out var handlers))
            {
                List<Delegate> snapshot;
                lock (handlers) { snapshot = handlers.ToList(); }

                var tasks = snapshot.Select(handler =>
                {
                    var method = handler.GetType().GetMethod("Invoke")!;
                    return (Task)method.Invoke(handler, new[] { @event, ct })!;
                });

                await Task.WhenAll(tasks);
            }
        }
    }

    public async ValueTask DisposeAsync()
    {
        _channel.Writer.Complete();
        _cts.Cancel();
        try { await _processingTask; } catch (OperationCanceledException) { }
        _cts.Dispose();
    }
}

public static class AsyncExtensions
{
    public static async Task<T> WithTimeout<T>(this Task<T> task, TimeSpan timeout)
    {
        using var cts = new CancellationTokenSource(timeout);
        var completedTask = await Task.WhenAny(task, Task.Delay(timeout, cts.Token));
        if (completedTask == task)
        {
            cts.Cancel();
            return await task;
        }
        throw new TimeoutException($"Operation timed out after {timeout.TotalSeconds}s");
    }

    public static async Task<Result<T>> TryAsync<T>(Func<Task<T>> action)
    {
        try
        {
            return Result<T>.Ok(await action());
        }
        catch (Exception ex)
        {
            return Result<T>.Err(ex);
        }
    }

    public static async IAsyncEnumerable<T> Merge<T>(
        params IAsyncEnumerable<T>[] sources)
    {
        var channel = Channel.CreateUnbounded<T>();

        var tasks = sources.Select(async source =>
        {
            await foreach (var item in source)
            {
                await channel.Writer.WriteAsync(item);
            }
        }).ToArray();

        _ = Task.WhenAll(tasks).ContinueWith(_ => channel.Writer.Complete());

        await foreach (var item in channel.Reader.ReadAllAsync())
        {
            yield return item;
        }
    }
}

#endregion

#region Generic Repository Pattern

public interface IRepository<T> where T : class
{
    Task<T?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken ct = default);
    Task<IReadOnlyList<T>> FindAsync(Expression<Func<T, bool>> predicate, CancellationToken ct = default);
    Task<T> AddAsync(T entity, CancellationToken ct = default);
    Task<T> UpdateAsync(T entity, CancellationToken ct = default);
    Task DeleteAsync(Guid id, CancellationToken ct = default);
    Task<int> CountAsync(Expression<Func<T, bool>>? predicate = null, CancellationToken ct = default);
    Task<bool> ExistsAsync(Guid id, CancellationToken ct = default);
}

public interface IUnitOfWork : IAsyncDisposable
{
    IRepository<User> Users { get; }
    IRepository<Product> Products { get; }
    Task<int> SaveChangesAsync(CancellationToken ct = default);
    Task BeginTransactionAsync(CancellationToken ct = default);
    Task CommitAsync(CancellationToken ct = default);
    Task RollbackAsync(CancellationToken ct = default);
}

#endregion

#region Middleware Pipeline

public delegate Task<TResponse> RequestDelegate<TRequest, TResponse>(TRequest request);

public interface IMiddleware<TRequest, TResponse>
{
    Task<TResponse> InvokeAsync(
        TRequest request,
        RequestDelegate<TRequest, TResponse> next,
        CancellationToken ct = default);
}

public sealed class MiddlewarePipeline<TRequest, TResponse>
{
    private readonly List<Func<RequestDelegate<TRequest, TResponse>, RequestDelegate<TRequest, TResponse>>> _components = new();

    public MiddlewarePipeline<TRequest, TResponse> Use(
        Func<RequestDelegate<TRequest, TResponse>, RequestDelegate<TRequest, TResponse>> middleware)
    {
        _components.Add(middleware);
        return this;
    }

    public MiddlewarePipeline<TRequest, TResponse> Use<TMiddleware>()
        where TMiddleware : IMiddleware<TRequest, TResponse>, new()
    {
        var middleware = new TMiddleware();
        _components.Add(next => request => middleware.InvokeAsync(request, next));
        return this;
    }

    public RequestDelegate<TRequest, TResponse> Build(RequestDelegate<TRequest, TResponse> handler)
    {
        var pipeline = handler;
        for (int i = _components.Count - 1; i >= 0; i--)
        {
            pipeline = _components[i](pipeline);
        }
        return pipeline;
    }
}

public sealed class LoggingMiddleware<TRequest, TResponse> : IMiddleware<TRequest, TResponse>
{
    public async Task<TResponse> InvokeAsync(
        TRequest request,
        RequestDelegate<TRequest, TResponse> next,
        CancellationToken ct = default)
    {
        var sw = Stopwatch.StartNew();
        Console.WriteLine($"[{DateTime.UtcNow:O}] Processing {typeof(TRequest).Name}...");

        try
        {
            var response = await next(request);
            sw.Stop();
            Console.WriteLine($"[{DateTime.UtcNow:O}] Completed in {sw.ElapsedMilliseconds}ms");
            return response;
        }
        catch (Exception ex)
        {
            sw.Stop();
            Console.WriteLine($"[{DateTime.UtcNow:O}] Failed after {sw.ElapsedMilliseconds}ms: {ex.Message}");
            throw;
        }
    }
}

#endregion

#region Source Generators Pattern (Simulated)

public static class SourceGenPatterns
{
    // Interceptor-like pattern
    [Audit("UserLookup", Level = AuditLevel.Info)]
    [RetryOnFailure(MaxAttempts = 3, InitialDelayMs = 200)]
    public static async Task<Result<User>> FindUserByEmailAsync(
        string email,
        IRepository<User> repo,
        CancellationToken ct = default)
    {
        var users = await repo.FindAsync(u => u.Email == email, ct);
        var user = users.FirstOrDefault();
        return user is not null
            ? Result<User>.Ok(user)
            : Result<User>.Err("User not found", "USER_NOT_FOUND");
    }

    // Primary constructor pattern (C# 12)
    public sealed class OrderService(
        IRepository<Product> productRepo,
        IRepository<User> userRepo,
        AsyncEventBus eventBus)
    {
        public async Task<Result<OrderConfirmation>> PlaceOrderAsync(
            Guid userId, IReadOnlyList<OrderItem> items, CancellationToken ct = default)
        {
            var user = await userRepo.GetByIdAsync(userId, ct);
            if (user is null)
                return Result<OrderConfirmation>.Err("User not found");

            var total = 0m;
            foreach (var item in items)
            {
                var product = await productRepo.GetByIdAsync(item.ProductId, ct);
                if (product is null)
                    return Result<OrderConfirmation>.Err($"Product {item.ProductId} not found");

                if (product.StockQuantity < item.Quantity)
                    return Result<OrderConfirmation>.Err($"Insufficient stock for {product.Name}");

                total += product.Price * item.Quantity;
            }

            var confirmation = new OrderConfirmation(
                OrderId: Guid.NewGuid(),
                UserId: userId,
                Items: items,
                Total: total,
                Timestamp: DateTimeOffset.UtcNow
            );

            await eventBus.PublishAsync(new OrderPlacedEvent(confirmation), ct);
            return Result<OrderConfirmation>.Ok(confirmation);
        }
    }

    public record OrderItem(Guid ProductId, int Quantity, decimal UnitPrice);
    public record OrderConfirmation(
        Guid OrderId,
        Guid UserId,
        IReadOnlyList<OrderItem> Items,
        decimal Total,
        DateTimeOffset Timestamp);
    public record OrderPlacedEvent(OrderConfirmation Order);
}

#endregion

#region Collection Expressions (C# 12)

public static class CollectionExpressionExamples
{
    public static void Demo()
    {
        // Collection expressions
        int[] numbers = [1, 2, 3, 4, 5];
        List<string> names = ["Alice", "Bob", "Charlie"];
        ImmutableArray<double> scores = [95.5, 87.3, 92.1];

        // Spread operator
        int[] first = [1, 2, 3];
        int[] second = [4, 5, 6];
        int[] combined = [.. first, .. second, 7, 8, 9];

        // In method calls
        ProcessItems([1, 2, 3, 4, 5]);

        // Dictionary-like initialization
        var config = new Dictionary<string, object>
        {
            ["host"] = "localhost",
            ["port"] = 8080,
            ["ssl"] = true,
            ["timeout"] = TimeSpan.FromSeconds(30)
        };

        // Spans
        ReadOnlySpan<int> span = [10, 20, 30, 40, 50];
        var sum = 0;
        foreach (var n in span) sum += n;
    }

    private static void ProcessItems(IReadOnlyList<int> items)
    {
        foreach (var item in items)
            Console.WriteLine(item);
    }
}

#endregion

#region String Interpolation and Raw Strings

public static class StringExamples
{
    public static void Demo()
    {
        // Interpolated strings
        var name = "World";
        var greeting = $"Hello, {name}!";

        // Verbatim interpolated
        var path = $@"C:\Users\{name}\Documents";

        // Raw string literals (C# 11)
        var json = """
            {
                "name": "Alice",
                "age": 30,
                "scores": [95, 87, 92]
            }
            """;

        // Raw interpolated strings
        var userId = Guid.NewGuid();
        var apiResponse = $$"""
            {
                "id": "{{userId}}",
                "status": "active",
                "metadata": {
                    "created": "{{DateTimeOffset.UtcNow:O}}"
                }
            }
            """;

        // String formatting
        var pi = Math.PI;
        Console.WriteLine($"Pi = {pi:F10}");
        Console.WriteLine($"Pi = {pi,20:E5}");
        Console.WriteLine($"Hex: {255:X4}");
        Console.WriteLine($"Currency: {1234.56m:C}");
        Console.WriteLine($"Percent: {0.8567:P2}");
    }
}

#endregion

#region Main Entry Point

public class Program
{
    public static async Task Main(string[] args)
    {
        Console.WriteLine("=== C# Syntax Highlighting Test ===\n");

        // Pattern matching
        Console.WriteLine(PatternMatchingExamples.Classify(42));
        Console.WriteLine(PatternMatchingExamples.Classify("hello"));
        Console.WriteLine(PatternMatchingExamples.Classify(null));
        Console.WriteLine(PatternMatchingExamples.Classify(3.14));

        // Shape matching
        Console.WriteLine(PatternMatchingExamples.DescribeShape(new Circle(5.0)));
        Console.WriteLine(PatternMatchingExamples.DescribeShape(new Rectangle(4, 4)));
        Console.WriteLine(PatternMatchingExamples.DescribeShape(new Triangle(3, 4, 5)));

        // Collection expressions
        CollectionExpressionExamples.Demo();

        // String examples
        StringExamples.Demo();

        // LINQ
        LinqExamples.QueryDemo();

        // Async event bus
        await using var eventBus = new AsyncEventBus();
        eventBus.Subscribe<SourceGenPatterns.OrderPlacedEvent>(async (evt, ct) =>
        {
            Console.WriteLine($"Order placed: {evt.Order.OrderId}");
            await Task.CompletedTask;
        });

        // Result type
        var result = Result<int>.Ok(42);
        var mapped = result.Map(x => x * 2).Map(x => $"Value: {x}");
        Console.WriteLine(mapped);

        Console.WriteLine("\n=== Done ===");
    }
}

#endregion
